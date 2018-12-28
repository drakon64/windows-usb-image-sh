#!/bin/sh -e

usage()
{
	echo 'windows-usb-image-sh

Shell script for copying disk images to block devices

Required arguments:
-s    Source image file
-d    Destination block device (/dev/disk/by-id/)
-c    SHA1 checksum of source image file"
-C|-D Specify whether to use Copy Mode (-C) or DD Mode (-D)

Optional arguments:
-b    Partition block size

Copy Mode:
Copy Mode will create a 512KB FAT32 partition at the start of the block device, and an NTFS partition in the remaining space. The FAT32 partition contains the UEFI:NTFS bootloader, and the NTFS partition contains the source image file contents.

DD Mode:
DD Mode will use "dd" to clone the source image onto the destination block device. Copying will not be performed if the destination block devices checksum is the same as that of the source images.'
	exit 0
}

unmount()
{
	echo Unmounting the USB
	udisksctl unmount -b "$DISK" || true
}

iso_checksum()
{
	CHECKSUM=$(echo "$CHECKSUM" | awk '{print tolower($0)}')

	if [ "$(sha1sum "$ISO" | awk '{print $1}')" = "$CHECKSUM" ] ; then
		echo The ISO file passed the checksum
	else
		echo The ISO file failed the checksum
		exit 1
	fi
}

cp_checksum()
{
	unmount
	iso_checksum

	echo Partitioning the USB
	(
		echo g
		echo n
		echo
		echo
		echo +1K
		echo t
		echo 1
		echo n
		echo
		echo
		echo
		echo t
		echo 2
		echo 1
		echo w
	) | fdisk "$DISK" || partprobe && sleep 3

	echo Downloading UEFI:NTFS
	UEFI_NTFS="$(mktemp)"
	wget https://github.com/pbatard/rufus/raw/master/res/uefi/uefi-ntfs.img -O "$UEFI_NTFS"

	if [ -z "$BLOCK_SIZE" ] ; then
		echo Creating the Windows partition
		mkfs.ntfs -Q "$DISK"-part2
	else
		echo Creating the Windows partition
		mkfs.ntfs -Q -s "$BLOCK_SIZE" "$DISK"-part2
	fi

	echo Mounting the Windows ISO
	LOOP=$(mktemp -d)
	mount "$ISO" -o loop,ro "$LOOP"

	CURRENT_PWD=$(pwd)

	uefi &
	windows &
	wait

	echo Unmounting the Windows ISO
	umount "$LOOP"

	echo Cleaning up
	rmdir "$LOOP"
}

uefi()
{
	if [ -z "$BLOCK_SIZE" ] ; then
		echo Copying UEFI:NTFS
		dd if="$UEFI_NTFS" of="$DISK"-part1 count=1
		rm "$UEFI_NTFS"
	else
		echo Copying UEFI:NTFS
		dd if="$UEFI_NTFS" of="$DISK"-part1 bs="$BLOCK_SIZE" count=1
		rm "$UEFI_NTFS"
	fi
}

windows()
{
	echo Generating checksums for the Windows partition files
	CHECKSUM_FILE_WINDOWS=$(mktemp)
	cd "$LOOP"
	find . -type f -exec sh -c "sha1sum {} >> $CHECKSUM_FILE_WINDOWS" \;

	echo Mounting the Windows partition
	WINDOWS=$(mktemp -d)
	mount "$DISK"-part2 "$WINDOWS"

	echo Copying the Windows partition files
	cp -r "$LOOP"/* "$WINDOWS"
	cd "$WINDOWS"
	echo Validating the Windows partition files
	if sha1sum --status -c "$CHECKSUM_FILE_WINDOWS" ; then
		echo The Windows partition passed the checksum
		rm "$CHECKSUM_FILE_WINDOWS"
		cd "$CURRENT_PWD"
		echo Unmounting the Windows partition
	else
		echo The Windows partition failed the checksum
		rm "$CHECKSUM_FILE_WINDOWS"
		cd "$CURRENT_PWD"
		echo Unmounting the Windows partition
	fi
	umount "$WINDOWS"
	rmdir "$WINDOWS"
}

dd_checksum()
{
	unmount
	iso_checksum

	if [ "$(head -c "$(stat -c "%s" "$ISO")" "$DISK" | sha1sum | awk '{print $1}')" = "$CHECKSUM" ] ; then
		echo The USB has passed the checksum
		exit 0
	elif [ -z "$BLOCK_SIZE" ] ; then
		dd if="$ISO" of="$DISK"
	else
		dd if="$ISO" of="$DISK" bs="$BLOCK_SIZE"
	fi
	if [ "$(head -c "$(stat -c "%s" "$ISO")" "$DISK" | sha1sum | awk '{print $1}')" = "$CHECKSUM" ] ; then
		echo The USB has passed the checksum
		udisksctl unmount -b "$DISK" || true
		exit 0
	else
		echo The USB has failed the checksum
		udisksctl unmount -b "$DISK" || true
		exit 1
	fi
}

while getopts "h:s:d:c:b:C:D" arg ; do
	case $arg in
		h)
			usage
			;;
		s)
			ISO=$OPTARG
			;;
		d)
			DISK=$OPTARG
			;;
		c)
			CHECKSUM=$OPTARG
			;;
		b)
			BLOCK_SIZE=$OPTARG
			;;
		C)
			cp_checksum
			;;
		D)
			dd_checksum
			;;
		*)
			usage
			;;
	esac
done
