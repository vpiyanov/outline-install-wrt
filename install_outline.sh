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

# Step 11: Create script /etc/init.d/tun2socks
if [ ! -f "/etc/init.d/tun2socks" ]; then
cat <<EOL > /etc/init.d/tun2socks
#!/bin/sh /etc/rc.common
USE_PROCD=1

# start after network and stop before
START=99
STOP=89

OUTLINEIP="$OUTLINEIP"
OUTLINECONF="$OUTLINECONF"
DEVICE="tun1"
LOGLEVEL="warning"
BUFFER="64kb"
NO_WAN_DEFAULT_ROUTE_WHEN_SERVICE_ENABLED="y"
DEFAULT_ROUTE_BACKUP="/tmp/default_route.backup"

start_service() {
    logger -s -t tun2socks "Starting..."
    DEFAULT_GW=\$(ip route | grep default | awk '{print \$3}')
    if [ -z "\$DEFAULT_GW" ]; then
        WWAN_GW=\$(ifstatus wwan | jsonfilter -e '\$.route[@.target="0.0.0.0"].nexthop' || ifstatus wwan | jsonfilter -e '\$.inactive.route[@.target="0.0.0.0"].nexthop')
        WAN_GW=\$(ifstatus wan | jsonfilter -e '\$.route[@.target="0.0.0.0"].nexthop' || ifstatus wan | jsonfilter -e '\$.inactive.route[@.target="0.0.0.0"].nexthop')
        DEFAULT_GW=\${WAN_GW:-\$WWAN_GW}

        if [ -z "\$DEFAULT_GW" ]; then
            logger -s -t tun2socks "Default route is not set. Not able to found gateway for wwan/wan."
            exit 1
        else
            logger -s -t tun2socks "Default route is not set. Gateway for wwan/wan identified automatically: \$DEFAULT_GW"
        fi
    else
        logger -s -t tun2socks "Default route is set. Save previous default route to \$DEFAULT_ROUTE_BACKUP"
        ip route save default > "\$DEFAULT_ROUTE_BACKUP"
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

    logger -s -t tun2socks "...Started!"
}

stop_service() {
    logger -s -t tun2socks "Stopping..."
    DEFAULT_IFACE=\$(ip route | awk '/default/ {print \$5}')

    service_stop /usr/bin/tun2socks

    if [ "\$DEFAULT_IFACE" = "\$DEVICE" ] && [ -e "\$DEFAULT_ROUTE_BACKUP" ]; then
        logger -s -t tun2socks "Restore previous default route"
        ip route restore default < "\$DEFAULT_ROUTE_BACKUP"
        rm "\$DEFAULT_ROUTE_BACKUP"
    fi

    if ip route | grep -q "\$OUTLINEIP"; then
        logger -s -t tun2socks "Delete route to OUTLINE Server"
        ip route del "\$OUTLINEIP"
    fi

    logger -s -t tun2socks "...Stopped!"
}

# Copied from /etc/rc.common:
default_disable() {
    name="\$(basename "\${initscript}")"
    rm -f "\$IPKG_INSTROOT"/etc/rc.d/S??\$name
    rm -f "\$IPKG_INSTROOT"/etc/rc.d/K??\$name
}
# Copied from /etc/rc.common:
default_enable() {
    err=1
    name="\$(basename "\${initscript}")"
    [ "\$START" ] && \
        ln -sf "../init.d/\$name" "\$IPKG_INSTROOT/etc/rc.d/S\${START}\${name##S[0-9][0-9]}" && \
        err=0
    [ "\$STOP" ] && \
        ln -sf "../init.d/\$name" "\$IPKG_INSTROOT/etc/rc.d/K\${STOP}\${name##K[0-9][0-9]}" && \
        err=0
    return \$err
}

