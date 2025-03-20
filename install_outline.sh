#!/bin/sh
# Outline scripted, xjasonlyu/tun2socks based installer for OpenWRT.
# https://github.com/vpiyanov/outline-install-wrt
echo 'Starting Outline OpenWRT install script'


# Step 1: Check for kmod-tun
opkg list-installed | grep kmod-tun > /dev/null
if [ $? -ne 0 ]; then
    echo "kmod-tun is not installed. Exiting."
    exit 1
    echo 'kmod-tun installed'
fi


# Step 2: Check for ip-full
opkg list-installed | grep ip-full > /dev/null
if [ $? -ne 0 ]; then
    echo "ip-full is not installed. Exiting."
    exit 1
    echo 'ip-full installed'
fi


# Step 3: Check for tun2socks then download tun2socks binary from GitHub
if [ ! -f "/tmp/tun2socks*" ]; then
ARCH=$(grep "OPENWRT_ARCH" /etc/os-release | awk -F '"' '{print $2}')
wget https://github.com/1andrevich/outline-install-wrt/releases/download/v2.5.1/tun2socks-linux-$ARCH -O /tmp/tun2socks
 # Check wget's exit status
    if [ $? -ne 0 ]; then
        echo "Download failed. No file for your Router's architecture"
        exit 1
   fi
fi


# Step 4: Check for tun2socks then move binary to /usr/bin
if [ ! -f "/usr/bin/tun2socks" ]; then
mv /tmp/tun2socks /usr/bin/
echo 'moving tun2socks to /usr/bin'
chmod +x /usr/bin/tun2socks
fi


# Step 5: Check for existing config in /etc/config/network then add entry
if ! grep -q "config interface 'tunnel'" /etc/config/network; then
echo "
config interface 'tunnel'
    option device 'tun1'
    option proto 'static'
    option ipaddr '172.16.10.1'
    option netmask '255.255.255.252'
    option gateway '172.16.10.2'
" >> /etc/config/network
    echo 'added entry into /etc/config/network'
fi
echo 'found entry into /etc/config/network'


# Step 6:Check for existing config /etc/config/firewall then add entry
if ! grep -q "option name 'proxy'" /etc/config/firewall; then 
echo "
config zone
    option name 'proxy'
    list network 'tunnel'
    option forward 'REJECT'
    option output 'ACCEPT'
    option input 'REJECT'
    option masq '1'
    option mtu_fix '1'
    option device 'tun1'
    option family 'ipv4'

config forwarding
    option name 'lan-proxy'
    option dest 'proxy'
    option src 'lan'
    option family 'ipv4'
" >> /etc/config/firewall
    echo 'added entry into /etc/config/firewall'
fi

echo 'found entry into /etc/config/firewall'


# Step 7: Restart network
echo 'Restarting Network....'
/etc/init.d/network restart
echo 'Restarted Network'


# Step 8: Read user variable for OUTLINE HOST IP
read -p "Enter Outline Server IP: " OUTLINEIP
# Read user variable for Outline config
read -p "Enter Outline (Shadowsocks) Config (format ss://base64coded@HOST:PORT/?outline=1): " OUTLINECONF


#Step 9. Check for default gateway and save it into DEFGW
#DEFGW=$(ip route | grep default | awk '{print $3}')
#echo 'checked default gateway'

#Step 10. Check for default interface and save it into DEFIF
#DEFIF=$(ip route | grep default | awk '{print $5}')
#echo 'checked default interface'


# Step 11: Create script /etc/init.d/tun2socks
if [ ! -f "/etc/init.d/tun2socks" ]; then
cat <<EOL > /etc/init.d/tun2socks
#!/bin/sh /etc/rc.common
USE_PROCD=1

# start after network and stop before
START=99
STOP=89

OUTLINEIP="45.89.55.209"
OUTLINECONF="ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpIaDc2aTBNNmxLaXExdzBuS2p4cGg4@45.89.55.209:16490/?outline=1"
DEVICE="tun1"
LOGLEVEL="warning"
BUFFER="64kb"

