#!/bin/sh -e

usage()
{
	echo "Usage: $0 -s <iso file> -d <destination block device> -c <iso sha1 checksum> [-b <partiton block size>] [--dd <run in DD mode>] [-h <help>]"
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

checksum_dd()
{
	if [ "$(head -c "$(stat -c "%s" "$ISO")" "$DISK" | sha1sum | awk '{print $1}')" = "$CHECKSUM" ] ; then
		echo The USB has passed the checksum
		exit 0
	else
		if [ -z "$BLOCK_SIZE" ] ; then
			dd if="$ISO" of="$DISK" count=1
		else
			dd if="$ISO" of="$DISK" bs="$BLOCK_SIZE" count=1
			if [ "$(head -c "$(stat -c "%s" "$ISO")" "$DISK" | sha1sum | awk '{print $1}')" = "$CHECKSUM" ] ; then
				echo The USB has passed the checksum
				udisksctl unmount -b "$DISK" || true
				exit 0
			else
				echo The USB has failed the checksum
				udisksctl unmount -b "$DISK" || true
				exit 1
			fi
		fi
	fi
}

while getopts "h:s:d:c:b:D" arg ; do
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
		D)
			DD=$OPTARG
			;;
		*)
			usage
			;;
	esac
done

CHECKSUM=$(echo "$CHECKSUM" | awk '{print tolower($0)}')

if [ "$(sha1sum "$ISO" | awk '{print $1}')" = "$CHECKSUM" ] ; then
	echo The ISO file passed the checksum
else
	echo The ISO file failed the checksum
	exit 1
fi

echo Unmounting the USB
udisksctl unmount -b "$DISK" || true

if [ -z "$DD" ] ; then
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
else
	checksum_dd
fi
