from flask import Flask, render_template, request, jsonify
from dotenv import load_dotenv
import requests
import json
import os
import urllib3
from datetime import datetime
from sshtunnel import SSHTunnelForwarder

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
load_dotenv()

app = Flask(__name__)

# ── AI provider (claude | openai) ─────────────────────────────
AI_PROVIDER = os.getenv("AI_PROVIDER", "claude")

if AI_PROVIDER == "openai":
    from openai import OpenAI
    ai_client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
    AI_MODEL  = os.getenv("OPENAI_MODEL", "gpt-4o")
else:
    import anthropic
    ai_client = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))
    AI_MODEL  = os.getenv("CLAUDE_MODEL", "claude-sonnet-4-6")

def call_ai(prompt: str) -> str:
    if AI_PROVIDER == "openai":
        resp = ai_client.chat.completions.create(
            model=AI_MODEL,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=1500,
        )
        return resp.choices[0].message.content
    else:
        msg = ai_client.messages.create(
            model=AI_MODEL,
            max_tokens=1500,
            messages=[{"role": "user", "content": prompt}],
        )
        return msg.content[0].text

WAZUH_HOST = os.getenv("WAZUH_HOST", "192.168.56.101")
WAZUH_USER = os.getenv("WAZUH_USER", "wazuh")
WAZUH_PASSWORD = os.getenv("WAZUH_PASSWORD", "wazuh")
WAZUH_SSH_USER = os.getenv("WAZUH_SSH_USER", "wazuh-user")
WAZUH_SSH_PASSWORD = os.getenv("WAZUH_SSH_PASSWORD", "wazuh")
WAZUH_INDEXER_USER = os.getenv("WAZUH_INDEXER_USER", "admin")
WAZUH_INDEXER_PASSWORD = os.getenv("WAZUH_INDEXER_PASSWORD", "WazuhLab123*")

HISTORY_FILE = "reports_history.json"

SCORING_CRITERIA = """
SCORING CRITERIA (total 100 points):
1. Alert context (ID, date, source/dest IPs, rule triggered): 10 points
2. IOCs identified (IPs, ports, processes, files): 20 points
3. Correct TP/FP verdict with solid justification: 25 points
4. Quality of analysis (timeline, correlation, context): 25 points
5. Recommended action (block, escalate, close, monitor): 20 points

For each missing or incorrect element, deduct points proportionally.
Always explain EXACTLY what was missing to reach 100/100.
"""

