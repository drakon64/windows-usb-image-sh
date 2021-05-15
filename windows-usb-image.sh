#!/bin/bash -e

USAGE='windows-usb-image-sh\n\nBash script for copying disk images to block devices\n\nRequired arguments:\n-s    Source image file\n-d    Destination block device (/dev/disk/by-id/)\n-c    SHA1 checksum of source image file\n-C|-D Specify whether to use Copy Mode (-C) or DD Mode (-D)\n\nOptional arguments:\n-b    Partition block size\n-h    Show help\n-H    Show full help\n'
FULL_USAGE='\nCopy Mode:\nCopy Mode will create a 512KB FAT32 partition at the start of the block device, and an NTFS partition in the remaining space. The FAT32 partition contains the UEFI:NTFS bootloader, and the NTFS partition contains the source image file contents.\n\nDD Mode:\nDD Mode will use "dd" to clone the source image onto the destination block device. Copying will not be performed if the destination block devices checksum is the same as that of the source images.\n'

#shellcheck disable=SC2059
usage()
{
	printf "$USAGE"
	exit 0
}

#shellcheck disable=SC2059
full_usage()
{
	printf "$USAGE"
	printf "$FULL_USAGE"
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

disk_mode()
{
	if [[ "$DISK" = /dev/disk/by-id/* ]] ; then
		UEFI_PART=-part1
		NTFS_PART=-part2
	elif [[ "$DISK" = /dev/sd* ]] || [[ "$DISK" = /dev/hd* ]] ; then
		UEFI_PART=1
		NTFS_PART=2
	elif [[ "$DISK" = /dev/nvme* ]] ; then
		UEFI_PART=p1
		NTFS_PART=p2
	elif [[ "$DISK" = /dev/disk* ]] ; then
		UEFI_PART=s1
		NTFS_PART=s2
	else
		echo Unknown block device path
		exit 1
	fi
}

os()
{
	UNAME="$(uname -s)"	

	if [ "$UNAME" = "Linux" ] ; then
		STAT=-c "%s"
	elif [ "$UNAME" = "BSD" ] || [ "$UNAME" = "Darwin" ] ; then
		STAT=-f%z
	else
		echo Unknown OS
		exit 1
	fi
}

cp_checksum()
{
	os

	if ! [ "$UNAME" = "Linux" ] ; then
		echo "Copy Mode is currently only supported under Linux"
		exit 1
	fi

	unmount
	iso_checksum
	disk_mode

	echo Partitioning the USB
	(
		echo g
		echo n
		echo
		echo
		echo +512K
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
	curl https://github.com/pbatard/rufus/raw/master/res/uefi/uefi-ntfs.img -o "$UEFI_NTFS"

	if [ -z "$BLOCK_SIZE" ] ; then
		echo Creating the Windows partition
		mkfs.ntfs -Q "$DISK$NTFS_PART"
	else
		echo Creating the Windows partition
		mkfs.ntfs -Q -s "$BLOCK_SIZE" "$DISK$NTFS_PART"
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

	exit
}

uefi()
{
	os

	echo Copying UEFI:NTFS
	UEFI_NTFS_CHECKSUM=$(sha1sum "$UEFI_NTFS" | awk '{print $1}')
	if [ -z "$BLOCK_SIZE" ] ; then
		dd if="$UEFI_NTFS" of="$DISK$UEFI_PART" || echo Failed to copy UEFI:NTFS to the UEFI partition
	else
		dd if="$UEFI_NTFS" of="$DISK$UEFI_PART" bs="$BLOCK_SIZE" || echo Failed to copy UEFI:NTFS to the UEFI partition
	fi
	if [ "$(head -c "$(stat "$STAT" "$UEFI_NTFS")" "$DISK$UEFI_PART" | sha1sum | awk '{print $1}')" = "$UEFI_NTFS_CHECKSUM" ] ; then
		echo The UEFI partition passed the checksum
	else
		echo The UEFI partition failed the checksum
	fi
	rm "$UEFI_NTFS"
}

windows()
{
	echo Generating checksums for the Windows partition files
	CHECKSUM_FILE_WINDOWS=$(mktemp)
	cd "$LOOP"
	find . -type f -exec sha1sum {} \; >> "$CHECKSUM_FILE_WINDOWS"

	echo Mounting the Windows partition
	WINDOWS=$(mktemp -d)
	mount "$DISK$NTFS_PART" "$WINDOWS"

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
	disk_mode
	os

	if [ "$(head -c "$(stat $STAT "$ISO")" "$DISK" | sha1sum | awk '{print $1}')" = "$CHECKSUM" ] ; then
		echo The USB already matches the ISO
		exit 0
	elif [ -z "$BLOCK_SIZE" ] ; then
		dd if="$ISO" of="$DISK"
	else
		dd if="$ISO" of="$DISK" bs="$BLOCK_SIZE"
	fi

	if [ "$(head -c "$(stat $STAT "$ISO")" "$DISK" | sha1sum | awk '{print $1}')" = "$CHECKSUM" ] ; then
		echo The USB has passed the checksum
		udisksctl unmount -b "$DISK" || true
		exit 0
	else
		echo The USB has failed the checksum
		udisksctl unmount -b "$DISK" || true
		exit 1
	fi
}

while getopts "s:d:c:b:CDhH" arg ; do
	case $arg in
		h)
			usage
			;;
		H)
			full_usage
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

usage
