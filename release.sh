#!/bin/sh

SCRIPT_DIR=$(dirname $(readlink -f "$0"))

RELEASE_TIMESTAMP=${RELEASE_TIMESTAMP:-$(date +%Y%m%d)}
ARCH=${ARCH:-$(rpm -E %{_host_cpu})}

if [ $? -ne 0 ] || [ -z "$ARCH" ]; then
  error 'failed to determine arch'
fi

release_name() {
  local _arch=${1:-$ARCH}
  echo pld-linux-base-$_arch-$RELEASE_TIMESTAMP
}

EFI_PART_SIZE_MB=${EFI_PART_SIZE_MB:-128}
FIRMWARE_PART_SIZE_MB=${FIRMWARE_PART_SIZE_MB:-128}
RELEASE_NAME=$(release_name)
DOCKER_REGISTRY=docker.io
DOCKER_REPO_PREFIX="jpalus/pld-linux-"
DOCKER_REPO="$DOCKER_REPO_PREFIX$ARCH"
DOCKER_TAG="$DOCKER_REPO:$RELEASE_TIMESTAMP"
DOCKER_TAG_LATEST="$DOCKER_REPO:latest"
DOCKER_MULTIARCH_ARCHS="aarch64 armv6hl armv7hnl"
DOCKER_MULTIARCH_REPO="jpalus/pld-linux-arm"
DOCKER_MULTIARCH_MANIFEST="$DOCKER_REGISTRY/$DOCKER_MULTIARCH_REPO:$RELEASE_TIMESTAMP"
DOCKER_MULTIARCH_MANIFEST_LATEST="$DOCKER_REGISTRY/$DOCKER_MULTIARCH_REPO:latest"

DOWNLOAD_URL="https://github.com/jpalus/pld-linux-arm/releases/download"
RELEASE_DOWNLOAD_URL="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-$RELEASE_TIMESTAMP"

BASIC_PKGS="bzip2 dhcp-client e2fsprogs gzip iproute2 less lz4 openssh-clients openssh-server ping shadow sudo systemd systemd-init tar unzip wget xz"

