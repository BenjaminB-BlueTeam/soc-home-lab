# ============================================================
#  SOC Home Lab — Setup & Launcher
#  Single entry point: install, configure, run
# ============================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# PSScriptRoot is empty when running as a compiled .exe — fall back to the exe's own directory
$ROOT = if ($PSScriptRoot) {
    $PSScriptRoot
} else {
    Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -Parent
}
$CONFIG_FILE   = "$ROOT\config.ini"
$VALIDATOR_DIR = "$ROOT\ai-validator"
$VBOX_DEFAULT  = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$WAZUH_OVA_URL = "https://documentation.wazuh.com/current/deployment-options/virtual-machine/virtual-machine.html"
$WAZUH_IP      = "192.168.56.101"

# ── Palette — Discord dark theme ─────────────────────────────
$BG       = [System.Drawing.Color]::FromArgb(49,  51,  56 )  # #313338  bg-primary
$SURFACE  = [System.Drawing.Color]::FromArgb(43,  45,  49 )  # #2B2D31  bg-secondary
$SURFACE2 = [System.Drawing.Color]::FromArgb(30,  31,  34 )  # #1E1F22  bg-tertiary / inputs
$ACCENT   = [System.Drawing.Color]::FromArgb(88,  101, 242)  # #5865F2  blurple
$GREEN    = [System.Drawing.Color]::FromArgb(35,  165, 90 )  # #23A55A
$RED      = [System.Drawing.Color]::FromArgb(242, 63,  67 )  # #F23F43
$YELLOW   = [System.Drawing.Color]::FromArgb(240, 178, 50 )  # #F0B232
$TEXT     = [System.Drawing.Color]::FromArgb(219, 222, 225)  # #DBDEE1
$MUTED    = [System.Drawing.Color]::FromArgb(128, 132, 142)  # #80848E
$SAFE     = [System.Drawing.Color]::FromArgb(181, 186, 193)  # #B5BAC1

# ── Helpers ───────────────────────────────────────────────────

function Find-Python {
    $candidates = @(
        "$env:LOCALAPPDATA\Python\bin\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "C:\Python314\python.exe",
        "C:\Python313\python.exe",
        "python"
    )
    foreach ($p in $candidates) {
        try { $v = & $p --version 2>&1; if ("$v" -match "Python 3") { return $p } } catch {}
    }
    return "python"
}

function Test-PythonInstalled { return [bool](Find-Python -ne "python" -or (& python --version 2>&1) -match "Python 3") }
function Test-VBoxInstalled   { return (Test-Path $VBOX_DEFAULT) }

function Get-VBoxVMs {
    if (-not (Test-Path $VBOX_DEFAULT)) { return @() }
    try { & $VBOX_DEFAULT list vms 2>$null | ForEach-Object { if ($_ -match '"(.+)"') { $matches[1] } } }
    catch { return @() }
}

function Find-WazuhVM { return (Get-VBoxVMs | Where-Object { $_ -match "wazuh" } | Select-Object -First 1) }
function Find-KaliVM  { return (Get-VBoxVMs | Where-Object { $_ -match "kali"  } | Select-Object -First 1) }

function Get-HostOnlyAdapter {
    $raw   = & $VBOX_DEFAULT list hostonlyifs 2>$null
    $names = $raw | Select-String "^Name:" | ForEach-Object { ($_ -split ":\s+", 2)[1].Trim() }
    if (-not $names) {
        & $VBOX_DEFAULT hostonlyif create 2>$null | Out-Null
        $raw   = & $VBOX_DEFAULT list hostonlyifs 2>$null
        $names = $raw | Select-String "^Name:" | ForEach-Object { ($_ -split ":\s+", 2)[1].Trim() }
    }
    return ($names | Select-Object -First 1)
}

function Get-BridgeAdapter {
    $raw = & $VBOX_DEFAULT list bridgedifs 2>$null
    $name = ""; $status = ""
    foreach ($line in ($raw -split "`n")) {
        if ($line -match "^Name:\s+(.+)")   { $name   = $matches[1].Trim() }
        if ($line -match "^Status:\s+(.+)") { $status = $matches[1].Trim()
            if ($status -eq "Up" -and $name) { return $name }
        }
    }
    return $name
}

function Configure-VMs($wazuhVM, $kaliVM) {
    $running  = & $VBOX_DEFAULT list runningvms 2>$null
    $hostOnly = Get-HostOnlyAdapter
    $bridge   = Get-BridgeAdapter
    if ($wazuhVM -and -not ($running -match [regex]::Escape($wazuhVM))) {
        & $VBOX_DEFAULT modifyvm $wazuhVM --graphicscontroller vmsvga 2>$null
        if ($bridge)   { & $VBOX_DEFAULT modifyvm $wazuhVM --nic1 bridged  --bridgeadapter1  $bridge   2>$null }
        if ($hostOnly) { & $VBOX_DEFAULT modifyvm $wazuhVM --nic2 hostonly --hostonlyadapter2 $hostOnly 2>$null }
    }
    if ($kaliVM -and -not ($running -match [regex]::Escape($kaliVM))) {
        if ($hostOnly) { & $VBOX_DEFAULT modifyvm $kaliVM --nic1 hostonly --hostonlyadapter1 $hostOnly 2>$null }
        & $VBOX_DEFAULT modifyvm $kaliVM --nic2 nat 2>$null
    }
}

function Test-WazuhReady {
    try { $t = New-Object System.Net.Sockets.TcpClient; $t.Connect($WAZUH_IP, 55000); $t.Close() } catch { return $false }
    try { $t = New-Object System.Net.Sockets.TcpClient; $t.Connect($WAZUH_IP, 9200);  $t.Close() } catch { return $false }
    return $true
}

function Read-Config {
    $cfg = @{}
    if (Test-Path $CONFIG_FILE) {
        Get-Content $CONFIG_FILE | ForEach-Object {
            if ($_ -match "^\s*([^#;=]+?)\s*=\s*(.*)$") { $cfg[$matches[1].Trim()] = $matches[2].Trim() }
        }
    }
    return $cfg
}

