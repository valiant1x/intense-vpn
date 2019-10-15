# lethean-vpn
This repository contains code needed to setup and run an exit node on the Lethean Virtual Private Network (VPN) or to use the Lethean network as a client in CLI mode.
If you are looking for GUI, please look [here](https://github.com/LetheanMovement/lethean-gui)

**Lethean uses gitflow. The master branch is the most stable/current release.**

**The exit node is currently only supported on Linux.**

# Design
ITNS (aka LTHN) VPN dispatcher is a tool that orchestrates all other modules (proxy, VPN, config, etc.). It does not provide any VPN functionality by itself.
The dispatcher uses system packages whenever possible but it runs all instances manually after invoking.
More info about technical design can be found [here](https://lethean.io/vpn-whitepaper/)

## Client mode
As a client, dispatcher uses global SDP platform to fetch data about provider and connect there. There is no automatic payment functionality inside client. It is up to user to send corresponding payments from wallet to provider.
Client will show only instructions what to pay. We do not want to have any connection from client to your wallet allowing automatic payment.
More information about client mode is [here](CLIENT.md)

## Server mode
As a server, dispatcher helps you to create, publish and run your service as a provider. More info about server mode is [here](SERVER.md) or installation on Raspberry PI [here](PI3SERVER)

## Docker
We have prepared docker images for you. It is probably easiest way how to run client or exit node.
There is directory which needs to be mounted to host: /opt/lthn/etc . If you want to get syslog events from docker, you must bind /dev/log too.

### General usage
```
 ENV1=value [ENV2=value2] docker run -p expose:internal \
   --mount type=bind,source=$(pwd)/etc,target=/opt/lthn/etc \
   --mount type=bind,source=/dev/log,target=/dev/log \
   limosek/lethean-vpn:devel [cmd [args]]

```
where cmd can be:
```
run [args] to run dispatcher
list [args] to list available services
connect uri [args] to run client
letheand [args] to run letheand
easy-deploy [args] to easy deploy node
upload-sdp [args] to upload SDP
sync-bc to fast sync blockhain data from server.
wallet-rpc [args] to run wallet-rpc-daemon
wallet-cli [args] to run wallet-cli
sh to go into shell

```

localetc is local directory to store configs
locallog is local directory to store logs
expose is port to expose to outside
internal is internal port of dispatcher

ENV variables which you can use:
```
# Daemon host. Set to empty string to use local daemon with complete copy of blockchain.
ENV DAEMON_HOST="$DAEMON_HOST"

# Wallet file. It is relative to etc directory.
ENV WALLET_FILE="vpn"

# If you want to use external wallet, set this to RPC of external wallet host
ENV WALLET_RPC_URI=""

# Wallet password. Default is to generate random password
ENV WALLET_PASSWORD=""

# Wallet RPC password. Default is to generate random password. Username used by dispatcher is 'dispatcher'
ENV WALLET_RPC_PASSWORD=""

# To restore wallet from this height. Only applicable for local wallet.
ENV WALLET_RESTORE_HEIGHT=349516

# CA password. Default to generate random password
ENV CA_PASSWORD=""

# Common Name for CN
ENV CA_CN="LTHNEasyDeploy"

# If you already have providerid. In other case, autogenerate
ENV PROVIDER_ID=""

# If you already have providerkey. In other case, autogenerate
ENV PROVIDER_KEY=""

# Provider name
ENV PROVIDER_NAME="EasyProvider"

# Provider type
ENV PROVIDER_TYPE="residential"

# Service endpoint. You need to change this in SDP later
ENV ENDPOINT="127.0.0.1"

# Service port
ENV PORT="$PORT"

```

### Recomended steps to use exit node
Create configs and certificates (or copy your existing /opt/lthn/etc dir here.)
Easiest way to create from scratch is probably to easy-deploy. Do not forget to allocate terminal for easy-deploy (-t -i):
```
 mkdir etc
 docker run -t -i \
   --mount type=bind,source=$(pwd)/etc,target=/opt/lthn/etc \
   --mount type=bind,source=/dev/log,target=/dev/log \
   limosek/lethean-vpn:devel easy-deploy

```

After easy-deploy, all config files will be stored in your local etc directory. 
You can edit sdp.json, dispatcher.ini and other things to respect your needs.
To upload your local SDP, use 
```
 docker run --mount type=bind,source=$(pwd)/etc,target=/opt/lthn/etc \
   --mount type=bind,source=/dev/log,target=/dev/log \
   limosek/lethean-vpn:devel upload-sdp

```

Than to run dispatcher:
```
 docker run -p 8080:8080 --mount type=bind,source=$(pwd)/etc,target=/opt/lthn/etc \
   --mount type=bind,source=/dev/log,target=/dev/log \
   limosek/lethean-vpn:devel

```

### Recomended steps to use client
Please note this is low level client. By default it does not dynamically create authid or mgmtid. It just need strict instructions what to do.
Even more, it will not send any payments for service. It will only instruct you how much pay and how to pay. You can parse your syslog messages to see how to pay.

List all services from SDP platform:
```
 docker run limosek/lethean-vpn:devel list
```

Connect to URI:
See [here](CLIENT.md) for information about URI format

```
 docker run  -p 8180:8180 --mount type=bind,source=/dev/log,target=/dev/log limosek/lethean-vpn:devel connect providerid:serviceid
```
Test proxy:
```
curl -x http://localhost:8180 -L https://lethean.io/
```

### Recomended steps to use lethean daemon
By default, docker image assumes that you want to use remote daemon provided by Lethean. If you want to run your own daemon, you can instruct docker
by setting DAEMON_HOST to empty string. But you need to store blockchain outside of the wallet:

```
DAEMON_HOST='' docker run \
   --mount type=bind,source=$(pwd)/etc,target=/opt/lthn/etc \
   --mount type=bind,source=$(pwd)/bcdata,target=/home/lthn \
  limosek/lethean-vpn:devel 
```

You can even use our docker image to run standalone daemon.
If blockchain dir is empty, docker image will pull actual data using zsync which is very fast.
```
docker run -t \
   --mount type=bind,source=$(pwd)/etc,target=/opt/lthn/etc \
   --mount type=bind,source=$(pwd)/bcdata,target=/home/lthn \
  limosek/lethean-vpn:devel letheand
```

## FAQ

### Provider

#### Q: Is it legal to be provider?
There can be local laws and legality issues in your country or company. Check your legislative about this. We cannot say universally that something is legal or not.
It can differ in countries over the world but you should follow at last some basic rules:

##### Safe your infrastructure #####
You should not allow user to connect to your own network until you are sure you want to. Please refer to [server](SERVER.md) documentation about access lists.

##### Do not allow bad users to do bad things #####
This is probably most critical and complex part. Primary goal of entire Lethean project is privacy for users. But, of course, somebody can use privacy to harmful somebody other. 
It is your responsibility as a provider to do maximum against these users. Our project is here for good users which needs privacy. We will implement many features how to help you with this filtering.

##### Filter traffic #####
You can filter your traffic for specific sites. Please refer to [server](SERVER.md)
 
#### Q: As a provider, do I need audit log?
If somebody does something harmful, you are responsible as an exit node. It is up to you.

#### Q: What is status of IPv4/IPv6 support?
Both client and server works perfectly on IPv4 network. We are working on full native IPv6 support but for now, see this matrix.

| Client  | Provider | Web        | Support             |
| ------- | -------- | -------    | ------------------- | 
| IPv4    | IPv4     | IPv4/IPv6  | Full                |
| IPv6    | IPv6     | IPv4/IPv6  | No-session-tracking |

### Client

#### Q: Will Lethean project make me anonymous? ####
There are lot of next dependencies which you *MUST* follow to be anonymous. Refer to [tor](https://www.torproject.org/). I a short review, your browser, your OS and all other tools around can be used to identify you. 
At least, use dedicated browser with anonymous mode enabled. 

## Directories

### client
 Everything related to client part. More information [here](CLIENT.md)
 
### conf
 Example config files and configuration templates.
 
### server
 Code related to VPN server part. More information [here](SERVER.md)

### lib
 Library files

### scripts
 Various scripts and tools

## Development
If you want to help developing, here are is some basic info.
Best and quickest way how to help is prepare pull request for us to review.

### Prepare your system

```
git clone ...
cd lethean-vpn
sudo pip3 install -r requirements.txt
sudo apt-get install dpkg-dev devscripts
sudo pip3 install py2deb
make python-debs
dpkg-buildpackage .
```
This should place all packages in upper directory '..'
Do not forget that you need to change subversion of debs if you want force
apt-get update and upgrade to work
```
dch -i
```
To create repository, copy debs to clean directory, cd to there and do
```
dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
```

## Testing
If you want to help testing, be as specific as possible. We will need
console logs, syslogs and audit log. Do not forget that there can be some
information which you should not share. Take care to clean data before
submiting.
