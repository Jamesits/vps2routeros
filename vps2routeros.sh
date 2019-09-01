#!/bin/bash

# VPS2RouterOS
# https://github.com/Jamesits/vps2routeros
# This script will cause permanent data loss
# Please read the documentation prior to running this
# You have been warned

### START config

# your default network interface to internet
# this is used to auto configure IPv4 after reboot
MAIN_INTERFACE=$(ip route list | grep default | head -n 1 | cut -d' ' -f 5)

# HDD device (not partition)
# May not be compatible with SCSI drives; see official document of RouterOS CHR
DISK=$(mount | grep ' /mnt/oldroot ' | cut -d' ' -f1 | sed 's/[0-9]*$//g')

# get IPv4 address in IP-CIDR format
ADDRESS=$(ip addr show $MAIN_INTERFACE | grep global | cut -d' ' -f 6 | head -n 1)

# get gateway IP
GATEWAY=$(ip route list | grep default | cut -d' ' -f 3)

# URL to RouterOS CHR
ROUTEROS_URL=https://download2.mikrotik.com/routeros/6.43.14/chr-6.43.14.img.zip

# URL to scripts
MENHERA_URL=https://cursed.im/menhera
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# mutex files
PHASE1_TRIGGER=/tmp/old_user_disconnected
PHASE2_TRIGGER=/tmp/new_user_connected

### END Phase 2 auto config

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
    echo "Preparing for phase 2..."
    # install dependencies of phase 2
    DEBIAN_FRONTEND=noninteractive chroot "${NEWROOT}" apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y pv util-linux udev

    # install ourselves into new rootfs for phase 2 execution
    cp ${SCRIPT_PATH} "${NEWROOT}/bin/vps2routeros"
    cat > "${NEWROOT}/bin/vps2routeros-loginshell" <<EOF
#!/bin/bash
/bin/vps2routeros --phase2
EOF
    chmod +x "${NEWROOT}/bin/vps2routeros"
    chmod +x "${NEWROOT}/bin/vps2routeros-loginshell"
    echo "/bin/vps2routeros-loginshell" >> /etc/shells

    chroot "${NEWROOT}" chsh -s /bin/vps2routeros-loginshell root
    
    # get rid of motd set up by menhera
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

    echo "Waiting for kernel to recognize the new disk..."
    # avoid racing with udev
    udevadm settle
    sleep 1
    
    ! partx -a $DISK
    udevadm settle
    sleep 1
    
    # we have to retry until it works
    while true; do
        if blockdev --rereadpt $DISK; then
            break
        fi
        sleep 1
    done
    
    udevadm settle
}

vps2routeros::write_routeros_init_script() {
    echo "Setting up RouterOS for first time use..."
    
    udevadm settle
    mkdir -p /mnt/routeros
    mount ${DISK}*1 /mnt/routeros
    cat > /mnt/routeros/rw/autorun.scr <<EOF
/ip address add address=$ADDRESS interface=[/interface ethernet find where name=ether1]
/ip route add gateway=$GATEWAY
/ip service disable telnet
/ip dns set servers=8.8.8.8,8.8.4.4
EOF
    umount /mnt/routeros
}

vps2routeros::reset() {
    echo "Rebooting..."
    sync; sync
    echo 1 > /proc/sys/kernel/sysrq
    echo b > /proc/sysrq-trigger
}

# https://stackoverflow.com/a/3232082/2646069
vps2routeros::confirm() {
    read -r -p "Continue? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            true
            ;;
        *)
            false
            ;;
    esac
}

vps2routeros::clear_processes_phase1() {
    echo "Disabling swap..."
    swapoff -a

    echo "Restarting init process..."
    menhera::__compat_reload_init
    
    touch ${PHASE1_TRIGGER}
}

vps2routeros::clear_processes_phase2() {
    echo -e "Waiting for init re-exec..."
    # hope 15s is enough for systemd re-exec to finish
    sleep 15

    echo "Killing all programs still using the old root..."
    OLDROOT=/mnt/oldroot
    fuser -kvm "${OLDROOT}" -15
}

vps2routeros::umount_disks() {
    echo "unmounting all partitions on disk ${DISK}..."
    
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
    # we are at phase 2, note that menhera.sh will not be loaded
    touch ${PHASE2_TRIGGER}
    
    if [[ $PHASE2_DEBUG -eq 1 ]]; then
        echo -e "You are entering phase 2 debug shell. Exit to continue installation."
        bash
    fi

    clear

    cat >> /dev/fd/2 <<EOF
VPS2RouterOS Phase 2 Checklist

We are going to install RouterOS onto the disk. 

Please confirm the settings:
Installation destination: ${DISK}
Network information:
    Interface: ${MAIN_INTERFACE}
    IPv4 address: ${ADDRESS}
    IPv4 gateway: ${GATEWAY}

Type y and press enter to continue the installation; type n and press enter to regret. If you choose to regret, the server will reboot.

IT IS YOUR LAST CHANCE TO REGRET.
EOF

    vps2routeros::confirm || vps2routeros::reset

    echo -e "Waiting for the last SSH connection to finish..."
    vps2routeros::wait_file ${PHASE1_TRIGGER}
    
    # end everything started by the old init
    vps2routeros::clear_processes_phase2
    
    # we don't need old root partitions any more
    vps2routeros::umount_disks

    # format and install RouterOS
    vps2routeros::install_routeros
    vps2routeros::write_routeros_init_script

    echo -e "Goodbye. See you in the RouterOS if everything is correct!"
    vps2routeros::reset
else
    # we are at phase 1
    clear
    
    cat >> /dev/fd/2 <<EOF
Welcome to VPS2RouterOS wizard. This script will convert your VPS to RouterOS. 

If you choose to continue, you acknowledge that:
    * You will strictly follow the guide displayed on the screen
    * All data on this server will be lost permenantly
    * All running processes will be force killed
    * The installation might not succeed; in this case, you will need to manually reboot or reinstall the server using methods provided by your server provider, and this might result in a fee
    * You have read and agreed the license of this script: https://github.com/Jamesits/vps2routeros/blob/master/LICENSE

Type y and press enter to continue the installation; type n and press enter to regret.
EOF
vps2routeros::confirm || exit -1

    clear

    cat >> /dev/fd/2 <<EOF
VPS2RouterOS Phase 1 Checklist

Please confirm:
    * You have closed all programs you can, and backed up all important data
    * You have disabled any firewall blocking SSH service (TCP port 22)
    * You can SSH into your system directly as root user (not via sudo, su, gksu or anything like that), either using password or SSH key (without PKI)
    * Your SSH client can maintain 2 SSH sessions to 1 server simultaneously

During the installation, other users except root will be unavailable. 

If something is wrong, cancel now, fix them and re-run this script.
EOF
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
    
    clear

    cat >> /dev/fd/2 <<EOF
VPS2RouterOS Phase Transition Checklist

We need you to go the temporary recovery environment we have just set up. 

Please execute:
    * Keep this SSH session connected
    * Start a new SSH session to this server with root user
    * Follow the instruction displayed on the new SSH session
EOF

    vps2routeros::wait_file ${PHASE2_TRIGGER}
    vps2routeros::clear_processes_phase1
    
    clear

    cat >> /dev/fd/2 <<EOF
Please now follow the instruction displayed on the new SSH session. This session will automatically disconnect in less than 1 minute.
EOF
    
    # Now we have done our job and can only wait to be killed
    while true; do sleep 1; done
fi
### END main procedure
