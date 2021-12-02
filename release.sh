#!/bin/sh

poldek_install() {
  local cmd msg="$1"; shift
  if [ $# -ge 2 ] && [ "$1" = "--root" ]; then
    CHROOT="chroot $2"
    shift 2
  else
    cmd="run_log"
  fi

  run_log_priv "$msg" $CHROOT poldek -iv --noask --pmopt='--define=_excludedocs\ 1' --pmopt='--define=_install_langs\ %{nil}' "$@"
}

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

is_on() {
  case "$1" in
    1|[Yy]|[Oo][Nn]|[Yy][Ee][Ss])
      return 0
      ;;
    *)
      return 1
      ;;
  esac
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
  poldek_install "Installing packages from $SCRIPT_DIR/base.pkgs" --pset="$SCRIPT_DIR/base.pkgs" --root="$CHROOT_DIR" --pmopt='--define=_tmppath\ /tmp'
  if [ ! -f jpalus.asc ]; then
    run_log "Preparing public key" gpg --output jpalus.asc --armor --export 'Jan Palus'
  fi
  run_log_priv "Importing public key" rpm --root="$CHROOT_DIR" --import jpalus.asc
  run_log_priv "Disabling default poldek repository configuration for $ARCH" sed -i -e "/^path.*=.*%{_prefix}\/PLD\/%{_arch}\/RPMS/ a auto = no\\nautoup = no" "$CHROOT_DIR/etc/poldek/repos.d/pld.conf"
  run_log_priv "Configuring custom $ARCH repository" tee "$CHROOT_DIR/etc/poldek/repos.d/jpalus.conf" <<EOF
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

image_unmount_fs() {
  if [ -n "$IMAGE_MOUNT_DIR" ] && [ -d "$IMAGE_MOUNT_DIR" ]; then
    if [ -d "$IMAGE_MOUNT_DIR/boot/firmware" ] && mountpoint -q "$IMAGE_MOUNT_DIR/boot/firmware"; then
      run_log_priv "Unmounting boot firmware partition" umount "$IMAGE_MOUNT_DIR/boot/firmware"
    fi
    if [ -d "$IMAGE_MOUNT_DIR/boot" ] && mountpoint -q "$IMAGE_MOUNT_DIR/boot"; then
      run_log_priv "Unmounting boot partition" umount "$IMAGE_MOUNT_DIR/boot"
    fi
    if mountpoint -q "$IMAGE_MOUNT_DIR"; then
      run_log_priv "Unmounting PLD root partition" umount "$IMAGE_MOUNT_DIR"
    fi
  fi
}

image_detach_loop_device() {
  if [ -n "$IMAGE_LO_DEVICE" ]; then
    run_log_priv "Detaching loop devcie" losetup -d $IMAGE_LO_DEVICE
    unset IMAGE_LO_DEVICE
  fi
}

image_exit_handler() {
  image_dispatch image_unmount_fs
  image_dispatch image_detach_loop_device
  if [ -d "$IMAGE_MOUNT_DIR" ]; then
      run_log "Removing temporary mount directory $IMAGE_MOUNT_DIR" rmdir "$IMAGE_MOUNT_DIR"
  fi
  if [ -f "$IMAGE_PATH" ]; then
    run_log "Removing image file" rm "$IMAGE_PATH"
  fi
}

image_dispatch() {
  local f=$1
  shift
  if ! type ${f}_$IMAGE_TYPE | grep -q 'not found'; then
    f=${f}_$IMAGE_TYPE
  fi
  eval $f "$@"
}

image_prepare_file() {
  IMAGE_FILENAME=$IMAGE_NAME-$RELEASE_NAME.img
  IMAGE_PATH=$SCRIPT_DIR/$IMAGE_FILENAME
  echo "Creating boot image for $IMAGE_DESC"
  run_log "Preparing image file $IMAGE_FILENAME" dd if=/dev/zero "of=$IMAGE_PATH" bs=1M count=$IMAGE_SIZE_MB
}

image_create_loop_device() {
  run_log_priv "Creating loop device" losetup -f "$IMAGE_PATH"
  IMAGE_LO_DEVICE=$(/sbin/losetup -j "$IMAGE_PATH" | tail -n 1 | cut -f1 -d:)
}

image_create_partitions() {
  run_log_priv "Creating partition table on $IMAGE_LO_DEVICE" sfdisk -q $IMAGE_LO_DEVICE <<EOF 
label: dos
- - - *
EOF
  IMAGE_ROOT_DEVICE=${IMAGE_LO_DEVICE}p1
}