poldek_install() {
  local cmd msg="$1"; shift
  if [ $# -ge 2 ] && [ "$1" = "--root" ]; then
    CHROOT="chroot $2"
    shift 2
  else
    cmd="run_log"
  fi

  run_log_priv "$msg" $CHROOT poldek -n jpalus -n th -n th-ready -n th-test -uv --noask --pmopt='--define=_excludedocs\ 1' --pmopt='--define=_install_langs\ %{nil}' "$@"
}

check_args_nr() {
  local expected_nr=$1
  shift

  if [ $# -ne $expected_nr ]; then
    shift $(test $# -lt $expected_nr && echo $# || echo $expected_nr)
    error "Invalid arguments: $@"
  fi
}

check_dep() {
  if ! PATH=/sbin:/usr/sbin:$PATH command -v $1 > /dev/null 2> /dev/null; then
    if [ "$PLD_ARM_IN_CONTAINER" = "1" ]; then
      run_log_priv "Installing ${2:-$1}" poldek -uv --noask ${2:-$1}
    else
      error "Mandatory command '$1' not found"
    fi
  fi
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
  local msg no_error cmd_status
  if [ "$1" = "-n" ]; then
    no_error=1; shift
  fi
  msg="$1"; shift
  log "Running $@"
  echo -n "$msg..."
  "$@" >> "$LOG_FILE" 2>&1
  cmd_status=$?
  if [ -z "$no_error" ]; then
    if [ $cmd_status -eq 0 ]; then
      echo "OK"
    else
      echo "FAILED"
      error "Command failed: $@"
    fi
  fi
  return $cmd_status
}

run_log_priv() {
  if [ "$(id -u)" != "0" ] && [ -z "$SUDO" ]; then
    echo "Non-root user detected, using sudo"
    SUDO="sudo"
  fi
  local msg no_error
  if [ "$1" = "-n" ]; then
    no_error=1; shift
  fi
  msg="$1"; shift
  run_log ${no_error:+-n} "$msg" $SUDO "$@"
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

create() {
  echo "Creating release $RELEASE_NAME"

  CHROOT_DIR="$(mktemp -t -d $RELEASE_NAME.XXXXXXXXXX)"
  if [ $? -ne 0 ]; then
    error 'failed to create temporary chroot directory'
  fi

  run_log_priv "Setting up temporary chroot in $CHROOT_DIR" rpm --initdb --root "$CHROOT_DIR"
  poldek_install "Installing packages from $SCRIPT_DIR/base.pkgs" --pset="$SCRIPT_DIR/base.pkgs" --root="$CHROOT_DIR" --pmopt='--define=_tmppath\ /tmp'
  if [ ! -f "$SCRIPT_DIR/jpalus.asc" ]; then
    check_dep wget
    run_log "Fetching public key" wget http://jpalus.fastmail.com/jpalus.asc -O "$SCRIPT_DIR/jpalus.asc"
  fi
  check_dep gpg gnupg2
  if ! gpg --show-keys "$SCRIPT_DIR/jpalus.asc" | grep -iq 7D4F29DD11CB9CAEBA20E59FEA3B49141E88A192; then
    error "Public key validation failed"
  fi
  run_log_priv "Importing public key" rpm --root="$CHROOT_DIR" --import "$SCRIPT_DIR/jpalus.asc"
  run_log_priv "Disabling default poldek repository configuration for $ARCH" sed -i -e "/^path.*=.*%{_prefix}\/PLD\/%{_arch}\/RPMS/ a auto = no\\nautoup = no" "$CHROOT_DIR/etc/poldek/repos.d/pld.conf"
  run_log_priv "Configuring custom $ARCH repository" tee "$CHROOT_DIR/etc/poldek/repos.d/jpalus.conf" <<EOF
[source]
type = pndir
name = jpalus
path = http://jpalus.fastmail.com.user.fm/dists/th/PLD/$ARCH/RPMS/
signed = yes
EOF
  if [ ! -e "$CHROOT_DIR/etc/dnf/repos.d" ]; then
    run_log_priv "Creating /etc/dnf/repos.d directory" mkdir -p "$CHROOT_DIR/etc/dnf/repos.d"
  fi
  run_log_priv "Configuring custom dnf repository" tee "$CHROOT_DIR/etc/dnf/repos.d/jpalus.repo" <<EOF
[jpalus]
name=PLD Linux ARM
baseurl=http://jpalus.fastmail.com.user.fm/dists/th/PLD/$ARCH/RPMS/
gpgkey=http://jpalus.fastmail.com.user.fm/jpalus.asc
enabled=1
EOF
  rpm --root="$CHROOT_DIR" -qa|sort > "$SCRIPT_DIR/$RELEASE_NAME.packages"
  check_dep tar
  check_dep xz
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
  case "$ARCH" in
    aarch64)
      IMAGE_ARCH=arm64
      IMAGE_VARIANT=
      ;;
    armv6*)
      IMAGE_ARCH=arm
      IMAGE_VARIANT=v6
      ;;
    armv7*)
      IMAGE_ARCH=arm
      IMAGE_VARIANT=v7
      ;;
  esac
  xz -dc < "$SCRIPT_DIR/$RELEASE_NAME.tar.xz" | run_log "Importing docker image $DOCKER_TAG" podman import --os linux --arch $IMAGE_ARCH ${IMAGE_VARIANT:+--variant $IMAGE_VARIANT} - $DOCKER_REGISTRY/$DOCKER_TAG
  run_log "Tagging docker image $DOCKER_TAG as latest" podman tag $DOCKER_REGISTRY/$DOCKER_TAG $DOCKER_REGISTRY/$DOCKER_TAG_LATEST
  run_log "Pushing docker tag $DOCKER_TAG" podman push -f v2s2 $DOCKER_REGISTRY/$DOCKER_TAG
  run_log "Pushing docker tag $DOCKER_TAG_LATEST" podman push -f v2s2 $DOCKER_REGISTRY/$DOCKER_TAG_LATEST
}

publish_dockerhub_multiarch() {
  local arch
  for arch in $DOCKER_MULTIARCH_ARCHS; do
    if [ -z "$(podman images -q $DOCKER_REGISTRY/$DOCKER_REPO_PREFIX$arch:$RELEASE_TIMESTAMP)" ]; then
      error "Image not found: $DOCKER_REGISTRY/$DOCKER_REPO_PREFIX$arch:$RELEASE_TIMESTAMP"
    fi
  done
  echo "Publishing multiarch manifest $DOCKER_MULTIARCH_REPO to Docker Hub"
  run_log "Creating manifest" podman manifest create $DOCKER_MULTIARCH_MANIFEST
  for arch in $DOCKER_MULTIARCH_ARCHS; do
    run_log "Adding $arch image to manifest" podman manifest add $DOCKER_MULTIARCH_MANIFEST $DOCKER_REGISTRY/$DOCKER_REPO_PREFIX$arch:$RELEASE_TIMESTAMP
  done
  run_log "Tagging $DOCKER_MULTIARCH_MANIFEST as latest" podman tag $DOCKER_MULTIARCH_MANIFEST $DOCKER_MULTIARCH_MANIFEST_LATEST
  run_log "Pushing manifest $DOCKER_MULTIARCH_MANIFEST" podman manifest push --all $DOCKER_MULTIARCH_MANIFEST
  run_log "Pushing manifest $DOCKER_MULTIARCH_MANIFEST_LATEST" podman manifest push --all $DOCKER_MULTIARCH_MANIFEST_LATEST
}

image_unmount_fs() {
  if [ -n "$IMAGE_MOUNT_DIR" ] && [ -d "$IMAGE_MOUNT_DIR" ]; then
    if [ -d "$IMAGE_MOUNT_DIR/boot/efi" ] && mountpoint -q "$IMAGE_MOUNT_DIR/boot/efi"; then
      run_log_priv "Unmounting EFI system partition" umount "$IMAGE_MOUNT_DIR/boot/efi"
    fi
    if [ -d "$IMAGE_MOUNT_DIR/boot/firmware" ] && mountpoint -q "$IMAGE_MOUNT_DIR/boot/firmware"; then
      run_log_priv "Unmounting boot firmware partition" umount "$IMAGE_MOUNT_DIR/boot/firmware"
    fi
    if [ -d "$IMAGE_MOUNT_DIR/boot" ] && mountpoint -q "$IMAGE_MOUNT_DIR/boot"; then
      run_log_priv "Unmounting boot partition" umount "$IMAGE_MOUNT_DIR/boot"
    fi
    if [ -d "$IMAGE_MOUNT_DIR/dev" ] && mountpoint -q "$IMAGE_MOUNT_DIR/dev"; then
      run_log_priv "Unmounting /dev" umount "$IMAGE_MOUNT_DIR/dev"
    fi
    if [ -d "$IMAGE_MOUNT_DIR/proc" ] && mountpoint -q "$IMAGE_MOUNT_DIR/proc"; then
      run_log_priv "Unmounting /proc" umount "$IMAGE_MOUNT_DIR/proc"
    fi
    if [ -d "$IMAGE_MOUNT_DIR/sys" ] && mountpoint -q "$IMAGE_MOUNT_DIR/sys"; then
      run_log_priv "Unmounting /sys" umount "$IMAGE_MOUNT_DIR/sys"
    fi
    if mountpoint -q "$IMAGE_MOUNT_DIR"; then
      run_log_priv "Unmounting PLD root partition" umount "$IMAGE_MOUNT_DIR"
    fi
  fi
}

image_detach_device() {
  if [ -n "$IMAGE_DEVICE" ]; then
    if [ -e "${IMAGE_DEVICE}p1" ]; then
      run_log_priv "Delete information about image device partitions" partx -d $IMAGE_DEVICE
    fi
    case "$IMAGE_DEVICE_TYPE" in
      loop)
        run_log_priv "Detaching loop devcie" losetup -d $IMAGE_DEVICE
        ;;
      qemu-nbd)
        run_log_priv "Detaching NBD devcie" qemu-nbd -d $IMAGE_DEVICE
        ;;
    esac
    unset IMAGE_DEVICE
  fi
}

