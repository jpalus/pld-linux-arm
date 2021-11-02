#!/bin/sh

setup_log_file() {
  if [ -z "$LOG_FILE" ]; then
    LOG_FILE="$SCRIPT_DIR/$RELEASE_NAME-$ACTION.log"
    : > "$LOG_FILE"
    echo "Logging to $LOG_FILE"
  fi
}

log() {
  setup_log_file
  echo "$@" >> "$LOG_FILE"
}

error() {
  setup_log_file
  echo "ERROR: $*" | tee -a "$LOG_FILE" >&2
  exit 1
}

run_log() {
  local msg="$1"; shift
  log "Running $@"
  echo -n "$msg..."
  "$@" >> "$LOG_FILE" 2>&1
  if [ $? -eq 0 ]; then
    echo "OK"
  else
    echo "FAILED"
    error "Command failed: $@"
  fi
}

run_log_priv() {
  if [ "$(id -u)" != "0" ] && [ -z "$SUDO" ]; then
    echo "Non-root user detected, using sudo"
    SUDO="sudo"
  fi
  local msg="$1"; shift
  run_log "$msg" $SUDO "$@"
}

ARCH=${ARCH:-$(rpm -E %{_host_cpu})}

if [ $? -ne 0 ] || [ -z "$ARCH" ]; then
  error 'failed to determine arch'
fi

SCRIPT_DIR=$(dirname $(readlink -f "$0"))
TIMESTAMP=$(date +%Y%m%d)
RELEASE_NAME="pld-linux-base-$ARCH-$TIMESTAMP"
DOCKER_REGISTRY=docker.io
DOCKER_REPO="jpalus/pld-linux-$ARCH"
DOCKER_TAG="$DOCKER_REPO:$TIMESTAMP"
DOCKER_TAG_LATEST="$DOCKER_REPO:latest"

create() {
  echo "Creating release $RELEASE_NAME"

  CHROOT_DIR="$(mktemp -t -d $RELEASE_NAME.XXXXXXXXXX)"
  if [ $? -ne 0 ]; then
    error 'failed to create temporary chroot directory'
  fi

  run_log_priv "Setting up temporary chroot in $CHROOT_DIR" rpm --initdb --root "$CHROOT_DIR"
  run_log_priv "Installing packages from $SCRIPT_DIR/base.pkgs" poldek -iv --pset="$SCRIPT_DIR/base.pkgs" --root="$CHROOT_DIR" --noask --pmopt='--define=_tmppath\ /tmp'
  if [ ! -f jpalus.asc ]; then
    run_log "Preparing public key" gpg --output jpalus.asc --armor --export 'Jan Palus'
  fi
  run_log_priv "Importing public key" rpm --root="$CHROOT_DIR" --import jpalus.asc
  run_log_priv "Disabling default poldek repository configuration for $ARCH" sed -i -e "/^path.*=.*%{_prefix}\/PLD\/%{_arch}\/RPMS/ a auto = no\\nautoup = no" "$CHROOT_DIR/etc/poldek/repos.d/pld.conf"
  cat <<EOF | run_log_priv "Configuring custom $ARCH repository" sponge "$CHROOT_DIR/etc/poldek/repos.d/jpalus.conf"
[source]
type = pndir
name = jpalus
path = http://jpalus.fastmail.com.user.fm/dists/th/PLD/$ARCH/RPMS/
signed = yes
EOF
  rpm --root="$CHROOT_DIR" -qa|sort > "$SCRIPT_DIR/$RELEASE_NAME.packages"
  run_log_priv "Creating archive $SCRIPT_DIR/$RELEASE_NAME.tar.xz" tar -Jcpf "$SCRIPT_DIR/$RELEASE_NAME.tar.xz" -C "$CHROOT_DIR" .

  if [ "$(id -u)" != "0" ]; then
    run_log_priv "Changing ownership of $RELEASE_NAME.tar.xz" chown $(id -u -n) "$SCRIPT_DIR/$RELEASE_NAME.tar.xz"
  fi

  run_log_priv 'Cleaning up' rm -rf "$CHROOT_DIR"
}