function Get-X11Layout {
    # Map Windows culture tag to X11 keyboard layout code
    $overrides = @{
        "pt-BR"="br";  "en-GB"="gb";  "fr-CH"="ch(fr)"; "de-CH"="ch"
        "de-AT"="de";  "fr-BE"="be";  "nl-BE"="be";      "es-MX"="latam"
        "es-AR"="latam"; "es-CO"="latam"; "es-CL"="latam"
    }
    $langMap = @{
        "fr"="fr"; "de"="de"; "es"="es"; "it"="it"; "pt"="pt"; "nl"="nl"
        "pl"="pl"; "ru"="ru"; "cs"="cz"; "sk"="sk"; "hu"="hu"; "ro"="ro"
        "bg"="bg"; "el"="gr"; "tr"="tr"; "ar"="ara"; "he"="il"; "ja"="jp"
        "ko"="kr"; "zh"="cn"; "uk"="ua"; "sv"="se"; "da"="dk"; "nb"="no"
        "fi"="fi"; "et"="ee"; "lv"="lv"; "lt"="lt"; "sl"="si"; "hr"="hr"
        "sr"="rs"; "mk"="mk"; "sq"="sq"; "is"="is"; "th"="th"
    }
    try {
        $tag  = (Get-Culture).Name
        $lang = $tag.Split("-")[0].ToLower()
        if ($overrides.ContainsKey($tag))  { return $overrides[$tag] }
        if ($langMap.ContainsKey($lang))   { return $langMap[$lang]  }
    } catch {}
    return "us"
}