image_exit_handler() {
  image_dispatch image_unmount_fs
  image_dispatch image_detach_device
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
  IMAGE_FILENAME=$IMAGE_NAME-$RELEASE_NAME.$IMAGE_EXT
  IMAGE_PATH=$SCRIPT_DIR/$IMAGE_FILENAME
  check_dep qemu-img
  echo "Creating boot image for $IMAGE_DESC"
  run_log "Preparing image file $IMAGE_FILENAME" qemu-img create -f $IMAGE_FORMAT "$IMAGE_PATH" ${IMAGE_SIZE_MB}M
}

image_create_device() {
  case "$IMAGE_DEVICE_TYPE" in
    loop)
      if [ "$IMAGE_FORMAT" != "raw" ]; then
        error "Only raw images are supported with loop device (image type configured: $IMAGE_FORMAT)"
      fi
      run_log_priv "Creating loop device" losetup -f "$IMAGE_PATH"
      IMAGE_DEVICE=$(/sbin/losetup -j "$IMAGE_PATH" | tail -n 1 | cut -f1 -d:)
      ;;
    qemu-nbd)
      test -e /dev/nbd0 || run_log_priv "/dev/nbd0 not present: try loading nbd module" modprobe nbd
      check_dep nbd-client nbd
      check_dep qemu-nbd qemu-common
      log "Finding available NBD device"
      for i in `seq 0 9`; do
        if [ ! -e /dev/nbd$i ]; then
          break
        fi
        if ! run_log_priv -n "Checking /dev/nbd$i" nbd-client -c /dev/nbd$i > /dev/null; then
          NBD_DEVICE=/dev/nbd$i
          break
        fi
      done
      if [ -z "$NBD_DEVICE" ]; then
        error "Failed to find available NBD device"
      fi
      run_log_priv "Creating nbd device" qemu-nbd -c $NBD_DEVICE "$IMAGE_PATH"
      IMAGE_DEVICE="$NBD_DEVICE"
      ;;
  esac
}

