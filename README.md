# windows-usb-image-sh

Bash script for copying Windows ISO images (or any ISO) to block devices

## RPM build status

<a href="https://copr.fedorainfracloud.org/coprs/socminarch/windows-usb-image-sh/package/windows-usb-image-sh/"><img src="https://copr.fedorainfracloud.org/coprs/socminarch/windows-usb-image-sh/package/windows-usb-image-sh/status_image/last_build.png" /></a>

## Required arguments
* `-s`    Source image file
* `-d`    Destination block device
* `-c`    SHA256 checksum of source image file
* `-C|-D` Specify whether to use Copy Mode (`-C`) or DD Mode (`-D`)

## Optional arguments
* `-E`    Specify to use exFAT instead of FAT32
* `-b`    Partition block size

## Copy Mode
Copy Mode will format the destination block device with an MBR partition table and create a FAT32 partition on it. This partition contains the source image file contents. The Windows `install.wim` file will be split into blocks of 4000MB to avoid FAT32 file size limitations. Optionally, the created partition can be formatted with exFAT instead, bypassing the FAT32 file size limitation.

This USB should be compatible with both BIOS and UEFI when formatted as FAT32. UEFI compatability is not guaranteed with exFAT filesystems.

## DD Mode
DD Mode will use `dd` to clone the source image onto the destination block device. Copying will not be performed if the destination block devices checksum is the same as that of the source images.