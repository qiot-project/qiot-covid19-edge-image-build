# This is the kickstart for Fedora IoT disk images.

text # don't use cmdline -- https://github.com/rhinstaller/anaconda/issues/931
lang en_US.UTF-8
keyboard us
timezone --utc Etc/UTC

selinux --enforcing
rootpw --lock --iscrypted locked

bootloader --timeout=1 --append="modprobe.blacklist=vc4 iomem=relaxed strict-devmem=0"

network --bootproto=dhcp --device=link --activate --onboot=on
services --enabled=NetworkManager,sshd,rngd

zerombr
clearpart --all --initlabel --disklabel=msdos
autopart --nohome --noswap --type=plain

# Equivalent of %include fedora-repo.ks
# Pull from the ostree repo that was created during the compose
ostreesetup --nogpg --osname=fedora-iot --remote=fedora-iot --url=https://dl.fedoraproject.org/iot/repo/ --ref=fedora/stable/aarch64/iot

reboot

%post --erroronfail
# Find the architecture we are on
arch=$(uname -m)
if [[ $arch == "armv7l" ]]; then
	arch="armhfp"
fi

# Setup Raspberry Pi firmware
if [[ $arch == "aarch64" ]] || [[ $arch == "armhfp" ]]; then
if [[ $arch == "aarch64" ]]; then
cp -P /usr/share/uboot/rpi_3/u-boot.bin /boot/efi/rpi3-u-boot.bin
cp -P /usr/share/uboot/rpi_4/u-boot.bin /boot/efi/rpi4-u-boot.bin
cat <<EOT > /boot/efi/config.txt
# Raspberry Pi 3
[pi3]
kernel=rpi3-u-boot.bin

# Raspberry Pi 4
[pi4]
kernel=rpi4-u-boot.bin

# Default Fedora configs for all Raspberry Pi Revisions
[all]
# Put the RPi into 64 bit mode
#arm_control=0x200
arm_64bit=1

dtparam=i2c_arm=on
#dtparam=i2s=on
dtparam=spi=on

# Enable UART
# Only enable UART if you're going to use it as it has speed implications
# Serial console is ttyS0 on RPi3 and ttyAMA0 on all other variants
# u-boot will auto detect serial and pass corrent options to kernel if enabled
# Speed details: https://www.raspberrypi.org/forums/viewtopic.php?f=28&t=141195
enable_uart=1

# Early boot delay in the hope monitors are initialised enough to provide EDID
bootcode_delay=1

# We need this to be 32Mb to support VCHI services and drivers which use them
# but this isn't used by mainline VC4 driver so reduce to lowest supported value
# You need to set this to at least 80 for using the camera
gpu_mem=32

# Use eXtended firmware by default
start_x=1

# New option to allow the firmware to load upstream dtb
# Will allow things like camera, touchscreen etc to work OOTB
upstream_kernel=1

# HAT and DT overlays. Documentation at Raspberry Pi here:
# https://www.raspberrypi.org/documentation/configuration/device-tree.md
# Each dtoverlay line is an individual HAT/overlay, multiple lines allowed
# The dtoverlay=upstream must be present for Fedora kernels
dtoverlay=miniuart-bt
dtoverlay=adau7002-simple
dtoverlay=upstream
# dtoverlay=rpi-sense

# Allow OS rather than firmware control CEC
mask_gpu_interrupt1=0x100

# Without this sdram runs at 400mhz, instead of 450
# https://github.com/Hexxeh/rpi-firmware/issues/172
audio_pwm_mode=0

# Other options you can adjust for all Raspberry Pi Revisions
# https://www.raspberrypi.org/documentation/configuration/config-txt/README.md
# All options documented at http://elinux.org/RPiconfig
# for more options see http://elinux.org/RPi_config.txt

EOT
else
cp -P /usr/share/uboot/rpi_2/u-boot.bin /boot/efi/rpi2-u-boot.bin
cp -P /usr/share/uboot/rpi_3_32b/u-boot.bin /boot/efi/rpi3-u-boot.bin
cp -P /usr/share/uboot/rpi_4_32b/u-boot.bin /boot/efi/rpi4-u-boot.bin
fi
fi

# Set the origin to the "main ref", distinct from /updates/ which is where bodhi writes.
# We want consumers of this image to track the two week releases.
ostree admin set-origin --index 0 fedora-iot https://dl.fedoraproject.org/iot/repo/ "fedora/stable/${arch}/iot"

# Make sure the ref we're supposedly sitting on (according
# to the updated origin) exists.
ostree refs "fedora-iot:fedora/stable/${arch}/iot" --create "fedora-iot:fedora/stable/${arch}/iot"

# Remove the old ref so that the commit eventually gets cleaned up.
ostree refs "fedora-iot:fedora/stable/${arch}/iot" --delete

# delete/add the remote with new options to enable gpg verification
# and to point them at the cdn url
ostree remote delete fedora-iot
ostree remote add --set=gpg-verify=true --set=gpgkeypath=/etc/pki/rpm-gpg/ --set=contenturl=mirrorlist=https://ostree.fedoraproject.org/iot/mirrorlist  fedora-iot 'https://ostree.fedoraproject.org/iot'

# We're getting a stray console= from somewhere, work around it
rpm-ostree kargs --delete=console=tty0

# older versions of livecd-tools do not follow "rootpw --lock" line above
# https://bugzilla.redhat.com/show_bug.cgi?id=964299
passwd -l root

# Work around https://bugzilla.redhat.com/show_bug.cgi?id=1193590
cp /etc/skel/.bash* /var/roothome

# Adding customization QIoT project
rpm-ostree install cockpit-system cockpit-ostree cockpit-podman i2c-tools
podman pull cockpit/ws
podman container runlabel --name cockpit-ws RUN cockpit/ws
podman container runlabel INSTALL cockpit/ws
systemctl enable cockpit.service
groupadd i2cuser
useradd -m -G wheel,i2cuser edge
echo "edge" | passwd --stdin edge
mkdir -p /home/edge/qiot/driver
mkdir -p /home/edge/qiot/containers/sensor/base/test
mkdir -p /home/edge/qiot/containers/sensor/service
mkdir -p /home/edge/qiot/containers/edge
echo "SUBSYSTEM==\"i2c-dev\", GROUP=\"i2cuser\", MODE=\"0660\"" | tee /etc/udev/rules.d/50-i2c.rules
systemctl disable firewalld
podman network create qiot

# Remove any persistent NIC rules generated by udev
rm -vf /etc/udev/rules.d/*persistent-net*.rules

echo "Removing random-seed so it's not the same in every image."
rm -f /var/lib/systemd/random-seed

echo "Packages within this iot image:"
echo "-----------------------------------------------------------------------"
rpm -qa --qf '%{size}\t%{name}-%{version}-%{release}.%{arch}\n' |sort -rn
echo "-----------------------------------------------------------------------"
# Note that running rpm recreates the rpm db files which aren't needed/wanted
rm -f /var/lib/rpm/__db*

echo "Zeroing out empty space."
# This forces the filesystem to reclaim space from deleted files
dd bs=1M if=/dev/zero of=/var/tmp/zeros || :
rm -f /var/tmp/zeros
echo "(Don't worry -- that out-of-space error was expected.)"

# For trac ticket https://pagure.io/atomic-wg/issue/128
rm -f /etc/sysconfig/network-scripts/ifcfg-*

# Anaconda is writing an /etc/resolv.conf from the install environment.
# The system should start out with an empty file, otherwise cloud-init
# will try to use this information and may error:
# https://bugs.launchpad.net/cloud-init/+bug/1670052
truncate -s 0 /etc/resolv.conf

%end
