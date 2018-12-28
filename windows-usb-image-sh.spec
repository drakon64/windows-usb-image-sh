Name: windows-usb-image-sh
Version: 20181228
Release: 0
Summary: Bash script for copying disk images to block devices
License: GPL-3.0
BuildRequires: unzip

%description
windows-usb-image-sh is a Bash script for copying disk images to block devices. It can either copy the disk image files to the block device (Copy Mode), or use DD to copy the disk image itself to the block device. Checksums are performed on both the source image and the destination block device to ensure data integrity.

%prep
%setup

%install
install -D -m 755 windows-usb-image.sh %buildroot/%_bindir/windows-usb-image

%files
defattr(-,root,root)
/%_bindir/windows-usb-image