function Get-BrowserUserAgent {
    try {
        $progId = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice").ProgId
        if ($progId -match "Chrome")  { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" }
        if ($progId -match "Firefox") { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0" }
        if ($progId -match "Edge")    { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0" }
    } catch {}
    return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
}

function Get-KaliIP($kaliVM) {
    try {
        $props = & $VBOX_DEFAULT guestproperty enumerate $kaliVM 2>$null
        foreach ($line in ($props -split "`n")) {
            if ($line -match "Net/\d+/V4/IP\s.*=\s+'(192\.168\.56\.\d+)'") { return $matches[1] }
        }
    } catch {}
    return "192.168.56.102"
}

function Get-WazuhIP($wazuhVM) {
    try {
        $props = & $VBOX_DEFAULT guestproperty enumerate $wazuhVM 2>$null
        foreach ($line in ($props -split "`n")) {
            if ($line -match "Net/\d+/V4/IP\s.*=\s+'(192\.168\.56\.\d+)'") { return $matches[1] }
        }
    } catch {}
    return $WAZUH_IP   # fall back to current value
}

$script:pForm  = $null
$script:pBar   = $null
$script:pMsg   = $null
$script:pDet   = $null
$script:pPct   = $null
$script:pTrack = $null

function Show-InstallChecklist($choices) {
    $STEP_H = 58; $STEP_X = 16; $STEP_W = 560

    $steps = [System.Collections.ArrayList]@()
    $steps.Add("python")    | Out-Null
    $steps.Add("vbox")      | Out-Null
    $steps.Add("pip")       | Out-Null
    if ($choices.installWazuh)  { $steps.Add("wazuh")     | Out-Null }
    if ($choices.installKali)   { $steps.Add("kali")      | Out-Null }
    if ($choices.installWazuh -or $choices.installKali) { $steps.Add("configure") | Out-Null }
    $steps.Add("save") | Out-Null

    $stepNames = @{
        python    = "Python 3"
        vbox      = "VirtualBox"
        pip       = "Python packages"
        wazuh     = "Wazuh SIEM"
        kali      = "Kali Linux"
        configure = "Configure VMs"
        save      = "Save configuration"
    }

    $formH = 68 + ($steps.Count * ($STEP_H + 8)) + 30
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "SOC Home Lab"; $form.Size = New-Object System.Drawing.Size(596, $formH)
    $form.StartPosition = "CenterScreen"; $form.BackColor = $BG; $form.ForeColor = $TEXT
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.FormBorderStyle = "FixedSingle"; $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $form.Add_FormClosing({ [System.Environment]::Exit(0) })

    $hdr = New-Object System.Windows.Forms.Panel
    $hdr.BackColor = $SURFACE; $hdr.Location = New-Object System.Drawing.Point(0,0)
    $hdr.Size = New-Object System.Drawing.Size(596, 52); $form.Controls.Add($hdr)
    $hIco = New-Object System.Windows.Forms.Panel
    $hIco.BackColor = $ACCENT; $hIco.Location = New-Object System.Drawing.Point(16,16); $hIco.Size = New-Object System.Drawing.Size(20,20); $hdr.Controls.Add($hIco)
    $hLbl = New-Object System.Windows.Forms.Label
    $hLbl.Text = "SOC Home Lab  —  Setup"; $hLbl.Font = New-Object System.Drawing.Font("Segoe UI",10,[System.Drawing.FontStyle]::Bold)
    $hLbl.ForeColor = $TEXT; $hLbl.Location = New-Object System.Drawing.Point(44,15); $hLbl.Size = New-Object System.Drawing.Size(460,24); $hdr.Controls.Add($hLbl)

    $stepControls = @{}
    $yOff = 60
    foreach ($key in $steps) {
        $p = New-Object System.Windows.Forms.Panel
        $p.BackColor = $SURFACE; $p.Location = New-Object System.Drawing.Point($STEP_X,$yOff); $p.Size = New-Object System.Drawing.Size($STEP_W,$STEP_H)

        $ico = New-Object System.Windows.Forms.Label
        $ico.Text = "○"; $ico.ForeColor = $MUTED
        $ico.Font = New-Object System.Drawing.Font("Segoe UI",12,[System.Drawing.FontStyle]::Bold)
        $ico.Location = New-Object System.Drawing.Point(12,17); $ico.Size = New-Object System.Drawing.Size(22,22); $p.Controls.Add($ico)

        $nm = New-Object System.Windows.Forms.Label
        $nm.Text = $stepNames[$key]; $nm.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
        $nm.ForeColor = $TEXT; $nm.Location = New-Object System.Drawing.Point(42,10); $nm.Size = New-Object System.Drawing.Size(185,18); $p.Controls.Add($nm)

        $st = New-Object System.Windows.Forms.Label
        $st.Text = "Waiting..."; $st.ForeColor = $MUTED; $st.Font = New-Object System.Drawing.Font("Segoe UI",8)
        $st.Location = New-Object System.Drawing.Point(42,30); $st.Size = New-Object System.Drawing.Size(190,16); $p.Controls.Add($st)

        $ob = New-Object System.Windows.Forms.Button
        $ob.Text = "Open download page"; $ob.BackColor = $ACCENT; $ob.ForeColor = [System.Drawing.Color]::White
        $ob.FlatStyle = "Flat"; $ob.FlatAppearance.BorderSize = 0; $ob.UseVisualStyleBackColor = $false
        $ob.Font = New-Object System.Drawing.Font("Segoe UI",8)
        $ob.Location = New-Object System.Drawing.Point(238,15); $ob.Size = New-Object System.Drawing.Size(160,26); $ob.Visible = $false; $p.Controls.Add($ob)

        $db = New-Object System.Windows.Forms.Button
        $db.Text = "Done  ✓"; $db.BackColor = $GREEN; $db.ForeColor = [System.Drawing.Color]::White
        $db.FlatStyle = "Flat"; $db.FlatAppearance.BorderSize = 0; $db.UseVisualStyleBackColor = $false
        $db.Font = New-Object System.Drawing.Font("Segoe UI",8,[System.Drawing.FontStyle]::Bold)
        $db.Location = New-Object System.Drawing.Point(406,15); $db.Size = New-Object System.Drawing.Size(86,26); $db.Visible = $false; $db.Enabled = $false; $p.Controls.Add($db)

        $form.Controls.Add($p)
        $stepControls[$key] = @{ icon=$ico; status=$st; openBtn=$ob; doneBtn=$db }
        $yOff += $STEP_H + 8
    }

    $progTrack = New-Object System.Windows.Forms.Panel
    $progTrack.BackColor = $SURFACE2; $progTrack.Location = New-Object System.Drawing.Point($STEP_X,($yOff+6)); $progTrack.Size = New-Object System.Drawing.Size($STEP_W,4)
    $form.Controls.Add($progTrack)
    $progBar = New-Object System.Windows.Forms.Panel
    $progBar.BackColor = $ACCENT; $progBar.Location = New-Object System.Drawing.Point($STEP_X,($yOff+6)); $progBar.Size = New-Object System.Drawing.Size(0,4)
    $form.Controls.Add($progBar)

    function Step-Running($k,$msg) {
        $stepControls[$k].icon.Text = "↻"; $stepControls[$k].icon.ForeColor = $YELLOW
        $stepControls[$k].status.Text = $msg; $stepControls[$k].status.ForeColor = $YELLOW
        [System.Windows.Forms.Application]::DoEvents()
    }
    function Step-Done($k,$msg) {
        $stepControls[$k].icon.Text = "✔"; $stepControls[$k].icon.ForeColor = $GREEN
        $stepControls[$k].status.Text = $msg; $stepControls[$k].status.ForeColor = $GREEN
        $stepControls[$k].openBtn.Visible = $false; $stepControls[$k].doneBtn.Visible = $false
        [System.Windows.Forms.Application]::DoEvents()
    }
    function Install-ViaWinget($id) {
        Start-Process winget -ArgumentList "install --id $id --silent --disable-interactivity --accept-package-agreements --accept-source-agreements" -WindowStyle Hidden -Wait
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }
    function Step-Manual($k,$url) {
        $stepControls[$k].icon.Text = "→"; $stepControls[$k].icon.ForeColor = $ACCENT
        $stepControls[$k].status.Text = "Download & import, then click Done →"
        $stepControls[$k].status.ForeColor = $TEXT
        $stepControls[$k].openBtn.Visible = $true; $stepControls[$k].openBtn.Enabled = $true
        $stepControls[$k].doneBtn.Visible = $true
        $capturedUrl = $url; $capturedBtn = $stepControls[$k].doneBtn
        $stepControls[$k].openBtn.Add_Click({ Start-Process $capturedUrl; $capturedBtn.Enabled = $true })
        [System.Windows.Forms.Application]::DoEvents()
    }
    function Prog($n,$t) { $progBar.Width = [int]($STEP_W * $n / $t); [System.Windows.Forms.Application]::DoEvents() }

    $form.Show(); [System.Windows.Forms.Application]::DoEvents()
    $done = 0; $total = $steps.Count

    if ($choices.installPython) {
        Step-Running "python" "Installing via winget..."
        Install-ViaWinget "Python.Python.3.13"
        $choices.pythonPath = Find-Python; Step-Done "python" "Python 3 installed"
    } else { Step-Done "python" "Already installed" }
    $done++; Prog $done $total

    if ($choices.installVBox) {
        Step-Running "vbox" "Installing via winget..."
        Install-ViaWinget "Oracle.VirtualBox"
        Step-Done "vbox" "VirtualBox installed"
    } else { Step-Done "vbox" "Already installed" }
    $done++; Prog $done $total

    Step-Running "pip" "Installing flask, anthropic, openai, paramiko..."
    Set-Location $VALIDATOR_DIR
    & $PYTHON -c "import flask, anthropic, openai, paramiko" 2>$null
    if ($LASTEXITCODE -ne 0) { & $PYTHON -m pip install -r requirements.txt --quiet 2>$null }
    $done++; Prog $done $total; Step-Done "pip" "All packages ready"

    if ($choices.installWazuh) {
        Step-Manual "wazuh" $WAZUH_OVA_URL
        $script:_wazuhDone = $false
        $stepControls["wazuh"].doneBtn.Add_Click({ $script:_wazuhDone = $true })
        while (-not $script:_wazuhDone) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
        $choices.wazuhVM = Find-WazuhVM; $done++; Prog $done $total; Step-Done "wazuh" "Wazuh VM imported"
    }

    if ($choices.installKali) {
        Step-Manual "kali" "https://www.kali.org/get-kali/#kali-virtual-machines"
        $script:_kaliDone = $false
        $stepControls["kali"].doneBtn.Add_Click({ $script:_kaliDone = $true })
        while (-not $script:_kaliDone) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
        $choices.kaliVM = Find-KaliVM; $done++; Prog $done $total; Step-Done "kali" "Kali VM imported"
    }

    if ($choices.installWazuh -or $choices.installKali) {
        Step-Running "configure" "Configuring network adapters and VMSVGA..."
        if ($choices.wazuhVM -or $choices.kaliVM) { Configure-VMs $choices.wazuhVM $choices.kaliVM }
        $done++; Prog $done $total; Step-Done "configure" "VMs configured"
    }

    Step-Running "save" "Writing .env and config.ini..."
    @(
        "AI_PROVIDER=$($choices.provider)",
        "ANTHROPIC_API_KEY=$(if ($choices.provider -eq 'claude') { $choices.apiKey } else { '' })",
        "OPENAI_API_KEY=$(if ($choices.provider -eq 'openai') { $choices.apiKey } else { '' })",
        "WAZUH_HOST=$WAZUH_IP", "WAZUH_PORT=55000", "WAZUH_USER=wazuh", "WAZUH_PASSWORD=wazuh",
        "WAZUH_SSH_USER=wazuh-user", "WAZUH_SSH_PASSWORD=wazuh",
        "WAZUH_INDEXER_USER=admin", "WAZUH_INDEXER_PASSWORD=WazuhLab123*"
    ) | Set-Content "$VALIDATOR_DIR\.env" -Encoding UTF8
    @(
        "[VMs]", "wazuh_vm_name=$($choices.wazuhVM)", "kali_vm_name=$($choices.kaliVM)", "",
        "[Network]", "wazuh_ip=$WAZUH_IP", "", "[API]", "ai_provider=$($choices.provider)", "",
        "[Paths]", "vboxmanage=$VBOX_DEFAULT"
    ) | Set-Content $CONFIG_FILE -Encoding UTF8
    $done++; Prog $done $total; Step-Done "save" "Configuration saved"

    Start-Sleep 1; $form.Close()
    return $choices
}

function Init-ProgressForm {
    $script:pForm = New-Object System.Windows.Forms.Form
    $script:pForm.Text            = "SOC Home Lab"
    $script:pForm.Size            = New-Object System.Drawing.Size(500, 170)
    $script:pForm.StartPosition   = "CenterScreen"
    $script:pForm.BackColor       = $BG
    $script:pForm.ForeColor       = $TEXT
    $script:pForm.Font            = New-Object System.Drawing.Font("Segoe UI", 9)
    $script:pForm.FormBorderStyle = "FixedSingle"
    $script:pForm.MaximizeBox     = $false
    $script:pForm.MinimizeBox     = $false
    $script:pForm.ControlBox      = $true
    $script:pForm.TopMost         = $true
    $script:pForm.Add_FormClosing({ [System.Environment]::Exit(0) })

    # Header strip
    $hdr = New-Object System.Windows.Forms.Panel
    $hdr.BackColor = $SURFACE
    $hdr.Location  = New-Object System.Drawing.Point(0, 0)
    $hdr.Size      = New-Object System.Drawing.Size(500, 46)
    $script:pForm.Controls.Add($hdr)

    $ico = New-Object System.Windows.Forms.Panel
    $ico.BackColor = $ACCENT
    $ico.Location  = New-Object System.Drawing.Point(16, 13); $ico.Size = New-Object System.Drawing.Size(20, 20)
    $hdr.Controls.Add($ico)

    $ttl = New-Object System.Windows.Forms.Label
    $ttl.Text      = "SOC Home Lab"
    $ttl.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $ttl.ForeColor = $TEXT
    $ttl.Location  = New-Object System.Drawing.Point(48, 14); $ttl.Size = New-Object System.Drawing.Size(420, 22)
    $hdr.Controls.Add($ttl)

    # Message
    $script:pMsg = New-Object System.Windows.Forms.Label
    $script:pMsg.Location  = New-Object System.Drawing.Point(20, 60)
    $script:pMsg.Size      = New-Object System.Drawing.Size(460, 20)
    $script:pMsg.ForeColor = $TEXT
    $script:pMsg.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $script:pForm.Controls.Add($script:pMsg)

    # Detail
    $script:pDet = New-Object System.Windows.Forms.Label
    $script:pDet.Location  = New-Object System.Drawing.Point(20, 82)
    $script:pDet.Size      = New-Object System.Drawing.Size(420, 16)
    $script:pDet.ForeColor = $MUTED
    $script:pDet.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
    $script:pForm.Controls.Add($script:pDet)

    # Percentage
    $script:pPct = New-Object System.Windows.Forms.Label
    $script:pPct.Location   = New-Object System.Drawing.Point(448, 82)
    $script:pPct.Size       = New-Object System.Drawing.Size(36, 16)
    $script:pPct.ForeColor  = $MUTED
    $script:pPct.Font       = New-Object System.Drawing.Font("Segoe UI", 8)
    $script:pPct.TextAlign  = "MiddleRight"
    $script:pForm.Controls.Add($script:pPct)

    # Progress track (background)
    $script:pTrack = New-Object System.Windows.Forms.Panel
    $script:pTrack.BackColor = $SURFACE2
    $script:pTrack.Location  = New-Object System.Drawing.Point(20, 116)
    $script:pTrack.Size      = New-Object System.Drawing.Size(460, 4)
    $script:pForm.Controls.Add($script:pTrack)

    # Progress fill (blurple)
    $script:pBar = New-Object System.Windows.Forms.Panel
    $script:pBar.BackColor = $ACCENT
    $script:pBar.Location  = New-Object System.Drawing.Point(20, 116)
    $script:pBar.Size      = New-Object System.Drawing.Size(0, 4)
    $script:pForm.Controls.Add($script:pBar)

    $script:pForm.Show()
    [System.Windows.Forms.Application]::DoEvents()
}

function Show-Progress($pct, $msg, $detail = "") {
    if ($null -eq $script:pForm -or $script:pForm.IsDisposed) { Init-ProgressForm }
    $script:pMsg.Text  = $msg
    $script:pDet.Text  = $detail
    $script:pPct.Text  = "$pct%"
    $script:pBar.Width = [int](460 * [math]::Min($pct, 100) / 100)
    [System.Windows.Forms.Application]::DoEvents()
}

# ── Setup Wizard ──────────────────────────────────────────────

function Show-Wizard {
    param([hashtable]$defaults = @{})

    $hasPython = Test-PythonInstalled
    $hasVBox   = Test-VBoxInstalled
    $wazuhVM   = if ($hasVBox) { Find-WazuhVM } else { $null }
    $kaliVM    = if ($hasVBox) { Find-KaliVM  } else { $null }

    # ── Form
    $form = New-Object System.Windows.Forms.Form
    $form.Text            = "SOC Home Lab"
    $form.Size            = New-Object System.Drawing.Size(580, 660)
    $form.StartPosition   = "CenterScreen"
    $form.BackColor       = $BG
    $form.ForeColor       = $TEXT
    $form.Font            = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox     = $false

    # Title
    $icoW = New-Object System.Windows.Forms.Panel
    $icoW.BackColor = $ACCENT
    $icoW.Location  = New-Object System.Drawing.Point(24, 22); $icoW.Size = New-Object System.Drawing.Size(24, 24)
    $form.Controls.Add($icoW)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "SOC Home Lab"; $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = $ACCENT; $lbl.Location = New-Object System.Drawing.Point(56, 18); $lbl.Size = New-Object System.Drawing.Size(490, 34)
    $form.Controls.Add($lbl)
    $sub = New-Object System.Windows.Forms.Label
    $sub.Text = "Cybersecurity training environment — automatic setup & launcher"
    $sub.ForeColor = $MUTED; $sub.Location = New-Object System.Drawing.Point(26, 54); $sub.Size = New-Object System.Drawing.Size(520, 18)
    $form.Controls.Add($sub)

    function Sep($y) {
        $s = New-Object System.Windows.Forms.Label; $s.BorderStyle = "Fixed3D"
        $s.Location = New-Object System.Drawing.Point(24, $y); $s.Size = New-Object System.Drawing.Size(520, 2); $form.Controls.Add($s)
    }
    function Title($text, $y) {
        $l = New-Object System.Windows.Forms.Label; $l.Text = $text
        $l.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
        $l.ForeColor = $ACCENT; $l.Location = New-Object System.Drawing.Point(24, $y); $l.Size = New-Object System.Drawing.Size(520, 18); $form.Controls.Add($l)
    }

    # Status row (icon + label + status + install checkbox)
    function StatusRow($label, $ok, $installText, $y) {
        $ico = New-Object System.Windows.Forms.Label
        $ico.Text = if ($ok) { "✓" } else { "✗" }; $ico.ForeColor = if ($ok) { $GREEN } else { $RED }
        $ico.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $ico.Location = New-Object System.Drawing.Point(24, $y); $ico.Size = New-Object System.Drawing.Size(20, 22); $form.Controls.Add($ico)
        $lv = New-Object System.Windows.Forms.Label; $lv.Text = $label; $lv.ForeColor = $TEXT
        $lv.Location = New-Object System.Drawing.Point(48, ($y + 2)); $lv.Size = New-Object System.Drawing.Size(190, 18); $form.Controls.Add($lv)
        $st = New-Object System.Windows.Forms.Label
        $st.Text = if ($ok) { "Detected" } else { "Not found" }; $st.ForeColor = if ($ok) { $GREEN } else { $YELLOW }
        $st.Location = New-Object System.Drawing.Point(250, ($y + 2)); $st.Size = New-Object System.Drawing.Size(80, 18); $form.Controls.Add($st)
        $chk = New-Object System.Windows.Forms.CheckBox
        $chk.Text = $installText; $chk.ForeColor = if (-not $ok) { $YELLOW } else { $MUTED }; $chk.BackColor = $BG
        $chk.Location = New-Object System.Drawing.Point(48, ($y + 22)); $chk.Size = New-Object System.Drawing.Size(470, 20)
        $chk.Checked = -not $ok; $chk.Enabled = -not $ok; $form.Controls.Add($chk)
        return $chk
    }

    Sep 74
    Title "SYSTEM CHECK" 84
    $chkPython = StatusRow "Python 3"   $hasPython "Install Python automatically via winget"            106
    $chkVBox   = StatusRow "VirtualBox" $hasVBox   "Install VirtualBox automatically via winget"        150
    $chkWazuh  = StatusRow "Wazuh SIEM" ([bool]$wazuhVM) "Open Wazuh download page (OVA ~3.5 GB)"       194
    $chkKali   = StatusRow "Kali Linux" ([bool]$kaliVM)  "Open Kali download page (VirtualBox image)"   238
    Sep 284

    # ── AI Provider
    Title "AI PROVIDER" 294
    $provLbl = New-Object System.Windows.Forms.Label
    $provLbl.Text = "Select the AI model used to analyse your SOC reports:"
    $provLbl.ForeColor = $MUTED; $provLbl.Location = New-Object System.Drawing.Point(24, 314); $provLbl.Size = New-Object System.Drawing.Size(520, 18)
    $form.Controls.Add($provLbl)

    $rClaude = New-Object System.Windows.Forms.RadioButton
    $rClaude.Text = "Claude (Anthropic)  —  claude-sonnet-4-6"
    $rClaude.ForeColor = $TEXT; $rClaude.BackColor = $BG; $rClaude.Checked = $true
    $rClaude.Location = New-Object System.Drawing.Point(44, 336); $rClaude.Size = New-Object System.Drawing.Size(280, 22); $form.Controls.Add($rClaude)

    $rOpenAI = New-Object System.Windows.Forms.RadioButton
    $rOpenAI.Text = "OpenAI  —  gpt-4o"
    $rOpenAI.ForeColor = $TEXT; $rOpenAI.BackColor = $BG
    $rOpenAI.Location = New-Object System.Drawing.Point(340, 336); $rOpenAI.Size = New-Object System.Drawing.Size(200, 22); $form.Controls.Add($rOpenAI)

    # API Key
    $keyLbl = New-Object System.Windows.Forms.Label
    $keyLbl.Text = "API Key:"; $keyLbl.ForeColor = $TEXT
    $keyLbl.Location = New-Object System.Drawing.Point(24, 368); $keyLbl.Size = New-Object System.Drawing.Size(60, 18); $form.Controls.Add($keyLbl)

    $txtKey = New-Object System.Windows.Forms.TextBox
    $txtKey.Location = New-Object System.Drawing.Point(24, 388); $txtKey.Size = New-Object System.Drawing.Size(520, 26)
    $txtKey.BackColor = $SURFACE2; $txtKey.ForeColor = $TEXT; $txtKey.BorderStyle = "FixedSingle"
    $txtKey.PasswordChar = "●"
    $form.Controls.Add($txtKey)

    # Pre-fill from existing .env
    if (Test-Path "$VALIDATOR_DIR\.env") {
        $lines = Get-Content "$VALIDATOR_DIR\.env"
        $prov  = ($lines | Select-String "^AI_PROVIDER=(.+)"      | Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value })
        $cKey  = ($lines | Select-String "^ANTHROPIC_API_KEY=(.+)" | Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value })
        $oKey  = ($lines | Select-String "^OPENAI_API_KEY=(.+)"    | Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value })
        if ($prov -eq "openai") { $rOpenAI.Checked = $true; $rClaude.Checked = $false }
        if ($cKey -and $rClaude.Checked) { $txtKey.Text = $cKey }
        if ($oKey -and $rOpenAI.Checked) { $txtKey.Text = $oKey }
    }


    # Links
    $lnkClaude = New-Object System.Windows.Forms.LinkLabel
    $lnkClaude.Text = "Get a Claude key →"; $lnkClaude.ForeColor = $ACCENT; $lnkClaude.LinkColor = $ACCENT
    $lnkClaude.Location = New-Object System.Drawing.Point(24, 420); $lnkClaude.Size = New-Object System.Drawing.Size(160, 18)
    $lnkClaude.Add_LinkClicked({ Start-Process "https://console.anthropic.com" }); $form.Controls.Add($lnkClaude)

    $lnkOAI = New-Object System.Windows.Forms.LinkLabel
    $lnkOAI.Text = "Get an OpenAI key →"; $lnkOAI.ForeColor = $ACCENT; $lnkOAI.LinkColor = $ACCENT
    $lnkOAI.Location = New-Object System.Drawing.Point(200, 420); $lnkOAI.Size = New-Object System.Drawing.Size(180, 18)
    $lnkOAI.Add_LinkClicked({ Start-Process "https://platform.openai.com/api-keys" }); $form.Controls.Add($lnkOAI)

    # Privacy notice
    $notice = New-Object System.Windows.Forms.Label
    $notice.Text = "[secured]  Your API key is saved only in the local .env file on this machine. It is never shared externally."
    $notice.ForeColor = $SAFE; $notice.Location = New-Object System.Drawing.Point(24, 446); $notice.Size = New-Object System.Drawing.Size(520, 18)
    $form.Controls.Add($notice)

    Sep 472

    # Status + button
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.ForeColor = $RED; $lblStatus.BackColor = $BG; $lblStatus.Location = New-Object System.Drawing.Point(24, 528); $lblStatus.Size = New-Object System.Drawing.Size(520, 18)
    $form.Controls.Add($lblStatus)

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = "Setup && Launch  →"; $btn.BackColor = $ACCENT
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.FlatStyle = "Flat"; $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btn.FlatAppearance.BorderSize = 0; $btn.UseVisualStyleBackColor = $false
    $btn.Location = New-Object System.Drawing.Point(24, 484); $btn.Size = New-Object System.Drawing.Size(520, 36)
    $btn.Add_Click({
        if ($txtKey.Text.Trim().Length -lt 10) { $lblStatus.Text = "Please enter a valid API key."; return }
        $form.DialogResult = "OK"; $form.Close()
    })
    $form.Controls.Add($btn); $form.AcceptButton = $btn

    if ($form.ShowDialog() -ne "OK") { exit 0 }

    return @{
        installPython = $chkPython.Checked
        installVBox   = $chkVBox.Checked
        installWazuh  = $chkWazuh.Checked
        installKali   = $chkKali.Checked
        provider      = if ($rClaude.Checked) { "claude" } else { "openai" }
        apiKey        = $txtKey.Text.Trim()
        wazuhVM       = if ($wazuhVM) { $wazuhVM } else { "" }
        kaliVM        = if ($kaliVM)  { $kaliVM  } else { "" }
    }
}

