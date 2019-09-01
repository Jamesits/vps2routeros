#!/bin/bash

# VPS2RouterOS
# https://github.com/Jamesits/vps2routeros
# This script will cause permanent data loss
# Please read the documentation prior to running this
# You have been warned

# ======================= please change these =================================
# your network interface to internet
# this is used to auto configure IPv4 after reboot
# (this may not work for every device)
# eth0 for most devices, ens3 for Vultr
# you can use `ip addr` or `ifconfig` to find out this
# default: the interface on the default route
MAIN_INTERFACE=$(ip route list | grep default | head -n 1 | cut -d' ' -f 5)

# HDD device (not partition)
# May not be compatible with SCSI drives; see official document of RouterOS CHR
# you can use `lsblk` to find out this
# default: the disk with a partition mounted to `/`
DISK=$(mount | grep ' /mnt/oldroot ' | cut -d' ' -f1 | sed 's/[0-9]*$//g')

# get IPv4 address in IP-CIDR format
# do not modify unless you know what you are doing
ADDRESS=$(ip addr show $MAIN_INTERFACE | grep global | cut -d' ' -f 6 | head -n 1)

# get gateway IP
# do not modify unless you know what you are doing
GATEWAY=$(ip route list | grep default | cut -d' ' -f 3)

# URL to RouterOS CHR
ROUTEROS_URL=https://download2.mikrotik.com/routeros/6.43.14/chr-6.43.14.img.zip

# URL to scripts
MENHERA_URL=https://cursed.im/menhera
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# Note: you can customize commands to be executed when RouterOS initializes.
# Search `Auto configure script` below
# do not modify that unless you know what you are doing

# ======================= no need to modify below ============================
PHASE1_TRIGGER=/tmp/old_user_disconnected
PHASE2_TRIGGER=/tmp/new_user_connected

set -Eeuo pipefail

### START vps2router.sh helpers
vps2routeros::get_menhera() {
    wget -q --show-progress ${MENHERA_URL} -O /tmp/menhera.sh
    source /tmp/menhera.sh --lib
}

vps2routeros::wait_file() {
    until [ -f "$1" ]
    do
        sleep 1
    done
}

vps2routeros::install_shell() {
    DEBIAN_FRONTEND=noninteractive chroot "${NEWROOT}" apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y pv util-linux udev

    cp ${SCRIPT_PATH} "${NEWROOT}/bin/vps2routeros"
    cat > "${NEWROOT}/bin/vps2routeros-loginshell" <<EOF
#!/bin/bash
/bin/vps2routeros --phase2
EOF
    chmod +x "${NEWROOT}/bin/vps2routeros"
    chmod +x "${NEWROOT}/bin/vps2routeros-loginshell"
    echo "/bin/vps2routeros-loginshell" >> /etc/shells

    chroot "${NEWROOT}" chsh -s /bin/vps2routeros-loginshell root
    cat > "${NEWROOT}/etc/motd" <<EOF
EOF
}

vps2routeros::download_routeros() {
    echo "Downloading RouterOS..."
    pushd /tmp/menhera
    wget -q --show-progress ${ROUTEROS_URL} -O chr.img.zip
    unzip chr.img.zip
    rm chr.img.zip
    popd
}

vps2routeros::install_routeros() {
    echo "Writing RouterOS to disk..."
    pv > $DISK < /tmp/menhera/chr-*.img

    # avoid racing with udev
    udevadm settle
    
    ! partx -a $DISK
    ! blockdev --rereadpt $DISK
    
    udevadm settle
}

vps2routeros::write_routeros_init_script() {
    echo "Setting up RouterOS for first time use..."
    
    udevadm settle
    mount ${DISK}*1 /mnt
    cat > /mnt/rw/autorun.scr <<EOF
/ip address add address=$ADDRESS interface=[/interface ethernet find where name=ether1]
/ip route add gateway=$GATEWAY
/ip service disable telnet
/ip dns set servers=8.8.8.8,8.8.4.4
EOF
    umount /mnt
}

vps2routeros::reset() {
    echo "Rebooting..."
    sync; sync
    ! echo b > /proc/sysrq-trigger
    reboot
}

# https://stackoverflow.com/a/3232082/2646069
vps2routeros::confirm() {
    # call with a prompt string or use a default
    read -r -p "${1:-Are you sure? [y/N]} " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            true
            ;;
        *)
            false
            ;;
    esac
}

vps2routeros::clear_processes() {
    echo "Disabling swap..."
    swapoff -a

    echo "Restarting init process..."
    menhera::__compat_reload_init
    # hope 15s is enough
    sleep 15

    touch ${PHASE1_TRIGGER}

    echo "Killing all programs still using the old root..."
    fuser -kvm "${OLDROOT}" -15
    # in most cases the parent process of this script will be killed, so goodbye
}

vps2routeros::umount_disks() {
    echo "unmounting ${DISK}..."
    
    for f in ${DISK}*
    do
        ! umount "$f"
    done
}

### END vps2router.sh helpers

### START main procedure

# check if this script is running under root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

PHASE2=0
PHASE2_DEBUG=0
while test $# -gt 0
do
    case "$1" in
        --phase2) PHASE2=1
            ;;
        --phase2-debug) PHASE2_DEBUG=1
            ;;
    esac
    shift
done

if [[ $PHASE2 -eq 1 ]]; then
    # we are at phase 2
    touch ${PHASE2_TRIGGER}
    echo -e "Now you are in the recovery environment and we are about to install RouterOS to your disk."
    
    if [[ $PHASE2_DEBUG -eq 1 ]]; then
        echo -e "You are entering phase 2 debug shell. Exit to continue installation."
        bash
    fi

    echo -e "Please confirm the settings:"
    echo -e "Installation destination: ${DISK}"
    echo -e "Network information:"
    echo -e "\tinterface: ${MAIN_INTERFACE}"
    echo -e "\tIPv4 address: ${ADDRESS}"
    echo -e "\tIPv4 gateway: ${GATEWAY}"
    echo -e "\nIf you continue, your disk will be formatted and no data will be preserved."
    echo -e "You can still abort installation now -- it will reboot."

    vps2routeros::confirm || vps2routeros::reset

    echo -e "Waiting for last user session to disconnect..."
    vps2routeros::wait_file ${PHASE1_TRIGGER}
    sleep 1
    
    # we don't need old root partitions any more
    vps2routeros::umount_disks

    # format and install RouterOS
    vps2routeros::install_routeros
    vps2routeros::write_routeros_init_script

    echo -e "Rebooting into RouterOS..."
    ### END main procedure
else
    # we are at phase 1
    echo -e "We will start a temporary RAM system as your recovery environment."
    echo -e "Note that this script will kill programs and umount filesystems without prompting."
    echo -e "Please confirm:"
    echo -e "\tYou have closed all programs you can, and backed up all important data"
    echo -e "\tYou can SSH into your system as root user"
    vps2routeros::confirm || exit -1

    vps2routeros::get_menhera
    menhera::get_rootfs
    menhera::sync_filesystem

    menhera::prepare_environment
    vps2routeros::download_routeros
    menhera::mount_new_rootfs
    menhera::copy_config
    menhera::install_software
    vps2routeros::install_shell
    menhera::swap_root

    ! rm -f ${PHASE1_TRIGGER}
    ! rm -f ${PHASE2_TRIGGER}

    echo -e "If you are connecting from SSH, please create a second session to this host use root user"
    echo -e "to continue installation."

    vps2routeros::wait_file ${PHASE2_TRIGGER}
    echo -e "You have logged in, please continue in the new session. This session will now disconnect."
    vps2routeros::clear_processes
fi