start_service() {
    DEFAULT_GW=\$(ip route | grep default | awk '{print \$3}')
    if [ -z "\$DEFAULT_GW" ]; then
        WWAN_GW=\$(ifstatus wwan | jsonfilter -e '\$.*.route[@.target="0.0.0.0"].nexthop' || ifstatus wwan | jsonfilter -e '\$.inactive.route[@.target="0.0.0.0"].nexthop')
        WAN_GW=\$(ifstatus wan | jsonfilter -e '\$.*.route[@.target="0.0.0.0"].nexthop' || ifstatus wan | jsonfilter -e '\$.inactive.route[@.target="0.0.0.0"].nexthop')
        DEFAULT_GW=\${WAN_GW:-\$WWAN_GW}

        if [ -z "\$DEFAULT_GW" ]; then
            logger -s -t tun2socks "Default route is not set. Not able to found gateway for wwan/wan."
            exit 1
        else
            logger -s -t tun2socks "Default route is not set. Gateway found automatically: \$DEFAULT_GW"
        fi
    else
        logger -s -t tun2socks "Default route is set. Save previous default route to /tmp/defroute.save"
        ip route save default > /tmp/defroute.save
    fi

    procd_open_instance
    procd_set_param user root
    procd_set_param command /usr/bin/tun2socks -device \$DEVICE -tcp-rcvbuf \$BUFFER -tcp-sndbuf \$BUFFER -proxy "\$OUTLINECONF" -loglevel \$LOGLEVEL
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn "3600" "5" "5"
    procd_close_instance

    logger -s -t tun2socks "Add route to OUTLINE Server"
    ip route add "\$OUTLINEIP" via "\$DEFAULT_GW"

    logger -s -t tun2socks "tun2socks is working!"
}

stop_service() {
    DEFAULT_IFACE=\$(ip route | awk '/default/ {print \$5}')

    service_stop /usr/bin/tun2socks

    if [ "\$DEFAULT_IFACE" = "\$DEVICE" ] && [ -e "/tmp/defroute.save" ]; then
        logger -s -t tun2socks "Restore previous default route"
        ip route restore default < /tmp/defroute.save
        rm /tmp/defroute.save
    fi

    if ip route | grep -q "\$OUTLINEIP"; then
        logger -s -t tun2socks "Delete route to OUTLINE Server"
        ip route del "\$OUTLINEIP"
    fi

    logger -s -t tun2socks "tun2socks has stopped!"
}
EOL

#DEFAULT_GATEWAY=""
#Ask user to use Outline as default gateway
#while [ "$DEFAULT_GATEWAY" != "y" ] && [ "$DEFAULT_GATEWAY" != "n" ]; do
#    echo "Use Outline as default gateway? [y/n]: "
#    read DEFAULT_GATEWAY
#done

echo 'script /etc/init.d/tun2socks created'
chmod +x /etc/init.d/tun2socks
fi


# Step 12: Create symbolic link
#if [ ! -f "/etc/rc.d/S99tun2socks" ]; then
#ln -s /etc/init.d/tun2socks /etc/rc.d/S99tun2socks
#echo '/etc/init.d/tun2socks /etc/rc.d/S99tun2socks symlink created'
#fi

# Step 15: Restart tun2sock when wan/wwan change status
cat <<EOL > /etc/hotplug.d/button/vpn
if [ "\$ACTION" = "pressed" ] && [ "\$BUTTON" = "BTN_0" ]; then
   logger -t hotplug-button "VPN switch changed to ON - starting VPN tunnel"
   /etc/init.d/tun2socks start
fi
if [ "\$ACTION" = "released" ] && [ "\$BUTTON" = "BTN_0" ]; then
   logger -t hotplug-button "VPN switch changed to OFF - stopping VPN tunnel"
   /etc/init.d/tun2socks stop
fi
EOL

# Step 14: Start or stop tun2sock when VPN switch changes status
cat <<EOL > /etc/hotplug.d/iface/99-restart-tun2socks
if [ "$INTERFACE" = "wan" ] || [ "$INTERFACE" = "wwan" ]; then
    logger -t hotplug-iface "$INTERFACE is $ACTION"

    if grep "gpio-512" /sys/kernel/debug/gpio | grep -q "lo"; then
        logger -t hotplug-iface "VPN switch is ON: restart tun2socks"
        /etc/init.d/tun2socks restart
    else
        logger -t hoplug-iface "VPN switch is OFF: doing nothing"
    fi
fi
EOL

# Step 15: Start service
#/etc/init.d/tun2socks start


echo 'Script finished'