image_efi_part() {
  if [ "$IMAGE_EFI_ENABLED" = "1" ]; then
    printf '%s' "size=${EFI_PART_SIZE_MB}MiB, type=ef"'\n'
    return 0
  else
    return 1
  fi
}

image_efi_fs() {
  if [ "$IMAGE_EFI_ENABLED" = "1" ]; then
    run_log_priv "Formatting EFI system partition" mkfs.vfat -F 32 -n EFI ${IMAGE_EFI_DEVICE}
  fi
}

image_create_partitions() {
  local part_table next_part_nr=1
  part_table="${part_table}$(image_efi_part)"
  if [ $? -eq 0 ]; then
    IMAGE_EFI_DEVICE=${IMAGE_DEVICE}p$next_part_nr
    next_part_nr=$((next_part_nr + 1))
  fi
  part_table="$part_table- - - *";
  IMAGE_ROOT_DEVICE=${IMAGE_DEVICE}p$next_part_nr
  run_log_priv "Creating partition table on $IMAGE_DEVICE" sfdisk -q $IMAGE_DEVICE <<EOF
$(printf "$part_table")
EOF
}

image_create_fs() {
  image_efi_fs
  run_log_priv "Formatting ext4 partition for PLD root" mkfs.ext4 -q -L PLD_ROOT ${IMAGE_ROOT_DEVICE}
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
  if [ -n "$IMAGE_EFI_DEVICE" ]; then
    if [ ! -e "$IMAGE_MOUNT_DIR/boot/efi" ]; then
      run_log_priv "Creating $IMAGE_MOUNT_DIR/boot/efi" mkdir -p $IMAGE_MOUNT_DIR/boot/efi
    fi
    run_log_priv "Mounting EFI system partition to $IMAGE_MOUNT_DIR/boot/efi" mount ${IMAGE_EFI_DEVICE} "$IMAGE_MOUNT_DIR/boot/efi"
  fi
}

