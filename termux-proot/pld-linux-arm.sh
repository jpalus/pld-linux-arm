DISTRO_NAME="PLD Linux Distribution"
TARBALL_URL['aarch64']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-aarch64-20261108.tar.xz"
TARBALL_SHA256['aarch64']="7d0a49dcdac04806c10ad3ed7b31bb87b9927dfe5f67bc0ea2c0be25d372d96f"
if uname -m | grep -q armv7 && test -e /proc/cpuinfo && grep -q neon /proc/cpuinfo; then
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-armv7hnl-20261108.tar.xz"
TARBALL_SHA256['arm']="c46410b9432379c448465aca5513b7ce6e1e3d73c65e736a244f5e5f7ec6d5a5"
else
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-armv6hl-20261108.tar.xz"
TARBALL_SHA256['arm']="204f5192e6e758364a5e0276050da244c495e619b6158d14d450ce7230e5ba4c"
fi
