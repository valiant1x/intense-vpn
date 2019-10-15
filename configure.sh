#!/usr/bin/env bash

# set PATH to find all binaries
PATH=$PATH:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin
if [ -z "$TOPDIR" ]; then
  export TOPDIR=$(realpath $(dirname $0))
fi
export PARMS="$@"

# Static defaults
LTHN_PREFIX=/opt/lthn/

# General usage help
usage() {
   echo
   echo "To configure server:"
   echo $0 "--server [--openvpn-bin bin] [--openssl-bin bin] [--haproxy-bin bin] [--python-bin bin] [--pip-bin bin] [--runas-user user] [--runas-group group] [--prefix prefix] [--with-capass pass] [--with-cn commonname] [--with-wallet-address address] [--with-wallet-rpc-pass pass] [--with-wallet-rpc-user user] [--with-wallet-rpc-uri uri] [--generate-ca] [--generate-dh] [--install-service] [--generate-ini] [--generate-providerid] [--with-providerid id --with-providerkey key]"
   echo
   echo "To configure client:"
   echo $0 "--client [--openvpn-bin bin] [--openssl-bin bin] [--haproxy-bin bin] [--python-bin bin] [--pip-bin bin] [--runas-user user] [--runas-group group] [--prefix prefix]"
   echo
   echo "To configure server and client:"
   echo $0 "--client --server ..."
   echo
   echo "To easy configure server and client:"
   echo $0 "--easy ..."
   echo
   exit
}

# Find command or report error. If env is already set, only test availability
# $1 - cmd
# $2 - env to get/set
# $3 - optional
findcmd() {
    local cmd="$1"
    local env="$2"
    eval "bin=\$$env"

    if [ -z "$bin" ]; then
        bin=$(PATH=$PATH:/usr/sbin which $cmd)
    fi

    if [ -z "$3" ]; then
      if [ -z "$bin" ]; then
        echo "Missing $cmd!"
      fi
    else
      if [ -z "$bin" ]; then
        echo "Not found $cmd"
      fi
    fi
    eval "$env=$bin"
}

defaults() {
    findcmd openvpn OPENVPN_BIN optional
    findcmd openssl OPENSSL_BIN
    findcmd haproxy HAPROXY_BIN
    findcmd python3 PYTHON_BIN
    findcmd pip3 PIP_BIN optional
    findcmd sudo SUDO_BIN optional

    [ -z "$LTHN_USER" ] && LTHN_USER="`whoami`"
    [ -z "$LTHN_GROUP" ] && LTHN_GROUP="$LTHN_USER"
    wallet_address="izxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    wallet_rpc_uri=http://127.0.0.1:14660/json_rpc
    wallet_rpc_user=dispatcher
    wallet_rpc_pass=SecretPass
}

summary() {
    echo
    if [ -z "$PYTHON_BIN" ] || [ -z "$HAPROXY_BIN" ] || [ -z "$OPENSSL_BIN" ]; then
        echo "Missing some dependencies to run intense-vpn. Look above. Exiting."
        usage
        exit 1
    fi

    echo "Intense-vpn configured."
    echo "Python bin:   $PYTHON_BIN"
    echo "pip bin:      $PIP_BIN"
    echo "sudo bin:     $SUDO_BIN"
    echo "Openssl bin:  $OPENSSL_BIN"
    echo "Openvpn bin:  $OPENVPN_BIN"
    echo "HAproxy bin:  $HAPROXY_BIN"
    echo "Prefix:       $LTHN_PREFIX"
    echo "Bin dir:      $bin_dir"
    echo "Conf dir:     $sysconf_dir"
    echo "CA dir:       $ca_dir"
    echo "Data dir:     $data_dir"
    echo "Temp dir:     $tmp_dir"
    echo "Run as user:  $LTHN_USER"
    echo "Run as group: $LTHN_GROUP"
    echo "Server:       $server"
    echo "Client:       $client"
    echo
}


# Generate root CA and keys
generate_ca() {
    local prefix="$1"
    local cn="$2"

    echo "Generating CA $cn"
    cd $prefix || exit 2
    mkdir -p private certs csr newcerts || exit 2
    touch index.txt
    echo -n 00 >serial
    "${OPENSSL_BIN}" genrsa -aes256 -out private/ca.key.pem -passout pass:$cert_pass 4096
    chmod 400 private/ca.key.pem
    "${OPENSSL_BIN}" req -config $TOPDIR/conf/ca.cfg -batch -subj "/CN=$cn" -passin pass:$cert_pass \
      -key private/ca.key.pem \
      -new -x509 -days 7300 -sha256 -extensions v3_ca \
      -out certs/ca.cert.pem
    if ! [ -f certs/ca.cert.pem ]; then
        echo "Error generating CA! See messages above."
        exit 2
    fi
}

