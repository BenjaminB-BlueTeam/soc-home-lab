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
│   │   └── Adapter 1 : host-only  (192.168.56.103 — DHCP)
│   └── Kali Linux 2025.4 (attacker — GUI)
│       ├── Adapter 1 : host-only  (192.168.56.101)
│       └── Adapter 2 : NAT        (internet)
└── AI Validator (Flask — localhost:5000)
    ├── Wazuh REST API  → port 55000
    ├── OpenSearch      → SSH tunnel → port 9200  (real alerts)
    └── AI API          → Claude or OpenAI
```

> **Network:** Host-Only isolated network `192.168.56.0/24`. Wazuh has no internet access. Kali has internet via NAT (needed for tool updates and Atomic Red Team).
> **Windows hosts file:** `192.168.56.103 wazuh` (optional convenience entry)

---

## Quick Start

**Prerequisites:** VirtualBox installed, Wazuh and Kali OVAs imported and configured.

1. Start Wazuh VM (headless)
2. Start Kali VM (GUI)
3. Copy `.env.example` to `.env` and fill in your API keys:
```bash
cd C:\Users\<you>\soc-home-lab\ai-validator
copy .env.example .env
# Edit .env — set ANTHROPIC_API_KEY, GITHUB_TOKEN
# WAZUH_HOST=192.168.56.103 (already correct in .env.example)
```
4. Launch the AI Validator **from the ai-validator directory**:
```bash
pip install -r requirements.txt
python app.py
```
5. Open http://localhost:5000

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
| Network reconnaissance | T1046 | Wazuh: "Listened ports status changed" | Tested ✅ |
| SSH brute force | T1110 | Wazuh rule 5758 + custom 100001 (level 12) | Tested ✅ |
| System info discovery | T1082 | Atomic Red Team test | Tested ✅ |
| User creation | T1136.001 | Wazuh custom rule 100002 (level 14) | Scripted |
| Privilege escalation | T1548.003 | Wazuh custom rule 100003 (level 12) | Scripted |
| Persistence (crontab) | T1053.003 | Wazuh syscheck | Scripted |
| Data exfiltration | T1048 | Wazuh + Suricata | Scripted |
| Credential access | T1003.008 | Wazuh auditd | Scripted |
| Defense evasion | T1070.003 | Wazuh syscheck | Scripted |
| Reverse shell | T1059.004 | Wazuh (outbound connection) | Scripted |

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
| Wazuh agent | wazuh-agent (on Kali) | 4.14.3 |
| Real alert source | OpenSearch via SSH tunnel | — |
| Network IDS | Suricata | 7.0.13 |
| Attack automation | Atomic Red Team (invoke-atomicredteam) | — |
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
| Wazuh Dashboard | https://192.168.56.103 | admin | admin |
| Wazuh REST API | https://192.168.56.103:55000 | wazuh | wazuh |
| OpenSearch (SSH tunnel) | localhost:9200 | admin | admin |
| Wazuh SSH | 192.168.56.103 | wazuh-user | wazuh |
| Kali Linux | — | kali | kali |
| AI Validator | http://localhost:5000 | — | — |

---

## Troubleshooting

**wazuh-indexer crashes (oom-kill)**
OpenSearch is memory-hungry. If alerts stop appearing in the AI Validator, restart the indexer:
```bash
sudo systemctl start wazuh-indexer
```
Monitor RAM on the Wazuh VM — 4GB minimum recommended.

**rockyou.txt not found**
The wordlist ships compressed on Kali. Decompress it before use:
```bash
sudo gunzip /usr/share/wordlists/rockyou.txt.gz
```

**AI Validator can't connect to Wazuh**
- Verify `WAZUH_HOST=192.168.56.103` in `ai-validator/.env`
- Make sure you launch `python app.py` from the `ai-validator/` directory, not the repo root
- If OpenSearch is down, the app falls back to Wazuh manager logs API (port 55000) automatically

**Atomic Red Team not found on Kali**
Installed at `~/AtomicRedTeam/` on Kali. PowerShell 7.5.4 required:
```powershell
Import-Module ~/AtomicRedTeam/invoke-atomicredteam/Invoke-AtomicRedTeam.psd1
Invoke-AtomicTest T1082
```

---

## License

MIT — free to use, fork, and adapt for learning purposes.
