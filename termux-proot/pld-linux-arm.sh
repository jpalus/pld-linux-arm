DISTRO_NAME="PLD Linux Distribution"
TARBALL_URL['aarch64']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20240209/pld-linux-base-aarch64-20240209.tar.xz"
TARBALL_SHA256['aarch64']="306a15b27c0daf6051d19ea7102fc9a4d226b9fdb6a8076f48cd0d6a2471c63d"
if uname -m | grep -q armv7 && test -e /proc/cpuinfo && grep -q neon /proc/cpuinfo; then
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20240209/pld-linux-base-armv7hnl-20240209.tar.xz"
TARBALL_SHA256['arm']="e9ba93bfeab4812724e77177fcb910f5f435c6088bfcf9c8133b86f87efeec85"
else
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20240209/pld-linux-base-armv6hl-20240209.tar.xz"
TARBALL_SHA256['arm']="617734333a51bda16eb6c2059e8985e210af737288df8d1ed2d4cd6dc564faf2"
fi