TEMPLATES = {
    "port_scan": """Alert ID: [WZ-XXXX]
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
[ ] Close - false positive""",

    "ssh_brute_force": """Alert ID: [WZ-XXXX]
Date/Time: [YYYY-MM-DD HH:MM:SS]
Source IP: [X.X.X.X]
Destination IP: [X.X.X.X]
Rule triggered: SSH brute force attempt
Severity: High

## What I observed
[Number of failed attempts, timeframe, usernames tried...]

## IOCs identified
- Source IP: [X.X.X.X]
- Target user(s): [root, admin, ...]
- Number of attempts: [X]
- Timeframe: [X attempts in Y seconds]

## My verdict
[ ] True Positive  [ ] False Positive

## Justification
[Threshold exceeded? Known attacker IP? Successful login after attempts?]

## Recommended action
[ ] Block source IP immediately
[ ] Reset compromised credentials
[ ] Escalate - possible breach
[ ] Close - false positive""",

    "privilege_escalation": """Alert ID: [WZ-XXXX]
Date/Time: [YYYY-MM-DD HH:MM:SS]
Source IP: [X.X.X.X]
User: [username]
Rule triggered: Privilege escalation attempt
Severity: High

## What I observed
[Which command was run, what privilege was attempted, context...]

## IOCs identified
- User: [username]
- Command executed: [sudo/su/exploit...]
- Target privilege: [root/admin]
- Process ID: [PID]

## My verdict
[ ] True Positive  [ ] False Positive

## Justification
[Is this user authorized? Is this expected behavior? Was escalation successful?]

## Recommended action
[ ] Isolate compromised account
[ ] Escalate immediately
[ ] Review sudo rules
[ ] Close - authorized action""",

    "data_exfiltration": """Alert ID: [WZ-XXXX]
Date/Time: [YYYY-MM-DD HH:MM:SS]
Source host: [hostname]
Destination IP: [X.X.X.X]
Rule triggered: Possible data exfiltration detected
Severity: High
MITRE ATT&CK: T1048 — Exfiltration Over Alternative Protocol

## What I observed
[Describe the transfer: tool used (curl/nc/scp/dns), volume, destination, timing...]

## IOCs identified
- Source host: [hostname]
- Destination IP/domain: [X.X.X.X or domain]
- Protocol/tool: [curl / netcat / scp / DNS tunnel...]
- Data volume: [X MB/KB]
- Process: [process name and PID]
- Port used: [port]

## My verdict
[ ] True Positive  [ ] False Positive

## Justification
[Is this destination known? Is this transfer expected? Is the volume abnormal? Is the process legitimate?]

## Recommended action
[ ] Block destination IP immediately
[ ] Isolate source host
[ ] Collect forensic evidence (pcap, process tree)
[ ] Escalate to IR team
[ ] Close - authorized transfer""",

    "persistence_cron": """Alert ID: [WZ-XXXX]
Date/Time: [YYYY-MM-DD HH:MM:SS]
Affected host: [hostname]
User: [username]
Rule triggered: Suspicious crontab modification detected
Severity: High
MITRE ATT&CK: T1053.003 — Scheduled Task/Job: Cron

## What I observed
[Describe the cron entry: file modified, command scheduled, frequency, who modified it...]

## IOCs identified
- Cron file modified: [/etc/cron.d/... or crontab -e]
- Scheduled command: [the actual command or script]
- Frequency: [* * * * * / timing]
- User who modified: [username]
- Command purpose: [reverse shell / download / beacon / unknown]

## My verdict
[ ] True Positive  [ ] False Positive

## Justification
[Is this cron entry expected? Does the command look malicious (curl|bash, /tmp/, base64...)? Is the user authorized?]

## Recommended action
[ ] Remove malicious cron entry immediately
[ ] Check for other persistence mechanisms
[ ] Audit all crontabs on the host
[ ] Escalate — possible full compromise
[ ] Close - authorized scheduled task""",

    "malware_detection": """Alert ID: [WZ-XXXX]
Date/Time: [YYYY-MM-DD HH:MM:SS]
Affected host: [hostname]
Rule triggered: Malware/suspicious file detected
Severity: Critical

## What I observed
[File name, path, hash, behavior observed...]

## IOCs identified
- File name: [filename]
- File path: [/path/to/file]
- MD5/SHA256: [hash]
- Process spawned: [process name]
- Network connection: [IP:port if any]

## My verdict
[ ] True Positive  [ ] False Positive

## Justification
[VirusTotal result? Known malware family? Behavior analysis?]

## Recommended action
[ ] Isolate host immediately
[ ] Collect forensic evidence
[ ] Escalate to IR team
[ ] Close - false positive"""
}

def get_wazuh_real_alerts(limit=20):
    """Query real security alerts from OpenSearch via SSH tunnel on port 9200.
    Only returns alerts with rule.level >= 5 to filter out PAM/SSH noise.
    Falls back to level >= 3 if nothing found at level 5.
    """
    try:
        with SSHTunnelForwarder(
            (WAZUH_HOST, 22),
            ssh_username=WAZUH_SSH_USER,
            ssh_password=WAZUH_SSH_PASSWORD,
            remote_bind_address=("127.0.0.1", 9200),
        ) as tunnel:
            url = f"https://127.0.0.1:{tunnel.local_bind_port}/wazuh-alerts-*/_search"

            def query(min_level):
                return {
                    "size": limit,
                    "sort": [{"timestamp": {"order": "desc"}}],
                    "query": {
                        "range": {"rule.level": {"gte": min_level}}
                    },
                }

            resp = requests.post(
                url,
                auth=(WAZUH_INDEXER_USER, WAZUH_INDEXER_PASSWORD),
                json=query(5),
                verify=False,
                timeout=10,
            )

            if resp.status_code != 200:
                print(f"[DEBUG] OpenSearch returned {resp.status_code}: {resp.text[:200]}")
                return None

            hits = resp.json().get("hits", {}).get("hits", [])

            # Fallback to level >= 3 if no significant alerts found
            if not hits:
                resp2 = requests.post(
                    url,
                    auth=(WAZUH_INDEXER_USER, WAZUH_INDEXER_PASSWORD),
                    json=query(3),
                    verify=False,
                    timeout=10,
                )
                if resp2.status_code == 200:
                    hits = resp2.json().get("hits", {}).get("hits", [])

            alerts = []
            for hit in hits:
                src = hit.get("_source", {})
                alerts.append({
                    "id": src.get("id", hit.get("_id", "")),
                    "timestamp": src.get("timestamp", ""),
                    "rule": src.get("rule", {}),
                    "agent": src.get("agent", {}),
                    "data": src.get("data", {}),
                    "full_log": src.get("full_log", ""),
                })
            return alerts

    except Exception as e:
        print(f"[DEBUG] SSH tunnel error: {e}")
        return None