image_install_basic_pkgs() {
  poldek_install "Installing basic packages" --root "$IMAGE_MOUNT_DIR" $BASIC_PKGS
}

image_systemd_setup() {
  run_log_priv "Setting systemd default target to multi-user.target" ln -sf /lib/systemd/system/multi-user.target "$IMAGE_MOUNT_DIR/etc/systemd/system/default.target"
  run_log_priv "Disabling network.service" rm "$IMAGE_MOUNT_DIR/etc/systemd/system/multi-user.target.wants/network.service"
  run_log_priv "Creating /etc/systemd/system/local-fs.target.wants" mkdir -p "$IMAGE_MOUNT_DIR/etc/systemd/system/local-fs.target.wants"
  run_log_priv "Enabling tmp.mount" ln -s /lib/systemd/system/tmp.mount "$IMAGE_MOUNT_DIR/etc/systemd/system/local-fs.target.wants/tmp.mount"
  run_log_priv "Masking pld-clean-tmp.service" ln -s /dev/null "$IMAGE_MOUNT_DIR/etc/systemd/system/pld-clean-tmp.service"
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
  if [ -n "$IMAGE_EFI_DEVICE" ]; then
    FSTAB="$FSTAB
$(_fstab_entry $IMAGE_EFI_DEVICE /boot/efi)"
  fi
  run_log_priv "Setting up fstab entries" tee -a "$IMAGE_MOUNT_DIR/etc/fstab" <<EOF 
$FSTAB
EOF
}

image_install_efi_bootloader() {
  if [ "$IMAGE_EFI_ENABLED" = "1" ]; then
    poldek_install "Installing EFI packages" --root "$IMAGE_MOUNT_DIR" grub2-platform-efi
  fi
}

image_install_bootloader() {
  image_install_efi_bootloader "$@"
}

image_setup_bootloader() {
  local efi_target

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
  if [ "$IMAGE_EFI_ENABLED" = "1" ]; then
    run_log_priv "Updating GRUB configuration" chroot "$IMAGE_MOUNT_DIR" update-grub
    case "$ARCH" in
      aarch64)
        efi_target=arm64-efi
        ;;
      armv*)
        efi_target=arm-efi
        ;;
    esac
    run_log_priv "Installing GRUB EFI application" chroot "$IMAGE_MOUNT_DIR" grub-install --target=$efi_target --efi-directory=/boot/efi --removable
  fi
}

image_install_initrd_generator() {
  poldek_install "Installing geninitrd" --root "$IMAGE_MOUNT_DIR" geninitrd
}

image_setup_initrd() {
  if [ -n "$IMAGE_INITRD_MODULES" ]; then
    run_log_priv "Configuring additional kernel modules in initrd" sed -i "s/^#PREMODS.*/PREMODS=\"$IMAGE_INITRD_MODULES\"/" "$IMAGE_MOUNT_DIR/etc/sysconfig/geninitrd"
  fi
  run_log_priv "Use lz4 compression for initrd" sed -i 's/^#COMPRESS.*/COMPRESS=lz4/' "$IMAGE_MOUNT_DIR/etc/sysconfig/geninitrd"
  run_log_priv "Use modprobe in initrd" tee -a "$IMAGE_MOUNT_DIR/etc/sysconfig/geninitrd" <<EOF
USE_MODPROBE=yes
EOF
  run_log_priv "Disable udev in initrd" sed -i "s/.*USE_UDEV=.*/USE_UDEV=no/" "$IMAGE_MOUNT_DIR/etc/sysconfig/geninitrd"
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
  if [ $ARCH = "aarch64" ]; then
    IMAGE_EFI_ENABLED=1
  fi
}

image_create_partitions_rpi() {
  local part_table next_part_nr=1
  IMAGE_FIRMWARE_DEVICE=${IMAGE_DEVICE}p$next_part_nr
  next_part_nr=$((next_part_nr + 1))
  part_table="label: dos\\nsize=${FIRMWARE_PART_SIZE_MB}MiB, type=c\\n$(image_efi_part)- - - *"
  if [ $? -eq 0 ]; then
    IMAGE_EFI_DEVICE=${IMAGE_DEVICE}p$next_part_nr
    next_part_nr=$((next_part_nr + 1))
  fi
  IMAGE_ROOT_DEVICE=${IMAGE_DEVICE}p$next_part_nr
  run_log_priv "Creating partition table on $IMAGE_DEVICE" sfdisk -q $IMAGE_DEVICE <<EOF
$(printf "$part_table")
EOF
}