image_create_fs() {
  run_log_priv "Creating ext4 partition for PLD root" mkfs.ext4 -q -L PLD_ROOT ${IMAGE_ROOT_DEVICE}
}

image_mount_fs() {
  run_log_priv "Mounting PLD root to $IMAGE_MOUNT_DIR" mount ${IMAGE_ROOT_DEVICE} "$IMAGE_MOUNT_DIR"
  if [ -n "$IMAGE_BOOT_DEVICE" ]; then
    if [ ! -e "$IMAGE_MOUNT_DIR/boot" ]; then
      run_log_priv "Creating $IMAGE_MOUNT_DIR/boot" mkdir -p $IMAGE_MOUNT_DIR/boot
    fi
    run_log_priv "Mounting boot to $IMAGE_MOUNT_DIR/boot" mount ${IMAGE_BOOT_DEVICE} "$IMAGE_MOUNT_DIR/boot"
  fi
  if [ -n "$IMAGE_FIRMWARE_DEVICE" ]; then
    if [ ! -e "$IMAGE_MOUNT_DIR/boot/firmware" ]; then
      run_log_priv "Creating $IMAGE_MOUNT_DIR/boot/firmware" mkdir -p $IMAGE_MOUNT_DIR/boot/firmware
    fi
    run_log_priv "Mounting boot firmware partition to $IMAGE_MOUNT_DIR/boot/firmware" mount ${IMAGE_FIRMWARE_DEVICE} "$IMAGE_MOUNT_DIR/boot/firmware"
  fi
}

_part_id() {
  local UUID LABEL
  eval $($SUDO blkid --output export "$1" | grep '^\(LABEL\|UUID\)=')
  if [ -n "$LABEL" ]; then
    echo "LABEL=$LABEL"
  elif [ -n "$UUID" ]; then
    echo "UUID=$UUID"
  else
    echo $1
  fi
}

_fstab_entry() {
  local TYPE
  eval $($SUDO blkid --output export "$1" | grep '^TYPE=')
  echo "$(_part_id $1) $2 $TYPE defaults 0 0"
}

image_prepare_fstab() {
  local FSTAB
  FSTAB="$(_fstab_entry $IMAGE_ROOT_DEVICE /)"
  if [ -n "$IMAGE_BOOT_DEVICE" ]; then
    FSTAB="$FSTAB
$(_fstab_entry $IMAGE_BOOT_DEVICE /boot)"
  fi
  if [ -n "$IMAGE_FIRMWARE_DEVICE" ]; then
    FSTAB="$FSTAB
$(_fstab_entry $IMAGE_FIRMWARE_DEVICE /boot/firmware)"
  fi
  run_log_priv "Setting up fstab entries" tee -a "$IMAGE_MOUNT_DIR/etc/fstab" <<EOF 
$FSTAB
EOF
}

image_install_bootloader() {
}

image_setup_bootloader() {
  run_log_priv "Creating /boot/extlinux directory" install -d "$IMAGE_MOUNT_DIR/boot/extlinux"
  run_log_priv "Configuring uboot extlinux entry" tee -a "$IMAGE_MOUNT_DIR/boot/extlinux/extlinux.conf" <<EOF
menu title PLD Boot Menu
default PLD
timeout 20
label PLD
  menu label PLD
  kernel /boot/vmlinuz
  append root=$(_part_id $IMAGE_ROOT_DEVICE) rw $IMAGE_BOOT_PARAMS
  initrd /boot/initrd
  fdtdir /boot/dtb
label PLD.old
  menu label PLD.old
  kernel /boot/vmlinuz.old
  append root=$(_part_id $IMAGE_ROOT_DEVICE) rw $IMAGE_BOOT_PARAMS
  initrd /boot/initrd.old
  fdtdir /boot/dtb.old
EOF
}

image_install_initrd_generator() {
  poldek_install "Installing geninitrd" --root "$IMAGE_MOUNT_DIR" -n jpalus -n th geninitrd
}

