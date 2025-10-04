DISTRO_NAME="PLD Linux Distribution"
TARBALL_URL['aarch64']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20251004/pld-linux-base-aarch64-20251004.tar.xz"
TARBALL_SHA256['aarch64']="edbe1f9ac1677504d2c892be7cae6805d264916a408da52c80547dd5051e1ab1"
if uname -m | grep -q armv7 && test -e /proc/cpuinfo && grep -q neon /proc/cpuinfo; then
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20251004/pld-linux-base-armv7hnl-20251004.tar.xz"
TARBALL_SHA256['arm']="9cc616f4e8cd99f8f813f0fa9da65ffdf03ca3a64e826481ffad2768428c657e"
else
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20251004/pld-linux-base-armv6hl-20251004.tar.xz"
TARBALL_SHA256['arm']="5ce6cb129e1c0c84be2bea7937208ef51878d963d41fce04833dd38020edc733"
fi
