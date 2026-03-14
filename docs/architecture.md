# Architecture

## Infrastructure

| Composant | OS | IP | Rôle |
|---|---|---|---|
| Wazuh SIEM | Amazon Linux 2023 | 192.168.56.101 | SIEM + Dashboard |
| Kali Linux | Kali Rolling | 192.168.56.102 | Attaquant |

## Réseau
- Réseau isolé Host-Only : 192.168.56.0/24
- Hyperviseur : VirtualBox
