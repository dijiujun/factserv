#!/bin/bash -eu

die() { echo $* >&2; exit 1; }
((!UID)) || die "Must be root"

# read the config file
here=${0%/*}
source $here/install.cfg

if (($#)); then
    # argument is -u?
    (($# == 1)) && [[ $1 == -u ]] || die "Usage: $0 [-u]"

    [ -f /etc/factory/installed ] || die "Can't uninstall, try '$0'"

    ifdown $dut_interface || true

    # Delete overlay files
    for f in $(find $here/overlay -type f,l -printf "%P\n"); do
        rm -f /$f

        # restore originals from backup
        ! [ -e /$f~ ] || cp -vP /$f~ /$f
    done

    # Delete etc/factory to show we did this
    rm -rf etc/factory

    echo "###################"
    echo "Uninstall complete!"
    exit 0
fi

! [ -f /etc/factory/install ] || die "$(cat /etc/factory/install) is currently installed, try '$0 -u' first"

# Verify interfaces
[[ -e /sys/class/net/$factory_interface ]] || die "Invalid network interface $factory_interface"
(($(cat /sys/class/net/$factory_interface/carrier 2>/dev/null))) || die "$factory_interface must be connected!"

[[ -e /sys/class/net/$dut_interface ]] || die "Invalid network interface $dut_interface"
! (($(cat /sys/class/net/$dut_interface/carrier 2>/dev/null))) || die "$dut_interface must not be connected!"

# Install packages
export DEBIAN_FRONTEND=noninteractive
apt update
apt upgrade
apt install -y apache2 arping curl dnsmasq htop iptables-persistent links mlocate net-tools postgresql psmisc python-psycogreen resolvconf smartmontools sudo sysstat tcpdump tmux vim

# Copy overlay files to root, backup existing
for file in $(find $here/overlay -type f,l -printf "%P\n"); do

    # create directory if needed
    [[ -d /${file%/*} ]] || mkdir -v -p /${file%/*}

    # copy with backup
    cp -v -P -b $here/overlay/$file /$file

    # also try to files
    [ -h /$file ] ||
    sed -i "s/FACTORY_INTERFACE/$factory_interface/g;
            s/DUT_INTERFACE/$dut_interface/g;
            s/DUT_IP/$dut_ip/g;
            s/DUT_NET/${dut_ip%.*}.*/g;
            s/ORGANIZATION/$organization/g;" /$file
done

git rev-parse HEAD --abbrev-ref HEAD > /etc/factory/installed

# Fix permissions
chown -R factory: ~factory/
chmod -R go= ~factory/.ssh
chown root:factory /var/www/html/downloads
chmod 775 /var/www/html/downloads

echo "Configuring postgresql, ignore warnings on reinstall"
su -lc "psql -f /etc/factory/schema.txt" postgres

# configure Apache
a2enmod cgi
a2enmod ssl
a2ensite default-ssl

# force UCT
ln -sf /usr/share/zoneinfo/UCT /etc/localtime

# configure iptables
iptables -F # flush everything
iptables -X # delete user chains
iptables -Z # zero counters

# trust lo
iptables -A INPUT -i lo -j ACCEPT

# allow expected
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# ssh from anywhere
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# http from dut interface
iptables -A INPUT -i $dut_interface -p tcp --dport 80 -j ACCEPT

# dhcp from dut interface
iptables -A INPUT -i $dut_interface -p udp --dport 67 -j ACCEPT

# dns from dut interface
iptables -A INPUT -i $dut_interface -p udp --dport 53 -j ACCEPT
iptables -A INPUT -i $dut_interface -p tcp --dport 53 -j ACCEPT

# https from non-routable networks
iptables -A INPUT -p tcp -s 10.0.0.0/8     --dport 443 -j ACCEPT
iptables -A INPUT -p tcp -s 172.16.0.0/12  --dport 443 -j ACCEPT
iptables -A INPUT -p tcp -s 192.168.0.0/16 --dport 443 -j ACCEPT

# NAT forward DUTs
iptables -t nat -A POSTROUTING -o $factory_interface -j MASQUERADE

# drop all other inputs
iptables -P INPUT DROP

# save for boot script
iptables-save > /etc/iptables/rules.v4

# disable ipv6
ip6tables -F # flush everything
ip6tables -P INPUT DROP
ip6tables-save > /etc/iptables/rules.v6

# configure dnsmasq
ifup $dut_interface
/etc/factory/update.dnsmasq

echo "#################"
echo "Install complete!"
