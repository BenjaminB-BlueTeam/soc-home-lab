# ============================================================
#  compile.ps1 — Generate SOC-Home-Lab.exe from .ps1
#  Run once: .\compile.ps1
#  Requires internet access to install PS2EXE on first run
# ============================================================

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installing PS2EXE module..." -ForegroundColor Cyan
    Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
}

Import-Module ps2exe

$src = "$PSScriptRoot\SOC-Home-Lab.ps1"
$out = "$PSScriptRoot\SOC-Home-Lab.exe"

Write-Host "Compiling $src..." -ForegroundColor Cyan

Invoke-PS2EXE `
    -InputFile   $src `
    -OutputFile  $out `
    -Title       "SOC Home Lab" `
    -Description "Cybersecurity training environment — setup and launcher" `
    -Version     "1.0.0" `
    -Company     "SOC Home Lab" `
    -NoConsole:$false

if (Test-Path $out) {
    $size = [math]::Round((Get-Item $out).Length / 1KB)
    Write-Host ""
    Write-Host "  ✓  SOC-Home-Lab.exe generated  ($size KB)" -ForegroundColor Green
    Write-Host "  →  Commit it or upload as a GitHub Release asset." -ForegroundColor DarkGray
} else {
    Write-Host "  ✗  Compilation failed." -ForegroundColor Red
}

Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
