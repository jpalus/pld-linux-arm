DISTRO_NAME="PLD Linux Distribution"
TARBALL_URL['aarch64']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20230809/pld-linux-base-aarch64-20230809.tar.xz"
TARBALL_SHA256['aarch64']="f4ecc643e5c20064f7f7010f2283b1d953095ee1414091fc3edefa95620fab73"
if uname -m | grep -q armv7 && test -e /proc/cpuinfo && grep -q neon /proc/cpuinfo; then
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20230809/pld-linux-base-armv7hnl-20230809.tar.xz"
TARBALL_SHA256['arm']="b69f5433367b9a6b6760a6f6e84ae40a6b75c82dd6bd96c729cff75e89387fb3"
else
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20230809/pld-linux-base-armv6hl-20230809.tar.xz"
TARBALL_SHA256['arm']="8e07ac0f8b2f859ee03148c7d96fd52e6bb5daf05b368872dde7f5f64114ebcb"
fi
