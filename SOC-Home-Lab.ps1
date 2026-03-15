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
$WAZUH_OVA_URL = "https://packages.wazuh.com/4.x/virtual-machine/wazuh-4.14.3.ova"
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
    try { $t = New-Object System.Net.Sockets.TcpClient; $t.Connect($WAZUH_IP, 55000); $t.Close(); return $true }
    catch { return $false }
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

function Get-KaliIP($kaliVM) {
    try {
        $props = & $VBOX_DEFAULT guestproperty enumerate $kaliVM 2>$null
        foreach ($line in ($props -split "`n")) {
            if ($line -match "Net/\d+/V4/IP\s.*=\s+'(192\.168\.56\.\d+)'") { return $matches[1] }
        }
    } catch {}
    return "192.168.56.102"
}

$script:pForm  = $null
$script:pBar   = $null
$script:pMsg   = $null
$script:pDet   = $null
$script:pPct   = $null
$script:pTrack = $null

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
    $script:pForm.ControlBox      = $false
    $script:pForm.TopMost         = $true

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
    $form.Size            = New-Object System.Drawing.Size(580, 640)
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
    $chkWazuh  = StatusRow "Wazuh SIEM" ([bool]$wazuhVM) "Download & import Wazuh OVA (~3.5 GB)"       194
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
    $notice.Text = "🔒  Your API key is saved only in the local .env file on this machine. It is never shared externally."
    $notice.ForeColor = $SAFE; $notice.Location = New-Object System.Drawing.Point(24, 446); $notice.Size = New-Object System.Drawing.Size(520, 18)
    $form.Controls.Add($notice)

    Sep 472

    # Status + button
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.ForeColor = $RED; $lblStatus.Location = New-Object System.Drawing.Point(24, 484); $lblStatus.Size = New-Object System.Drawing.Size(380, 18)
    $form.Controls.Add($lblStatus)

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = "Setup && Launch  →"; $btn.BackColor = $ACCENT
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.FlatStyle = "Flat"; $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btn.FlatAppearance.BorderSize = 0
    $btn.Location = New-Object System.Drawing.Point(396, 476); $btn.Size = New-Object System.Drawing.Size(148, 36)
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

$PYTHON = Find-Python

$total = 6 + [int]$choices.installPython + [int]$choices.installVBox + [int]$choices.installWazuh + [int]$choices.installKali
$step  = 0

# Install Python
if ($choices.installPython) {
    $step++; Show-Progress ([math]::Round($step/$total*25)) "Installing Python 3..." "via winget — may take a few minutes"
    winget install --id Python.Python.3.13 --silent --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    $PYTHON = Find-Python
}

