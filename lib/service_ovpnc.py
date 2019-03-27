from service import Service
import config
import os
import sys
import re
import log
import time
import select
from subprocess import Popen
from subprocess import PIPE
from service_ovpn import ServiceOvpn
import services
import pathlib
ON_POSIX = 'posix' in sys.builtin_module_names

class ServiceOvpnClient(ServiceOvpn):
    """
    Openvpn service client class
    """ 
    
    OPTS = dict(
        outbound_proxy_host=None, outbound_proxy_port=3128,
        crt = None, key = None, crtkey = None,
        paymentid='authid1',
        tundev = "tun1",
        mgmtport = "11193",
        reneg = 600,
        enabled = True
    )
    OPTS_HELP = dict(
        http_proxy_host = "HTTP proxy used for connection to ovpn",
        reneg = "Renegotiation interval"
    )
            
    def connect(self, sdp):
        self.sdp = sdp
        while True:
            services.SERVICES.sleep(10)
        
    def orchestrate(self):
        ret = super().orchestrate()
        return True
    
    def createConfig(self):
        if (not os.path.exists(self.dir)):
            os.mkdir(self.dir)
        os.chdir(self.dir)
        tfile = config.Config.PREFIX + "/etc/openvpn_client.tmpl"
        try:
            tf = open(tfile, "rb")
            tmpl = tf.read()
        except (IOError, OSError):
            log.L.error("Cannot open openvpn template file %s" % (tfile))
            sys.exit(1)
        ca = services.SERVICES.sdp.getCertificates()
        cafile = self.dir + "ca.crt"
        try:
            caf = open(cafile, "wb")
            caf.write(ca.encode())
            caf.close()
        except (IOError, OSError):
            log.L.error("Cannot write ca file %s" % (cafile))
            sys.exit(1)
        if (config.Config.CAP.servicePort):
            self.cfg['port'] = config.Config.CAP.servicePort
        elif ('port' not in self.cfg):
            self.cfg['port'] = self.json['vpn'][0]['port'].split('/')[0]
        if (config.Config.CAP.serviceProto):
            self.cfg['proto'] = config.Config.CAP.serviceProto
        elif ('proto' not in self.cfg):
            self.cfg['proto'] = self.json['vpn'][0]['port'].split('/')[1]
        if (config.Config.CAP.serviceFqdn):
            self.cfg['endpoint'] = config.Config.CAP.serviceFqdn
        elif ('endpoint' not in self.cfg):
            self.cfg['endpoint'] = self.json['vpn'][0]['endpoint']
        if (config.CONFIG.CAP.vpncStandalone):
            mgmt_comment = '#'
            authfile=str(pathlib.Path(self.dir + 'vpnc.auth')).replace('\\','\\\\')
            try:
                af = open(authfile, "w")
                af.write(self.cfg["paymentid"].upper() + "\n")
                af.write(self.cfg["paymentid"].upper() + "\n")
                af.close()
            except (IOError, OSError):
                log.L.error("Cannot write auth file %s" % (authfile))
                sys.exit(1)            
        else:
            mgmt_comment = ''
            authfile=''
        if (config.CONFIG.CAP.httpsProxyHost):
            proxy_comment = ''
            http_proxy = config.CONFIG.CAP.httpsProxyHost
            http_proxy_port = config.CONFIG.CAP.httpsProxyPort
        elif 'outbound_proxy_host' in self.cfg:
            proxy_comment = ''
            http_proxy = self.cfg['outbound_proxy_host']
            http_proxy_port = self.cfg['outbound_proxy_port']
        else:
            proxy_comment = '#'
            http_proxy = ''
            http_proxy_port = ''
        if self.cfg['proto']=='UDP' and proxy_comment!='#':
            log.L.error("Cannot use outbound HTTP proxy to proxy UDP connection to OpenVPN!. Exiting.")
            sys.exit(14)
        if (config.CONFIG.CAP.vpncBlockDns):
            bdns_comment='#'
            log.L.warning("block-outside-dns not supported yet.")
        else:
            bdns_comment='#'
        if (config.CONFIG.CAP.vpncBlockRoute):
            rgw_comment='#'
        else:
            rgw_comment=''
        pull_filter=""
        if (config.CONFIG.CAP.vpncBlockDns):
            pull_filter += "pull-filter ignore dhcp-option\n"
        if (config.CONFIG.CAP.vpncBlockRoute):
            pull_filter += "pull-filter ignore route\n"
            pull_filter += "pull-filter ignore route-gateway\n"
        self.cfg["tundev"] = config.Config.CAP.vpncTun
        self.cfg["mgmtport"] = config.Config.CAP.vpncMgmtPort
        if (config.CONFIG.isWindows()):
            wc='#'
            log_append='log-append log'
        else:
            wc=''
            log_append=''

        out = tmpl.decode("utf-8").format(
                          port=self.cfg['port'],
                          proto=self.cfg['proto'].lower(),
                          ip=self.cfg['endpoint'],
                          f_ca=ca,
                          tundev=self.cfg["tundev"],
                          tunnode=str(pathlib.Path(config.Config.PREFIX + '/dev/net/tun')).replace('\\','\\\\'),
                          reneg=60,
                          mtu=1400,
                          mssfix=1300,
                          hproxy_comment=proxy_comment,
                          http_proxy=http_proxy,
                          http_proxy_port=http_proxy_port,
                          payment_header=config.Config.CAP.authidHeader,
                          mgmt_header=config.Config.CAP.mgmtHeader,
                          mgmt_sock="127.0.0.1 %s" % self.cfg["mgmtport"],
                          rgw_comment=rgw_comment,
                          bdns_comment=bdns_comment,
                          auth_file=authfile,
                          pull_filters=pull_filter,
                          mgmt_comment=mgmt_comment,
                          comment_dn=wc,
                          comment_syslog=wc,
                          log_append=log_append
                          )
        try:
            cf = open(self.cfgfile, "wb")
            cf.write(out.encode())
            log.L.warning("Configuration files created at %s" % (self.dir))
        except (IOError, OSError):
            log.L.error("Cannot write haproxy config file %s" % (self.cfgfile))