image_create_fs_rpi() {
  run_log_priv "Creating vfat partition for boot firmware" mkfs.vfat -F 32 -n RPI_FW ${IMAGE_FIRMWARE_DEVICE}
  image_create_fs
}

image_install_bootloader_rpi() {
  poldek_install "Installing uboot" --root "$IMAGE_MOUNT_DIR" $(echo "$ARCH" | grep -q armv6 && echo uboot-image-raspberry-pi-zero) $(echo "$ARCH" | grep -q 'armv[67]' && echo uboot-image-raspberry-pi-2) $(echo "$ARCH" | grep -q 'aarch64' && echo uboot-image-raspberry-pi-arm64)
  if echo "$ARCH" | grep -q armv6; then
    run_log_priv "Copying uboot image for Raspberry Pi Zero W" cp "$IMAGE_MOUNT_DIR/usr/share/uboot/rpi_0_w/u-boot.bin" "$IMAGE_MOUNT_DIR/boot/firmware/uboot-rpi_0_w.bin"
    run_log_priv "Configuring uboot for Raspberry Pi Zero W" tee -a "$IMAGE_MOUNT_DIR/boot/firmware/config.txt" <<EOF
[pi0w]
kernel=uboot-rpi_0_w.bin
enable_uart=1
gpu_mem=32
EOF
  fi
  if echo "$ARCH" | grep -q 'armv[67]'; then
    run_log_priv "Copying uboot image for Raspberry Pi 2" cp "$IMAGE_MOUNT_DIR/usr/share/uboot/rpi_2/u-boot.bin" "$IMAGE_MOUNT_DIR/boot/firmware/uboot-rpi_2.bin"
    run_log_priv "Configuring uboot for Raspberry Pi 2" tee -a "$IMAGE_MOUNT_DIR/boot/firmware/config.txt" <<EOF
[pi2]
kernel=uboot-rpi_2.bin
EOF
  fi
  if echo "$ARCH" | grep -q 'aarch64'; then
    image_install_efi_bootloader
    run_log_priv "Copying uboot image for Raspberry Pi" cp "$IMAGE_MOUNT_DIR/usr/share/uboot/rpi_arm64/u-boot.bin" "$IMAGE_MOUNT_DIR/boot/firmware/uboot.bin"
    run_log_priv "Configuring uboot for Raspberry Pi" tee -a "$IMAGE_MOUNT_DIR/boot/firmware/config.txt" <<EOF
kernel=uboot.bin
arm_64bit=1
EOF
  fi
  run_log_priv "Configuring common boot params for all Raspberry Pis" tee -a "$IMAGE_MOUNT_DIR/boot/firmware/config.txt" <<EOF
[all]
upstream_kernel=1
enable_uart=1
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
  IMAGE_INITRD_MODULES="fixed gpio-regulator i2c-meson rtc-pcf8563 g12a pinctrl-meson-g12a reset-meson g12a-aoclk pwrseq_emmc mmc-block meson-gx-mmc"
  IMAGE_DISPLAY_ENABLED=1
  IMAGE_SOUND_ENABLED=1
}

image_install_bootloader_odroid_n2() {
  poldek_install "Installing uboot" --root "$IMAGE_MOUNT_DIR" uboot-image-odroid-n2
  run_log_priv "Writing uboot image" dd if="$IMAGE_MOUNT_DIR/usr/share/uboot/odroid-n2/u-boot.bin" of="$IMAGE_DEVICE" bs=512 seek=1 conv=notrunc,fsync
}

