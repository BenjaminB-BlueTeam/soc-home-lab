"""
health_check.py — Check and repair Wazuh services via SSH
Usage: python health_check.py
Returns exit code 0 if OK or repaired, 1 if unreachable.
"""

import sys
import pathlib
import paramiko
from dotenv import load_dotenv
import os

load_dotenv(pathlib.Path(__file__).parent / ".env")

HOST     = os.getenv("WAZUH_HOST", "192.168.56.101")
SSH_USER = os.getenv("WAZUH_SSH_USER", "wazuh-user")
SSH_PASS = os.getenv("WAZUH_SSH_PASSWORD", "wazuh")

SERVICES = ["wazuh-manager", "wazuh-indexer"]

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

try:
    client.connect(HOST, port=22, username=SSH_USER, password=SSH_PASS, timeout=10)
except Exception as e:
    print(f"ERROR: Cannot connect via SSH to {HOST} — {e}", file=sys.stderr)
    sys.exit(1)

needs_restart = []
for svc in SERVICES:
    _, out, _ = client.exec_command(f"systemctl is-active {svc} 2>&1")
    status = out.read().decode().strip()
    print(f"  {svc}: {status}")
    if status != "active":
        needs_restart.append(svc)

if needs_restart:
    print(f"Restarting: {', '.join(needs_restart)}...")
    cmd = "sudo systemctl restart " + " ".join(needs_restart) + " 2>&1"
    _, out, _ = client.exec_command(cmd)
    out.read()  # wait for completion
    print("RESTARTED")
else:
    print("OK: all services active")

client.close()
sys.exit(0)
