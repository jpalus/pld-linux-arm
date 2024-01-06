DISTRO_NAME="PLD Linux Distribution"
TARBALL_URL['aarch64']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20240106/pld-linux-base-aarch64-20240106.tar.xz"
TARBALL_SHA256['aarch64']="c89b4d45863823ef990c5508d087b19fbef00876e66dc4c9b8aff319ef73f280"
if uname -m | grep -q armv7 && test -e /proc/cpuinfo && grep -q neon /proc/cpuinfo; then
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20240106/pld-linux-base-armv7hnl-20240106.tar.xz"
TARBALL_SHA256['arm']="b6f5da1efa0a15ce3253245e97da27d56c5dd13d1f2f503dd7a2bac0ab5428da"
else
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20240106/pld-linux-base-armv6hl-20240106.tar.xz"
TARBALL_SHA256['arm']="9cd9b1ae1df0536cd7b78a9853524fdfcbbafd6adca48a36f970a33493c737a7"
fi
