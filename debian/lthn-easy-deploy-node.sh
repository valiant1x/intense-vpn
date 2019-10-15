#!/bin/bash

set -e

# Set defaults. Can be overriden by env variables
[ -z "$LTHNPREFIX" ] && LTHNPREFIX=/
[ -z "$PROVIDERID" ] && PROVIDERID=""
[ -z "$PROVIDERKEY" ] && PROVIDERKEY=""
[ -z "$DAEMON_HOST" ] && DAEMON_HOST="sync.lethean.io"
[ -z "$WALLETFILE" ] && WALLETFILE="/var/lib/lthn/wallet"
[ -z "$WALLETPASS" ] && WALLETPASS="walletpass"
[ -z "$WALLETRPCUSER" ] && WALLETRPCUSER="user"
[ -z "$WALLETRPCPASS" ] && WALLETRPCPASS="pass"
[ -z "$WALLETRPCHOST" ] && WALLETRPCHOST="127.0.0.1"
[ -z "$WALLETRPCPORT" ] && WALLETRPCPORT="13660"
[ -z "$WALLETRESTOREHEIGHT" ] && WALLETRESTOREHEIGHT="464227"
[ -z "$CAPASS" ] && CAPASS=1234
[ -z "$CACN" ] && CACN=ITNSFakeNode
[ -z "$ENDPOINT" ] && ENDPOINT="1.2.3.4"
[ -z "$PORT" ] && PORT="8080"
[ -z "$PROVTYPE" ] && PROVTYPE="residential"

export WALLETRPCURI="http://$WALLETRPCHOST:$WALLETRPCPORT/json_rpc"

if [ -z "$DAEMON_HOST" ]; then
  DAEMON_ARG=""
else
  DAEMON_ARG="--daemon-host $DAEMON_HOST"
fi

export LTHNPREFIX BRANCH CAPASS CACN ENDPOINT PORT PROVTYPE WALLET EMAIL DAEMON_BIN_URL DAEMON_HOST WALLETPASS \
  WALLETRPCUSER WALLETRPCPASS \
  PROVIDERID PROVIDERKEY ZABBIX_SERVER ZABBIX_PSK ZABBIX_PORT ZABBIX_META USER HOME HTTP_PROXY HTTPS_PROXY
  
sysdctl(){
  if [ "$(whoami)" == "root" ]; then
    if which systemctl >/dev/null; then
      systemctl $*
    else
      echo "Not running systemctl "$* >&2
    fi
  fi
}

if [ "$(whoami)" == "root" ]; then
  sleep 1
  chown -R lthn:lthn /etc/lthn /etc/tinyproxy
  chmod -R o-rwx /etc/lthn
  sysdctl disable haproxy
  sysdctl stop haproxy
  sysdctl disable openvpn
  sysdctl stop openvpn
  sysdctl enable tinyproxy
  sysdctl start tinyproxy
  if [ -f /etc/default/lethean-wallet-vpn-rpc ]; then chown lthn /etc/default/lethean-wallet-vpn-rpc; fi
  sudo -E -u lthn bash $(realpath "$0") "$@"
  if [ -z "$DAEMON_HOST" ]; then
    sysdctl enable lethean-daemon
    sysdctl start lethean-daemon
  fi
  if [ "$WALLETRPCHOST" = "127.0.0.1" ]; then
    sysdctl enable lethean-wallet-vpn-rpc
    sysdctl start lethean-wallet-vpn-rpc
  fi
  exit
else
  if [ "$(whoami)" != "lthn" ]; then
    echo "Must be run as root, not $(whoami). Exiting"
    exit 2
  fi
fi

if [ -f /etc/lthn/dispatcher.ini ]; then
  echo "dispatcher.ini already exists! Stopping. To continue, remove old /etc/lthn/dispatcher.ini and run again by yourself!"
  exit 2
fi

cat <<EOF >/etc/default/lethean-wallet-vpn-rpc
RPCPORT=$WALLETRPCPORT
DAEMONHOST=$DAEMON_HOST
WALLETPASS="$WALLETPASS"
WALLETRPCURI="$WALLETRPCURI"
RPCLOGIN="$WALLETRPCUSER:$WALLETRPCPASS"
LETHEANWALLET="$WALLETFILE"
EOF

#rm -rf /tmp/lthn-easy
mkdir -p /tmp/lthn-easy
cd /tmp/lthn-easy
mkdir -p conf

cat >conf/ca.cfg <<EOF
[ ca ]
default_ca = CA_itnsvpn
[ CA_itnsvpn ]
dir               = ./
certs             = \$dir/certs
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial
RANDFILE          = \$dir/private/.rand
private_key       = \$dir/private/ca.key.pem
certificate       = \$dir/certs/ca.cert.pem
crlnumber         = \$dir/crlnumber
crl               = \$dir/crl/ca.crl.pem
crl_extensions    = crl_ext
default_crl_days  = 30
default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_strict
[ req ]
default_bits        = 4096
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256
x509_extensions     = v3_ca
[ usr_cert ]
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "OpenSSL Generated Client Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection

