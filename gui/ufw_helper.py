#!/usr/bin/env python3
"""UFW privileged helper — runs as root via pkexec.

Protocol (stdin / stdout, line-buffered):
  startup  →  writes "READY\n"
  per cmd  ←  NUL-separated args + "\n"
             →  "{rc}\x00{output with \n→\x01}\n"
"""
import sys
import subprocess

sys.stdout.write('READY\n')
sys.stdout.flush()

for line in sys.stdin:
    line = line.rstrip('\n')
    if not line:
        continue
    args = line.split('\x00')
    r = subprocess.run(['ufw', '--force'] + args, capture_output=True, text=True)
    out = (r.stdout + r.stderr).replace('\n', '\x01')
    sys.stdout.write(f'{r.returncode}\x00{out}\n')
    sys.stdout.flush()