generate_crt() {
    local name="$1"
    local cn="$2"
    echo "Generating crt (name=$name,cn=$cn)"
    "${OPENSSL_BIN}" genrsa -aes256 \
      -out private/$name.key.pem -passout pass:$cert_pass 4096
    chmod 400 private/$name.key.pem
    "${OPENSSL_BIN}" req -config $TOPDIR/conf/ca.cfg -batch -subj "/CN=$cn" -passin "pass:$cert_pass" \
      -key private/$name.key.pem \
      -new -sha256 -out csr/$name.csr.pem
    "${OPENSSL_BIN}" ca -batch -config $TOPDIR/conf/ca.cfg -subj "/CN=$cn" -passin "pass:$cert_pass" \
      -extensions server_cert -days 375 -notext -md sha256 \
      -in csr/$name.csr.pem \
      -out certs/$name.cert.pem
    (cat certs/ca.cert.pem certs/$name.cert.pem; openssl rsa -passin "pass:$cert_pass" -text <private/$name.key.pem) >certs/$name.all.pem
    (cat certs/$name.cert.pem; openssl rsa -passin "pass:$cert_pass" -text <private/$name.key.pem) >certs/$name.both.pem
    if ! [ -f certs/$name.cert.pem ]; then
        echo "Error generating cert $name! See messages above."
        exit 2
    fi
}

generate_env() {
    cat <<EOF
LTHN_PREFIX=$LTHN_PREFIX
OPENVPN_BIN=$OPENVPN_BIN
PYTHON_BIN=$PYTHON_BIN
PIP_BIN=$PIP_BIN
SUDO_BIN=$SUDO_BIN
LVMGMT_BIN=$LVMGMT_BIN
HAPROXY_BIN=$HAPROXY_BIN
OPENSSL_BIN=$OPENSSL_BIN
LTHN_USER=$LTHN_USER
LTHN_GROUP=$LTHN_GROUP
SERVER=$server
CLIENT=$client

EOF
}

defaults

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -h|--help)
        usage
    ;;
    --prefix)
        LTHN_PREFIX="$2"
        shift
        shift
    ;;
    --openvpn-bin)
        OPENVPN_BIN="$2"
        shift
        shift
    ;;
    --haproxy-bin)
        HAPROXY_BIN="$2"
        shift
        shift
    ;;
    --openssl-bin)
        OPENSSL_BIN="$2"
        shift
        shift
    ;;
    --python-bin)
        PYTHON_BIN="$2"
        shift
        shift
    ;;
    --pip-bin)
        PIP_BIN="$2"
        shift
        shift
    ;;
    --sudo-bin)
        SUDO_BIN="$2"
        shift
        shift
    ;;
    --lvmgmt-bin)
        LVMGMT_BIN="$2"
        shift
        shift
    ;;
    --runas-user)
        LTHN_USER="$2"
        shift
        shift
    ;;
    --runas-group)
        LTHN_GROUP="$2"
        shift
        shift
    ;;
    --with-capass)
        cert_pass="$2"
        shift
        shift
    ;;
    --with-cn)
        cert_cn="$2"
        shift
        shift
    ;;
    --with-wallet-address)
        wallet_address="$2"
        cfg_wallet=1
        shift
        shift
    ;;
    --with-wallet-rpc-uri)
        wallet_rpc_uri="$2"
        cfg_wallet=1
        shift
        shift
    ;;
    --with-wallet-rpc-user)
        wallet_rpc_user="$2"
        cfg_wallet=1
        shift
        shift
    ;;
    --with-wallet-rpc-pass)
        wallet_rpc_pass="$2"
        cfg_wallet=1
        shift
        shift
    ;;
    --with-providerid)
        PROVIDERID="$2"
        generate_ini=1
        shift
        shift
    ;;
    --with-providerkey)
        PROVIDERKEY="$2"
        generate_ini=1
        shift
        shift
    ;;
    --generate-providerid)
        generate_providerid=1
        generate_ini=1
        shift
    ;;
    --generate-ca)
        generate_ca=1
        shift
    ;;
    --generate-dh)
        generate_dh=1
        shift
    ;;
    --generate-ini)
        generate_ini=1
        shift
    ;;
    --install-service)
        install_service=1
        shift
    ;;
    --easy)
        cert_pass="1234"
        cert_cn="LTHNEasyDeploy"
        LTHN_USER="`whoami`"
        install_service=1
        generate_providerid=1
        generate_ca=1
        generate_ini=1
        generate_dh=1
        server=1
        client=1
        shift
    ;;
    --client)
        client=1
        shift
    ;;
    --server)
        server=1
        shift
    ;;
    *)
    echo "Unknown option $1"
    usage
    exit 1;
    ;;
esac
done

if [ -z "$client" ] && [ -z "$server" ]; then
    echo "You must select which parts to configure".
    $0 -h
    exit 1
fi

