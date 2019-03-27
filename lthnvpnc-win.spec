# -*- mode: python -*-

block_cipher = None


a = Analysis(['client\\lthnvpnc.py'],
             pathex=['lib', "'C:\\Python37\\Lib\\site-packages'", 'C:\\Users\\jorda\\Desktop\\intense-vpn', 'C:\\Windows\\system32\\downlevel'],
             binaries=[('bin/openvpn.exe', 'bin'), ('bin/tstunnel.exe', 'bin'), ('bin/haproxy.exe', 'bin')],
             datas=[('lib', 'lib'), ('conf', 'conf'), ('bin/cygwin1.dll', 'bin'), ('bin/cygcrypto-1.0.0.dll', 'bin'), ('bin/cygz.dll', 'bin'), ('bin/cygpcre-1.dll', 'bin'), ('bin/cygssl-1.0.0.dll', 'bin'), ('bin/liblzo2-2.dll', 'bin'), ('bin/libpkcs11-helper-1.dll', 'bin'), ('bin/libcrypto-1_1-x64.dll', 'bin'), ('bin/libssl-1_1-x64.dll', 'bin'), ('bin/libeay32.dll', 'bin')],
             hiddenimports=[],
             hookspath=[],
             runtime_hooks=[],
             excludes=[],
             win_no_prefer_redirects=False,
             win_private_assemblies=False,
             cipher=block_cipher,
             noarchive=False)
pyz = PYZ(a.pure, a.zipped_data,
             cipher=block_cipher)
exe = EXE(pyz,
          a.scripts,
          a.binaries,
          a.zipfiles,
          a.datas,
          [],
          name='lthnvpnc',
          debug=False,
          bootloader_ignore_signals=False,
          strip=False,
          upx=True,
          runtime_tmpdir=None,
          console=True )
