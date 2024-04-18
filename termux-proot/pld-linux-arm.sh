DISTRO_NAME="PLD Linux Distribution"
TARBALL_URL['aarch64']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20240418/pld-linux-base-aarch64-20240418.tar.xz"
TARBALL_SHA256['aarch64']="37fc99093856de1a14bf8af3c969e6a551e9603489a79df38e588bc1b0586127"
if uname -m | grep -q armv7 && test -e /proc/cpuinfo && grep -q neon /proc/cpuinfo; then
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20240418/pld-linux-base-armv7hnl-20240418.tar.xz"
TARBALL_SHA256['arm']="e59919189ebd587067cd76801481a79103d329252e1a2d6b4e1320d588a66cd4"
else
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20240418/pld-linux-base-armv6hl-20240418.tar.xz"
TARBALL_SHA256['arm']="6ff64593ad724c3ecae4e7f1058c9b690db56cb663c48a7d3121639fae3df78e"
fi