image_setup_initrd() {
  if [ -n "$IMAGE_INITRD_MODULES" ]; then
    run_log_priv "Configuring additional kernel modules in initrd" sed -i "s/^#PREMODS.*/PREMODS=\"$IMAGE_INITRD_MODULES\"/" "$IMAGE_MOUNT_DIR/etc/sysconfig/geninitrd"
  fi
  run_log_priv "Use lz4 compression for initrd" sed -i 's/^#COMPRESS.*/COMPRESS=lz4/' "$IMAGE_MOUNT_DIR/etc/sysconfig/geninitrd"
  run_log_priv "Use modprobe in initrd" tee -a "$IMAGE_MOUNT_DIR/etc/sysconfig/geninitrd" <<EOF
USE_MODPROBE=yes
EOF
}

image_install_board_pkgs() {
}

image_setup_params_rpi() {
  IMAGE_TYPE=rpi
  IMAGE_NAME=raspberry-pi
  IMAGE_DESC="Raspberry Pi"
  IMAGE_BOOT_PARAMS="console=tty1"
  IMAGE_INITRD_MODULES="clk-raspberrypi bcm2835-dma pwm-bcm2835 i2c-bcm2835 bcm2835 mmc-block bcm2835-rng"
  IMAGE_DISPLAY_ENABLED=1
  IMAGE_SOUND_ENABLED=1
  IMAGE_WIFI_ENABLED=1
}

image_create_partitions_rpi() {
  run_log_priv "Creating partition table on $IMAGE_LO_DEVICE" sfdisk -q $IMAGE_LO_DEVICE <<EOF 
label: dos
size=256MiB, type=c
- - - *
EOF
  IMAGE_FIRMWARE_DEVICE=${IMAGE_LO_DEVICE}p1
  IMAGE_ROOT_DEVICE=${IMAGE_LO_DEVICE}p2
}

image_create_fs_rpi() {
  run_log_priv "Creating vfat partition for boot firmware" mkfs.vfat -F 32 -n RPI_FW ${IMAGE_FIRMWARE_DEVICE}
  run_log_priv "Creating ext4 partition for PLD root" mkfs.ext4 -q -L PLD_ROOT ${IMAGE_ROOT_DEVICE}
}

image_install_bootloader_rpi() {
  poldek_install "Installing uboot" --root "$IMAGE_MOUNT_DIR" $(echo "$ARCH" | grep -q armv6 && echo uboot-image-raspberry-pi-zero) $(echo "$ARCH" | grep -q 'armv[67]' && echo uboot-image-raspberry-pi-2)
  if echo "$ARCH" | grep -q armv6; then
    run_log_priv "Copying uboot image for Raspberry Pi Zero W" cp "$IMAGE_MOUNT_DIR/usr/share/uboot/rpi_0_w/u-boot.bin" "$IMAGE_MOUNT_DIR/boot/firmware/uboot-rpi_0_w.bin"
    run_log_priv "Configuring uboot for Raspberry Pi Zero W" tee -a "$IMAGE_MOUNT_DIR/boot/firmware/config.txt" <<EOF
[pi0w]
kernel=uboot-rpi_0_w.bin
enable_uart=1
EOF
  fi
  if echo "$ARCH" | grep -q 'armv[67]'; then
    run_log_priv "Copying uboot image for Raspberry Pi 2" cp "$IMAGE_MOUNT_DIR/usr/share/uboot/rpi_2/u-boot.bin" "$IMAGE_MOUNT_DIR/boot/firmware/uboot-rpi_2.bin"
    run_log_priv "Configuring uboot for Raspberry Pi 2" tee -a "$IMAGE_MOUNT_DIR/boot/firmware/config.txt" <<EOF
[pi2]
kernel=uboot-rpi_2.bin
EOF
  fi
  run_log_priv "Configuring common boot params for all Raspberry Pis" tee -a "$IMAGE_MOUNT_DIR/boot/firmware/config.txt" <<EOF
[all]
upstream_kernel=1
EOF
}

image_install_board_pkgs_rpi() {
  poldek_install "Installing raspberrypi-firmware linux-firmware-broadcom rng-tools" --root "$IMAGE_MOUNT_DIR" raspberrypi-firmware linux-firmware-broadcom rng-tools
  run_log_priv "Configuring rng-tools" sed -i 's/^#RNGD_OPTIONS=.*/RNGD_OPTIONS=" -x jitter -x pkcs11 -x rtlsdr "/' "$IMAGE_MOUNT_DIR/etc/sysconfig/rngd"
}

