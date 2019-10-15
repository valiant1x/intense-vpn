#!/bin/sh

if ! [ -f /dev/net/tun ]; then
  mknod /dev/net/tun c 10 200  
  chmod 660 /dev/net/tun
  chown tun:netdev /dev/net/tun
fi

mkdir -p /var/run/lthn
chmod 770 /var/run/lthn
chown lthn:lthn /var/run/lthn

