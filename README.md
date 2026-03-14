# 🛡️ SOC Home Lab

> Virtualized personal SOC environment with real-time intrusion detection and AI-powered investigation validation.

## 🎯 Objective

Simulate a realistic SOC environment to practice alert analysis, incident response and threat hunting — with an AI system that validates investigation reports and provides feedback.

## 🏗️ Tech Stack

| Component | Tool | Role |
|---|---|---|
| SIEM | Wazuh 4.14 | Detection, alerts, dashboard |
| Attacker | Kali Linux | Attack simulation |
| Automation | Atomic Red Team | MITRE ATT&CK scenarios |
| AI Validator | Claude API | Investigation feedback & scoring |
| Hypervisor | VirtualBox | Local virtualization |

## 📁 Structure
```
soc-home-lab/
├── docs/               # Architecture & documentation
├── investigations/     # Investigation reports
├── attacks/            # Automated attack scripts
├── wazuh-rules/        # Custom detection rules
└── ai-validator/       # AI validation system
```

## 🚀 Scenarios Covered

- [ ] Network reconnaissance (nmap)
- [ ] SSH brute force
- [ ] Privilege escalation
- [ ] Data exfiltration
- [ ] Persistence (malicious crontab)

## 📊 Status

🟢 SIEM operational | 🟢 Kali agent connected | 🔄 Atomic Red Team in progress
