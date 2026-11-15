# Zeigt einen mit Stufe 2b gelesenen Kernel-Log-Ringpuffer als Text.
# Aufruf: python3 kernel_log_lesen.py logs/kernel_log_<stempel>.bin
import sys, re, os
b = open(sys.argv[1], 'rb').read()
meta = sys.argv[1].replace('kernel_log_', 'kernel_log_meta_').replace('.bin', '.txt')
end = None
if os.path.exists(meta):
    m = dict(l.split(' ', 1) for l in open(meta).read().splitlines())
    end = int(m['log_end']) % len(b)
data = b[end:] + b[:end] if end is not None else b
txt = data.replace(b'\x00', b'').decode('latin1', 'replace')
print(txt)
