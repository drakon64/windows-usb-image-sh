# windows-usb-image-sh

Bash script for copying disk images to block devices

## Required arguments
* `-s`    Source image file
* `-d`    Destination block device (`/dev/disk/by-id/`)
* `-c`    SHA1 checksum of source image file
* `-C|-D` Specify whether to use Copy Mode (`-C`) or DD Mode (`-D`)

## Optional arguments
* `-b`    Partition block size

## Copy Mode
Copy Mode will create a 512KB FAT32 partition at the start of the block device, and an NTFS partition in the remaining space. The FAT32 partition contains the UEFI:NTFS bootloader, and the NTFS partition contains the source image file contents.

## DD Mode
DD Mode will use `dd` to clone the source image onto the destination block device. Copying will not be performed if the destination block devices checksum is the same as that of the source images.

<a href="https://copr.fedorainfracloud.org/coprs/socminarch/windows-usb-image-sh/package/windows-usb-image-sh/"><img src="https://copr.fedorainfracloud.org/coprs/socminarch/windows-usb-image-sh/package/windows-usb-image-sh/status_image/last_build.png" /></a>
