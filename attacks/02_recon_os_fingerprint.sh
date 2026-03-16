#!/bin/bash
# ──────────────────────────────────────────────────────────────────
# MITRE ATT&CK : T1082 — System Information Discovery
# Technique    : Détection OS + fingerprint agressif (nmap -A)
# Génère       : Alertes Suricata (patterns de scan agressif)
# Run depuis   : Kali VM
# Usage        : bash 02_recon_os_fingerprint.sh [IP_CIBLE]
# ──────────────────────────────────────────────────────────────────

TARGET=${1:-192.168.56.102}

echo "[*] OS fingerprint + scripts de détection → $TARGET"
nmap -A -sV --script=banner,ssh-hostkey "$TARGET"
