DISTRO_NAME="PLD Linux Distribution"
TARBALL_URL['aarch64']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-aarch64-20251215.tar.xz"
TARBALL_SHA256['aarch64']="9d86e822619fa5a8111b4823ab9f97b9caef7f5c670669cf4d9fb8d6e7922887"
if uname -m | grep -q armv7 && test -e /proc/cpuinfo && grep -q neon /proc/cpuinfo; then
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-armv7hnl-20251215.tar.xz"
TARBALL_SHA256['arm']="f2252ffa746785fcae540be846279b967dca50b4e517289cee87db29488a96a6"
else
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-armv6hl-20251215.tar.xz"
TARBALL_SHA256['arm']="4e6a76173b528e66ddab6538e673291d895b7d627b134e9b1509f806d40a897d"
fi
