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
  run_log "Importing docker image $DOCKER_TAG" podman import "$SCRIPT_DIR/$RELEASE_NAME.tar.xz" $DOCKER_TAG
  run_log "Tagging docker image $DOCKER_TAG as latest" podman tag $DOCKER_TAG $DOCKER_TAG_LATEST
  run_log "Pushing docker tag $DOCKER_TAG" podman push $DOCKER_TAG
  run_log "Pushing docker tag $DOCKER_TAG_LATEST" podman push $DOCKER_TAG_LATEST
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
        error "Unknown publish target: $2"
        ;;
    esac
    ;;
  *)
    error "Unknown action: $1"
esac
