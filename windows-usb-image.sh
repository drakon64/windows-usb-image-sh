#!/bin/sh -e

ISO=$1
DISK=$2
CHECKSUM=$3
BLOCK_SIZE=$4

CHECKSUM=$(echo "$CHECKSUM" | awk '{print tolower($0)}' )

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
	echo +100M
	echo t
	echo 1
	echo n
	echo
	echo
	echo
	echo t
	echo 2
	echo 11
	echo w
) | fdisk "$DISK" || partprobe

if [ -z "$BLOCK_SIZE" ]
then
	echo Creating the EFI System Partition
	mkfs.fat -F 32 "$DISK"-part1

	echo Creating the Windows partition
	mkfs.ntfs -Q "$DISK"-part2
else
	echo Creating the EFI System Partition
	mkfs.fat -F 32 -S "$BLOCK_SIZE" "$DISK"-part1

	echo Creating the Windows partition
	mkfs.ntfs -Q -s "$BLOCK_SIZE" "$DISK"-part2
fi

echo Mounting the Windows ISO
LOOP=$(mktemp -d)
mount "$ISO" -o loop,ro "$LOOP"

echo Generating checksums for the EFI System Partition files
CHECKSUM_FILE_EFI=$(mktemp)
find "$LOOP"/efi -type f -exec sh -c "sha1sum {} >> $CHECKSUM_FILE_EFI" \;

echo Mounting the EFI System Partition
EFI=$(mktemp -d)
mount "$DISK"-part1 "$EFI"

CURRENT_PWD=$(pwd)

echo Copying the EFI System Partition files
cp -r "$LOOP"/efi "$EFI"
cd "$EFI"
echo Validating the EFI System Partition files
if ! sha1sum -c "$CHECKSUM_FILE_EFI" | grep -q FAILED
then
	echo The EFI System Partition passed the checksum
	cd "$CURRENT_PWD"
	echo Unmounting the EFI System Partition
	EFI_PASS=1
else
	echo The EFI System Partition failed the checksum
	cd "$CURRENT_PWD"
	echo Unmounting the EFI System Partition
	EFI_PASS=0
fi
umount "$EFI"
rmdir "$EFI"

if [ $EFI_PASS -eq 1 ]
then
	echo Generating checksums for the Windows partition files
	CHECKSUM_FILE_WINDOWS=$(mktemp)
	find "$LOOP" -type f -exec sh -c "sha1sum {} >> $CHECKSUM_FILE_WINDOWS" \;

	echo Mounting the Windows partition
	WINDOWS=$(mktemp -d)
	mount "$DISK"-part2 "$WINDOWS"

	echo Copying the Windows partition files
	cp -r "$LOOP"/* "$WINDOWS"
	cd "$WINDOWS"
	echo Validating the Windows partition files
	if ! sha1sum -c "$CHECKSUM_FILE_WINDOWS" | grep -q FAILED
	then
		echo The Windows partition passed the checksum
		echo Removing the EFI directory from the Windows partition
		rm -rf efi
		cd "$CURRENT_PWD"
		echo Unmounting the Windows partition
	else
		echo The Windows partition failed the checksum
		cd "$CURRENT_PWD"
		echo Unmounting the Windows partition
	fi
	umount "$WINDOWS"
	rmdir "$WINDOWS"
fi

echo Unmounting the Windows ISO
umount "$LOOP"
echo Cleaning up
rm -rf "$LOOP" "$CHECKSUM_FILE"
