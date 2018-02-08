#!/bin/bash

# The MIT License (MIT)
#
# Copyright (c) 2015 Philip Huppert
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

DISK="/dev/loop0"
PARTITION="${DISK}p1"

HOSTNAME="opi0"
PASSWORD="root"
USERNAME="opi0"

TIMEZONE="Europe/Vienna"
CONSOLE_KEYMAP="de-latin1"
CONSOLE_FONT="lat9w-16"

PACSTRAP="bash
bzip2
connman
coreutils
crda
e2fsprogs
gawk
gettext
glibc
grep
gzip
iproute2
linux-armv7
vi 
nano
openssh
pacman
pacman-mirrorlist
procps-ng
sed
shadow
socat
tar
udisks2
usbutils
util-linux
which
wpa_supplicant
systemd-sysvcompat 
uboot-tools
"


ETH0_MODE="DHCP" # DHCP/STATIC/OFF
# only for static mode
ETH0_ADDR="192.168.0.200/24"
ETH0_GW="192.168.0.1" # empty -> no gateway for eth0
ETH0_DNS="192.168.0.1" # empty -> no DNS for eth0

ETH1_MODE="OFF"
ETH1_ADDR="192.168.56.15/24"
ETH1_GW=""
ETH1_DNS=""


function announce {
	>&2 echo -n "$1"
}

function check_fail {
	if [[ $1 -ne 0 ]]; then
		>&2 echo "FAIL!"
		exit 1
	else
		>&2 echo "OK!"
	fi
}

function lbSetup {
announce "create card.img file... "
truncate -s 2500M card.img
check_fail $?

announce "create loopback device "
losetup /dev/loop0 card.img
check_fail $?
}

function prepareDisk {
announce "Checking internet connectivity... "
wget -q --tries=10 --timeout=20 --spider http://google.de
check_fail $?


announce "Creating partition table... "
parted -s "$DISK" mklabel msdos
check_fail $?


announce "Creating root partition... "
parted -s -a optimal "$DISK" mkpart primary 0 2500
check_fail $?

announce "Making partition bootable... "
parted -s "$DISK" set 1 boot on
check_fail $?


announce "Formatting root partition with ext4... "
mkfs.ext4 -F "$PARTITION"
check_fail $?

}


function mountParts {
announce "Mounting partition... "
mount "$PARTITION" /mnt
check_fail $?
}

function installBase {
announce "Installing base system... "
pacstrap -c /mnt $PACSTRAP
check_fail $?

}


