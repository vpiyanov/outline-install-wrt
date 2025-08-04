#!/bin/sh

echo "Deleting interface 'tunnel'"
uci delete network.tunnel

echo "Deleting firewall zone 'proxy'"
uci del firewall.$(uci show firewall | grep "name='proxy'" | cut -d. -f2)

echo "Deleting firewall forwarding 'lan-proxy'"
uci del firewall.$(uci show firewall | grep "name='lan-proxy'" | cut -d. -f2)


