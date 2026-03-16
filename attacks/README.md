# Attacks

Scripts d'attaque pour générer des alertes Wazuh/Suricata.
Chaque script correspond à un scénario MITRE ATT&CK documenté.

---

## Prérequis

- VM Kali Linux démarrée (GUI)
- VM Wazuh démarrée (headless)
- IP Wazuh : `192.168.56.102` par défaut (ajustable en argument)
- IP Kali  : `192.168.56.103` par défaut (vérifier avec `ip a`)

---

## Deux types de scripts

### Depuis Kali (attaque réseau)
Ces scripts se lancent directement depuis un terminal Kali.
Ils génèrent des alertes **NETWORK** (badge bleu dans l'AI Validator).

| Script | MITRE | Technique | Alerte générée |
|--------|-------|-----------|----------------|
| `01_recon_port_scan.sh` | T1046 | Nmap SYN scan | Suricata rule 86601 |
| `02_recon_os_fingerprint.sh` | T1082 | Nmap -A aggressive | Suricata (scan agressif) |
| `03_ssh_brute_force.sh` | T1110 | Hydra SSH | Wazuh rule 5712 + custom 100001 |

### Depuis la cible (post-exploitation)
Ces scripts se lancent depuis un shell **sur la VM Wazuh** (via SSH après brute force, ou directement).
Ils génèrent des alertes **HOST** (badge gris dans l'AI Validator).

| Script | MITRE | Technique | Alerte générée | Root requis |
|--------|-------|-----------|----------------|-------------|
| `04_user_creation.sh` | T1136.001 | useradd backdoor | Wazuh rule 5902 + custom 100002 | ✅ |
| `05_privilege_escalation.sh` | T1548.003 | sudo abuse | Wazuh rules 5401/5402 + custom 100003 | ❌ |
| `06_persistence_cron.sh` | T1053.003 | Cron beacon | Wazuh syscheck | ✅ |
| `07_data_exfiltration.sh` | T1048 | curl + netcat | Wazuh + Suricata | ❌ |
| `08_credential_access.sh` | T1003.008 | /etc/shadow dump | Wazuh auditd | ✅ |
| `09_defense_evasion.sh` | T1070.003 | History clear | Wazuh syscheck | ❌ |
| `10_reverse_shell.sh` | T1059.004 | Bash /dev/tcp | Wazuh (connexion sortante) | ❌ |

---

## Workflow recommandé

```
1. Lancer le script depuis Kali (ou depuis la cible via SSH)
2. Attendre 15-30s que l'alerte remonte dans Wazuh
3. Ouvrir l'AI Validator → http://localhost:5000
4. Cliquer sur l'alerte dans la liste pour pré-remplir le rapport
5. Compléter le rapport, scorer, pusher sur GitHub
```

---

## Cleanup

Chaque script affiche sa commande de cleanup à la fin.
Pour `04_user_creation.sh` : `sudo userdel -r svc_backup`
Pour `06_persistence_cron.sh` : `sudo rm /etc/cron.d/svc_update`
