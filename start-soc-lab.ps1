# ============================================================
#  SOC Home Lab - Launcher
#  Run this after setup.ps1 to start all services
# ============================================================

$Host.UI.RawUI.WindowTitle = "SOC Home Lab - Launcher"
$Host.UI.RawUI.BackgroundColor = "Black"
$Host.UI.RawUI.ForegroundColor = "Green"
Clear-Host

$ROOT           = $PSScriptRoot
$CONFIG_FILE    = "$ROOT\config.ini"
$VALIDATOR_PATH = "$ROOT\ai-validator"

# ── Read config ─────────────────────────────────────────────

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
        try {
            $v = & $p --version 2>&1
            if ("$v" -match "Python 3") { return $p }
        } catch {}
    }
    return "python"
}

function Test-WazuhReady($ip) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect($ip, 55000)
        $tcp.Close()
        return $true
    } catch { return $false }
}

function Read-Config {
    $cfg = @{}
    if (Test-Path $CONFIG_FILE) {
        Get-Content $CONFIG_FILE | ForEach-Object {
            if ($_ -match "^\s*([^#;=]+?)\s*=\s*(.+)$") {
                $cfg[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
    }
    return $cfg
}

# ── Progress UI ─────────────────────────────────────────────

function Show-Progress($percent, $msg, $detail = "") {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║           SOC HOME LAB - LAUNCHER            ║" -ForegroundColor Cyan
    Write-Host "  ║     Wazuh  •  Kali Linux  •  AI Validator    ║" -ForegroundColor Cyan
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

# ── Main ────────────────────────────────────────────────────

# Check config exists
if (-not (Test-Path $CONFIG_FILE)) {
    Write-Host "  [!] No config found. Please run setup.ps1 first." -ForegroundColor Red
    Write-Host ""
    Write-Host "  .\setup.ps1" -ForegroundColor Cyan
    Start-Sleep 3
    exit 1
}

$cfg = Read-Config

$VBOX     = $cfg.vboxmanage
$WAZUH_VM = $cfg.wazuh_vm_name
$KALI_VM  = $cfg.kali_vm_name
$WAZUH_IP = $cfg.wazuh_ip

# Step 1 - Check VBox
Show-Progress 5 "Checking VirtualBox..." "Verifying installation"
if (-not (Test-Path $VBOX)) {
    Write-Host "  [ERROR] VBoxManage not found. Run setup.ps1 first." -ForegroundColor Red
    pause; exit 1
}
Start-Sleep 1

# Step 2 - Check running VMs
Show-Progress 10 "Checking VM states..." "Querying VirtualBox"
$runningVMs   = & $VBOX list runningvms 2>$null
$wazuhRunning = $runningVMs -match [regex]::Escape($WAZUH_VM)
$kaliRunning  = $runningVMs -match [regex]::Escape($KALI_VM)
Start-Sleep 1

# Step 3 - Start Wazuh
if ($wazuhRunning) {
    Show-Progress 50 "Wazuh already running — skipping..." "VM already active"
    Start-Sleep 2
} else {
    Show-Progress 15 "Starting Wazuh SIEM (headless)..." "Launching VM in background"
    & $VBOX startvm $WAZUH_VM --type headless 2>$null
    # Initial wait — services need time to start
    $bootTime = 90
    for ($i = 1; $i -le $bootTime; $i++) {
        $pct = 15 + [math]::Round(25 * $i / $bootTime)
        Show-Progress $pct "Wazuh SIEM booting... ($i/$bootTime sec)" "Starting indexer, manager and dashboard"
        Start-Sleep 1
    }
    # Poll API until ready (up to 90s extra)
    Show-Progress 42 "Waiting for Wazuh API on port 55000..." "Checking every 5 seconds"
    for ($t = 0; $t -lt 90; $t += 5) {
        if (Test-WazuhReady $WAZUH_IP) { break }
        Show-Progress 42 "Waiting for Wazuh API... ($t/90s)" "Port 55000 not yet open — services still starting"
        Start-Sleep 5
    }
    if (Test-WazuhReady $WAZUH_IP) {
        Show-Progress 50 "Wazuh API ready!" "Port 55000 is responding"
    } else {
        Show-Progress 50 "Wazuh API not responding yet" "You may need to restart wazuh-manager inside the VM"
    }
    Start-Sleep 1
}

# Step 4 - Start Kali
if ($kaliRunning) {
    Show-Progress 55 "Kali Linux already running — skipping..." "VM already active"
    Start-Sleep 2
} else {
    Show-Progress 55 "Starting Kali Linux..." "Launching GUI"
    & $VBOX startvm $KALI_VM --type gui 2>$null
    $bootTime = 20
    for ($i = 1; $i -le $bootTime; $i++) {
        $pct = 55 + [math]::Round(15 * $i / $bootTime)
        Show-Progress $pct "Kali Linux booting... ($i/$bootTime sec)" "Loading desktop environment"
        Start-Sleep 1
    }
}

# Step 5 - Start Validator
Show-Progress 75 "Starting AI Validator..." "Launching Flask server"
$env:ANTHROPIC_API_KEY = $cfg.anthropic_api_key
$PYTHON = Find-Python
Set-Location $VALIDATOR_PATH
Start-Process -FilePath $PYTHON -ArgumentList "app.py" -WindowStyle Minimized

for ($i = 1; $i -le 5; $i++) {
    $pct = 75 + [math]::Round(15 * $i / 5)
    Show-Progress $pct "AI Validator starting... ($i/5 sec)" "Initializing Flask on port 5000"
    Start-Sleep 1
}

# Step 6 - Open browser
Show-Progress 95 "Opening dashboard..." "Launching browser"
Start-Process "http://localhost:5000"
Start-Sleep 2

# Done
Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║         ALL SERVICES STARTED!                ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  ████████████████████████████████████████████  100%" -ForegroundColor Green
Write-Host ""
Write-Host "  ✓ Wazuh SIEM    →  https://$WAZUH_IP" -ForegroundColor White
Write-Host "  ✓ Kali Linux    →  VirtualBox window" -ForegroundColor White
Write-Host "  ✓ AI Validator  →  http://localhost:5000" -ForegroundColor White
Write-Host ""
Write-Host "  Press any key to close this window..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")