image_setup_params_odroid_n2() {
  IMAGE_TYPE=odroid_n2
  IMAGE_NAME=odroid-n2
  IMAGE_DESC="Odroid N2/N2+"
  IMAGE_BOOT_PARAMS="earlycon"
  IMAGE_INITRD_MODULES="fixed pwm-regulator gpio-regulator rtc_pcf8563 g12a pwm-meson reset-meson clk-cpu-dyndiv clk-dualdiv clk-mpll clk-phase clk-pll clk-regmap g12a-aoclk meson-aoclk meson-eeclk sclk-div meson_sm i2c-meson meson_saradc pinctrl-meson-axg-pmx pwrseq_emmc meson-gx-mmc meson-mx-sdio pinctrl-meson-g12a meson-canvas meson-clk-measure meson-ee-pwrc meson-gx-pwrc-vpu meson-secure-pwrc mmc-block "
  IMAGE_DISPLAY_ENABLED=1
  IMAGE_SOUND_ENABLED=1
}

image_install_bootloader_odroid_n2() {
  poldek_install "Installing uboot" --root "$IMAGE_MOUNT_DIR" uboot-image-odroid-n2
  run_log_priv "Writing uboot image" dd if="$IMAGE_MOUNT_DIR/usr/share/uboot/odroid-n2/u-boot.bin" of="$IMAGE_LO_DEVICE" bs=512 seek=1 conv=notrunc,fsync
}

image_create() {
  if [ ! -f "$SCRIPT_DIR/$RELEASE_NAME.tar.xz" ]; then
    error "$SCRIPT_DIR/$RELEASE_NAME.tar.xz does not exist"
  fi

  trap image_exit_handler EXIT INT HUP
  image_dispatch image_prepare_file
  image_dispatch image_create_loop_device
  image_dispatch image_create_partitions
  run_log_priv "Probing for new partitions" partprobe $IMAGE_LO_DEVICE
  image_dispatch image_create_fs
  IMAGE_MOUNT_DIR=$(mktemp -d)
  image_dispatch image_mount_fs
  run_log_priv "Extracting $RELEASE_NAME to $IMAGE_MOUNT_DIR" tar xf "$SCRIPT_DIR/$RELEASE_NAME.tar.xz" -C "$IMAGE_MOUNT_DIR"
  image_dispatch image_prepare_fstab
  echo -e 'pld\npld' | run_log_priv "Setting root password" chroot "$IMAGE_MOUNT_DIR" passwd
  image_dispatch image_install_bootloader
  image_dispatch image_setup_bootloader
  image_dispatch image_install_initrd_generator
  image_dispatch image_setup_initrd
  image_dispatch image_install_board_pkgs
  KERNEL_PKGS="kernel"
  if is_on "$IMAGE_DISPLAY_ENABLED"; then
    KERNEL_PKGS="$KERNEL_PKGS kernel-drm"
  fi
  if is_on "$IMAGE_SOUND_ENABLED"; then
    KERNEL_PKGS="$KERNEL_PKGS kernel-sound-alsa"
  fi
  poldek_install "Installing kernel" --root "$IMAGE_MOUNT_DIR" $KERNEL_PKGS
  poldek_install "Installing systemd-networkd" --root "$IMAGE_MOUNT_DIR" systemd-networkd
  if is_on "$IMAGE_WIFI_ENABLED"; then
    poldek_install "Installing iwd wireless-regdb" --root "$IMAGE_MOUNT_DIR" iwd wireless-regdb
  fi
  run_log_priv "Enabling networkd link handling" rm "$IMAGE_MOUNT_DIR/etc/udev/rules.d/80-net-setup-link.rules"
  run_log_priv "Cleaning up poldek cache" rm -rf "$IMAGE_MOUNT_DIR/root/.poldek-cache"
  run_log "Compressing image" xz "$IMAGE_PATH"
}

image_sign() {
  if [ ! -f "$SCRIPT_DIR/$IMAGE_NAME-$RELEASE_NAME.img.xz" ]; then
    error "$SCRIPT_DIR/$IMAGE_NAME-$RELEASE_NAME.img.xz does not exist"
  fi
  echo "Signing image $IMAGE_NAME-$RELEASE_NAME.img.xz"
  run_log 'Signing' gpg --sign --armor --detach-sig "$SCRIPT_DIR/$IMAGE_NAME-$RELEASE_NAME.img.xz"
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
        IMAGE_SIZE_MB=1024
        case "$3" in
          rpi|odroid-n2)
            ACTION=$1-$2-$3
            eval image_setup_params_$(echo $3|tr - _)
            $1_$2
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
