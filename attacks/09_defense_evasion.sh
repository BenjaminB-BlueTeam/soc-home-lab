#!/bin/bash
# ──────────────────────────────────────────────────────────────────
# MITRE ATT&CK : T1070.003 — Indicator Removal: Clear Command History
#                T1070.002 — Indicator Removal: Clear Linux Logs
# Technique    : Suppression des traces d'activité (historique, logs)
# Génère       : Wazuh syscheck (modification fichiers logs)
# Run depuis   : Cible (Wazuh VM)
# Usage        : bash 09_defense_evasion.sh
# ──────────────────────────────────────────────────────────────────

echo "[*] Phase 1 — Suppression de l'historique bash"
history -c
export HISTFILE=/dev/null
unset HISTFILE
echo "" > ~/.bash_history
echo "[+] Historique bash effacé"

echo ""
echo "[*] Phase 2 — Désactivation de l'enregistrement futur"
export HISTSIZE=0
export HISTFILESIZE=0
echo "[+] HISTSIZE et HISTFILESIZE mis à 0"

echo ""
echo "[*] Phase 3 — Nettoyage des fichiers temporaires d'attaque"
rm -f /tmp/sensitive_*.csv /tmp/recon_*.txt /tmp/scan_*.txt 2>/dev/null
echo "[+] Fichiers temporaires supprimés"

echo ""
echo "[*] Phase 4 — Tentative de modification des logs système (root requis)"
if [ "$(id -u)" -eq 0 ]; then
    # On simule seulement — on n'efface pas les vrais logs
    echo "" >> /var/log/auth.log
    echo "[+] Entrée vide ajoutée à auth.log (simulation syscheck)"
    echo "[!] En réel : shred -u /var/log/auth.log ou echo > /var/log/auth.log"
else
    echo "[-] Root requis pour modifier /var/log/auth.log"
fi

echo ""
echo "[!] Wazuh syscheck devrait détecter les modifications dans /var/log/"