# ── Main ──────────────────────────────────────────────────────

$choices = Show-Wizard

$PYTHON   = Find-Python
$choices  = Show-InstallChecklist $choices
if ($choices.pythonPath) { $PYTHON = $choices.pythonPath }

$cfg      = Read-Config
$WAZUH_VM = $cfg.wazuh_vm_name
$KALI_VM  = $cfg.kali_vm_name

# ── LAUNCH ────────────────────────────────────────────────────

$running      = & $VBOX_DEFAULT list runningvms 2>$null
$wazuhRunning = [bool]($WAZUH_VM -and ($running -match [regex]::Escape($WAZUH_VM)))
$kaliRunning  = [bool]($KALI_VM  -and ($running -match [regex]::Escape($KALI_VM)))

# Start Wazuh
if ($WAZUH_VM) {
    if ($wazuhRunning) {
        Show-Progress 62 "Wazuh already running — skipping boot..." "Checking API health"
    } else {
        Show-Progress 62 "Starting Wazuh SIEM (headless)..." "Launching VM"
        & $VBOX_DEFAULT startvm $WAZUH_VM --type headless 2>$null
        $bootTime = 90
        for ($i = 1; $i -le $bootTime; $i++) {
            $pct = 62 + [math]::Round(14 * $i / $bootTime)
            Show-Progress $pct "Wazuh booting... ($i/$bootTime s)" "Starting indexer, manager and dashboard"
            Start-Sleep 1
        }
    }

    # Resolve Wazuh's actual IP via VBoxManage guestproperty (handles DHCP changes)
    $detectedIP = Get-WazuhIP $WAZUH_VM
    if ($detectedIP -ne $WAZUH_IP) {
        $WAZUH_IP = $detectedIP
        (Get-Content "$VALIDATOR_DIR\.env") -replace "^WAZUH_HOST=.*", "WAZUH_HOST=$WAZUH_IP" |
            Set-Content "$VALIDATOR_DIR\.env" -Encoding UTF8
        (Get-Content $CONFIG_FILE) -replace "^wazuh_ip=.*", "wazuh_ip=$WAZUH_IP" |
            Set-Content $CONFIG_FILE -Encoding UTF8
    }

    # Poll until both API (55000) and OpenSearch (9200) are ready — up to 3 min
    Show-Progress 78 "Waiting for Wazuh services..." "API :55000 + OpenSearch :9200"
    for ($t = 0; $t -lt 180; $t += 5) {
        if (Test-WazuhReady) { break }
        $pct = [int](78 + ($t / 180) * 2)
        Show-Progress $pct "Waiting for Wazuh services... ($t/180 s)" "API + OpenSearch starting"
        Start-Sleep 5
    }

    # Auto-repair if still not ready
    if (-not (Test-WazuhReady)) {
        Show-Progress 80 "Wazuh API not responding — attempting repair..." "Restarting services via SSH"
        $repairScript = @"
import paramiko, sys
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
try:
    client.connect('$WAZUH_IP', username='wazuh-user', password='wazuh', timeout=10)
    _, out, _ = client.exec_command('sudo systemctl is-active wazuh-manager 2>&1')
    if out.read().decode().strip() != 'active':
        client.exec_command('sudo systemctl restart wazuh-manager wazuh-indexer 2>&1')
        print('RESTARTED')
    else:
        print('OK')
    client.close()
except Exception as e:
    print(f'SKIP: {e}')
"@
        $tmp = [System.IO.Path]::GetTempFileName() + ".py"
        $repairScript | Set-Content $tmp -Encoding UTF8
        $repairResult = & $PYTHON $tmp 2>&1
        Remove-Item $tmp -ErrorAction SilentlyContinue

        if ("$repairResult" -match "RESTARTED") {
            for ($t = 0; $t -lt 60; $t += 5) {
                Show-Progress 82 "Services restarted — waiting for API... ($t/60 s)" ""
                if (Test-WazuhReady) { break }
                Start-Sleep 5
            }
        }
    }
} else {
    Show-Progress 78 "No Wazuh VM configured — skipping..." "Use the wizard to download and import Wazuh"
}

