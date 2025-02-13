DISTRO_NAME="PLD Linux Distribution"
TARBALL_URL['aarch64']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20250213/pld-linux-base-aarch64-20250213.tar.xz"
TARBALL_SHA256['aarch64']="9c23f858b1a8a8d6c188b8651d2ff7c48d420dbfde39087cf237b43e6552413a"
if uname -m | grep -q armv7 && test -e /proc/cpuinfo && grep -q neon /proc/cpuinfo; then
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20250213/pld-linux-base-armv7hnl-20250213.tar.xz"
TARBALL_SHA256['arm']="8c35aac4d863c8fe28f6f5d8baea0b674e195c27d40a275448700d6d8cd417d5"
else
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-20250213/pld-linux-base-armv6hl-20250213.tar.xz"
TARBALL_SHA256['arm']="20943aea057b4fa44b63a3aaf8c1a9913923000ee717a9b4401fe98a8766bccc"
fi
