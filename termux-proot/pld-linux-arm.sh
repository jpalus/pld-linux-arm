DISTRO_NAME="PLD Linux Distribution"
TARBALL_URL['aarch64']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-aarch64-20261012.tar.xz"
TARBALL_SHA256['aarch64']="9d797b13dc571f64a0e82340e9cb4565f26e0566802eebd1dadd24e39501560b"
if uname -m | grep -q armv7 && test -e /proc/cpuinfo && grep -q neon /proc/cpuinfo; then
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-armv7hnl-20261012.tar.xz"
TARBALL_SHA256['arm']="4287d26b18fefac4e281677a1c992e9919385f1e0948e4b2a33495d705f77eba"
else
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-armv6hl-20261012.tar.xz"
TARBALL_SHA256['arm']="e49e36351a665ab5fc18ac39d831f131331d0a65128d68b1bd35b0fe9d94bd78"
fi
