#!/bin/bash -e

USAGE='windows-usb-image-sh\n\nBash script for copying Windows ISO images (or any ISO) to block devices\n\nRequired arguments:\n-s    Source image file\n-d    Destination block device (/dev/disk/by-id/)\n-c    SHA1 checksum of source image file\n-C|-D Specify whether to use Copy Mode (-C) or DD Mode (-D)\n\nOptional arguments:\n-b    Partition block size\n-h    Show help\n-H    Show full help\n'
FULL_USAGE='\nCopy Mode:\nCopy Mode will format the destination block device with an MBR partition table and create a FAT32 partition on it. This partition contains the source image file contents. The Windows "install.wim" file will be split into blocks of 1000MB to avoid FAT32 file size limitations.\n\nThis USB should be compatible with both BIOS and UEFI.\n\nDD Mode:\nDD Mode will use "dd" to clone the source image onto the destination block device. Copying will not be performed if the destination block devices checksum is the same as that of the source images.\n'

usage()
{
	printf "%b" "$USAGE"
	exit 0
}

full_usage()
{
	printf "%b" "$USAGE"
	printf "%b" "$FULL_USAGE"
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
		STAT="-f%z"
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

check_if_writeable()
{
	if ! [ -w "$DISK" ] ; then
		echo Cannot write to "$DISK": Permission denied
		exit 1
	fi
}

cp_checksum()
{
	disk_mode
	check_if_writeable
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
		(
			echo edit 1
			echo EF
			echo
			echo
			echo
			echo flag 1
			echo quit
			echo y
		) | fdisk -e "$DISK"
		PART_MOUNT="/Volumes/WIN"
	else
		(
			echo o
			echo n
			echo
			echo
			echo
			echo
			echo t
			echo ef
			echo a
			echo w
		) | fdisk "$DISK" || partprobe && sleep 3
		mkfs.fat -F 32 "$DISK""$PART"
		PART_MOUNT=$(mktemp -d)
		mount "$DISK""$PART" "$PART_MOUNT"
	fi

	echo Generating checksums for the Windows partition files
	CHECKSUM_FILE_WINDOWS=$(mktemp)
	find "$LOOP" -type f \( ! -iname "install.wim" \) -exec sha1sum {} \; >> "$CHECKSUM_FILE_WINDOWS"
	if [ "$UNAME" = "BSD" ] || [ "$UNAME" = "Darwin" ] ; then
		sed -i ".bak" "s#$LOOP/##g" "$CHECKSUM_FILE_WINDOWS"
	else
		sed -i "s#$LOOP/##g" "$CHECKSUM_FILE_WINDOWS"
	fi

	echo Copying the Windows ISO files
	rsync -qcah --exclude=sources/install.wim "$LOOP"/* "$PART_MOUNT"

	echo Splitting the Windows "install.wim" file
	TEMPWIM=$(mktemp -d)
	wimsplit "$LOOP"/sources/install.wim "$TEMPWIM"/install.swm 1000 --check

	echo Generating checksums for the split "install.wim" file
	CHECKSUM_FILE_TEMPWIM=$(mktemp)
	find "$TEMPWIM" -type f -exec sha1sum {} \; >> "$CHECKSUM_FILE_TEMPWIM"
	if [ "$UNAME" = "BSD" ] || [ "$UNAME" = "Darwin" ] ; then
		sed -i ".bak" "s#$TEMPWIM/##g" "$CHECKSUM_FILE_TEMPWIM"
	else
		sed -i "s#$TEMPWIM/##g" "$CHECKSUM_FILE_TEMPWIM"
	fi

	echo Moving the split "install.wim" to the USB
	mv "$TEMPWIM"/install*.swm "$PART_MOUNT"/sources/

	echo Removing the temporary "install.wim" directory
	rmdir "$TEMPWIM"

	echo Validating the Windows partition files
	if cd "$PART_MOUNT" ; sha1sum --status -c "$CHECKSUM_FILE_WINDOWS" ; then
		echo The Windows partition passed the checksum
	else
		WINDOWS_FAILED=true
		echo The Windows partition failed the checksum
	fi
	rm "$CHECKSUM_FILE_WINDOWS"

	echo Validating the Windows "install.wim" files
	if cd "$PART_MOUNT/sources" ; sha1sum --status -c "$CHECKSUM_FILE_TEMPWIM" ; then
		echo The Windows "install.wim" files passed the checksum
	else
		WIM_FAILED=true
		echo The Windows "install.wim" files failed the checksum
	fi
	rm "$CHECKSUM_FILE_TEMPWIM"

	unmount || true

	echo Unmounting the Windows ISO
	umount "$LOOP"

	if ! [ "$UNAME" = "Darwin" ] ; then
		echo Cleaning up
		rmdir "$LOOP" "$PART_MOUNT"
	fi

	if [ -n "$WINDOWS_FAILED" ] || [ -n "$WIM_FAILED" ] ; then
		exit 0
	else
		exit 1
	fi
}

dd_checksum()
{
	disk_mode
	check_if_writeable
	os
	unmount
	iso_checksum

	echo Checking if the USB already matches the ISO
	if [ "$(head -c "$(stat "$STAT" "$ISO")" "$DISK" | sha1sum | awk '{print $1}')" = "$CHECKSUM" ] ; then
		echo The USB already matches the ISO
		exit 0
	elif [ -z "$BLOCK_SIZE" ] ; then
		echo Writing the ISO to the USB
		dd if="$ISO" of="$DISK"
	else
		echo Writing the ISO to the USB
		dd if="$ISO" of="$DISK" bs="$BLOCK_SIZE"
	fi

	echo Checking the USB integrity
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
