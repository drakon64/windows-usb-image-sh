#!/bin/sh -e

ISO=$1
DISK=$2
CHECKSUM=$3
CHECKSUM_EXEC=$4

CHECKSUM=$(echo "$CHECKSUM" | awk '{print tolower($0)}' )

if [ "$($CHECKSUM_EXEC $ISO | awk '{print $1}')" = "$CHECKSUM" ]
then
	echo "ISO PASS"
else
	echo "ISO FAIL"
	exit 1
fi

(
	echo g
	echo n
	echo
	echo
	echo
	echo t
	echo 1
	echo w
) | fdisk $DISK || partprobe

sleep 3

mkfs.ntfs -Q -s 512 $DISK-part1

LOOP=$(mktemp -d)
EFI=$(mktemp -d)
CHECKSUM_FILE=$(mktemp)

mount $ISO -o loop,ro $LOOP

find $LOOP -type f -exec sh -c "$CHECKSUM_EXEC {} >> $CHECKSUM_FILE" \;

mount $DISK-part1 $EFI

cp -r $LOOP $EFI
(
	cd $EFI
	$CHECKSUM_EXEC -c $CHECKSUM_FILE
)

umount $LOOP $EFI
udisksctl power-off --block-device $DISK
rmdir $LOOP $EFI
rm $CHECKSUM_FILE
