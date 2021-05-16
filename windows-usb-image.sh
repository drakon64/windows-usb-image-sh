#!/bin/bash -e

USAGE='windows-usb-image-sh\n\nBash script for copying disk images to block devices\n\nRequired arguments:\n-s    Source image file\n-d    Destination block device (/dev/disk/by-id/)\n-c    SHA1 checksum of source image file\n-C|-D Specify whether to use Copy Mode (-C) or DD Mode (-D)\n\nOptional arguments:\n-b    Partition block size\n-h    Show help\n-H    Show full help\n'
FULL_USAGE='\nCopy Mode (Linux only):\nCopy Mode will create a 512KB FAT32 partition at the start of the block device, and an NTFS partition in the remaining space. The FAT32 partition contains the UEFI:NTFS bootloader, and the NTFS partition contains the source image file contents.\n\nDD Mode:\nDD Mode will use "dd" to clone the source image onto the destination block device. Copying will not be performed if the destination block devices checksum is the same as that of the source images.\n'

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

os()
{
	UNAME="$(uname -s)"	

	if [ "$UNAME" = "Linux" ] ; then
		UNMOUNT="udisksctl"
		UNMOUNT_ARGS="unmount -b"

		STAT=-c "%s"
	elif [ "$UNAME" = "BSD" ] || [ "$UNAME" = "Darwin" ] ; then
		if [ "$UNAME" = "Darwin" ] ; then
			UNMOUNT="diskutil"
			UNMOUNT_ARGS="unmountDisk"
		else
			UNMOUNT="udisksctl"
			UNMOUNT_ARGS="unmount -b"
		fi
		STAT=-f%z
	else
		echo Unknown OS
		exit 1
	fi
}

unmount()
{
	echo Unmounting the USB
	"$UNMOUNT" "$UNMOUNT_ARGS" "$DISK"
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
		PART=-part1
	elif [[ "$DISK" = /dev/sd* ]] || [[ "$DISK" = /dev/hd* ]] ; then
		PART=1
	elif [[ "$DISK" = /dev/nvme* ]] ; then
		PART=p1
	elif [[ "$DISK" = /dev/disk* ]] ; then
		PART=s1
	else
		echo Unknown block device path
		exit 1
	fi
}

cp_checksum()
{
	os
	unmount
	iso_checksum

	echo Mounting the Windows ISO
	if ! [ "$UNAME" = "Darwin" ] ; then
		LOOP=$(mktemp -d)
		mount "$ISO" -o loop,ro "$LOOP"
	else
		LOOP=$(hdiutil mount "$ISO" | awk '{ print $2 }')
	fi

	echo Formatting the USB drive as FAT32
	if [ "$UNAME" = "Darwin" ] ; then
		diskutil eraseDisk FAT32 WIN MBR "$DISK"
		PART_MOUNT="/Volumes/WIN/"
	else
		(
			echo g
			echo n
			echo
			echo
			echo 
			echo t
			echo 1
			echo 1
			echo w
		) | fdisk "$DISK" || partprobe && sleep 3
		mkfs.fat -F F32 "$DISK""$PART"
		PART_MOUNT=$(mktemp -d)
		mount -o loop "$DISK""$PART" "$PART_MOUNT"
	fi

	echo Generating checksums for the Windows partition files
	CHECKSUM_FILE_WINDOWS=$(mktemp)
	find "$LOOP" -type f \( ! -iname "install.wim" \) -exec sha1sum {} \; >> "$CHECKSUM_FILE_WINDOWS"

	echo Copying the Windows ISO files
	rsync -qah --exclude=sources/install.wim "$LOOP"/* "$PART_MOUNT"

	echo Splitting the Windows 10 install.wim file
	wimsplit "$LOOP"/sources/install.wim /Volumes/WIN/sources/install.swm 1000 --check

	echo Validating the Windows partition files
	if $(cd "$PART_MOUNT" ; sha1sum --status -c "$CHECKSUM_FILE_WINDOWS") ; then
		echo The Windows partition passed the checksum
	else
		FAILED=true
		echo The Windows partition failed the checksum
	fi
	rm "$CHECKSUM_FILE_WINDOWS"

	unmount || true
	
	echo Unmounting the Windows ISO
	umount "$LOOP"

	if ! [ "$UNAME" = "Darwin" ] ; then
		echo Cleaning up
		rmdir "$LOOP" "$PART_MOUNT" 
	fi
	
	if ! [ -z "$FAILED" ] ; then
	exit 0
	else
		exit 1
	fi
}

dd_checksum()
{
	unmount
	iso_checksum
	disk_mode
	os

	if [ "$(head -c "$(stat "$STAT" "$ISO")" "$DISK" | sha1sum | awk '{print $1}')" = "$CHECKSUM" ] ; then
		echo The USB already matches the ISO
		exit 0
	elif [ -z "$BLOCK_SIZE" ] ; then
		dd if="$ISO" of="$DISK"
	else
		dd if="$ISO" of="$DISK" bs="$BLOCK_SIZE"
	fi

	if [ "$(head -c "$(stat "$STAT" "$ISO")" "$DISK" | sha1sum | awk '{print $1}')" = "$CHECKSUM" ] ; then
		echo The USB has passed the checksum
		unmount || true
		exit 0
	else
		echo The USB has failed the checksum
		unmount || true
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
