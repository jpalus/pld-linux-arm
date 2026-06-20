DISTRO_NAME="PLD Linux Distribution"
TARBALL_URL['aarch64']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-aarch64-20260620.tar.xz"
TARBALL_SHA256['aarch64']="67a1cb8a02fcbe93228ddc40cdb8e1d12dc216f56ddb5aca41d6456d53369874"
if uname -m | grep -q armv7 && test -e /proc/cpuinfo && grep -q neon /proc/cpuinfo; then
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-armv7hnl-20260620.tar.xz"
TARBALL_SHA256['arm']="f5c92f8917032ee12b98232a58e04cff5ae52cbc942de3eb3683b9c88cd9c40b"
else
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-armv6hl-20260620.tar.xz"
TARBALL_SHA256['arm']="28b7d4566b3701b266c941ed25c9eb34d337ede9448b41b225ba3fed23751c95"
fi