# Custom enable command
enable() {
    logger -s -t tun2socks "Enabling..."

    default_enable

    if [ "\$NO_WAN_DEFAULT_ROUTE_WHEN_SERVICE_ENABLED" = "y" ]; then
        logger -s -t tun2socks "Disable default route for WAN/WWAN"
        uci set network.wwan.defaultroute='0'
        uci set network.wan.defaultroute='0'
        uci commit network
    fi

    start
    logger -s -t tun2socks "...Enabled"
}

# Custom disable command
disable() {
    logger -s -t tun2socks "Disabling..."

    stop
    default_disable

    if [ "\$NO_WAN_DEFAULT_ROUTE_WHEN_SERVICE_ENABLED" = "y" ]; then
        logger -s -t tun2socks "Enable default route for WAN/WWAN"
        uci set network.wwan.defaultroute='1'
        uci set network.wan.defaultroute='1'
        uci commit network

        logger -s -t tun2socks "Restart WAN/WWAN to set default route"
        ifup wwan
        ifup wan
    fi
    logger -s -t tun2socks "...Disabled"
}
EOL
chmod +x /etc/init.d/tun2socks
echo 'script /etc/init.d/tun2socks created'
fi

# Ask user to use Outline as default gateway
DEFAULT_GATEWAY="y"
echo -n "Use Outline as default gateway? [y]: "
read DEFAULT_GATEWAY
if [ "$DEFAULT_GATEWAY" = "y" ] || [ -z "$DEFAULT_GATEWAY" ]; then
    uci set network.tunnel.defaultroute='1'
    uci commit
fi

# Enable or disable tun2sock when VPN toggle switch changes status
USE_SWITCH_BUTTON="n"
echo -n "Use physical switch button to toggle VPN stage? [n]: "
read USE_SWITCH_BUTTON
if [ "$USE_SWITCH_BUTTON" = "y" ]; then
cat <<EOL > /etc/rc.button/BTN_0
#!/bin/sh
if [ "\$ACTION" = "pressed" ]; then
   logger -t vpn-switch-button "VPN switch \$BUTTON changed to ON - starting VPN tunnel"
   /etc/init.d/tun2socks enable
fi
if [ "\$ACTION" = "released" ]; then
   logger -t vpn-switch-button "VPN switch \$BUTTON changed to OFF - stopping VPN tunnel"
   /etc/init.d/tun2socks disable
fi
EOL
chmod a+rwx /etc/rc.button/BTN_0
fi

# Step 15: Enable or disable tun2sock when VPN push button is pressed
USE_PUSH_BUTTON="n"
echo -n "Use physical push button (e.g. WPS) to toggle VPN stage? [n]: "
read USE_PUSH_BUTTON
if [ "$USE_PUSH_BUTTON" = "y" ]; then
cat <<EOL > /etc/rc.button/wps
#!/bin/sh
if [ "$ACTION" = "released" ]; then
  if [ "$SEEN" -lt 1 ]; then
    logger -t vpn-push-button "VPN push button '$BUTTON' short press - enabling VPN tunnel"
    /etc/init.d/tun2socks enable
  else
    logger -t vpn-push-button "VPN push button '$BUTTON' long press - disabling VPN tunnel"
    /etc/init.d/tun2socks disable
  fi
fi
chmod a+rwx /etc/rc.button/wps
EOL
fi

# Step 16: Restart tun2sock when wan/wwan change status
cat <<EOL > /etc/hotplug.d/iface/99-restart-tun2socks
if [ "\$INTERFACE" = "wan" ] || [ "\$INTERFACE" = "wwan" ]; then
    logger -t hotplug-iface "\$INTERFACE is \$ACTION"

    if /etc/init.d/tun2socks enabled; then
        logger -t hotplug-iface "VPN is enabled: restart tun2socks"
        /etc/init.d/tun2socks restart
    else
        logger -t hoplug-iface "VPN is disabled: do nothing"
    fi
fi
EOL

echo 'Script finished.'
/etc/init.d/tun2socks enable