$wazuhOK = if ($WAZUH_VM) { Test-WazuhReady } else { $false }

# Start Kali
if ($KALI_VM) {
    if ($kaliRunning) {
        Show-Progress 88 "Kali Linux already running — skipping..." ""
    } else {
        Show-Progress 88 "Starting Kali Linux..." "GUI mode"
        & $VBOX_DEFAULT startvm $KALI_VM --type gui 2>$null
        Start-Sleep 5
    }
} else {
    Show-Progress 88 "No Kali VM configured — skipping..." ""
}

# Configure Kali — keyboard layout + SSH auto-start
$x11Layout = Get-X11Layout
$KALI_IP   = Get-KaliIP $KALI_VM
Show-Progress 90 "Configuring Kali (keyboard: $x11Layout)..." "Waiting for SSH on $KALI_IP"
$kaliScript = @"
import paramiko, socket, time, sys

def wait_ssh(host, timeout=40):
    for _ in range(timeout):
        try:
            s = socket.socket(); s.settimeout(1); s.connect((host, 22)); s.close(); return True
        except: time.sleep(1)
    return False

host = '$KALI_IP'
if not wait_ssh(host):
    print('NO_SSH'); sys.exit(0)

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
try:
    c.connect(host, username='kali', password='kali', timeout=8)
    for cmd in [
        'sudo localectl set-x11-keymap $x11Layout',
        'sudo localectl set-keymap $x11Layout',
        'sudo systemctl enable ssh',
    ]:
        _, o, e = c.exec_command(cmd, timeout=10)
        o.read(); e.read()
    c.close()
    print('CONFIGURED')