sign() {
  if [ ! -f "$SCRIPT_DIR/$RELEASE_NAME.tar.xz" ]; then
    error "$SCRIPT_DIR/$RELEASE_NAME.tar.xz does not exist"
  fi
  echo "Signing release $RELEASE_NAME"
  run_log 'Signing' gpg --sign --armor --detach-sig "$SCRIPT_DIR/$RELEASE_NAME.tar.xz"
}

publish_dockerhub() {
  if [ ! -f "$SCRIPT_DIR/$RELEASE_NAME.tar.xz" ]; then
    error "$SCRIPT_DIR/$RELEASE_NAME.tar.xz does not exist"
  fi
  echo "Publishing release $RELEASE_NAME to Docker Hub"
  run_log "Importing docker image $DOCKER_TAG" podman import "$SCRIPT_DIR/$RELEASE_NAME.tar.xz" $DOCKER_REGISTRY/$DOCKER_TAG
  run_log "Tagging docker image $DOCKER_TAG as latest" podman tag $DOCKER_REGISTRY/$DOCKER_TAG $DOCKER_REGISTRY/$DOCKER_TAG_LATEST
  run_log "Pushing docker tag $DOCKER_TAG" podman push $DOCKER_REGISTRY/$DOCKER_TAG
  run_log "Pushing docker tag $DOCKER_TAG_LATEST" podman push $DOCKER_REGISTRY/$DOCKER_TAG_LATEST
}

image_rpi_exit_handler() {
  if [ -n "$IMAGE_RPI_MOUNT_DIR" ] && [ -d "$IMAGE_RPI_MOUNT_DIR" ]; then
    if [ -d "$IMAGE_RPI_MOUNT_DIR/boot/firmware" ] && mountpoint -q "$IMAGE_RPI_MOUNT_DIR/boot/firmware"; then
      run_log_priv "Unmounting boot firmware partition" umount "$IMAGE_RPI_MOUNT_DIR/boot/firmware"
    fi
    if mountpoint -q "$IMAGE_RPI_MOUNT_DIR"; then
      run_log_priv "Unmounting PLD root partition" umount "$IMAGE_RPI_MOUNT_DIR"
    fi
  fi
  if [ -n "$IMAGE_RPI_LO_DEVICE" ]; then
      run_log_priv "Detaching loop devcie" losetup -d $IMAGE_RPI_LO_DEVICE
  fi
  if [ -d "$IMAGE_RPI_MOUNT_DIR" ]; then
      run_log "Removing temporary mount directory $IMAGE_RPI_MOUNT_DIR" rmdir "$IMAGE_RPI_MOUNT_DIR"
  fi
  if [ -f "$IMAGE_RPI_PATH" ]; then
    run_log "Removing image file" rm "$IMAGE_RPI_PATH"
  fi
}

