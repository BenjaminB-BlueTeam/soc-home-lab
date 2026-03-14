let currentAttack = 'port_scan';
let currentSev = 'medium';

async function loadTemplate(type) {
  const r = await fetch(`/api/template/${type}`);
  const d = await r.json();
  document.getElementById('report-input').value = d.template;
}

function selectAttack(btn) {
  document.querySelectorAll('.attack-btn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  currentAttack = btn.dataset.type;
  loadTemplate(currentAttack);
}

function selectSev(btn) {
  document.querySelectorAll('.sev-btn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  currentSev = btn.dataset.sev;
}

function clearReport() {
  loadTemplate(currentAttack);
}

async function importFromWazuh() {
  const section = document.getElementById('wazuh-alerts-section');
  const list = document.getElementById('wazuh-alerts-list');
  section.style.display = 'block';
  list.innerHTML = '<div class="wazuh-alert-item"><span class="alert-meta">Loading alerts...</span></div>';

  try {
    const r = await fetch('/api/wazuh/alerts');
    const d = await r.json();

    if (!d.alerts || d.alerts.length === 0) {
      list.innerHTML = '<div class="wazuh-alert-item"><span class="alert-meta">No alerts found</span></div>';
      return;
    }

    const sourceLabel = d.source === 'opensearch'
      ? '<div class="alert-source source-live">● OpenSearch — real alerts</div>'
      : '<div class="alert-source source-fallback">⚠ Fallback: manager logs (no SSH tunnel)</div>';

    list.innerHTML = sourceLabel + d.alerts.map(a => {
      const lvl = a.rule?.level || 0;
      const sev = lvl >= 12 ? 'critical' : lvl >= 8 ? 'high' : lvl >= 5 ? 'medium' : '';
      return `
      <div class="wazuh-alert-item ${sev}" onclick='fillFromAlert(${JSON.stringify(a)})'>
        <div class="alert-rule">${a.rule?.description || 'Unknown rule'}</div>
        <div class="alert-meta">${a.agent?.name || 'unknown'} • Level ${lvl} • ${(a.timestamp || '').substring(0,19)}</div>
      </div>`
    }).join('');

  } catch(e) {
    list.innerHTML = '<div class="wazuh-alert-item"><span class="alert-meta" style="color:var(--red)">Cannot connect to Wazuh</span></div>';
  }
}

function fillFromAlert(alert) {
  const ts = (alert.timestamp || '').substring(0,19).replace('T',' ');
  const srcIp = alert.data?.srcip || alert.agent?.ip || 'N/A';
  const agentName = alert.agent?.name || 'N/A';
  const rule = alert.rule?.description || 'N/A';
  const level = alert.rule?.level || 'N/A';

  document.getElementById('report-input').value =
`Alert ID: ${alert.id || 'WZ-XXXX'}
Date/Time: ${ts}
Source IP: ${srcIp}
Agent: ${agentName}
Rule triggered: ${rule}
Rule level: ${level}

## What I observed
[Describe what you saw based on this alert...]

## IOCs identified
- Source IP: ${srcIp}
- Rule: ${rule}
- Agent: ${agentName}

## My verdict
[ ] True Positive  [ ] False Positive

## Justification
[Why is this a TP or FP?]

## Recommended action
[ ] Block source IP
[ ] Escalate to Tier 2
[ ] Monitor and watch
[ ] Close - false positive`;
}

async function analyzeReport() {
  const report = document.getElementById('report-input').value;
  if (report.trim().length < 50) {
    alert('Report is too short. Please fill in the template.');
    return;
  }

  const btn = document.getElementById('analyze-btn');
  btn.disabled = true;

  document.getElementById('feedback-empty').style.display = 'none';
  document.getElementById('feedback-result').style.display = 'none';
  document.getElementById('loading').classList.add('active');
  switchTab('feedback');

  try {
    const r = await fetch('/api/validate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ report, attack_type: currentAttack, severity: currentSev })
    });
    const d = await r.json();

    document.getElementById('loading').classList.remove('active');
    document.getElementById('feedback-result').style.display = 'block';

    const scoreEl = document.getElementById('score-number');
    scoreEl.textContent = d.score;
    scoreEl.style.color = d.score >= 80 ? 'var(--green)' : d.score >= 60 ? 'var(--yellow)' : 'var(--red)';

    const isTP = d.verdict.toLowerCase().includes('true');
    document.getElementById('verdict-badge').innerHTML =
      `<span class="verdict-badge ${isTP ? 'verdict-tp' : 'verdict-fp'}">${d.verdict}</span>`;

    const confMatch = d.feedback.match(/\*\*CONFIDENCE\*\*:\s*([^\n]+)/);
    if (confMatch) {
      document.getElementById('confidence-text').textContent = `Confidence: ${confMatch[1].trim()}`;
    }

    renderFeedback(d.feedback);
    loadHistory();

  } catch(e) {
    document.getElementById('loading').classList.remove('active');
    document.getElementById('feedback-empty').style.display = 'block';
    document.getElementById('feedback-empty').innerHTML =
      '<div class="empty-icon">❌</div><div class="empty-text">Error connecting to AI</div>';
  }

  btn.disabled = false;
}

function renderFeedback(text) {
  const sections = [
    { key: 'WHAT WAS DONE WELL',          cls: 'good',    icon: '✓' },
    { key: 'WHAT IS MISSING OR INCORRECT', cls: 'bad',     icon: '⚠' },
    { key: 'HOW TO REACH 100/100',         cls: 'improve', icon: '→' },
    { key: 'RECOMMENDATION',               cls: 'rec',     icon: '💡' },
  ];

  const cleanText = text
    .replace(/\n---\n/g, '\n')
    .replace(/\r/g, '');

  let html = '';
  const keys = sections.map(s => s.key);

  sections.forEach((s, i) => {
    const startMarker = `**${s.key}**`;
    const startIdx = cleanText.indexOf(startMarker);
    if (startIdx === -1) return;

    let endIdx = cleanText.length;
    keys.forEach((k, j) => {
      if (j === i) return;
      const idx = cleanText.indexOf(`**${k}**`, startIdx + startMarker.length);
      if (idx !== -1 && idx < endIdx) endIdx = idx;
    });

    const content = cleanText
      .substring(startIdx + startMarker.length, endIdx)
      .replace(/^:\s*/, '')
      .trim();

    if (content) {
      html += `
        <div class="feedback-section ${s.cls}">
          <h4>${s.icon} ${s.key}</h4>
          <p class="feedback-raw">${content}</p>
        </div>`;
    }
  });

  document.getElementById('feedback-sections').innerHTML =
    html || `<div class="feedback-section"><pre class="feedback-raw">${cleanText}</pre></div>`;
}

async function loadHistory() {
  const r = await fetch('/api/history');
  const d = await r.json();
  const list = document.getElementById('history-list');

  if (!d.history || d.history.length === 0) {
    list.innerHTML = '<div class="empty-state"><div class="empty-icon">📋</div><div class="empty-text">No reports yet</div></div>';
    return;
  }

  list.innerHTML = d.history.map(h => {
    const isTP = (h.verdict || '').toLowerCase().includes('true');
    const scoreColor = h.score >= 80 ? 'var(--green)' : h.score >= 60 ? 'var(--yellow)' : 'var(--red)';
    return `
      <div class="history-item">
        <div class="history-header">
          <span class="history-id">${h.id}</span>
          <span class="history-score" style="color:${scoreColor}">${h.score}/100</span>
        </div>
        <div class="history-meta">
          ${(h.attack_type || '').replace(/_/g,' ')} •
          <span style="color:${isTP ? 'var(--green)' : 'var(--red)'}">${h.verdict}</span> •
          ${h.date}
        </div>
      </div>`;
  }).join('');
}

function switchTab(tab) {
  document.querySelectorAll('.tab').forEach((t, i) => {
    t.classList.toggle('active', i === (tab === 'feedback' ? 0 : 1));
  });
  document.querySelectorAll('.tab-content').forEach((c, i) => {
    c.classList.toggle('active', i === (tab === 'feedback' ? 0 : 1));
  });
  if (tab === 'history') loadHistory();
}

// Init
loadTemplate(currentAttack);
loadHistory();