except Exception as ex:
    print(f'ERROR: {ex}')
"@
$tmpK = [System.IO.Path]::GetTempFileName() + ".py"
$kaliScript | Set-Content $tmpK -Encoding UTF8
$kaliResult = & $PYTHON $tmpK 2>&1
Remove-Item $tmpK -ErrorAction SilentlyContinue

if ("$kaliResult" -match "CONFIGURED") {
    Show-Progress 92 "Kali configured — keyboard: $x11Layout, SSH enabled at boot" ""
} else {
    Show-Progress 92 "Kali SSH not available — keyboard not configured" "Open Kali terminal and run: sudo systemctl start ssh"
}

# Start AI Validator
Show-Progress 93 "Starting AI Validator..." "Flask on port 5000"
Set-Location $VALIDATOR_DIR
Start-Process -FilePath $PYTHON -ArgumentList "app.py" -WindowStyle Minimized
for ($i = 1; $i -le 6; $i++) {
    Show-Progress (93 + $i) "AI Validator starting... ($i/6 s)" "Initializing Flask"
    Start-Sleep 1
}

# Open two browser tabs
Show-Progress 99 "Opening browser tabs..." "Wazuh dashboard + AI Validator"
Start-Process "https://$WAZUH_IP"
Start-Sleep 2
Start-Process "http://localhost:5000"
Start-Sleep 1

