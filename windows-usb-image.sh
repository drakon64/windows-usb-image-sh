#!/bin/sh -e

ISO=$1
DISK=$2
CHECKSUM=$3

CHECKSUM=$(echo "$CHECKSUM" | awk '{print tolower($0)}' )

if [ "$(sha1sum "$ISO" | awk '{print $1}')" = "$CHECKSUM" ]
then
	echo ISO PASS
else
	echo ISO FAIL
	exit 1
fi

udisksctl unmount --block-device $DISK || true

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

sleep 3

mkfs.fat -F 32 -S 512 "$DISK"-part1
mkfs.ntfs -Q -s 512 "$DISK"-part2

LOOP=$(mktemp -d)
mount "$ISO" -o loop,ro "$LOOP"

CHECKSUM_FILE_EFI=$(mktemp)
find "$LOOP"/efi -type f -exec sh -c "sha1sum {} >> $CHECKSUM_FILE_EFI" \;

EFI=$(mktemp -d)
mount "$DISK"-part1 "$EFI"

cp -r "$LOOP"/efi "$EFI"
(
	cd "$EFI"
	if [ -z "$(sha1sum -c "$CHECKSUM_FILE_EFI" | grep FAILED)" ]
	then
		echo ESP OK
	else
		echo ESP FAIL
	fi
)

CHECKSUM_FILE_WINDOWS=$(mktemp)
find "$LOOP" -type f -exec sh -c "sha1sum {} >> $CHECKSUM_FILE_WINDOWS" \;

WINDOWS=$(mktemp -d)
mount "$DISK"-part2 "$WINDOWS"

cp -r "$LOOP"/* "$WINDOWS"
(
	cd "$WINDOWS"
	if [ -z "$(sha1sum -c "$CHECKSUM_FILE_WINDOWS" | grep FAILED)" ]
	then
		echo Windows OK
	else
		echo Windows FAIL
	fi
)

umount "$LOOP" "$EFI" "$WINDOWS"
rm -rf "$LOOP" "$CHECKSUM_FILE" "$EFI" "$WINDOWS"
