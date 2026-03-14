# Architecture

## Infrastructure

| Component | OS | IP | Role |
|---|---|---|---|
| Wazuh SIEM | Amazon Linux 2023 | 192.168.56.101 | SIEM + Dashboard |
| Kali Linux | Kali Rolling | 192.168.56.102 | Attacker |

## Network
- Isolated Host-Only network : 192.168.56.0/24
- Hypervisor : VirtualBox
- DHCP enabled : 192.168.56.100 - 192.168.56.254

## VM Specifications

| VM | RAM | CPU | Disk |
|---|---|---|---|
| Wazuh | 4 GB | 2 cores | 50 GB |
| Kali | 2 GB | 1 core | 80 GB |

## Data Flow
1. Kali agent sends logs → Wazuh server (192.168.56.101)
2. Wazuh indexes and analyzes events
3. Alerts visible on dashboard (https://192.168.56.101)
4. Analyst investigates → writes report → AI validates
