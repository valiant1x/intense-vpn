FROM python:3.7.1-stretch as letheanvpn
MAINTAINER Lukas Macura <lukas@lethean.io>

LABEL "io.lethean.vpn-server"="Lethean.IO"
LABEL version="1.0"
LABEL description="Letehan.io VPN server"

ARG DAEMON_HOST="sync.lethean.io"
ARG PORT="8080"

ARG ZSYNC_URL="https://monitor.lethean.io/bc/data.mdb.zsync"
ARG ZSYNC_DATA_URL="http://monitor.lethean.io/bc/data.mdb"
ARG ZSYNC_DATA_SHA="http://monitor.lethean.io/bc/data.mdb.sha256"

# Debian packages to install (needs to be in same directory)
ARG DEBS=""

# Daemon host. Set to empty string to use local daemon with complete copy of blockchain.
ENV DAEMON_HOST="$DAEMON_HOST"

# Wallet file. It is relative to etc directory.
ENV WALLETFILE="/var/lib/lthn/wallet"

# If you want to use external wallet, set this to RPC of external wallet host
ENV WALLET_RPC_URI=""

# Wallet password. Default is to generate random password
ENV WALLETPASS=""

# Wallet RPC password. Default is to generate random password. Username used by dispatcher is 'dispatcher'
ENV WALLETRPCPASS=""

# To restore wallet from this height. Only applicable for local wallet.
ENV WALLET_RESTORE_HEIGHT=349516

# CA password. Default to generate random password
ENV CAPASS=""

# Common Name for CN
ENV CACN="LTHNEasyDeploy"

# If you already have providerid. In other case, autogenerate
ENV PROVIDERID=""

# If you already have providerkey. In other case, autogenerate
ENV PROVIDERKEY=""

# Provider type
ENV PROVTYPE="residential"

# Service endpoint. You need to change this in SDP later
ENV ENDPOINT="127.0.0.1"

# Service port
ENV PORT="$PORT"


# Zabbix parameters
ENV ZABBIX_SERVER="zabbix"
ENV ZABBIX_HOSTNAME="lethean-vpn"
ENV ZABBIX_META="LETHEANNODE"

ENV ZSYNC_URL="$ZSYNC_URL"
ENV ZSYNC_DATA_URL="$ZSYNC_DATA_URL"
ENV ZSYNC_DATA_SHA="$ZSYNC_DATA_SHA"

ENTRYPOINT ["/entrypiont-lethean-vpn.sh"]
CMD ["run"]

USER root
RUN apt-get update && apt-get install -y apt-utils pwgen joe less haproxy openvpn squid net-tools wget stunnel zsync pwgen rsyslog
RUN  echo  'deb [trusted=yes] http://monitor.lethean.io/dl/stretch/ ./' >/etc/apt/sources.list.d/lethean.list
RUN apt-get update

RUN rm -f /tmp/*deb
COPY Dockerfile *.deb /tmp/
RUN rm -f /tmp/*dbgsym*deb
RUN if [ -n "${DEBS}" ]; then \
     dpkg -i /tmp/*.deb; apt-get install -y -f;  \
    else \
      apt-get install -y lethean-vpn lethean-wallet-cli lethean-wallet-rpc lethean-wallet-vpn-rpc; \
    fi

RUN wget https://repo.zabbix.com/zabbix/4.0/debian/pool/main/z/zabbix-release/zabbix-release_4.0-2+stretch_all.deb && \
   dpkg -i zabbix-release_4.0-2+stretch_all.deb
RUN apt-get update && apt-get install -y zabbix-agent zabbix-sender && mkdir /var/run/zabbix && chown -R lthn /var/log/zabbix /var/run/zabbix
COPY ./server/docker-run.sh /entrypiont-lethean-vpn.sh

RUN chmod +x /entrypiont-lethean-vpn.sh

RUN ln -sf /etc/lthn/lethean-wallet-rpc.default /etc/default/lethean-wallet-rpc
RUN ln -sf /etc/lthn/lethean-wallet-vpn-rpc.default /etc/default/lethean-wallet-vpn-rpc

RUN mkdir /etc/skel/lthn; cp /etc/lthn/* /etc/skel/lthn/
RUN rm -rf /tmp/*deb

COPY debian/lthn-easy-deploy-node.sh /usr/bin/
RUN chmod +x /usr/bin/lthn-easy-deploy-node.sh
