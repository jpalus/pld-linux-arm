DISTRO_NAME="PLD Linux Distribution"
TARBALL_URL['aarch64']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20240818/pld-linux-base-aarch64-20240818.tar.xz"
TARBALL_SHA256['aarch64']="b9c571c99f7b6a527e022a4f78f08a80507e1a04dceba29ad1501f0c7d98fda8"
if uname -m | grep -q armv7 && test -e /proc/cpuinfo && grep -q neon /proc/cpuinfo; then
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20240818/pld-linux-base-armv7hnl-20240818.tar.xz"
TARBALL_SHA256['arm']="b372a40980cafd0bb9a374ba8043c55564ef37957a17f5adeacc9892d55e64e4"
else
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20240818/pld-linux-base-armv6hl-20240818.tar.xz"
TARBALL_SHA256['arm']="ea8f13119388e5d47e004bf2dbe870ee41fbf8b6f4c61b182a9b11bce712fa5a"
fi
