#!/bin/sh

/etc/init.d/tun2socks stop
/etc/init.d/tun2socks disable

echo "Deleting interface 'tunnel'"
uci delete network.tunnel

echo "Deleting firewall zone 'proxy'"
uci del firewall.$(uci show firewall | grep "name='proxy'" | cut -d. -f2)

echo "Deleting firewall forwarding 'lan-proxy'"
uci del firewall.$(uci show firewall | grep "name='lan-proxy'" | cut -d. -f2)

uci commit

rm /etc/init.d/tun2socks
rm /etc/hotplug.d/iface/99-restart-tun2socks
rm /usr/bin/tun2socks
