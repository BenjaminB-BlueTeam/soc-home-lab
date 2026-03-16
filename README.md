# SOC Home Lab

> Virtualized SOC environment with real-time intrusion detection, network IDS, and AI-powered investigation validation.
> Built on Windows 11 with VirtualBox — no cloud, no cost, runs entirely on your machine.

---

## Objective

Practice real SOC analyst workflows: detect attacks with Wazuh, investigate alerts, write investigation reports, and get instant AI feedback scored out of 100. Designed to build and demonstrate blue team skills for a junior analyst CV.

---

## Architecture

```
Windows 11 (host)
├── VirtualBox
│   ├── Wazuh v4.14.3 (SIEM — headless, no GUI)
│   │   ├── eth0 : 192.168.1.x     (bridge — home network)
│   │   └── eth1 : 192.168.56.x   (host-only — static IP 192.168.56.101)
│   └── Kali Linux 2025.4 (attacker — GUI)
│       ├── Adapter 1 : host-only  (192.168.56.x)
│       └── Adapter 2 : NAT        (internet)
└── AI Validator (Flask — localhost:5000)
    ├── Wazuh REST API  → port 55000
    ├── OpenSearch      → SSH tunnel → port 9200  (real alerts)
    └── AI API          → Claude or OpenAI
```

---

## Quick Start

**Prérequis :** VirtualBox installé, VMs Wazuh et Kali importées et configurées.

1. Démarrer la VM Wazuh (headless)
2. Démarrer la VM Kali (GUI)
3. Lancer l'AI Validator :
```bash
cd ai-validator
pip install -r requirements.txt
python app.py
```
4. Ouvrir http://localhost:5000

---

## Features

### Auto-import Wazuh alerts
Alerts load automatically when the validator opens — no manual import button. A silent background refresh runs every 30 seconds and updates the list without interrupting your report.

### NETWORK vs HOST alert tagging
Every alert is tagged at a glance:

| Badge | Meaning | Source |
|---|---|---|
| `NETWORK` (blue) | Detected by Suricata IDS on the network | rule 86601 / groups: ids, suricata |
| `HOST` (gray) | Detected by Wazuh agent on the OS | auth, syscheck, process, cron… |

### Severity color coding
Alert severity is shown as a left-border stripe and a pill badge:

| Level | Badge |
|---|---|
| 12+ | CRITICAL (red) |
| 8–11 | HIGH (orange) |
| 5–7 | MEDIUM (yellow) |
| < 5 | low (muted) |

### One-click report pre-fill
Click any alert in the list to instantly populate the report textarea with the alert's timestamp, source IP, agent name, rule description, and rule level — plus blank sections for your analysis.

### AI-scored investigation reports
Submit a report and get:
- A score out of 100
- True Positive / False Positive verdict
- Confidence rating
- Structured feedback: what was done well, what is missing, and exactly how to reach 100/100
- Full history of past reports

### Push reports to GitHub
After scoring, push the investigation report directly to the `investigations/` folder on GitHub in one click. The report is saved as a formatted Markdown file with score, verdict, and AI feedback — ready to share with a recruiter.

---

## AI Provider

The validator supports two AI providers — configure in `ai-validator/.env`:

| Provider | Model | API Key |
|---|---|---|
| Claude (Anthropic) | claude-sonnet-4-6 | [console.anthropic.com](https://console.anthropic.com) |
| OpenAI | gpt-4o | [platform.openai.com](https://platform.openai.com/api-keys) |

Your API key is saved locally in `ai-validator/.env` only. It is never shared or transmitted anywhere other than the selected AI provider.

---

## Attack Scenarios

| Scenario | MITRE ATT&CK | Detection | Status |
|---|---|---|---|
| Network reconnaissance | T1046 | Suricata: SCAN nmap SYN | Tested |
| SSH brute force | T1110 | Wazuh rule 5712 (level 12) | Tested |
| User creation | T1136.001 | Wazuh rule 5902 | Tested |
| Data exfiltration | T1048 | Wazuh + Suricata | Tested |
| Persistence (crontab) | T1053.003 | Wazuh rule 5903 | Tested |
| Privilege escalation | T1548.003 | Wazuh rule 5402 | Tested |

Each scenario has a matching report template in the AI Validator (selectable via the Attack Type buttons). After running an attack from Kali, click an alert in the validator to pre-fill your report.

---

## AI Validator — Scoring Criteria

| Criteria | Points |
|---|---|
| Alert context (ID, date/time, IPs, rule triggered) | 10 |
| IOCs identified (IPs, ports, processes, hashes, files) | 20 |
| TP/FP verdict with clear justification | 25 |
| Analysis quality (timeline, correlation, reasoning) | 25 |
| Recommended action | 20 |

---

## Tech Stack

| Component | Tool | Version |
|---|---|---|
| SIEM | Wazuh | 4.14.3 |
| Attacker VM | Kali Linux | 2025.4 |
| Wazuh agent | wazuh-agent | 4.14.3 |
| Real alert source | OpenSearch via SSH tunnel | — |
| Network IDS | Suricata | 7.0.13 |
| AI Validator backend | Flask + Claude / OpenAI | Python 3.x |
| AI Validator frontend | Vanilla JS + CSS | — |
| Hypervisor | VirtualBox | 7.x |

---

## Repository Structure

```
soc-home-lab/
├── attacks/                    # Attack scripts to run from Kali
├── docs/                       # Architecture, config, incident response playbooks
├── wazuh-rules/                # Custom detection rules (XML, MITRE-mapped)
├── investigations/             # Investigation reports pushed from AI Validator
└── ai-validator/
    ├── app.py                  # Flask backend — Wazuh API + AI integration + GitHub push
    ├── health_check.py         # SSH health check & service repair for Wazuh
    ├── requirements.txt        # Python dependencies
    ├── .env.example            # Environment variable template
    ├── .env                    # Your local config (not committed)
    ├── reports_history.json
    ├── static/
    │   ├── css/style.css       # Dark theme
    │   └── js/app.js           # Auto-import, silent refresh, NETWORK/HOST tagging, GitHub push
    └── templates/
        └── index.html
```

---

## Default Credentials

| Service | URL | Username | Password |
|---|---|---|---|
| Wazuh Dashboard | https://192.168.56.101 | admin | WazuhLab123* |
| Wazuh REST API | https://192.168.56.101:55000 | wazuh | wazuh |
| Kali Linux | — | kali | kali |
| AI Validator | http://localhost:5000 | — | — |

---

## License

MIT — free to use, fork, and adapt for learning purposes.
