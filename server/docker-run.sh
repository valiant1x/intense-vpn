#!/bin/bash

set -e

export CONF=/etc/lthn
export HOME=/var/lib/lthn

errorExit(){
    echo "$2" >&2
    echo "Exiting with return code $1" >&2
    exit $1
}

prepareConf(){
    cat >/etc/lthn/rsyslog.conf <<EOF

module(load="imuxsock") # provides support for local system logging
module(load="imklog")   # provides kernel logging support
$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat

$FileOwner root
$FileGroup adm
$FileCreateMode 0640
$DirCreateMode 0755
$Umask 0022

$WorkDirectory /var/spool/rsyslog

*.*                        /dev/console

EOF
}

runDaemon(){
    . /etc/default/lethean-daemon
    letheand start --non-interactive --standard-json --config-file ${LETHEAND_CONFIG} --pidfile ${LETHEAND_PID} --log-file ${LETHEAND_LOG} --data-dir ${LETHEAND_DATA}
    letheand status
    tail -f /var/log/lthn/letheand.log
}

runWalletVpnRpc(){
    . /etc/default/lethean-wallet-vpn-rpc
    rm -f /var/lib/lthn/lethean-wallet-vpn-rpc.*.login
    lethean-wallet-vpn-rpc --vpn-rpc-bind-port ${RPCPORT} --password ${WALLETPASS} --rpc-login ${RPCLOGIN} --daemon-host ${DAEMONHOST} --wallet-file ${LETHEANWALLET} --log-file /dev/stdout &
}

runWalletCli(){
    lethean-wallet-cli "$@"
}

refreshWallet(){
    [ -z "$WALLETRESTOREHEIGHT" ] && WALLETRESTOREHEIGHT="464227"
    . /etc/default/lethean-wallet-vpn-rpc
    lethean-wallet-cli --wallet $WALLETFILE --daemon-host ${DAEMONHOST} --restore-height "$WALLETRESTOREHEIGHT" --password "$WALLETPASS" --log-file /dev/stdout --log-level 4 --command refresh
}

testServerConf(){
    if ! [ -f /etc/lthn/sdp.json ] || ! [ -f /etc/lthn/dispatcher.ini ]; then
        errorExit 1 "We are not configured! Exiting! Run easy-deploy first or configure manually"
    fi
}

prepareSquid(){
cat >$CONF/squid.conf <<EOF
acl SSL_ports port 443
acl Safe_ports port 80          # http
acl Safe_ports port 21          # ftp
acl Safe_ports port 443         # https
acl Safe_ports port 70          # gopher
acl Safe_ports port 210         # wais
acl Safe_ports port 1025-65535  # unregistered ports
acl Safe_ports port 280         # http-mgmt
acl Safe_ports port 488         # gss-http
acl Safe_ports port 591         # filemaker
acl Safe_ports port 777         # multiling http
acl Safe_ports port 8080
acl SSL_ports port 8443
acl SSL_ports port 8080
acl SSL_ports port 80
acl CONNECT method CONNECT
acl localnet dst 172.16.0.0/12
acl localnet dst 192.168.0.0/16
acl localnet dst 10.0.0.0/8
access_log syslog:local0.info squid
cache_log /dev/null
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access deny localnet
http_access allow localhost manager
http_access deny manager
http_access allow localhost
http_access deny all
http_port 3128
coredump_dir /var/spool/squid
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320
EOF
}

prepareZabbix(){
cat >$CONF/zabbix_agentd.conf <<EOF
PidFile=/var/lib/lthn/zabbix_agentd.pid
LogFile=/dev/null
LogFileSize=0
Server=127.0.0.1
ServerActive=127.0.0.1
HostnameItem=system.hostname
EOF
}

