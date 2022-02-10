chroots with unofficial port of [PLD Linux](https://www.pld-linux.org) to **armv6hl**, **armv7hnl** and **aarch64** architectures.

Tested as primary OS on following devices:
* aarch64 port
  * *Pinebook Pro*
  * *Odroid N2+*

* armv7hnl port
  * *Raspberry Pi 2*
  * *Turris Omnia*

* armv6hl port
  * *Raspberry Pi Zero W*

Docker images available at [Docker Hub](https://hub.docker.com/u/jpalus).

Bootable images:

**Raspberry Pi**
* `raspberry-pi-pld-linux-base-armv6hl` bootable on Raspberry Pi Zero W and Raspberry Pi 2, `raspberry-pi-pld-linux-base-armv7hnl` bootable on Raspberry Pi 2
* requires at least 1GB of storage
* write image to SD card ie:
```
xz -dc raspberry-pi-pld-linux-base-armv7hnl-20211102.img.xz | dd of=/dev/mmcblk1 bs=4M
```
* root password: *pld*

**Odroid N2/N2+**
* requires at least 1GB of storage
* write image to SD card ie:
```
xz -dc odroid-n2-pld-linux-base-aarch64-20211202.img.xz | dd of=/dev/mmcblk1 bs=4M
```

**Pinebook Pro**
* requires at least 1GB of storage
* write image to SD card ie:
```
xz -dc pinebook-pro-pld-linux-base-aarch64-20220210.img.xz | dd of=/dev/mmcblk1 bs=4M
```
* root password: *pld*
