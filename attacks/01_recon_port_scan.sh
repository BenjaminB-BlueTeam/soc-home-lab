#!/bin/bash
# ──────────────────────────────────────────────────────────────────
# MITRE ATT&CK : T1046 — Network Service Scanning
# Technique    : SYN scan + détection service/version (nmap)
# Génère       : Alerte Suricata (rule 86601) — badge NETWORK
# Run depuis   : Kali VM
# Usage        : bash 01_recon_port_scan.sh [IP_CIBLE]
# ──────────────────────────────────────────────────────────────────

TARGET=${1:-192.168.56.102}

echo "[*] SYN scan + détection service → $TARGET"
nmap -sS -sV --top-ports 1000 -T4 "$TARGET" -oN /tmp/recon_portscan.txt

echo ""
echo "[*] Résultats sauvegardés : /tmp/recon_portscan.txt"
cat /tmp/recon_portscan.txt
