#!/bin/bash

# VARIABLES
DISK="/dev/sda"
UEFI="/dev/sda1"
LUKS="/dev/sda2"

DEFAULT_PSWD="azerty123"

CRPROOT="cryptroot"

VGRP="vgrp_chocolatine"
VGROOT="root"
VGHOME="home"
VGSWP="swap"
VGSHARED="shared"
VGVM="virtualisation"
VGTMP="tmp"
VGSTFF="moumoute" # for encrypt part (10 GB)

MMTPATH="/dev/vgrp_chocolatine/moumoute"
ROOTPATH="/dev/vgrp_chocolatine/root"
HOMEPATH="/dev/vgrp_chocolatine/home"
SWPATH="/dev/vgrp_chocolatine/swap"
SHRDPATH="/dev/vgrp_chocolatine/shared"
VMPATH="/dev/vgrp_chocolatine/virtualisation"
TMPATH="/dev/vgrp_chocolatine/tmp"

MNTBOOT="/mnt/boot"
MNTHOME="/mnt/home"
MNTSHRD="/mnt/shared"
MNTVM="/mnt/var/virtualisation"
MNTMP="/mnt/tmp"

HOSTNAME="archlinux"

USRDAD="papounet"
USRSON="filston"

USRGRP="famille"
VMGRP="vmbox"


# FUNCTIONS
default_password(){
   echo "$DEFAULT_PSWD"
}

# PARTITIONNING
sgdisk -og $DISK
sgdisk -n 1:0:+512M -t 1:ef00 $DISK # for UEFI
sgdisk -n 2:0:0 -t 2:8300 $DISK # for LUKS

# DISK ENCRYPTION WITH LUKS
default_password | cryptsetup luksFormat $LUKS --batch-mode
default_password | cryptsetup open $LUKS $CRPROOT

# LVM CREATION
pvcreate /dev/mapper/$CRPROOT
vgcreate $VGRP /dev/mapper/$CRPROOT

lvcreate -L 20G -n $VGROOT $VGRP
lvcreate -L 5G -n $VGSWP $VGRP
lvcreate -L 20G -n $VGVM $VGRP
lvcreate -L 5G -n $VGSHARED $VGRP
lvcreate -L 2G -n $VGTMP $VGRP
lvcreate -L 10G -n $VGSTFF $VGRP
lvcreate -l 100%FREE -n $VGHOME $VGRP

# MOUMOUTE VOLUME ENCRYPTION
default_password | cryptsetup luksFormat $MMTPATH --batch-mode
default_password | cryptsetup open $MMTPATH stuff

# FORMATTING PARTITIONS
mkfs.fat -F32 -n UEFI $UEFI
mkfs.ext4 -L ROOT $ROOTPATH
mkfs.ext4 -L HOME $HOMEPATH
mkswap -L SWAP $SWPATH
mkfs.ext4 -L SHARED $SHRDPATH
mkfs.ext4 -L VM $VMPATH
mkfs.ext4 -L TMP $TMPATH
mkfs.ext4 -L STUFF /dev/mapper/stuff

# ASSEMBLY PARTITIONS
mount -o defaults,noatime,discard $ROOTPATH /mnt
mkdir -p $MNTBOOT
mkdir -p $MNTHOME
mkdir -p $MNTSHRD
mkdir -p $MNTVM
mkdir -p $MNTMP
mount -o defaults,nodev,noexec,nosuid $UEFI $MNTBOOT
mount -o defaults,noatime,nodev,nosuid $HOMEPATH $MNTHOME
mount -o defaults,nodev,nosuid,noexec $SHRDPATH $MNTSHRD
mount -o defaults,noatime,discard $VMPATH $MNTVM
mount -o defaults,nosuid,nodev,noexec,relatime,discard $TMPATH $MNTMP
swapon $SWPATH

# MOUNT SYSTEM DIRECTORIES
mount --rbind /dev /mnt/dev
mount --rbind /proc /mnt/proc
mount --rbind /sys /mnt/sys

# INSTALL ARCHLINUX PACKAGES
pacstrap /mnt base linux linux-firmware

# FSTAB
mkdir -p /mnt/etc
genfstab -U /mnt >> /mnt/etc/fstab

# CHROOT
arch-chroot /mnt <<EOF

# UPDATE PACKAGE DATABASE
pacman -Sy

# LVM ACTIVATION
vgscan --mknodes
vgchange -ay

# MODIFY INITCPIO HOOKS
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf

# TIMEZONE
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc

# LANGUAGE
echo "fr_FR.UTF-8 UTF-8" > /etc/locale.gen
echo "fr_FR.ISO-8859-1 ISO-8859-1" >> /etc/locale.gen
locale-gen
echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
echo "FONT=lat9w-16" > /etc/vconsole.conf
echo "KEYMAP=fr" >> /etc/vconsole.conf

# HOSTNAME
echo "$HOSTNAME" > /etc/hostname

# USERS
echo "root:$DEFAULT_PSWD" | chpasswd

groupadd $USRGRP
useradd -m -G wheel,$USRGRP -s /bin/bash $USRDAD
echo "$USRDAD:$DEFAULT_PSWD" | chpasswd
useradd -m -G $USRGRP -s /bin/bash $USRSON
echo "$USRSON:$DEFAULT_PSWD" | chpasswd

# SHARED DIRECTORY
mkdir -p /shared
chown $USRDAD:$USRGRP /shared
chmod 2770 /shared
chmod g+s /shared

# SUDO FOR WHEEL GROUP
pacman -S --noconfirm sudo
echo "%wheel ALL=(ALL) ALL" | EDITOR='tee -a' visudo

# VMBOX
pacman -S --noconfirm virtualbox virtualbox-host-dkms linux-headers
ln -s $VMPATH /var/lib/virtualbox
mkdir -p /home/$USRDAD/.config/VirtualBox
echo "DefaultMachineFolder=$VMPATH" > /home/$USRDAD/.config/VirtualBox/VirtualBox.xml
chown -R $USRDAD:$USRDAD /home/$USRDAD/.config/VirtualBox
usermod -aG vboxusers $USRDAD

# OTHER PACKAGES
pacman -S --noconfirm firefox vim htop neofetch git gcc make

# I3
pacman -S --noconfirm xorg-server xorg-xinit xorg-xrandr \
    i3-wm i3status i3lock dmenu alacritty \
    lightdm lightdm-gtk-greeter
systemctl enable lightdm

# GRUB
pacman -S --noconfirm lvm2 device-mapper
mkinitcpio -P
echo "GRUB_CMDLINE_LINUX=\"cryptdevice=$LUKS:$CRPROOT root=/dev/mapper/$VGRP-$VGROOT keymap=fr\"" >> /etc/default/grub
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# SETUP NETWORK
pacman -S --noconfirm networkmanager dhclient
systemctl enable NetworkManager

EOF 

systemctl restart NetworkManager

sync
umount -R /mnt
swapoff -a
reboot