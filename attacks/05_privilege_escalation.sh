#!/bin/bash
# ──────────────────────────────────────────────────────────────────
# MITRE ATT&CK : T1548.003 — Abuse Elevation Control Mechanism: Sudo
# Technique    : Tentatives sudo répétées + énumération des mauvaises configs
# Génère       : Wazuh rules 5401/5402 + rule custom 100003 (5 échecs / 60s)
# Run depuis   : Cible (Wazuh VM) — utilisateur non-root
# Usage        : bash 05_privilege_escalation.sh
# ──────────────────────────────────────────────────────────────────

echo "[*] Phase 1 — Tentatives sudo avec mauvais mot de passe (x6)"
for i in $(seq 1 6); do
    echo "[*] Tentative $i/6"
    echo "wrongpassword" | sudo -S id 2>/dev/null || true
    sleep 2
done

echo ""
echo "[*] Phase 2 — Énumération des commandes NOPASSWD"
sudo -l 2>/dev/null | grep -i nopasswd || echo "[-] Aucun NOPASSWD trouvé"

echo ""
echo "[*] Phase 3 — Recherche de binaires SUID hors chemins standards"
find / -perm -4000 -type f 2>/dev/null \
    | grep -Ev "^/usr/bin|^/usr/sbin|^/bin|^/sbin" \
    | head -10

echo ""
echo "[!] Script terminé. Vérifier les alertes Wazuh rules 5401/5402/100003."
