DISTRO_NAME="PLD Linux Distribution"
TARBALL_URL['aarch64']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-aarch64-20260304.tar.xz"
TARBALL_SHA256['aarch64']="be6fcb200d95d3e6758a84658ed448ab3ed238d904d4cb2c6397b541d3bcaa5c"
if uname -m | grep -q armv7 && test -e /proc/cpuinfo && grep -q neon /proc/cpuinfo; then
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-armv7hnl-20260304.tar.xz"
TARBALL_SHA256['arm']="81f1b610754870ca6be4dcddf8cff4bfac665046b0266cc5a8d868dc329a7fcd"
else
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-armv6hl-20260304.tar.xz"
TARBALL_SHA256['arm']="a460b5645fa0f818669d5ad922aefe8d4fbbaff4f4dfc70f2957a2c77ad1306e"
fi
