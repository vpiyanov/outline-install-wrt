#!/bin/sh

if [ -f "/etc/init.d/tun2socks" ]; then
  /etc/init.d/tun2socks disable
  rm /etc/init.d/tun2socks
fi
if [ -f "/etc/hotplug.d/iface/99-restart-tun2socks" ]; then
  rm /etc/hotplug.d/iface/99-restart-tun2socks
fi
if [ -f "/usr/bin/tun2socks" ]; then
  rm /usr/bin/tun2socks
fi


if grep -q "config interface 'tunnel'" /etc/config/network; then
  echo "Deleting interface 'tunnel'"
  uci delete network.tunnel
fi
if grep -q "option name 'proxy'" /etc/config/firewall; then 
  echo "Deleting firewall zone 'proxy'"
  uci del firewall.$(uci show firewall | grep "name='proxy'" | cut -d. -f2)
  echo "Deleting firewall forwarding 'lan-proxy'"
  uci del firewall.$(uci show firewall | grep "name='lan-proxy'" | cut -d. -f2)
fi
uci commit

echo 'Restarting Network....'
/etc/init.d/network restart
