# Investigation Report — port scan

**Date :** 2026-03-16
**Scénario :** port scan
**Verdict :** Cannot Determine (Template Not Filled)
**Score AI :** 4/100

---

## Rapport

Alert ID: [WZ-XXXX]
Date/Time: [YYYY-MM-DD HH:MM:SS]
Source IP: [X.X.X.X]
Destination IP: [X.X.X.X]
Rule triggered: Nmap port scan detected
Severity: Medium

## What I observed
[Describe the scan pattern you saw in Wazuh - number of ports, timing, flags...]

## IOCs identified
- Source IP: [X.X.X.X]
- Ports scanned: [list ports]
- Scan type: [SYN/UDP/Full]
- Duration: [X seconds]

## My verdict
[ ] True Positive  [ ] False Positive

## Justification
[Why is this a TP or FP? Is this IP known? Is this expected behavior?]

## Recommended action
[ ] Block source IP
[ ] Escalate to Tier 2
[ ] Monitor and watch
[ ] Close - false positive

---

## Feedback AI

**VERDICT**: Cannot Determine (Template Not Filled)
**CONFIDENCE**: 0%
**SCORE**: 4/100

---

**WHAT WAS DONE WELL**:
- The report template structure is present and shows awareness of the required sections (Alert context, IOCs, verdict, justification, recommended action)
- The correct rule type (Nmap port scan) is referenced in the header, indicating basic familiarity with the alert category

---

**WHAT IS MISSING OR INCORRECT**:
- **Alert Context (-9/10)**: Every single field is a placeholder — Alert ID, Date/Time, Source IP, and Destination IP are all `[brackets]`. No real data was populated. Only 1 point retained for having the section header present.
- **IOCs Identified (-19/20)**: All IOC fields are unfilled — source IP, ports scanned, scan type, and duration are all template placeholders. Zero actionable intelligence provided. 1 point retained for listing the correct IOC categories.
- **TP/FP Verdict (-25/25)**: Neither checkbox is selected. No verdict was made. The justification section contains only a placeholder prompt. This is a complete failure of the core analytical task.
- **Quality of Analysis (-24/25)**: The "What I observed" section is entirely blank (placeholder text). There is no timeline, no scan pattern description, no flag analysis (SYN/RST behavior), no correlation with threat intel, no check against asset inventory, and no context about whether the source IP is internal/external or known. 1 point retained for the section existing.
- **Recommended Action (-20/20)**: No checkbox is selected. No action was recommended. This leaves the SOC with no guidance on how to respond.

---

**HOW TO REACH 100/100**:
- **Populate every alert header field** with real data from the SIEM: exact Alert ID, precise timestamp (e.g., `2024-11-14 03:42:17`), real source and destination IPs pulled directly from Wazuh
- **Document the full IOC list**: include every port probed (e.g., 22, 80, 443, 3389...), the exact scan type observed (SYN stealth, full TCP connect, UDP), total ports hit, and scan duration in seconds
- **Write a concrete observation paragraph**: describe the packet pattern — e.g., "285 SYN packets sent to sequential ports within 4 seconds, no corresponding ACK responses, consistent with Nmap default scan behavior"
- **Make a definitive TP/FP decision** and justify it: check the source IP against threat intel feeds (VirusTotal, AbuseIPDB), verify if it's an authorized internal scanner (vulnerability scanner, pen test), and cross-reference with change management records
- **Select and justify a specific recommended action**: e.g., "Block source IP at perimeter firewall and escalate to Tier 2 for threat hunt on destination host" — vague non-answers are not acceptable in a live SOC environment

---

**RECOMMENDATION**:
**Do not submit this report in its current state.** Go back to Wazuh and open the actual alert. Pull the raw log data, extract every field, and rewrite the report from scratch using real values. Before concluding TP or FP, look up the source IP on AbuseIPDB and check your internal asset register to confirm whether this IP belongs to an authorized scanner. Only then select your verdict and action. This report as submitted provides zero investigative value and would delay incident response in a real environment.

---

*Généré automatiquement via AI Validator — SOC Home Lab*