image_setup_params_pinebook_pro() {
  IMAGE_TYPE=pbp
  IMAGE_NAME=pinebook-pro
  IMAGE_DESC="Pinebook Pro"
  IMAGE_BOOT_PARAMS="earlycon=uart8250,mmio32,0xff1a0000 console=ttyS2,1500000n8 console=tty1"
  IMAGE_INITRD_MODULES="8250-dw pinctrl-rockchip i2c-rk3x fixed pl330 fan53555 rk8xx-i2c rk808-regulator pwm-rockchip pwm-bl rtc-rk808 gpio-rockchip sdhci_of_arasan dw_mmc_rockchip phy_rockchip_emmc mmc_block pcie-rockchip-host phy-rockchip-pcie nvme_core nvme phy_rockchip_inno_usb2 dwc3 dwc3_of_simple phy_rockchip_typec typec-extcon fusb302 rockchipdrm panel_edp"
  IMAGE_DISPLAY_ENABLED=1
  IMAGE_SOUND_ENABLED=1
  IMAGE_WIFI_ENABLED=1
}

image_install_bootloader_pbp() {
  poldek_install "Installing uboot" --root "$IMAGE_MOUNT_DIR" uboot-image-pinebook-pro
  run_log_priv "Writing pre-bootloader image" dd if="$IMAGE_MOUNT_DIR/usr/share/uboot/pinebook-pro-rk3399/idbloader.img" of=$IMAGE_DEVICE seek=64 conv=notrunc,fsync
  run_log_priv "Writing uboot image" dd if="$IMAGE_MOUNT_DIR/usr/share/uboot/pinebook-pro-rk3399/u-boot.itb" of=$IMAGE_DEVICE seek=16384 conv=notrunc,fsync
}

image_install_board_pkgs_pbp() {
  poldek_install "Installing linux-firmware bcm43456-firmware" --root "$IMAGE_MOUNT_DIR" linux-firmware bcm43456-firmware
}

image_setup_params_qemu() {
  IMAGE_TYPE=qemu
  IMAGE_NAME=qemu
  IMAGE_DESC="QEMU"
  IMAGE_FORMAT=qcow2
  IMAGE_EXT=qcow2
  IMAGE_DEVICE_TYPE=qemu-nbd
  IMAGE_EFI_ENABLED=1
  IMAGE_INITRD_MODULES="virtio-blk virtio-pci virtio_pci_modern_dev virtio-mmio"
}

image_create() {
  if [ ! -f "$SCRIPT_DIR/$RELEASE_NAME.tar.xz" ]; then
    error "$SCRIPT_DIR/$RELEASE_NAME.tar.xz does not exist"
  fi

  trap image_exit_handler EXIT INT HUP
  image_dispatch image_prepare_file
  image_dispatch image_create_device
  image_dispatch image_create_partitions
  run_log_priv "Probing for new partitions" partx -u $IMAGE_DEVICE
  image_dispatch image_create_fs
  IMAGE_MOUNT_DIR=$(mktemp -d)
  image_dispatch image_mount_fs
  run_log_priv "Extracting $RELEASE_NAME to $IMAGE_MOUNT_DIR" tar xf "$SCRIPT_DIR/$RELEASE_NAME.tar.xz" -C "$IMAGE_MOUNT_DIR"
  run_log_priv "Binding /dev to $IMAGE_MOUNT_DIR/dev" mount -o bind /dev "$IMAGE_MOUNT_DIR/dev"
  run_log_priv "Binding /proc to $IMAGE_MOUNT_DIR/proc" mount -o bind /proc "$IMAGE_MOUNT_DIR/proc"
  run_log_priv "Binding /sys to $IMAGE_MOUNT_DIR/sys" mount -o bind /sys "$IMAGE_MOUNT_DIR/sys"
  image_dispatch image_install_basic_pkgs
  image_dispatch image_systemd_setup
  image_dispatch image_prepare_fstab
  run_log_priv "Setting root password" chroot "$IMAGE_MOUNT_DIR" passwd <<EOF
pld
pld
EOF
  image_dispatch image_install_bootloader
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
  image_dispatch image_setup_bootloader
  poldek_install "Installing systemd-networkd" --root "$IMAGE_MOUNT_DIR" systemd-networkd
  if is_on "$IMAGE_WIFI_ENABLED"; then
    poldek_install "Installing iwd wireless-regdb" --root "$IMAGE_MOUNT_DIR" iwd wireless-regdb
  fi
  run_log_priv "Enabling networkd link handling" rm "$IMAGE_MOUNT_DIR/etc/udev/rules.d/80-net-setup-link.rules"
  run_log_priv "Auto-configure Ethernet devices with networkd" sh -c "cat > $IMAGE_MOUNT_DIR/etc/systemd/network/50-ether.network" <<EOF
[Match]
Type=ether

[Network]
DHCP=yes
EOF
  run_log_priv "Cleaning up poldek cache" rm -rf "$IMAGE_MOUNT_DIR/root/.poldek-cache"
  image_unmount_fs
  run_log "Compressing image" xz "$IMAGE_PATH"
}