# ── Done — close progress, show ready dialog ──────────────────
if ($script:pForm -and -not $script:pForm.IsDisposed) { $script:pForm.Close() }

$wazuhOK = Test-WazuhReady   # fresh check after all startup steps

$readyForm = New-Object System.Windows.Forms.Form
$readyForm.Text            = "SOC Home Lab — Ready"
$readyForm.Size            = New-Object System.Drawing.Size(480, 280)
$readyForm.StartPosition   = "CenterScreen"
$readyForm.BackColor       = $BG
$readyForm.ForeColor       = $TEXT
$readyForm.Font            = New-Object System.Drawing.Font("Segoe UI", 9)
$readyForm.FormBorderStyle = "FixedSingle"
$readyForm.MaximizeBox     = $false
$readyForm.TopMost         = $true

# Header
$rHdr = New-Object System.Windows.Forms.Panel
$rHdr.BackColor = $SURFACE; $rHdr.Location = New-Object System.Drawing.Point(0, 0); $rHdr.Size = New-Object System.Drawing.Size(480, 52)
$readyForm.Controls.Add($rHdr)

$rIco = New-Object System.Windows.Forms.Panel
$rIco.BackColor = $ACCENT
$rIco.Location  = New-Object System.Drawing.Point(16, 15); $rIco.Size = New-Object System.Drawing.Size(22, 22)
$rHdr.Controls.Add($rIco)

