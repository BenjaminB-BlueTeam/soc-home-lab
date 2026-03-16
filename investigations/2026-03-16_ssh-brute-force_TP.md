# Investigation Report — ssh brute force

**Date :** 2026-03-16
**Scénario :** ssh brute force
**Verdict :** True Positive
**Score AI :** 72/100

---

## Rapport

Alert ID: 1773670287.1345528
Date/Time: 2026-03-16 15:11:27
Source IP: 192.168.56.101 (Kali-Attacker)
Destination IP: 192.168.56.103 (wazuh-server)
Rule triggered: Maximum authentication attempts exceeded (Rule 5758)
Rule level: 8
MITRE ATT&CK: T1110 — Brute Force / Credential Access

## What I observed
Wazuh detected a massive SSH brute force attack from 192.168.56.101 (Kali) 
targeting the root account on wazuh-server. Rule 5758 fired 68 times 
(rule.firedtimes: 68), indicating repeated authentication failures in a short 
timeframe. The full log confirms: "maximum authentication attempts exceeded 
for root from 192.168.56.101 port 59474 ssh2 [preauth]". The attack used 
Hydra with the rockyou.txt wordlist targeting SSH port 22.

## IOCs identified
- Source IP: 192.168.56.101 (Kali attacker)
- Target user: root
- Source port: 59474
- Protocol: SSH2
- Rule fired: 68 times
- Decoder: sshd / journald

## My verdict
[X] True Positive  [ ] False Positive

## Justification
This is a clear True Positive. The source IP 192.168.56.101 is the Kali 
attacker VM. Rule 5758 fired 68 times in minutes, consistent with automated 
brute force behavior. The target was root — a high-value account. The log 
explicitly states "maximum authentication attempts exceeded" confirming the 
brute force threshold was reached. No legitimate user can generate 68 failed 
auth attempts in this timeframe.

## Recommended action
[X] Block source IP
[ ] Escalate to Tier 2
[ ] Monitor and watch
[ ] Close - false positive

---

## Feedback AI

**VERDICT**: True Positive
**CONFIDENCE**: 95%
**SCORE**: 72/100

---

**WHAT WAS DONE WELL**:
- Excellent alert context: Alert ID, timestamp, source/destination IPs, hostname labels, rule ID, rule level, and MITRE ATT&CK mapping (T1110) are all clearly documented — this alone shows strong foundational habits
- IOC identification is solid: source IP, target username (root), source port, protocol, decoder, and rule fire count are all listed — this is more thorough than most junior analysts provide
- Verdict is correct (True Positive) with logical, well-structured justification — the reasoning is concise and references concrete evidence (rule fired 68 times, root targeting, explicit log message)
- Attacker tooling identified (Hydra + rockyou.txt) which adds significant intelligence value to the report

---

**WHAT IS MISSING OR INCORRECT**:

- **IOC section missing destination port (SSH/22) explicitly listed as an IOC** (-3 points): The destination port 22 is mentioned in the body but never formally listed in the IOC block. Every network-level IOC must appear in the IOC table for operational use by other analysts or firewall teams
- **No timeline reconstruction** (-10 points): There is no event timeline showing the progression of events (e.g., first failed attempt → threshold breach at attempt X → rule fired at 15:11:27). A timeline is critical for understanding attack velocity and duration, and it is entirely absent from this report
- **No authentication success/failure outcome analysis** (-8 points): The report never confirms whether the brute force *succeeded or failed*. Was root ever authenticated? Were there any successful SSH logins following the failures? This is the most critical question in any brute force investigation and its omission is a serious analytical gap
- **No process or file-level IOCs** (-4 points): No mention of whether any processes were spawned on the target (wazuh-server), no file artifacts checked (e.g., auth.log entries, bash history, /tmp contents), and no check for lateral movement post-event
- **Recommended action is incomplete** (-3 points): "Block source IP" is correct but insufficient. No mention of *where* to block (firewall? host-level iptables? Wazuh active response?), no escalation path defined if root was compromised, and no recommendation to audit the wazuh-server for post-compromise indicators

---

**HOW TO REACH 100/100**:
- **Add a formal timeline**: Document first observed event, rate of attempts (e.g., 68 attempts in ~30 seconds), exact moment rule 5758 fired, and any events after — this demonstrates analytical rigor and helps incident responders understand urgency
- **Explicitly confirm or deny authentication success**: Query auth logs or Wazuh for any `Accepted password` or `session opened` events from 192.168.56.101 — state clearly "no successful login detected" or escalate immediately if one was found
- **Expand IOC table**: Add destination port 22, process name (sshd), log source file (/var/log/auth.log or journald), and any post-exploitation artifacts checked
- **Strengthen the recommended action section**: Specify the blocking mechanism (e.g., "Add 192.168.56.101 to Wazuh active response blocklist and host firewall via iptables"), add "Audit wazuh-server for indicators of compromise if any login succeeded," and define escalation criteria

---

**RECOMMENDATION**:
**Immediately verify whether any SSH session from 192.168.56.101 was successfully authenticated** — search Wazuh for Rule 5715 (`sshd: authentication success`) or grep auth logs for `Accepted` from that IP. If *any* successful login exists, escalate to Tier 2 instantly, isolate the wazuh-server, and treat this as an active compromise. If no success is confirmed, proceed with blocking the source IP via active response and document the negative finding explicitly in the report. Do not close this alert until post-authentication status is 100% confirmed.

---

*Généré automatiquement via AI Validator — SOC Home Lab*