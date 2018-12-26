#!/bin/sh -e

ISO=$1
DISK=$2
CHECKSUM=$3
BLOCK_SIZE=$4

CHECKSUM=$(echo "$CHECKSUM" | awk '{print tolower($0)}' )

uefi()
{
	if [ -z "$BLOCK_SIZE" ]
	then
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
	if sha1sum --status -c "$CHECKSUM_FILE_WINDOWS"
	then
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

if [ "$(sha1sum "$ISO" | awk '{print $1}')" = "$CHECKSUM" ]
then
	echo The ISO file passed the checksum
else
	echo The ISO file failed the checksum
	exit 1
fi

echo Unmounting the USB
udisksctl unmount -b "$DISK" || true

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

if [ -z "$BLOCK_SIZE" ]
then
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

windows &
uefi &
wait

echo Unmounting the Windows ISO
umount "$LOOP"
echo Cleaning up
rmdir "$LOOP"
