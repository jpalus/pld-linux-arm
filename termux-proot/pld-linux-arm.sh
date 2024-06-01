DISTRO_NAME="PLD Linux Distribution"
TARBALL_URL['aarch64']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20240601/pld-linux-base-aarch64-20240601.tar.xz"
TARBALL_SHA256['aarch64']="20288a5c1cb996523fe96815202fd1d8eaf0d4f5bf9a9d342189aaee31953888"
if uname -m | grep -q armv7 && test -e /proc/cpuinfo && grep -q neon /proc/cpuinfo; then
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20240601/pld-linux-base-armv7hnl-20240601.tar.xz"
TARBALL_SHA256['arm']="de95cb00db24e982a028a16aed8c90e811f216f79d452be1341052c0a79e21eb"
else
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20240601/pld-linux-base-armv6hl-20240601.tar.xz"
TARBALL_SHA256['arm']="a9c6706be3ac3309aaed16326c164e2fd1f45619f7519a386692d2c630a6dca3"
fi
