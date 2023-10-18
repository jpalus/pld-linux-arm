DISTRO_NAME="PLD Linux Distribution"
TARBALL_URL['aarch64']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20231018/pld-linux-base-aarch64-20231018.tar.xz"
TARBALL_SHA256['aarch64']="73c1cb0da7d6d17cfda2bbea965bc6274fea0a7a1fd96fac04f41c33bdde71dc"
if uname -m | grep -q armv7 && test -e /proc/cpuinfo && grep -q neon /proc/cpuinfo; then
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20231018/pld-linux-base-armv7hnl-20231018.tar.xz"
TARBALL_SHA256['arm']="9674604ddd4e29a51e01609bbee202bd65a0f51c9f462cb21978ea1c0bc5afe2"
else
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20231018/pld-linux-base-armv6hl-20231018.tar.xz"
TARBALL_SHA256['arm']="976c4de65d5e972aa857a5ca9003128eb3e8cc7b311b6e737a90991e31754aa7"
fi