if [ "${LTHN_PREFIX}" != "/" ]; then
  bin_dir=${LTHN_PREFIX}/bin/
  sysconf_dir=${LTHN_PREFIX}/etc/
  ca_dir=${LTHN_PREFIX}/etc/ca/
  data_dir=${LTHN_PREFIX}/var/
  tmp_dir=${LTHN_PREFIX}/tmp/
else
  bin_dir=${LTHN_PREFIX}usr/bin/
  sysconf_dir=${LTHN_PREFIX}etc/lthn/
  ca_dir=${LTHN_PREFIX}etc/lthn/ca/
  data_dir=${LTHN_PREFIX}var/lib/lthn/
  tmp_dir=${LTHN_PREFIX}tmp/
fi

if ! $HAPROXY_BIN -v | grep -qE "version 1.7|version 1.6|version 1.8|version 1.9"; then
    echo "Incompatible version of haproxy! You need 1.6.x, 1.7.x, 1.8.x or 1.9.x version for now."
    $HAPROXY_BIN -v
    exit 1
fi

if [ -f server/lvmgmt.py ]; then
  LVMGMT_BIN=server/lvmgmt.py
else
  LVMGMT_BIN=/usr/bin/lvmgmt
fi

mkdir -p build
if [ -n "$generate_ca" ] && ! [ -f build/etc/ca/index.txt ]; then
    export cert_pass cert_cn
    if [ -z "$cert_pass" ] || [ -z "$cert_cn" ] ; then
        echo "You must specify --with-capass yourpassword --with_cn CN!"
        exit 2
    fi
    if [ "$cert_pass" = "1234" ]; then
    	echo "Generating with default password!"
    fi
    (
    rm -rf build/etc/ca
    mkdir -p build/etc/ca
    generate_ca build/etc/ca/ "$cert_cn"
    generate_crt openvpn "$cert_cn.openvpn"
    generate_crt ha "$cert_cn.ha"
    )
fi

mkdir -p build/etc

if [ -n "$generate_dh" ]; then
    if ! [ -f  build/etc/dhparam.pem ]; then
      "$OPENSSL_BIN" dhparam -out build/etc/dhparam.pem 2048
    fi
fi

if [ -n "$PROVIDERID" ]; then
    echo $PROVIDERID >build/etc/provider.public
    echo $PROVIDERKEY >build/etc/provider.private
else
    if [ -n "$generate_providerid" ]; then
        "$PYTHON_BIN" "$LVMGMT_BIN" --wallet-address 'izxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' --audit-log build/audit.log --ca '' -f conf/dispatcher.ini.tmpl --generate-providerid build/etc/provider || exit 1
    fi
fi

if [ -n "$generate_ini" ]; then
    sed \
        -e "s#{ca}#${LTHN_PREFIX}/etc/ca/certs/ca.cert.pem#g" \
        -e "s#{providerid}#$(cat build/etc/provider.public)#g" \
        -e "s#{providerkey}#$(cat build/etc/provider.private)#g" \
        -e "s#{vpncrt}#${LTHN_PREFIX}/etc/ca/certs/openvpn.cert.pem#g" \
        -e "s#{vpnkey}#${LTHN_PREFIX}/etc/ca/private/openvpn.key.pem#g" \
        -e "s#{vpnboth}#${LTHN_PREFIX}/etc/ca/certs/openvpn.both.pem#g" \
        -e "s#{hacrt}#${LTHN_PREFIX}/etc/ca/certs/ha.cert.pem#g" \
        -e "s#{hakey}#${LTHN_PREFIX}/etc/ca/private/ha.key.pem#g" \
        -e "s#{haboth}#${LTHN_PREFIX}/etc/ca/certs/ha.both.pem#g" \
        -e "s#{wallet_rpc_user}#$wallet_rpc_user#g" \
        -e "s#{wallet_rpc_pass}#$wallet_rpc_pass#g" \
        -e "s#{wallet_address}#$wallet_address#g" \
        -e "s#{wallet_rpc_uri}#$wallet_rpc_uri#g" \
      <conf/dispatcher.ini.tmpl >build/etc/dispatcher.ini
    if [ -n "$cfg_wallet" ]; then
       sed -i -e "s#^;wallet-address#wallet-address#g" build/etc/dispatcher.ini
       sed -i -e "s#^;wallet-rpc-uri#wallet-rpc-uri#g" build/etc/dispatcher.ini
       sed -i -e "s#^;wallet-username#wallet-username#g" build/etc/dispatcher.ini
       sed -i -e "s#^;wallet-password#wallet-password#g" build/etc/dispatcher.ini
    fi
fi

if [ -n "$install_service" ] && [ -f conf/lthnvpnd.service ] ; then
    mkdir -p build/etc/systemd/system
    cp conf/lthnvpnd.service build/etc/systemd/system/
fi

if [ -n "$client"  ]; then
    touch build/etc/dispatcher.ini
fi

generate_env >env.mk
summary

if [ -n "$PARMS" ]; then
    echo "./configure.sh $PARMS" >configure.log
fi