[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

[ policy_strict ]
countryName             = optional
stateOrProvinceName     = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional
EOF


if ! [ -f "$WALLETFILE" ]; then
  lethean-wallet-cli --mnemonic-language English --generate-new-wallet $WALLETFILE $DAEMON_ARG --restore-height "$WALLETRESTOREHEIGHT" --password "$WALLETPASS" --log-file /dev/stdout --log-level 4 --command exit
fi
WALLET=$(cat ${WALLETFILE}.address.txt)
lethean-wallet-cli --wallet $WALLETFILE $DAEMON_ARG --restore-height "$WALLETRESTOREHEIGHT" --password "$WALLETPASS" --log-file /dev/stdout --log-level 4 --command refresh

cat >conf/dispatcher.ini.tmpl <<EOF
[global]
provider-id={providerid}
provider-key={providerkey}
EOF

TOPDIR=$(pwd) /usr/lib/lthn/lthn-configure.sh --generate-providerid --with-wallet-address "$WALLET" --with-wallet-rpc-pass "user" --with-wallet-rpc-pass "pass" --easy --client --server --prefix / --python-bin /usr/bin/python3 --pip-bin /usr/bin/pip3 --runas-user lthn --runas-group lthn "$@"
PROVIDERID=$(cat build/etc/provider.public)
PROVIDERKEY=$(cat build/etc/provider.private)

if ! [ -f /etc/tinyproxy/tinyproxy.conf.dpkg ]; then
  cp /etc/tinyproxy/tinyproxy.conf /etc/tinyproxy/tinyproxy.conf.dpkg
  cat >/etc/tinyproxy/tinyproxy.conf <<EOF
User tinyproxy
Group tinyproxy
Port 8888
Timeout 600
DefaultErrorFile "/usr/share/tinyproxy/default.html"
StatFile "/usr/share/tinyproxy/stats.html"
Logfile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Info
PidFile "/run/tinyproxy/tinyproxy.pid"
MaxClients 100
MinSpareServers 5
MaxSpareServers 20
StartServers 10
MaxRequestsPerChild 0
Allow 127.0.0.1
ViaProxyName "tinyproxy"
DisableViaHeader Yes
ConnectPort 80
ConnectPort 443
ConnectPort 5060
ConnectPort 8443
EOF
else
  echo "Tinyproxy already configured. Not touching its conf file. Remove /etc/tinyproxy/tinyprox.conf.dpkg to initialise again."
fi

cat >/etc/lthn/dispatcher.ini <<EOF
[global]
;log-level=DEBUG
ca=/etc/lthn/ca/certs/ca.cert.pem
provider-id=$PROVIDERID
provider-key=$PROVIDERKEY
provider-name=Provider
provider-terms=Some Terms

wallet-address=$WALLET
wallet-username=$WALLETRPCUSER
wallet-password=$WALLETRPCPASS
wallet-rpc-uri=$WALLETRPCURI

[service-1A]
name=Proxy
backend_proxy_server=127.0.0.1:8888
crt=/etc/lthn/ca/certs/ha.cert.pem
key=/etc/lthn/ca/private/ha.key.pem
crtkey=/etc/lthn/ca/certs/ha.both.pem
endpoint=127.0.0.1

[service-1B]
crt=/etc/lthn/ca/certs/vpn.cert.pem
key=/etc/lthn/ca/private/vpn.key.pem
crtkey=/etc/lthn/ca/certs/vpn.both.pem
reneg=60
enabled=false

EOF

rm -f build/etc/dispatcher.ini
if [ -d /etc/lthn/ca/ ]; then
  echo "Old CA dir already exists! Stopping. To continue, remove old /etc/lthn/ca and run again by yourself!"
  exit 2
fi
rm -rf /etc/lthn/ca/
cp -R build/etc/* /etc/lthn/

lvmgmt --generate-sdp \
     --sdp-provider-type $PROVTYPE \
     --sdp-provider-name EasyProvider \
     --wallet-address "$WALLET" \
     --sdp-service-crt /etc/lthn/ca/certs/ha.cert.pem \
     --sdp-service-name proxy --sdp-service-id 1a --sdp-service-endpoint $ENDPOINT --sdp-service-port $PORT \
     --sdp-service-type proxy --sdp-service-cost 0.001 --sdp-service-dlspeed 1 --sdp-service-ulspeed 1 \
     --sdp-service-prepaid-mins 10 --sdp-service-verifications 0

cat /etc/lthn/sdp.json
echo "Send payment to SDP service for subscription and run 'lvmgmt --upload-sdp' after" >&2
