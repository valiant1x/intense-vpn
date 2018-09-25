
import atexit
import config
import log
from sdp import *
import sys
from service_mgmt import ServiceMgmt
from service_ha import ServiceHa
from service_syslog import ServiceSyslog
from service_ovpn import ServiceOvpn
from service_http import ServiceHttp

SERVICES = None

class Services(object):
    
    def load(self):
        
        self.services = {}
        sdp = SDP()
        sdp.load(config.Config.SDPFILE)
        for id_ in sdp.listServices():
            s = sdp.getService(id_)
            cfg = config.CONFIG.getService(id_)
            if ("enabled" in cfg and cfg["enabled"]) or not "enabled" in cfg:
                if (s["type"]):
                    if (s["type"] == "vpn"):
                        so = ServiceOvpn(id_, s)
                    elif (s["type"] == "proxy"):
                        so = ServiceHa(id_, s)
                    else:
                        log.L.error("Unknown service type %s in SDP!" % (s["type"]))
                        sys.exit(1)
                self.services[id_.upper()] = so
            else:
                log.L.warning("Service %s disabled m config file." % (id_))
        self.syslog = ServiceSyslog("SS")
        self.mgmt = ServiceMgmt("MS")
        self.http = ServiceHttp("HS")
 
    def run(self):
        if self.syslog.isEnabled():
            self.syslog.run()
        if self.mgmt.isEnabled():
            self.mgmt.run()
        if self.http.isEnabled():
            self.http.run()
        if (config.CONFIG.CAP.runServices):
            for id in self.services:
                s = self.services[id]
                s.run()
        atexit.register(self.stop)
    
    def createConfigs(self):
        for id in self.services:
            s = self.services[id]
            s.createConfig()
            
    def orchestrate(self):
        if self.syslog.isEnabled():
            self.syslog.orchestrate()
        if self.mgmt.isEnabled():
            self.mgmt.orchestrate()
        if self.http.isEnabled():
            self.http.orchestrate()
        for id in self.services:
            if (not self.services[id].orchestrate()):
                log.L.error("Service %s died! Exiting!" % (self.services[id].id))
                self.stop()
                sys.exit(3)

    def stop(self):
        for id in self.services:
            s = self.services[id]
            if (s.isAlive()):
                s.stop()
        if self.syslog.isEnabled():
            self.syslog.stop()
        if self.mgmt.isEnabled():
            self.mgmt.stop()
        if self.http.isEnabled():
            self.http.stop()
            
    def show(self):
        for id in self.services:
            s = self.services[id]
            s.show()
            
    def getAll(self):
        return(self.services.keys())
    
    def get(self, id):
        key = "%s" % (id)
        if key.upper() in self.services:
            return(self.services[key.upper()])
        else:
            return(None)


