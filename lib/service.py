import config
import log
import socket
import os
import time
import sys
import subprocess
import pathlib

class Service(object):
    """
    Service class
    """
    
    OPTS = dict( enabled = True )
    OPTS_HELP = dict()
    OPTS_REQUIRED = dict()
    SOCKET_TIMEOUT = 0.01
    PROCESSED_LOG_MSGS = []
    
    def __init__(self, id=None, json=None, cfg=None):
        if (id):
            self.id = id.upper()
        else:
            self.id = "00"
        if (not json):
            self.type = "none"
            self.name = "none"
            self.cost = "none"
            self.json = "{}" 
        else:
            self.type = json["type"]
            self.name = json["name"]
            self.cost = float(json["cost"])
            self.json = json    
            
        if (cfg):
            self.cfg = cfg
        else:
            self.cfg = config.CONFIG.getService(self.id)
        if (config.CONFIG.CAP.serviceDir):
            self.dir = config.CONFIG.CAP.serviceDir
        else:
            self.dir = config.Config.PREFIX + "/var/%s_%s/" % (self.type, self.id)

        self.cfgfile = str(pathlib.Path(self.dir + "/cfg"))
        self.pidfile = str(pathlib.Path(self.dir + "/pid"))
        self.mgmtfile = str(pathlib.Path(self.dir + "/mgmt"))
        self.logfile = str(pathlib.Path(self.dir + "/log"))
        self.process = None
        if (not self.cfg):
            self.cfg = {}
        for o in self.OPTS:
            if o in self.cfg:
                log.L.debug("Setting service %s parameter %s to %s" % (id,o,self.cfg[o]))
            else:
                if (self.OPTS[o]):
                    log.L.debug("Setting service %s parameter %s to default (%s)" % (id,o,self.OPTS[o]))
                    self.cfg[o] = "%s" % (self.OPTS[o])
        for c in self.cfg:
            if c not in self.OPTS.keys():
                log.L.warning("Unknown parameter %s for service %s" % (c,id))
        if id is not "00":
            for o in self.OPTS_REQUIRED:
                if o not in self.cfg:
                    log.L.error("Service %s is not configured. You need to edit config file to add:\n[service-%s]\n%s=something" % (id, id, o))
                    sys.exit(2)
        self.initphase = 0
        
    def isEnabled(self):
        if "enabled" in self.cfg:
            return(self.cfg["enabled"])
        else:
            return(True)
        
    def disable(self):
        self.cfg["enabled"] = None
        
    def enable(self):
        self.cfg["enabled"] = True
        
    def helpOpts(self, name):
        print(name)
        for o in self.OPTS:
            if not o in self.OPTS_HELP:
                self.OPTS_HELP[o] = ''
            if self.OPTS_HELP[o] == '':
                print("%s: (default=%s)" % (o, self.OPTS[o]))
            else:
                print("%s: %s, (default=%s)" % (o, self.OPTS_HELP[o], self.OPTS[o]))
        print()
        
    def run(self):
        log.L.info("Starting service %s[%s]" % (self.name, self.id))
        
    def waitForPid(self):
        log.L.info("Waiting for pid")
        i=0
        if config.CONFIG.isWindows():
            maxwait=200
        else:
            maxwait=40
        pid = 0
        while not pid>0 and i<maxwait:
            if os.path.isfile(self.pidfile):
                pid=open(self.pidfile).read().strip()
                if (pid.isdigit()):
                    pid = int(pid)
                else:
                    pid = 0
            time.sleep(0.1)
            i = i+1
        if (i==maxwait):
            log.L.error("Error getting PID for service %s" % (self.id))
            sys.exit(1)
        self.pid=pid
        return(pid)

    def stop(self):
        if (self.mgmtfile is not None and os.path.exists(self.mgmtfile)):
            os.remove(self.mgmtfile)
        if (self.pidfile is not None and os.path.exists(self.pidfile)):
            os.remove(self.pidfile)
        if self.process:
            self.process.kill()
        log.L.info("Stopped service %s[%s]" % (self.name, self.id))
        
    def getCost(self):
        return(self.cost)
        
    def getLine(self):
        if config.CONFIG.isWindows() and pathlib.Path(self.logfile).is_file():
            with open(self.logfile, 'rU') as f:
                f = f.readlines()
            global PROCESSED_LOG_MSGS
            for line in f:
                if not line in self.PROCESSED_LOG_MSGS:
                    self.PROCESSED_LOG_MSGS.append(line)
                    return(line)
            return(None)
        if not self.process:
            return(None)
        try:
            outs, errs = self.process.communicate(timeout=0.05)
            return(outs + errs)
        except subprocess.TimeoutExpired:
            pass
        except ValueError:
            return(None)
            
    def mgmtConnect(self, ip=None, port=None):
        if (ip):
            self.mgmtip = ip
        if (port):
            self.mgmtport = port
        if (self.mgmtip == "socket"):
            self.mgmt = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        else:
            self.mgmt = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        i = 0
        while (i < 50):
            try:
                if (self.mgmtip == "socket"):
                    self.mgmt.connect(self.mgmtfile)
                else:
                    self.mgmt.connect((self.mgmtip, int(self.mgmtport)))
            except socket.error:
                time.sleep(self.SOCKET_TIMEOUT)
                i += 1
            else:
                break
        self.mgmt.settimeout(self.SOCKET_TIMEOUT)
        
    def mgmtClose(self):
        return(self.mgmt.close())
        
    def mgmtRead(self, inside=None):
        line = ""
        try:
            while True:
                self.mgmt.settimeout(self.SOCKET_TIMEOUT)
                c = self.mgmt.recv(1).decode("utf-8")
                if c != "\n" and c != "":
                    line += c
                else:
                    break
        except socket.timeout:
            pass
        except OSError:
            if (inside):
                log.L.error("%s[%s]-mgmt-in: Cannot reconnect. Exiting!" % (self.type, self.id))
                sys.exit(2)
            else:
                log.L.debug("%s[%s]-mgmt-in: reconnecting." % (self.type, self.id))
                self.mgmtConnect(self.mgmtip, self.mgmtport)
                return(self.mgmtRead(True))
        else:
            pass
        if (line != ""):
            log.L.debug("%s[%s]-mgmt-in: %s" % (self.type, self.id, repr(line)))
            if not self.mgmtEvent(line):
                return None
            else:
                return(line)
        else:
            return(None)
        
    def mgmtWrite(self, msg, inside=None):
        try:
            log.L.debug("%s[%s]-mgmt-out: %s" % (self.type, self.id, repr(msg)))
            ret = not self.mgmt.sendall(msg.encode())
            reconnect = None
        except:
            if (inside):
                log.L.error("%s[%s]-mgmt-out: Cannot reconnect. Exiting!" % (self.type, self.id))
                sys.exit(2)
            else:
                log.L.debug("%s[%s]-mgmt-out: reconnecting." % (self.type, self.id))
                self.mgmtConnect(self.mgmtip, self.mgmtport)
                reconnect = True        
        if reconnect:
            return(self.mgmtWrite(msg, True))
        else:
            return(ret)

    def mgmtEvent(self, msg):
        pass

    def isAlive(self):
        if config.CONFIG.isWindows():
            # check if pid exists in running processes
            pid = self.pid
            if (pid != 0):
                filterByPid = "PID eq %s" % pid
                pidStr = str(pid)
                cmd = ["cmd", "/c", "tasklist", "/FI", filterByPid, "|", "findstr",  pidStr]
                result = subprocess.call(cmd, stdout=subprocess.DEVNULL)
                return (result == 0)
            else:
                return False
        else:
            self.process.poll()
            return(self.process.returncode == None)
    
    def getCost(self):
        return(self.cost)
    
    def getName(self):
        return(self.name)
    
    def getType(self):
        return(self.type)
    
    def getId(self):
        return(self.id)
    
    def getCfg(self):
        return(self.cfg)
    
    def show(self):
        log.L.info("Service %s (%s), id %s" % (self.getName(), self.getType(), self.getId()))
        
    def getJson(self):
        return(self.json)
    
    def addAuthId(self, authid, msg=""):
        log.A.audit(log.A.AUTHID, log.A.MODIFY, paymentid=authid.getId(), serviceid=self.id, msg='activated')
        return(True)
        
    def delAuthId(self, authid, msg=""):
        log.A.audit(log.A.AUTHID, log.A.MODIFY, paymentid=authid.getId(), serviceid=self.id, msg='deactivated')
        return(True)

    def getSessions(self):
        return({})