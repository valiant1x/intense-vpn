PASS=1234
CN=ItnsVPNFakeCN
DOCKER=docker

-include env.mk

all:
env.mk:
	@if [ "$(MAKECMDGOALS)" != "docker" ]; then \
	    if ! [ -f env.mk ]; then echo "You must configure first!" ; ./configure.sh --help; exit 1; fi; \
	    echo "Seems to be configured. Run make install."; \
	fi
	

install: env.mk
	chmod +x install.sh
	INSTALL_PREFIX=$(INSTALL_PREFIX) \
	FORCE=$(FORCE) \
	LTHN_PREFIX=$(LTHN_PREFIX) \
	OPENVPN_BIN=$(OPENVPN_BIN) \
	PYTHON_BIN=$(PYTHON_BIN) \
	PIP_BIN=$(PIP_BIN) \
	SUDO_BIN=$(SUDO_BIN) \
	HAPROXY_BIN=$(HAPROXY_BIN) \
	OPENSSL_BIN=$(OPENSSL_BIN) \
	LTHN_USER=$(LTHN_USER) \
	LTHN_GROUP=$(LTHN_GROUP) \
	CLIENT=$(CLIENT) \
	SERVER=$(SERVER) \
	./install.sh
	
install-client:
	@$(MAKE) install CLIENT=y
	
install-server:
	@$(MAKE) install SERVER=y

clean:
	@echo Note this cleans only build directory. If you want to uninstall package, do it manually by removing files from install location.
	@echo Your last install dir is $(LTHN_PREFIX)
	rm -rf build

ca: build/ca/index.txt
	
build/ca/index.txt: env.mk
	./configure.sh --generate-ca --with-capass "$(PASS)" --with-cn "$CN"

docker-img:
	docker build -t lethean/lethean-vpn:devel .

docker: docker-img

docker-clean:
	docker rm -v lethean-vpn:devel 

docker-shell:
	mkdir -p build/etc
	mkdir -p build/bcdata
	docker run -i -t \
	  --mount type=bind,source=$$(pwd)/build/etc,target=/opt/lthn/etc \
   	  --mount type=bind,source=$$(pwd)/build/bcdata,target=/home/lthn \
	  lethean/lethean-vpn:devel sh

lthnvpnc-win:
	# tstunnel.exe: https://www.stunnel.org/
	# -- required files: libssl-1_1-x64.dll, libcrypto-1_1-x64.dll
	# haproxy.exe: https://www.haproxy.org/
	# -- compiled under cygwin; required files cyg*.dll (5 DLLs in total)
	# openvpn.exe: https://openvpn.net/
	# -- required files: libpkcs11-helper-1.dll, libeay32.dll, liblzo2-2.dll
	@echo pyinstaller lthnvpnc-win.spec