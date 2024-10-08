DISTRO_NAME="PLD Linux Distribution"
TARBALL_URL['aarch64']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20241009/pld-linux-base-aarch64-20241009.tar.xz"
TARBALL_SHA256['aarch64']="94a62fa0455688095cab642447893116161a866e0b3f0c17c6d7f6c908abe88f"
if uname -m | grep -q armv7 && test -e /proc/cpuinfo && grep -q neon /proc/cpuinfo; then
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20241009/pld-linux-base-armv7hnl-20241009.tar.xz"
TARBALL_SHA256['arm']="419f1fc8c7e7222231bb7fa45dac551bff76f8bc74de2570e2579e845c3a410d"
else
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20241009/pld-linux-base-armv6hl-20241009.tar.xz"
TARBALL_SHA256['arm']="0f83ad7d21c9e0e10a7416d99db1551867cd3682a3085b4980f2f43c2e9063a3"
fi