image_create_rpi() {
  if [ ! -f "$SCRIPT_DIR/$RELEASE_NAME.tar.xz" ]; then
    error "$SCRIPT_DIR/$RELEASE_NAME.tar.xz does not exist"
  fi

  trap image_rpi_exit_handler EXIT INT HUP

  IMAGE_RPI_FILENAME=raspberry-pi-$RELEASE_NAME.img
  IMAGE_RPI_PATH=$SCRIPT_DIR/$IMAGE_RPI_FILENAME
  IMAGE_RPI_SIZE_MB=2048
  echo "Creating boot image for Raspberry Pi"
  run_log "Preparing image file $IMAGE_RPI_FILENAME" dd if=/dev/zero "of=$IMAGE_RPI_PATH" bs=1M count=$IMAGE_RPI_SIZE_MB
  run_log_priv "Creating loop device" losetup -f "$IMAGE_RPI_PATH"
  IMAGE_RPI_LO_DEVICE=$(/sbin/losetup -j "$IMAGE_RPI_PATH" | tail -n 1 | cut -f1 -d:)
  run_log_priv "Creating partition table on $IMAGE_RPI_LO_DEVICE" sfdisk -q $IMAGE_RPI_LO_DEVICE <<EOF 
label: dos
size=256MiB, type=c
- - - *
EOF
  run_log_priv "Probing for new partitions" partprobe $IMAGE_RPI_LO_DEVICE
  run_log_priv "Creating vfat partition for boot firmware" mkfs.vfat -F 32 -n RPI_FW ${IMAGE_RPI_LO_DEVICE}p1
  run_log_priv "Creating ext4 partition for PLD root" mkfs.ext4 -q -L PLD_ROOT ${IMAGE_RPI_LO_DEVICE}p2
  IMAGE_RPI_MOUNT_DIR=$(mktemp -d)
  run_log_priv "Mounting PLD root to $IMAGE_RPI_MOUNT_DIR" mount ${IMAGE_RPI_LO_DEVICE}p2 "$IMAGE_RPI_MOUNT_DIR"
  run_log_priv "Extracting $RELEASE_NAME to $IMAGE_RPI_MOUNT_DIR" tar xf "$SCRIPT_DIR/$RELEASE_NAME.tar.xz" -C "$IMAGE_RPI_MOUNT_DIR"
  run_log_priv "Create directory for firmware mount" install -d "$IMAGE_RPI_MOUNT_DIR/boot/firmware"
  run_log_priv "Mounting boot firmware partition to $IMAGE_RPI_MOUNT_DIR/boot/firmware" mount ${IMAGE_RPI_LO_DEVICE}p1 "$IMAGE_RPI_MOUNT_DIR/boot/firmware"
  run_log_priv "Setting up fstab entries" tee -a "$IMAGE_RPI_MOUNT_DIR/etc/fstab" <<EOF 
LABEL=PLD_ROOT / ext4 defaults 0 0
LABEL=RPI_FW /boot/firmware vfat defaults 0 0
EOF
  echo -e 'pld\npld' | run_log_priv "Setting root password" chroot "$IMAGE_RPI_MOUNT_DIR" passwd
  run_log_priv "Installing uboot" chroot "$IMAGE_RPI_MOUNT_DIR" poldek -iv --noask $(echo "$ARCH" | grep -q armv6 && echo uboot-image-raspberry-pi-zero) $(echo "$ARCH" | grep -q 'armv[67]' && echo uboot-image-raspberry-pi-2)
  if echo "$ARCH" | grep -q armv6; then
    run_log_priv "Copying uboot image for Raspberry Pi Zero W" cp "$IMAGE_RPI_MOUNT_DIR/usr/share/uboot/rpi_0_w/u-boot.bin" "$IMAGE_RPI_MOUNT_DIR/boot/firmware/uboot-rpi_0_w.bin"
    run_log_priv "Configuring uboot for Raspberry Pi Zero W" tee -a "$IMAGE_RPI_MOUNT_DIR/boot/firmware/config.txt" <<EOF
[pi0w]
kernel=uboot-rpi_0_w.bin
EOF
  fi
  if echo "$ARCH" | grep -q 'armv[67]'; then
    run_log_priv "Copying uboot image for Raspberry Pi 2" cp "$IMAGE_RPI_MOUNT_DIR/usr/share/uboot/rpi_2/u-boot.bin" "$IMAGE_RPI_MOUNT_DIR/boot/firmware/uboot-rpi_2.bin"
    run_log_priv "Configuring uboot for Raspberry Pi 2" tee -a "$IMAGE_RPI_MOUNT_DIR/boot/firmware/config.txt" <<EOF
[pi2]
kernel=uboot-rpi_2.bin
EOF
  fi
  run_log_priv "Configuring common boot params for all Raspberry Pis" tee -a "$IMAGE_RPI_MOUNT_DIR/boot/firmware/config.txt" <<EOF
[all]
upstream_kernel=1
EOF
  run_log_priv "Creating /boot/extlinux directory" install -d "$IMAGE_RPI_MOUNT_DIR/boot/extlinux"
  run_log_priv "Configuring uboot extlinux entry" tee -a "$IMAGE_RPI_MOUNT_DIR/boot/extlinux/extlinux.conf" <<EOF
label PLD
  menu label PLD
  kernel /boot/vmlinuz
  append root=LABEL=PLD_ROOT rw console=tty1
  initrd /boot/initrd
  fdtdir /boot/dtb
EOF
  run_log_priv "Installing geninitrd" chroot "$IMAGE_RPI_MOUNT_DIR" poldek -n jpalus -n th -iv --noask geninitrd
  run_log_priv "Configuring additional kernel modules in initrd" sed -i 's/^#PREMODS.*/PREMODS="clk-raspberrypi bcm2835-dma pwm-bcm2835 i2c-bcm2835 bcm2835 mmc-block bcm2835-rng"/' "$IMAGE_RPI_MOUNT_DIR/etc/sysconfig/geninitrd"
  run_log_priv "Use lz4 compression for initrd" sed -i 's/^#COMPRESS.*/COMPRESS=lz4/' "$IMAGE_RPI_MOUNT_DIR/etc/sysconfig/geninitrd"
  run_log_priv "Use modprobe in initrd" tee -a "$IMAGE_RPI_MOUNT_DIR/etc/sysconfig/geninitrd" <<EOF
USE_MODPROBE=yes
EOF
  run_log_priv "Installing raspberrypi-firmware" chroot "$IMAGE_RPI_MOUNT_DIR" poldek -iv --noask raspberrypi-firmware
  run_log_priv "Installing kernel" chroot "$IMAGE_RPI_MOUNT_DIR" poldek -iv --noask kernel kernel-drm kernel-sound-alsa
  run_log_priv "Installing rng-tools systemd-networkd wireless-regdb" chroot "$IMAGE_RPI_MOUNT_DIR" poldek -uv --noask rng-tools systemd-networkd wireless-regdb
  run_log_priv "Configuring rng-tools" sed -i 's/^#RNGD_OPTIONS=.*/RNGD_OPTIONS=" -x jitter -x pkcs11 -x rtlsdr "/' "$IMAGE_RPI_MOUNT_DIR/etc/sysconfig/rngd"
  run_log_priv "Enabling networkd link handling" rm "$IMAGE_RPI_MOUNT_DIR/etc/udev/rules.d/80-net-setup-link.rules"
  run_log_priv "Cleaning up poldek cache" rm -rf "$IMAGE_RPI_MOUNT_DIR/root/.poldek-cache"
  run_log "Compressing image" xz "$IMAGE_RPI_PATH"
}

image_sign_rpi() {
  if [ ! -f "$SCRIPT_DIR/raspberry-pi-$RELEASE_NAME.img.xz" ]; then
    error "$SCRIPT_DIR/raspberry-pi-$RELEASE_NAME.img.xz does not exist"
  fi
  echo "Signing image raspberry-pi-$RELEASE_NAME.img.xz"
  run_log 'Signing' gpg --sign --armor --detach-sig "$SCRIPT_DIR/raspberry-pi-$RELEASE_NAME.img.xz"
}

case "$1" in
  create|sign)
    ACTION=$1
    $1
    ;;
  publish)
    case "$2" in
      dockerhub)
        ACTION=$1-$2
        $1_$2
        ;;
      *)
        ACTION=unknown
        error "Unknown publish target: $2"
        ;;
    esac
    ;;
  image)
    case "$2" in
      create|sign)
        case "$3" in
          rpi)
            ACTION=$1-$2-$3
            $1_$2_$3
            ;;
          *)
            ACTION=unknown
            error "Unknown image target: $3"
            ;;
        esac
	;;
      *)
        ACTION=unknown
        error "Unknown image action: $2"
        ;;
    esac
    ;;
  *)
    ACTION=unknown
    error "Unknown action: $1"
esac