case $1 in
easy-deploy)
    if ! [ -f /etc/lthn/dispatcher.ini ]; then
        cp /etc/skel/lthn/* /etc/lthn/
    fi
    chown -R lthn:lthn /var/lib/lthn /etc/lthn
    lthn-easy-deploy-node.sh
    echo >&2
    ;;

prepare-conf)
    prepareConf
    ;;

upload-sdp)
    lvmgmt --upload-sdp
    ;;

lthnvpnd|run)
    cd /var/lib/lthn
    testServerConf
    . /etc/default/lethean-wallet-vpn-rpc
    if ! [ -f $CONF/zabbix_agentd.conf ]; then
      prepareZabbix || { errorExit 2 "Cannot create $CONF/zabbix_agentd.conf! "; }
    fi
    echo "Starring syslog" >&2
    rsyslogd -f /etc/lthn/rsyslog.conf
    if [ -x /usr/sbin/zabbix_agentd ]; then
       echo "Starting zabbix agent" >&2
       zabbix_agentd -c $CONF/zabbix_agentd.conf
    fi
    if ! [ -f $CONF/squid.conf ]; then
      prepareSquid || { errorExit 2 "Cannot create $CONF/squid.conf! "; }
    fi
    echo "Starting squid -f $CONF/squid.conf" >&2
    squid -f $CONF/squid.conf
    if [ -z "$DAEMON_HOST" ]; then
        runDaemon
    fi
    refreshWallet
    runWalletVpnRpc
    unset HTTP_PROXY
    unset http_proxy
    shift
    while ! curl "$WALLETRPCURI" >/dev/null 2>/dev/null; do
        echo "Waiting for walet rpc server."
        sleep 5
    done

    echo "Starting dispatcher" >&2
    exec su -s /bin/sh lthn -c "lthnvpnd --wallet-rpc-uri '$WALLETRPCURI' --syslog $@"
    ;;

wallet-vpn-rpc)
    shift
    runWalletVpnRpc "$@"
    ;;

wallet-refresh)
    shift
    refreshWallet
    ;;

wallet-cli)
    shift
    runWalletCli "$@"
    ;;

zsync-make)
    if [ -d "$LMDB" ]; then
        cd $LMDB
        zsyncmake -v -b 262144 -f data.mdb -u "$ZSYNC_DATA_URL" data.mdb
        sha256sum data.mdb | cut -d ' ' -f 1 >data.mdb.sha256
    else
        errorExit 2 "LMDB database does not exist!"
    fi
    ;;

sync-bc)
    shift
    letheand syncbc
    ;;

clean-bc)
    shift
    letheand cleanbc
    ;;

letheand)
    shift
    runDaemon "$@"
    ;;

connect|lthnvpnc)
    if ! [ -f "$CONF/ha_info.http" ] || ! [ -f "$CONF/dispatcher.ini" ]; then
        prepareConf
    fi
    shift
    exec lthnvpnc connect --syslog "$@"
    ;;

list)
    if ! [ -f "$CONF/ha_info.http" ] || ! [ -f "$CONF/dispatcher.ini" ]; then
        prepareConf
    fi
    shift
    exec lthnvpnc list "$@"
    ;;

lvmgmt)
    shift
    exec lvmgmt "$@"
    ;;

root)
    cd /home/lthn
    su --preserve-environment lthn
    ;;

sh|bash)
    /bin/bash
    ;;

*)
    echo "Bad command. Use one of:"
    echo "run [args] to run dispatcher"
    echo "list [args] to list available services"
    echo "connect uri [args] to run client"
    echo "letheand [args] to run letheand"
    echo "easy-deploy [args] to easy deploy node"
    echo "prepare-conf [args] to prepare new conf dir"
    echo "upload-sdp [args] to upload SDP"
    echo "sync-bc to fast sync blockhain data from server."
    echo "clean-bc to clean blockchain data."
    echo "wallet-vpn-rpc [args] to run wallet-rpc-daemon"
    echo "wallet-cli [args] to run wallet-cli"
    echo "sh to go into shell" 
    exit 2
    ;;
esac
