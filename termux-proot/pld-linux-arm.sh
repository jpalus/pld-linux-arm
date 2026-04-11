DISTRO_NAME="PLD Linux Distribution"
TARBALL_URL['aarch64']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-aarch64-20260411.tar.xz"
TARBALL_SHA256['aarch64']="00f409fd624135ce350571bb93df9b5ba56f6dd095485838857d6513b79d571b"
if uname -m | grep -q armv7 && test -e /proc/cpuinfo && grep -q neon /proc/cpuinfo; then
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-armv7hnl-20260411.tar.xz"
TARBALL_SHA256['arm']="43a446e20e4b58b247fcfdace8c88bf58e8267eb8eee78980c8e72c4e6df3951"
else
TARBALL_URL['arm']="https://github.com/jpalus/pld-linux-arm/releases/download/pld-linux-arm-/pld-linux-base-armv6hl-20260411.tar.xz"
TARBALL_SHA256['arm']="a309c2e5ce7142053ea3789fda6d196523c686ec11cc87db019a5071acb370f5"
fi
