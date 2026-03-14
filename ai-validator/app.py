from flask import Flask, render_template, request, jsonify
from dotenv import load_dotenv
import anthropic
import requests
import json
import os
import urllib3
from datetime import datetime

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
load_dotenv()

app = Flask(__name__)

client = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))
WAZUH_HOST = os.getenv("WAZUH_HOST", "192.168.56.101")
WAZUH_USER = os.getenv("WAZUH_USER", "admin")
WAZUH_PASSWORD = os.getenv("WAZUH_PASSWORD", "admin")

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

def get_wazuh_alerts(limit=20):
    try:
        auth_url = f"https://{WAZUH_HOST}/security/user/authenticate"
        auth_resp = requests.post(
            auth_url,
            auth=(WAZUH_USER, WAZUH_PASSWORD),
            verify=False,
            timeout=5
        )
        token = auth_resp.json()["data"]["token"]
        headers = {"Authorization": f"Bearer {token}"}
        alerts_url = f"https://{WAZUH_HOST}/alerts"
        params = {"limit": limit, "sort": "-timestamp"}
        resp = requests.get(alerts_url, headers=headers, params=params, verify=False, timeout=5)
        return resp.json().get("data", {}).get("affected_items", [])
    except Exception as e:
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
    alerts = get_wazuh_alerts()
    return jsonify({"alerts": alerts})

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

    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1500,
        messages=[{"role": "user", "content": prompt}]
    )

    feedback = message.content[0].text

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

@app.route("/api/history")
def history():
    return jsonify({"history": load_history()})

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000)