def get_wazuh_alerts(limit=20):
    try:
        port = os.getenv("WAZUH_PORT", "55000")
        base = f"https://{WAZUH_HOST}:{port}"

        auth_resp = requests.post(
            f"{base}/security/user/authenticate",
            auth=(WAZUH_USER, WAZUH_PASSWORD),
            verify=False,
            timeout=5
        )

        if auth_resp.status_code != 200:
            return []

        token = auth_resp.json()["data"]["token"]
        headers = {"Authorization": f"Bearer {token}"}

        resp = requests.get(
            f"{base}/manager/logs",
            headers=headers,
            params={
                "limit": limit,
                "sort": "-timestamp",
                "level": "warning"
            },
            verify=False,
            timeout=5
        )

        if resp.status_code != 200:
            return []

        items = resp.json().get("data", {}).get("affected_items", [])
        
        # Formater pour ressembler à des alertes
        alerts = []
        for item in items:
            alerts.append({
                "id": item.get("timestamp", ""),
                "timestamp": item.get("timestamp", ""),
                "rule": {
                    "description": item.get("description", "No description"),
                    "level": 7 if item.get("level") == "warning" else 3
                },
                "agent": {
                    "name": "wazuh-server",
                    "ip": WAZUH_HOST
                }
            })
        return alerts

    except Exception as e:
        print(f"[DEBUG] Error: {e}")
        return []

def load_history():
    if os.path.exists(HISTORY_FILE):
        with open(HISTORY_FILE, "r") as f:
            return json.load(f)
    return []

def save_history(entry):
    history = load_history()
    history.insert(0, entry)
    history = history[:50]
    with open(HISTORY_FILE, "w") as f:
        json.dump(history, f, indent=2)

@app.route("/")
def index():
    return render_template("index.html", templates=list(TEMPLATES.keys()))

@app.route("/api/template/<attack_type>")
def get_template(attack_type):
    return jsonify({"template": TEMPLATES.get(attack_type, "")})

@app.route("/api/wazuh/alerts")
def wazuh_alerts():
    alerts = get_wazuh_real_alerts()
    if alerts is not None:
        return jsonify({"alerts": alerts, "source": "opensearch"})
    # Fallback to manager logs if SSH tunnel fails
    alerts = get_wazuh_alerts()
    return jsonify({"alerts": alerts, "source": "manager_logs"})

@app.route("/api/validate", methods=["POST"])
def validate():
    data = request.json
    report = data.get("report", "")
    attack_type = data.get("attack_type", "unknown")

    if len(report.strip()) < 50:
        return jsonify({"error": "Report too short"}), 400

    prompt = f"""You are a senior SOC analyst reviewing a junior analyst's investigation report.

{SCORING_CRITERIA}

Attack type: {attack_type}

Evaluate this report and respond in this EXACT format:

**VERDICT**: [True Positive / False Positive]
**CONFIDENCE**: [0-100]%
**SCORE**: [0-100]/100

**WHAT WAS DONE WELL**:
- [point 1]
- [point 2]

**WHAT IS MISSING OR INCORRECT**:
- [point 1 with exact points lost]
- [point 2 with exact points lost]

**HOW TO REACH 100/100**:
- [exact action 1]
- [exact action 2]

**RECOMMENDATION**:
[What the analyst should do next as immediate action]

Be precise, educational and constructive. This is for training.

--- REPORT ---
{report}
--- END ---"""

    feedback = call_ai(prompt)

    score_line = [l for l in feedback.split("\n") if "**SCORE**" in l]
    score = 0
    if score_line:
        try:
            score = int(score_line[0].split(":")[1].strip().split("/")[0].replace("*","").strip())
        except:
            score = 0

    verdict_line = [l for l in feedback.split("\n") if "**VERDICT**" in l]
    verdict = "Unknown"
    if verdict_line:
        verdict = verdict_line[0].split(":")[1].strip().replace("*","").strip()

    entry = {
        "id": datetime.now().strftime("WZ-%Y%m%d-%H%M%S"),
        "date": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "attack_type": attack_type,
        "verdict": verdict,
        "score": score,
        "report": report[:200] + "..." if len(report) > 200 else report
    }
    save_history(entry)

    return jsonify({
        "feedback": feedback,
        "score": score,
        "verdict": verdict,
        "history_entry": entry
    })

@app.route("/api/info")
def info():
    return jsonify({"provider": AI_PROVIDER, "model": AI_MODEL})

@app.route("/api/history")
def history():
    return jsonify({"history": load_history()})

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000)