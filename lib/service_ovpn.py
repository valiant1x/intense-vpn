from service import Service
import config
import os
import sys
import ctypes
import re
import log
import time
import select
from subprocess import Popen
from subprocess import PIPE
import atexit
import services
import time
import win32pipe
import win32file
import pywintypes
ON_POSIX = 'posix' in sys.builtin_module_names

class ServiceOvpn(Service):
    
    def isClient(self):
        return(self.__class__.__name__=="ServiceOvpnClient")
    
    def run(self):
        self.createConfig()
        if config.Config.CAP.d=='INFO':
            verb="2"
        elif config.Config.CAP.d=='DEBUG':
            verb="3"
        else:
            verb="1"
        # delete old log file
        try:
            os.remove(self.logfile)
        except OSError:
            pass

        isWindowsWithAdminNeeded = False
        isWindowsWithInteractivePipeReady = False
        interactiveServicePipeExists = False
        if config.CONFIG.isWindows():
            # are we an admin? if so, we can use bundled openvpn bin
            # if user is not an admin, we need either the openvpn-gui interactive service or admin rights
            if not ctypes.windll.shell32.IsUserAnAdmin():                
                # use interactive service named pipe, if it exists
                ERROR_FILE_NOT_FOUND = 2
                ERROR_PIPE_BUSY = 231
                handlePipe = None
                try:
                    log.L.debug("Attempting to connect to Interactive Service...")
                    # prepare interactive service startup msg request
                    # https://community.openvpn.net/openvpn/wiki/OpenVPNInteractiveService
                    workingdir = os.path.split(self.cfgfile)[0]
                    openvpnoptions = "--config \"" + self.cfgfile + "\" --writepid \"" + self.pidfile + "\" --verb " + verb
                    stdin = ""
                    wzero = u"\u0000"
                    startupMsg = (workingdir + wzero + openvpnoptions + wzero + stdin + wzero).encode("utf-16-le")
                    pipeName = r'\\.\pipe\openvpn$Lethean\service'

                    handlePipe = win32file.CreateFile(pipeName, win32file.GENERIC_READ | win32file.GENERIC_WRITE, 0, None, win32file.OPEN_EXISTING, 0, None)

                    if (handlePipe != win32file.INVALID_HANDLE_VALUE):
                        log.L.info("OVPN Lethean service pipe opened")
                    else:
                        log.L.error("Failed opening LTHNVPN service pipe: invalid handle")

                        err = ctypes.windll.kernel32.GetLastError()
                        if (err == ERROR_FILE_NOT_FOUND):
                            log.L.warning("Lethean VPN service not found! Make sure OpenVPN Interactive Service (Lethean) service is running. If service does not exist, please install OpenVPN and run the Install_LTHN_Service script.")
                        elif (err != ERROR_PIPE_BUSY):
                            log.L.error("Failed opening LTHNVPN service pipe: %d" % err)
                        elif ((ctypes.windll.kernel32.WaitNamedPipeA(pipeName, 20000)) == 0):
                            log.L.error("Failed waiting to open LTHNVPN service pipe!")

                        sys.exit(1)

                    res = win32pipe.SetNamedPipeHandleState(handlePipe, win32pipe.PIPE_READMODE_MESSAGE, None, None)
                    if res == 0:
                        log.L.debug("SetNamedPipeHandleState return code: %d" % res)

                    win32file.WriteFile(handlePipe, startupMsg)

                    while True:
                        resp = win32file.ReadFile(handlePipe, 64*1024)
                        log.L.debug("Pipe message received %d" % resp[0])
                        if (resp[0] == 0):
                            decoded = resp[1].decode("utf-16-le")
                            log.L.debug("Pipe data received: %s" % decoded)
                            if ('Process ID' in decoded.split('\n')[2]):
                                interactiveServicePipeExists = True
                                cmd = ''
                                log.L.info('Success! PID of openvpn is ' + decoded.split('\n')[1])
                            break

                except pywintypes.error as e:
                    if (e.args[0] == ERROR_FILE_NOT_FOUND):
                        log.L.warning("Lethean VPN service not found! Make sure OpenVPN Interactive Service (Lethean) service is running. If service does not exist, please install OpenVPN and run the Install_LTHN_Service script.")
                    else:
                        log.L.error("Error opening OVPN LTHN service pipe! %d %s %s" % (e.args[0], e.args[1], e.args[2]))
                finally:
                    if (handlePipe and handlePipe != win32file.INVALID_HANDLE_VALUE):
                        win32file.CloseHandle(handlePipe)
                # if interactive service does not exist, request admin privileges to run openvpn
                if not interactiveServicePipeExists:
                    log.L.info("We are not an admin and we failed to interact with Lethean VPN service. Requesting admin elevation...")
                    isWindowsWithAdminNeeded = True
        if not interactiveServicePipeExists:
            if config.Config.SUDO_BIN:
                cmd = [config.Config.SUDO_BIN, config.Config.CAP.openvpnBin, "--config", self.cfgfile, "--writepid", self.pidfile, "--verb", verb]
            else:
                if isWindowsWithAdminNeeded:
                    cmd = ["\"" + config.Config.CAP.openvpnBin + "\"", "--config", "\"" + self.cfgfile + "\"", "--writepid", "\"" + self.pidfile + "\"", "--verb", verb]
                else:
                    cmd = [config.Config.CAP.openvpnBin, "--config", self.cfgfile, "--writepid", self.pidfile, "--verb", verb]
            os.chdir(self.dir)
            if (os.path.isfile(self.pidfile)):
                os.remove(self.pidfile)
            log.A.audit(log.A.START, log.A.SERVICE, cmd=" ".join(cmd), serviceid=self.id)
            if self.isClient():
                if (config.Config.CAP.vpncStandalone):
                    command = cmd[0]
                    if config.Config.CAP.noRun:
                        log.L.warning("Exiting from dispatcher. Run manually:\n%s" % (" ".join(cmd)))
                        atexit.unregister(services.SERVICES.stop)
                        sys.exit()
                    else:
                        if not os.path.isfile(config.Config.CAP.openvpnBin):
                            log.L.error("Openvpn binary %s not found. Cannot continue!" % (config.Config.CAP.openvpnBin))
                            sys.exit(1)
                        log.L.warning("Running %s and exiting from dispatcher." % (" ".join(cmd)))
                        os.execv(command, cmd)
            if not os.path.isfile(config.Config.CAP.openvpnBin):
                log.L.error("Openvpn binary %s not found. Cannot continue!" % (config.Config.CAP.openvpnBin))
                sys.exit(1)
            if (isWindowsWithAdminNeeded):
                log.L.info("Requesting UAC prompt for %s using params %s" % (cmd[0], ' '.join(cmd[1:])))
                SW_HIDE = 0
                result = ctypes.windll.shell32.ShellExecuteW(None, "runas", cmd[0], ' '.join(cmd[1:]), None, SW_HIDE)
                if (result <= 32):
                    log.L.error("Failed to launch OpenVPN with admin rights! You must either provide admin rights or install openvpn and Lethean service.")
                    sys.exit(1)
            else:
                self.process = Popen(cmd, stdout=PIPE, stderr=PIPE, bufsize=1, close_fds=ON_POSIX)

        self.pid = self.waitForPid()
        log.L.info("Run service %s: %s [pid=%s]" % (self.id, " ".join(cmd), self.pid))
        if not config.CONFIG.isWindows():
            self.stdout = select.poll()
            self.stderr = select.poll()
            self.stdout.register(self.process.stdout, select.POLLIN)
            self.stderr.register(self.process.stderr, select.POLLIN)
        else:
            self.stdout=None
            self.stderr=None
        self.mgmtConnect("127.0.0.1", self.cfg["mgmtport"])
        log.L.warning("Started service %s[%s]" % (self.name, self.id))
        self.starttime=time.time()
        
    def mgmtConnect(self, ip=None, port=None):
        return(super().mgmtConnect("127.0.0.1", self.cfg["mgmtport"]))
        
    def mgmtEvent(self, msg):
        p = re.search("^>CLIENT:CONNECT,(\d*),(\d*)", msg)
        if (p):
            cid = p.group(1)
            kid = p.group(2)
            self.mgmtAuthClient(cid, kid)
        p = re.search("^>PASSWORD:Need 'Auth' username/password", msg)
        if (p):
            self.mgmtWrite("username 'Auth' '%s'\r\n" % (self.cfg["paymentid"]))
            l = self.mgmtRead()
            while (l is not None):
                l = self.mgmtRead()
            self.mgmtWrite("password 'Auth' '%s'\r\n" % (self.cfg["paymentid"]))
            l = self.mgmtRead()
            while (l is not None):
                l = self.mgmtRead()
        p = re.search("^>STATE:(\d*),RECONNECTING,auth-failure,,", msg)
        if (p and self.isClient()):
            if self.initphase==1:
                log.A.audit(log.A.NPAYMENT, log.A.PWALLET, wallet=self.sdp["provider"]["wallet"], paymentid=self.cfg["paymentid"], anon="no")
                self.initphase += 1
            elif time.time()-self.starttime>float(config.Config.CAP.paymentTimeout):
                log.L.error("Timeout waiting for payment!")
                sys.exit(2)
        p = re.search("^>STATE:(\d*),EXITING,tls-error,,", msg)
        if (p and self.isClient()):
            log.L.error("TLS Error! Bad configuration or old SDP? Exiting.")
            sys.exit(2)
        p = re.search("^>STATE:(\d*),CONNECTED,SUCCESS", msg)    
        if (p and self.isClient()):
            log.L.warning("Connected!")
        p = re.search("^>LOG:(\d*),W,ERROR:(.*)", msg)
        if (p and self.isClient()):
            log.L.error("Error seting up VPN! (%s). Exiting." % p.group(2).strip())
            sys.exit(2)
        p = re.search("^>LOG:(\d*),F,(.*)", msg)
        if (p and self.isClient()):
            log.L.error("Error seting up VPN! (%s). Exiting." % p.group(2).strip())
            sys.exit(2)
        return True
            
    def unHold(self):
        self.mgmtWrite("hold off\r\n")
        l = self.mgmtRead()
        self.mgmtWrite("hold release\r\n")
        while (l is not None):
            l = self.mgmtRead()
        self.mgmtWrite("log on\r\n")
        while (l is not None):
            l = self.mgmtRead()
        self.mgmtWrite("state on\r\n")
        while (l is not None):
            l = self.mgmtRead()
                    
    def stop(self):
        if config.Config.CAP.noRun:
            return()
        self.mgmtWrite("signal SIGTERM\r\n")
        l = self.mgmtRead()
        while (l is not None):
            l = self.mgmtRead()
        log.L.warning("Stopped service %s[%s]" % (self.name, self.id))
        return()
    
    def orchestrate(self):
        l = self.mgmtRead()
        while (l is not None):
            l = self.mgmtRead()
        if (self.initphase==0):
            self.unHold()
            self.initphase = 1
        l = self.getLine()
        while (l is not None):
            log.L.debug("%s[%s]-stderr: %s" % (self.type, self.id, l))
            l = self.getLine()
        
        return(self.isAlive())
    
