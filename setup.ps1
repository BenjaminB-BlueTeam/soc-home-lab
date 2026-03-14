# ============================================================
#  SOC Home Lab - Setup & Installer
#  Detects what's missing, asks before installing anything
# ============================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ROOT          = $PSScriptRoot
$CONFIG_FILE   = "$ROOT\config.ini"
$VBOX_DEFAULT  = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$VALIDATOR_DIR = "$ROOT\ai-validator"
$WAZUH_OVA_URL = "https://packages.wazuh.com/4.x/virtual-machine/wazuh-4.14.3.ova"
$KALI_OVA_URL  = "https://cdimage.kali.org/kali-2025.1/kali-linux-2025.1-virtualbox-amd64.7z"

# ── Helpers ─────────────────────────────────────────────────

function Test-Command($cmd) {
    return [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
}

function Test-PythonInstalled {
    return (Test-Command "python") -and ((python --version 2>&1) -match "Python 3")
}

function Test-VBoxInstalled {
    return (Test-Path $VBOX_DEFAULT)
}

function Get-VBoxVMs {
    if (-not (Test-Path $VBOX_DEFAULT)) { return @() }
    try {
        $raw = & $VBOX_DEFAULT list vms 2>$null
        return $raw | ForEach-Object { if ($_ -match '"(.+)"') { $matches[1] } }
    } catch { return @() }
}

function Test-VMExists($name) {
    $vms = Get-VBoxVMs
    return ($vms | Where-Object { $_ -match [regex]::Escape($name) }).Count -gt 0
}

function Find-WazuhVM {
    $vms = Get-VBoxVMs
    return ($vms | Where-Object { $_ -match "wazuh" } | Select-Object -First 1)
}

function Find-KaliVM {
    $vms = Get-VBoxVMs
    return ($vms | Where-Object { $_ -match "kali" } | Select-Object -First 1)
}

function Get-HostOnlyAdapter {
    $raw = & $VBOX_DEFAULT list hostonlyifs 2>$null
    $names = $raw | Select-String "^Name:" | ForEach-Object { ($_ -split ":\s+", 2)[1].Trim() }
    if (-not $names) {
        & $VBOX_DEFAULT hostonlyif create 2>$null | Out-Null
        $raw = & $VBOX_DEFAULT list hostonlyifs 2>$null
        $names = $raw | Select-String "^Name:" | ForEach-Object { ($_ -split ":\s+", 2)[1].Trim() }
    }
    return ($names | Select-Object -First 1)
}

function Get-BridgeAdapter {
    $raw = & $VBOX_DEFAULT list bridgedifs 2>$null
    $lines = $raw -split "`n"
    $name = ""; $status = ""
    foreach ($line in $lines) {
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

# ── Colors ───────────────────────────────────────────────────

$BG       = [System.Drawing.Color]::FromArgb(10, 14, 26)
$SURFACE  = [System.Drawing.Color]::FromArgb(15, 22, 41)
$SURFACE2 = [System.Drawing.Color]::FromArgb(21, 29, 53)
$ACCENT   = [System.Drawing.Color]::FromArgb(0, 212, 255)
$GREEN    = [System.Drawing.Color]::FromArgb(16, 185, 129)
$YELLOW   = [System.Drawing.Color]::FromArgb(245, 158, 11)
$RED      = [System.Drawing.Color]::FromArgb(239, 68, 68)
$MUTED    = [System.Drawing.Color]::FromArgb(100, 116, 139)
$TEXT     = [System.Drawing.Color]::FromArgb(226, 232, 240)

# ── Main Setup Window ────────────────────────────────────────

function Show-SetupWindow {

    # Detect state
    $hasPython  = Test-PythonInstalled
    $hasVBox    = Test-VBoxInstalled
    $wazuhVM    = if ($hasVBox) { Find-WazuhVM } else { $null }
    $kaliVM     = if ($hasVBox) { Find-KaliVM }  else { $null }
    $hasWazuh   = [bool]$wazuhVM
    $hasKali    = [bool]$kaliVM

    # Form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "SOC Home Lab - Setup"
    $form.Size = New-Object System.Drawing.Size(560, 660)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = $BG
    $form.ForeColor = $TEXT
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false

    # Title
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "🛡️  SOC Home Lab — Setup"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = $ACCENT
    $lblTitle.Location = New-Object System.Drawing.Point(24, 20)
    $lblTitle.Size = New-Object System.Drawing.Size(500, 30)
    $form.Controls.Add($lblTitle)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "Checking your environment and configuring the lab."
    $lblSub.ForeColor = $MUTED
    $lblSub.Location = New-Object System.Drawing.Point(26, 52)
    $lblSub.Size = New-Object System.Drawing.Size(500, 18)
    $form.Controls.Add($lblSub)

    # Separator
    function Add-Sep($y) {
        $s = New-Object System.Windows.Forms.Label
        $s.BorderStyle = "Fixed3D"
        $s.Location = New-Object System.Drawing.Point(24, $y)
        $s.Size = New-Object System.Drawing.Size(500, 2)
        $form.Controls.Add($s)
    }

    Add-Sep 76

    # Section helper
    function Add-SectionTitle($text, $y) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $text
        $l.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
        $l.ForeColor = $ACCENT
        $l.Location = New-Object System.Drawing.Point(24, $y)
        $l.Size = New-Object System.Drawing.Size(500, 18)
        $form.Controls.Add($l)
    }

    # Status row helper
    function Add-StatusRow($label, $detected, $y) {
        # Icon
        $ico = New-Object System.Windows.Forms.Label
        $ico.Text = if ($detected) { "✓" } else { "✗" }
        $ico.ForeColor = if ($detected) { $GREEN } else { $RED }
        $ico.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $ico.Location = New-Object System.Drawing.Point(24, $y)
        $ico.Size = New-Object System.Drawing.Size(20, 22)
        $form.Controls.Add($ico)

        # Label
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $label
        $lbl.ForeColor = $TEXT
        $lbl.Location = New-Object System.Drawing.Point(48, ($y + 2))
        $lbl.Size = New-Object System.Drawing.Size(260, 18)
        $form.Controls.Add($lbl)

        # Status text
        $status = New-Object System.Windows.Forms.Label
        $status.Text = if ($detected) { "Detected" } else { "Not found" }
        $status.ForeColor = if ($detected) { $GREEN } else { $YELLOW }
        $status.Location = New-Object System.Drawing.Point(320, ($y + 2))
        $status.Size = New-Object System.Drawing.Size(100, 18)
        $form.Controls.Add($status)

        return $status
    }

    # Checkbox helper
    function Add-InstallCheck($text, $y, $enabled) {
        $chk = New-Object System.Windows.Forms.CheckBox
        $chk.Text = $text
        $chk.ForeColor = if ($enabled) { $YELLOW } else { $MUTED }
        $chk.BackColor = $BG
        $chk.Location = New-Object System.Drawing.Point(48, $y)
        $chk.Size = New-Object System.Drawing.Size(460, 20)
        $chk.Checked = $enabled
        $chk.Enabled = $enabled
        $form.Controls.Add($chk)
        return $chk
    }

    # ── SECTION 1: Prerequisites ──
    Add-SectionTitle "PREREQUISITES" 88
    Add-StatusRow "Python 3.x" $hasPython 110
    $chkPython = Add-InstallCheck "Install Python automatically via winget" 132 (-not $hasPython)

    Add-StatusRow "VirtualBox" $hasVBox 160
    $chkVBox = Add-InstallCheck "Install VirtualBox automatically via winget" 182 (-not $hasVBox)

    Add-Sep 212

    # ── SECTION 2: Virtual Machines ──
    Add-SectionTitle "VIRTUAL MACHINES" 222

    $wazuhLabel = if ($hasWazuh) { "Wazuh VM: $wazuhVM" } else { "Wazuh SIEM VM" }
    $kaliLabel  = if ($hasKali)  { "Kali VM: $kaliVM" }   else { "Kali Linux VM" }

    Add-StatusRow $wazuhLabel $hasWazuh 244
    $chkWazuh = Add-InstallCheck "Download & import Wazuh OVA (~3.5 GB)" 266 (-not $hasWazuh)

    Add-StatusRow $kaliLabel $hasKali 294
    $chkKali = Add-InstallCheck "Download & import Kali Linux OVA (~3 GB)" 316 (-not $hasKali)

    Add-Sep 346

    # ── SECTION 3: Python packages ──
    Add-SectionTitle "PYTHON PACKAGES" 356
    $lblPkg = New-Object System.Windows.Forms.Label
    $lblPkg.Text = "flask, anthropic, python-dotenv, requests — will be installed automatically."
    $lblPkg.ForeColor = $MUTED
    $lblPkg.Location = New-Object System.Drawing.Point(24, 376)
    $lblPkg.Size = New-Object System.Drawing.Size(500, 18)
    $form.Controls.Add($lblPkg)

    Add-Sep 406

    # ── SECTION 4: API Key ──
    Add-SectionTitle "ANTHROPIC API KEY" 416

    $lblAPI = New-Object System.Windows.Forms.Label
    $lblAPI.Text = "Required for the AI Validator. Get yours at console.anthropic.com"
    $lblAPI.ForeColor = $MUTED
    $lblAPI.Location = New-Object System.Drawing.Point(24, 436)
    $lblAPI.Size = New-Object System.Drawing.Size(500, 18)
    $form.Controls.Add($lblAPI)

    $txtAPI = New-Object System.Windows.Forms.TextBox
    $txtAPI.Location = New-Object System.Drawing.Point(24, 458)
    $txtAPI.Size = New-Object System.Drawing.Size(500, 26)
    $txtAPI.BackColor = $SURFACE2
    $txtAPI.ForeColor = $TEXT
    $txtAPI.BorderStyle = "FixedSingle"
    $txtAPI.PasswordChar = "●"
    $txtAPI.PlaceholderText = "sk-ant-..."

    # Check if already configured
    if (Test-Path $CONFIG_FILE) {
        $existingCfg = Get-Content $CONFIG_FILE | Where-Object { $_ -match "anthropic_api_key=(.+)" }
        if ($existingCfg) {
            $txtAPI.Text = ($existingCfg -split "=", 2)[1].Trim()
        }
    }
    $form.Controls.Add($txtAPI)

    $lnkAPI = New-Object System.Windows.Forms.LinkLabel
    $lnkAPI.Text = "Open console.anthropic.com"
    $lnkAPI.Location = New-Object System.Drawing.Point(24, 488)
    $lnkAPI.Size = New-Object System.Drawing.Size(250, 18)
    $lnkAPI.ForeColor = $ACCENT
    $lnkAPI.LinkColor = $ACCENT
    $lnkAPI.Add_LinkClicked({ Start-Process "https://console.anthropic.com" })
    $form.Controls.Add($lnkAPI)

    Add-Sep 514

    # Status label
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = ""
    $lblStatus.ForeColor = $RED
    $lblStatus.Location = New-Object System.Drawing.Point(24, 524)
    $lblStatus.Size = New-Object System.Drawing.Size(380, 18)
    $form.Controls.Add($lblStatus)

    # ── Buttons ──
    $btnSetup = New-Object System.Windows.Forms.Button
    $btnSetup.Text = "Setup & Launch →"
    $btnSetup.Location = New-Object System.Drawing.Point(384, 516)
    $btnSetup.Size = New-Object System.Drawing.Size(140, 36)
    $btnSetup.BackColor = $ACCENT
    $btnSetup.ForeColor = [System.Drawing.Color]::FromArgb(10, 14, 26)
    $btnSetup.FlatStyle = "Flat"
    $btnSetup.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnSetup.FlatAppearance.BorderSize = 0

    $btnSetup.Add_Click({
        if ($txtAPI.Text.Trim().Length -lt 10) {
            $lblStatus.Text = "Please enter your Anthropic API key."
            return
        }
        $form.DialogResult = "OK"
        $form.Close()
    })
    $form.Controls.Add($btnSetup)
    $form.AcceptButton = $btnSetup

    $result = $form.ShowDialog()
    if ($result -ne "OK") { exit 0 }

    return @{
        installPython = $chkPython.Checked
        installVBox   = $chkVBox.Checked
        installWazuh  = $chkWazuh.Checked
        installKali   = $chkKali.Checked
        apiKey        = $txtAPI.Text.Trim()
        wazuhVM       = $wazuhVM
        kaliVM        = $kaliVM
    }
}

# ── Console Progress ─────────────────────────────────────────

function Show-Progress($percent, $msg, $detail = "") {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║         SOC HOME LAB — SETUP                 ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    $w = 44
    $f = [math]::Round($w * $percent / 100)
    $bar = ("█" * $f) + ("░" * ($w - $f))
    Write-Host "  [$bar] $percent%" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ► $msg" -ForegroundColor Yellow
    if ($detail) { Write-Host "    $detail" -ForegroundColor DarkGray }
    Write-Host ""
}

# ── Main ─────────────────────────────────────────────────────

# Show setup window
$choices = Show-SetupWindow

$step = 0
$total = 6 +
    [int]$choices.installPython +
    [int]$choices.installVBox +
    [int]$choices.installWazuh +
    [int]$choices.installKali

# Step: Install Python
if ($choices.installPython) {
    $step++
    Show-Progress ([math]::Round($step/$total*80)) "Installing Python..." "Using winget - this may take a few minutes"
    winget install --id Python.Python.3.13 --silent --accept-package-agreements --accept-source-agreements
    refreshenv 2>$null
}

# Step: Install VirtualBox
if ($choices.installVBox) {
    $step++
    Show-Progress ([math]::Round($step/$total*80)) "Installing VirtualBox..." "Using winget - this may take a few minutes"
    winget install --id Oracle.VirtualBox --silent --accept-package-agreements --accept-source-agreements
    # Refresh path
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

# Step: Install Python packages
$step++
Show-Progress ([math]::Round($step/$total*80)) "Installing Python packages..." "flask, anthropic, python-dotenv, requests"
Set-Location $VALIDATOR_DIR
pip install -r requirements.txt --quiet

# Step: Download & import Wazuh OVA
if ($choices.installWazuh) {
    $step++
    $ovaPath = "$env:TEMP\wazuh-4.14.3.ova"
    Show-Progress ([math]::Round($step/$total*80)) "Downloading Wazuh OVA..." "~3.5 GB - please wait"

    # Check if already downloaded
    if (-not (Test-Path $ovaPath)) {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($WAZUH_OVA_URL, $ovaPath)
    }

    Show-Progress ([math]::Round($step/$total*80)) "Importing Wazuh VM into VirtualBox..." "This may take a few minutes"
    & $VBOX_DEFAULT import $ovaPath --vsys 0 --memory 4096 2>$null
    $choices.wazuhVM = Find-WazuhVM
}

# Step: Download & import Kali OVA
if ($choices.installKali) {
    $step++
    Show-Progress ([math]::Round($step/$total*80)) "Opening Kali Linux download page..." "Download the VirtualBox image then re-run setup"
    Start-Process "https://www.kali.org/get-kali/#kali-virtual-machines"
    Write-Host "  After downloading and extracting Kali, re-run this setup." -ForegroundColor Yellow
    Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    $choices.kaliVM = Find-KaliVM
}

# Step: Configure VM network + VMSVGA
$step++
Show-Progress ([math]::Round($step/$total*80)) "Configuring VM network adapters..." "host-only + bridge + VMSVGA"
if ($choices.wazuhVM -or $choices.kaliVM) {
    Configure-VMs $choices.wazuhVM $choices.kaliVM
}
Start-Sleep 1

# Step: Save config
$step++
Show-Progress ([math]::Round($step/$total*80)) "Saving configuration..." ""

$wazuhIP = "192.168.56.101"

$cfgLines = @(
    "[VMs]",
    "wazuh_vm_name=$($choices.wazuhVM)",
    "kali_vm_name=$($choices.kaliVM)",
    "",
    "[Network]",
    "wazuh_ip=$wazuhIP",
    "",
    "[API]",
    "anthropic_api_key=$($choices.apiKey)",
    "",
    "[Paths]",
    "vboxmanage=$VBOX_DEFAULT"
)
$cfgLines | Set-Content $CONFIG_FILE -Encoding UTF8

# Save .env
$envLines = @(
    "ANTHROPIC_API_KEY=$($choices.apiKey)",
    "WAZUH_HOST=$wazuhIP",
    "WAZUH_PORT=55000",
    "WAZUH_USER=wazuh",
    "WAZUH_PASSWORD=wazuh",
    "WAZUH_SSH_USER=wazuh-user",
    "WAZUH_SSH_PASSWORD=wazuh",
    "WAZUH_INDEXER_USER=admin",
    "WAZUH_INDEXER_PASSWORD=WazuhLab123*"
)
$envLines | Set-Content "$VALIDATOR_DIR\.env" -Encoding UTF8

# Done
Show-Progress 100 "Setup complete!" "All components are ready"
Start-Sleep 1

Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║           SETUP COMPLETE!                    ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  ✓ Python packages installed" -ForegroundColor Green
Write-Host "  ✓ Configuration saved" -ForegroundColor Green
Write-Host "  ✓ .env file created" -ForegroundColor Green
Write-Host ""
Write-Host "  ─────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  To start the lab next time, just run:" -ForegroundColor White
Write-Host "  .\start-soc-lab.ps1   (or .exe)" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Ask to launch now
$launch = [System.Windows.Forms.MessageBox]::Show(
    "Setup complete! Launch SOC Lab now?",
    "SOC Home Lab",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)

if ($launch -eq "Yes") {
    Set-Location $ROOT
    & ".\start-soc-lab.ps1"
} else {
    Write-Host "  Press any key to exit..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}