$rTitle = New-Object System.Windows.Forms.Label
$rTitle.Text = "SOC Home Lab — Ready"; $rTitle.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$rTitle.ForeColor = $GREEN; $rTitle.Location = New-Object System.Drawing.Point(52, 16); $rTitle.Size = New-Object System.Drawing.Size(400, 24)
$rHdr.Controls.Add($rTitle)

# Status rows
$y = 68

# Wazuh row — keep named refs so the Recheck button can update them
$wazuhDot = New-Object System.Windows.Forms.Label
$wazuhDot.Text = "●"; $wazuhDot.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$wazuhDot.ForeColor = if ($wazuhOK) { $GREEN } else { $YELLOW }
$wazuhDot.Location = New-Object System.Drawing.Point(20, $y); $wazuhDot.Size = New-Object System.Drawing.Size(14, 18)
$readyForm.Controls.Add($wazuhDot)

$wazuhSvcLbl = New-Object System.Windows.Forms.Label
$wazuhSvcLbl.Text = "Wazuh SIEM"; $wazuhSvcLbl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$wazuhSvcLbl.ForeColor = $TEXT; $wazuhSvcLbl.Location = New-Object System.Drawing.Point(36, $y); $wazuhSvcLbl.Size = New-Object System.Drawing.Size(120, 18)
$readyForm.Controls.Add($wazuhSvcLbl)

$wazuhSubLbl = New-Object System.Windows.Forms.Label
$wazuhSubLbl.Text = "https://$WAZUH_IP  (admin / WazuhLab123*)$(if (-not $wazuhOK) { '  — API still starting' } else { '' })"
$wazuhSubLbl.ForeColor = $MUTED; $wazuhSubLbl.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$wazuhSubLbl.Location = New-Object System.Drawing.Point(36, ($y + 18)); $wazuhSubLbl.Size = New-Object System.Drawing.Size(420, 16)
$readyForm.Controls.Add($wazuhSubLbl)
$y += 46

# Kali + Validator rows
foreach ($row in @(
    @{ color = $GREEN; text = "Kali Linux";   sub = "VirtualBox window" },
    @{ color = $GREEN; text = "AI Validator"; sub = "http://localhost:5000" }
)) {
    $dot = New-Object System.Windows.Forms.Label
    $dot.Text = "●"; $dot.ForeColor = $row.color; $dot.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $dot.Location = New-Object System.Drawing.Point(20, $y); $dot.Size = New-Object System.Drawing.Size(14, 18)
    $readyForm.Controls.Add($dot)

    $svc = New-Object System.Windows.Forms.Label
    $svc.Text = $row.text; $svc.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $svc.ForeColor = $TEXT; $svc.Location = New-Object System.Drawing.Point(36, $y); $svc.Size = New-Object System.Drawing.Size(120, 18)
    $readyForm.Controls.Add($svc)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text = $row.sub; $sub.ForeColor = $MUTED; $sub.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $sub.Location = New-Object System.Drawing.Point(36, ($y + 18)); $sub.Size = New-Object System.Drawing.Size(420, 16)
    $readyForm.Controls.Add($sub)
    $y += 46
}

# Footer info
$rInfo = New-Object System.Windows.Forms.Label
$rInfo.Text = "AI provider: $($choices.provider)  |  Key saved in ai-validator\.env"
$rInfo.ForeColor = $MUTED; $rInfo.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$rInfo.Location = New-Object System.Drawing.Point(20, 212); $rInfo.Size = New-Object System.Drawing.Size(440, 16)
$readyForm.Controls.Add($rInfo)

# Recheck button
$rRecheck = New-Object System.Windows.Forms.Button
$rRecheck.Text = "Recheck Wazuh"; $rRecheck.BackColor = $SURFACE2; $rRecheck.ForeColor = $MUTED
$rRecheck.FlatStyle = "Flat"; $rRecheck.FlatAppearance.BorderSize = 0
$rRecheck.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$rRecheck.Location = New-Object System.Drawing.Point(220, 204); $rRecheck.Size = New-Object System.Drawing.Size(126, 32)
$rRecheck.Add_Click({
    $ok = Test-WazuhReady
    $wazuhDot.ForeColor    = if ($ok) { $GREEN } else { $YELLOW }
    $wazuhSubLbl.Text      = "https://$WAZUH_IP  (admin / WazuhLab123*)$(if (-not $ok) { '  — API still starting' } else { '' })"
    [System.Windows.Forms.Application]::DoEvents()
})
$readyForm.Controls.Add($rRecheck)

# Close button
$rBtn = New-Object System.Windows.Forms.Button
$rBtn.Text = "Close"; $rBtn.BackColor = $ACCENT; $rBtn.ForeColor = [System.Drawing.Color]::White
$rBtn.FlatStyle = "Flat"; $rBtn.FlatAppearance.BorderSize = 0
$rBtn.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$rBtn.Location = New-Object System.Drawing.Point(356, 204); $rBtn.Size = New-Object System.Drawing.Size(100, 32)
$rBtn.Add_Click({ $readyForm.Close() })
$readyForm.Controls.Add($rBtn)
$readyForm.AcceptButton = $rBtn

$readyForm.ShowDialog() | Out-Null