image_sign() {
  if [ ! -f "$SCRIPT_DIR/$IMAGE_NAME-$RELEASE_NAME.$IMAGE_EXT.xz" ]; then
    error "$SCRIPT_DIR/$IMAGE_NAME-$RELEASE_NAME.$IMAGE_EXT.xz does not exist"
  fi
  echo "Signing image $IMAGE_NAME-$RELEASE_NAME.$IMAGE_EXT.xz"
  run_log 'Signing' gpg --sign --armor --detach-sig "$SCRIPT_DIR/$IMAGE_NAME-$RELEASE_NAME.$IMAGE_EXT.xz"
}

update_termux_proot() {
  cat <<EOF > termux-proot/pld-linux-arm.sh
DISTRO_NAME="PLD Linux Distribution"
TARBALL_URL['aarch64']="$RELEASE_DOWNLOAD_URL/$(release_name aarch64).tar.xz"
TARBALL_SHA256['aarch64']="$(sha256sum $SCRIPT_DIR/$(release_name aarch64).tar.xz | cut -f1 -d' ')"
if uname -m | grep -q armv7 && test -e /proc/cpuinfo && grep -q neon /proc/cpuinfo; then
TARBALL_URL['arm']="$RELEASE_DOWNLOAD_URL/$(release_name armv7hnl).tar.xz"
TARBALL_SHA256['arm']="$(sha256sum $SCRIPT_DIR/$(release_name armv7hnl).tar.xz | cut -f1 -d' ')"
else
TARBALL_URL['arm']="$RELEASE_DOWNLOAD_URL/$(release_name armv6hl).tar.xz"
TARBALL_SHA256['arm']="$(sha256sum $SCRIPT_DIR/$(release_name armv6hl).tar.xz | cut -f1 -d' ')"
fi
EOF
}

case "$1" in
  -c)
    shift
    echo Running in container: $DOCKER_TAG_LATEST
    exec podman run --cap-add SYS_CHROOT --rm -t -a=stdin -a=stderr -a=stdout -e ARCH=$ARCH -e PLD_ARM_IN_CONTAINER=1 -e RELEASE_TIMESTAMP=$RELEASE_TIMESTAMP -v="$SCRIPT_DIR:/pld-linux-arm" $DOCKER_TAG_LATEST "/pld-linux-arm/$(basename $0)" "$@"
    ;;
  create|sign)
    check_args_nr 1 "$@"
    ACTION=$1
    $1
    ;;
  publish)
    case "$2" in
      dockerhub)
        check_args_nr 2 "$@"
        ACTION=$1-$2
        $1_$2
        ;;
      dockerhub-multiarch)
        check_args_nr 2 "$@"
        ACTION=$1-$2
        $1_dockerhub_multiarch
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
        IMAGE_FORMAT=raw
        IMAGE_EXT=img
        IMAGE_DEVICE_TYPE=loop
        case "$3" in
          rpi|odroid-n2|pinebook-pro|qemu)
            check_args_nr 3 "$@"
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
  update)
    case "$2" in
      termux-proot)
        update_termux_proot
        ;;
      *)
        ACTION=unknown
        error "Unknown update action: $2"
        ;;
    esac
    ;;
  *)
    ACTION=unknown
    error "Unknown action: $1"
esac