function configure {
# announce "Configuring fstab... "
# genfstab -p /mnt >> /mnt/etc/fstab
# check_fail $?

announce "Setting root password... "
echo "root:$PASSWORD" | arch-chroot /mnt chpasswd 
check_fail $?

announce "Setting hostname... "
echo "$HOSTNAME" > /mnt/etc/hostname
check_fail $?


announce "Configuring root's bash... "
cp /mnt/etc/skel/.bash* /mnt/root
check_fail $?

announce "Configuring root's bashrc... "
cat <<EOF > /mnt/root/.bashrc
#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ \$- != *i* ]] && return

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=10000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

alias ls='ls --color=auto'
alias ll='ls -halF'
alias l='ls -hlF'

alias rm='rm -i'
alias mv='mv -i'
alias cp='cp -i'

alias cd..='cd ..'
alias j='jobs'

PS1='[\u@\h \W]\\$ '

EOF
check_fail $?


announce "Setting timezone... "
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /mnt/etc/localtime
check_fail $?

announce "Enabling locales... "
sed -i 's/^#en_US\.UTF/en_US\.UTF/' /mnt/etc/locale.gen && sed -i 's/^#de_DE\.UTF/de_DE\.UTF/' /mnt/etc/locale.gen
check_fail $?

announce "Configuring locales... "
cat <<EOF > /mnt/etc/locale.conf
LANG="en_US.UTF-8"
LC_CTYPE="de_DE.UTF-8"
LC_NUMERIC="de_DE.UTF-8"
LC_TIME="de_DE.UTF-8"
LC_COLLATE="de_DE.UTF-8"
LC_MONETARY="de_DE.UTF-8"
LC_MESSAGES="en_US.UTF-8"
LC_PAPER="de_DE.UTF-8"
LC_NAME="de_DE.UTF-8"
LC_ADDRESS="de_DE.UTF-8"
LC_TELEPHONE="de_DE.UTF-8"
LC_MEASUREMENT="de_DE.UTF-8"
LC_IDENTIFICATION="de_DE.UTF-8"
EOF
check_fail $?

announce "Configuring vconsole... "
echo -en "KEYMAP=$CONSOLE_KEYMAP\nFONT=$CONSOLE_FONT\n" > /mnt/etc/vconsole.conf
check_fail $?

announce "Generating locales... "
arch-chroot /mnt locale-gen
check_fail $?


announce "create user... "
arch-chroot /mnt useradd -m -U -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:pass" | arch-chroot /mnt chpasswd 
# check_fail $?


announce "Configuring interface names... "
ln -sf /dev/null /mnt/etc/udev/rules.d/80-net-setup-link.rules
check_fail $?

if [ "$ETH0_MODE" = "DHCP" ]; then
    announce "Configuring eth0 for DHCP... "
	cat <<EOF > /mnt/etc/systemd/network/eth0_DHCP.network
[Match]
Name=eth0

[Network]
DHCP=v4
EOF
	check_fail $?
fi

if [ "$ETH1_MODE" = "DHCP" ]; then
	announce "Configuring eth1 for DHCP... "
	cat <<EOF > /mnt/etc/systemd/network/eth1_DHCP.network
[Match]
Name=eth1

[Network]
DHCP=v4
EOF
	check_fail $?
fi

if [ "$ETH0_MODE" = "STATIC" ]; then
	announce "Configuring eth0 for STATIC... "
	cat <<EOF > /mnt/etc/systemd/network/eth0_STATIC.network
[Match]
Name=eth0

[Network]
Address=$ETH0_ADDR
EOF
    check_fail $?

    if [ -n "$ETH0_GW" ]; then
        announce "Configuring gateway for eth0... "
        echo "Gateway=$ETH0_GW" >> /mnt/etc/systemd/network/eth0_STATIC.network
        check_fail $?
    fi

    if [ -n "$ETH0_DNS" ]; then
        announce "Configuring DNS for eth0... "
        echo "DNS=$ETH0_DNS" >> /mnt/etc/systemd/network/eth0_STATIC.network
        check_fail $?
    fi
fi

if [ "$ETH1_MODE" = "STATIC" ]; then
	announce "Configuring eth1 for STATIC... "
	cat <<EOF > /mnt/etc/systemd/network/eth1_STATIC.network
[Match]
Name=eth1

[Network]
Address=$ETH1_ADDR
EOF
	check_fail $?

    if [ -n "$ETH1_GW" ]; then
        announce "Configuring gateway for eth1... "
        echo "Gateway=$ETH1_GW" >> /mnt/etc/systemd/network/eth1_STATIC.network
        check_fail $?
    fi

    if [ -n "$ETH1_DNS" ]; then
        announce "Configuring DNS for eth1... "
        echo "DNS=$ETH1_DNS" >> /mnt/etc/systemd/network/eth1_STATIC.network
        check_fail $?
    fi
fi

announce "Enabling networking... "
arch-chroot /mnt systemctl enable systemd-networkd
check_fail $?

announce "Enabling DNS... "
arch-chroot /mnt systemctl enable systemd-resolved
check_fail $?

announce "Configuring NTP... "
sed -i 's/^#NTP=$/NTP=0.de.pool.ntp.org 1.de.pool.ntp.org 2.de.pool.ntp.org 3.de.pool.ntp.org/' /mnt/etc/systemd/timesyncd.conf
check_fail $?

announce "Generating first-boot script... "
cat <<EOF > /mnt/firstboot.sh
#!/bin/bash
timedatectl set-ntp true
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
systemctl disable firstboot.service
rm -f /etc/systemd/system/firstboot.service
rm -f /firstboot.sh
EOF
check_fail $?

announce "Generating first-boot service... "
cat <<EOF > /mnt/etc/systemd/system/firstboot.service
[Unit]
Description=Configuration script for first boot of system
After=basic.target

[Service]
Type=oneshot
User=root
ExecStart=/bin/bash /firstboot.sh

[Install]
WantedBy=basic.target
EOF
check_fail $?


announce "Generating fstab.."
cat <<EOF > /mnt/etc/fstab
/dev/mmcblk0p2  /               ext4    defaults,ro,data=ordered,noatime        0       0

tmpfs           /tmp            tmpfs   nodev,nosuid,size=50M   0       0
tmpfs           /var/tmp        tmpfs   nodev,nosuid,size=10M   0       0
tmpfs           /var/log        tmpfs   nodev,nosuid,size=10M   0       0
tmpfs           /var/cache      tmpfs   nodev,nosuid,size=10M   0       0
tmpfs           /run            tmpfs   nodev,nosuid,size=20M   0       0

tmpfs           /home/opi0     tmpfs   nodev,nosuid,size=50M,uid=opi0,gid=opi0       0       0
EOF
check_fail $?

# announce "Enabling first-boot service... "
# arch-chroot /mnt systemctl enable firstboot.service
# check_fail $?

announce "generate ssh host keys "
arch-chroot /mnt ssh-keygen -A
check_fail $?


announce "copy config files... "
cp connman.conf /mnt/etc/dbus-1/system.d/
echo "connman"
arch-chroot /mnt systemctl enable connman
echo "sshd"
arch-chroot /mnt systemctl enable sshd

echo "disable rfkill"
arch-chroot /mnt systemctl disable systemd-rfkill

# echo "firstboot"
# arch-chroot /mnt systemctl enable firstboot.service
check_fail $?

echo "systemd config"
echo "RuntimeWatchdogSec=15" >> /mnt/etc/systemd/system.conf
echo "ShutdownWatchdogSec=15" >> /mnt/etc/systemd/system.conf
echo "Storage=volatile" >> /mnt/etc/systemd/journald.conf

}

lbSetup
prepareDisk
mountParts
installBase
configure
umount /dev/loop0*
losetup -d /dev/loop0
7z -mmt4 -mx3 a card.img.7z card.img