# Install VirtualBox
if ($choices.installVBox) {
    $step++; Show-Progress ([math]::Round($step/$total*25)) "Installing VirtualBox..." "via winget — may take a few minutes"
    winget install --id Oracle.VirtualBox --silent --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

# Python packages
$step++; Show-Progress ([math]::Round($step/$total*35)) "Installing Python packages..." "flask, anthropic, openai, sshtunnel, paramiko..."
Set-Location $VALIDATOR_DIR
& $PYTHON -m pip install -r requirements.txt --quiet 2>$null

# Download & import Wazuh
if ($choices.installWazuh) {
    $step++; $ovaPath = "$env:TEMP\wazuh-4.14.3.ova"
    Show-Progress ([math]::Round($step/$total*35)) "Downloading Wazuh OVA..." "~3.5 GB — please wait"
    if (-not (Test-Path $ovaPath)) { (New-Object System.Net.WebClient).DownloadFile($WAZUH_OVA_URL, $ovaPath) }
    Show-Progress ([math]::Round($step/$total*40)) "Importing Wazuh VM..." "Configuring 4096 MB RAM"
    & $VBOX_DEFAULT import $ovaPath --vsys 0 --memory 4096 2>$null
    $choices.wazuhVM = Find-WazuhVM
}

# Download Kali
if ($choices.installKali) {
    $step++
    Start-Process "https://www.kali.org/get-kali/#kali-virtual-machines"
    Show-Progress ([math]::Round($step/$total*40)) "Opening Kali download page..." "Download the VirtualBox image (.vbox), extract and import it, then press Enter"
    Read-Host "Press Enter once Kali is imported in VirtualBox"
    $choices.kaliVM = Find-KaliVM
}

# Configure VM network + VMSVGA
$step++; Show-Progress ([math]::Round($step/$total*55)) "Configuring VMs..." "network adapters + VMSVGA (requires VMs to be off)"
if ($choices.wazuhVM -or $choices.kaliVM) { Configure-VMs $choices.wazuhVM $choices.kaliVM }
Start-Sleep 1

# Save .env
$step++; Show-Progress ([math]::Round($step/$total*60)) "Saving configuration..." ""
$envLines = @(
    "AI_PROVIDER=$($choices.provider)",
    "ANTHROPIC_API_KEY=$(if ($choices.provider -eq 'claude') { $choices.apiKey } else { '' })",
    "OPENAI_API_KEY=$(if ($choices.provider -eq 'openai') { $choices.apiKey } else { '' })",
    "WAZUH_HOST=$WAZUH_IP",
    "WAZUH_PORT=55000",
    "WAZUH_USER=wazuh",
    "WAZUH_PASSWORD=wazuh",
    "WAZUH_SSH_USER=wazuh-user",
    "WAZUH_SSH_PASSWORD=wazuh",
    "WAZUH_INDEXER_USER=admin",
    "WAZUH_INDEXER_PASSWORD=WazuhLab123*"
)
$envLines | Set-Content "$VALIDATOR_DIR\.env" -Encoding UTF8

@(
    "[VMs]",
    "wazuh_vm_name=$($choices.wazuhVM)",
    "kali_vm_name=$($choices.kaliVM)",
    "",
    "[Network]",
    "wazuh_ip=$WAZUH_IP",
    "",
    "[API]",
    "ai_provider=$($choices.provider)",
    "",
    "[Paths]",
    "vboxmanage=$VBOX_DEFAULT"
) | Set-Content $CONFIG_FILE -Encoding UTF8

$cfg      = Read-Config
$WAZUH_VM = $cfg.wazuh_vm_name
$KALI_VM  = $cfg.kali_vm_name

# ── LAUNCH ────────────────────────────────────────────────────

$running      = & $VBOX_DEFAULT list runningvms 2>$null
$wazuhRunning = [bool]($running -match [regex]::Escape($WAZUH_VM))
$kaliRunning  = [bool]($running -match [regex]::Escape($KALI_VM))

# Start Wazuh
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

# Poll API — up to 90s extra
Show-Progress 78 "Waiting for Wazuh API on port 55000..." "Polling every 5 seconds"
for ($t = 0; $t -lt 90; $t += 5) {
    if (Test-WazuhReady) { break }
    $pct = [int](78 + ($t / 90) * 2)
    Show-Progress $pct "Waiting for Wazuh API... ($t/90 s)" "Services still starting up"
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

$wazuhOK = Test-WazuhReady

# Start Kali
if ($kaliRunning) {
    Show-Progress 88 "Kali Linux already running — skipping..." ""
} else {
    Show-Progress 88 "Starting Kali Linux..." "GUI mode"
    & $VBOX_DEFAULT startvm $KALI_VM --type gui 2>$null
    Start-Sleep 5
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
foreach ($row in @(
    @{ icon = "●"; color = $(if ($wazuhOK) { $GREEN } else { $YELLOW }); text = "Wazuh SIEM"; sub = "https://$WAZUH_IP  (admin / WazuhLab123*)$(if (-not $wazuhOK) { '  ⚠ API not responding' } else { '' })" },
    @{ icon = "●"; color = $GREEN; text = "Kali Linux";   sub = "VirtualBox window" },
    @{ icon = "●"; color = $GREEN; text = "AI Validator"; sub = "http://localhost:5000" }
)) {
    $dot = New-Object System.Windows.Forms.Label
    $dot.Text = $row.icon; $dot.ForeColor = $row.color; $dot.Font = New-Object System.Drawing.Font("Segoe UI", 8)
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

# Close button
$rBtn = New-Object System.Windows.Forms.Button
$rBtn.Text = "Close"; $rBtn.BackColor = $SURFACE2; $rBtn.ForeColor = $TEXT
$rBtn.FlatStyle = "Flat"; $rBtn.FlatAppearance.BorderSize = 0
$rBtn.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$rBtn.Location = New-Object System.Drawing.Point(356, 204); $rBtn.Size = New-Object System.Drawing.Size(100, 32)
$rBtn.Add_Click({ $readyForm.Close() })
$readyForm.Controls.Add($rBtn)
$readyForm.AcceptButton = $rBtn

$readyForm.ShowDialog() | Out-Null
