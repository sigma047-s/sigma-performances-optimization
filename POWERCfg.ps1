#Requires -RunAsAdministrator

# -----------------------------------------------------------------------------
# SIGMA PERFORMANCES - POWERCfg REGISTRY ONLY
# -----------------------------------------------------------------------------

Write-Host "`n========== SIGMA PERFORMANCES ==========" -ForegroundColor Green
Write-Host ""
Write-Host "[WARNING] This will apply PowerCfg registry values only." -ForegroundColor Yellow
Write-Host "It will NOT change CPU power settings or run powercfg." -ForegroundColor Red
Write-Host "Make sure you have a System Restore point!" -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "Proceed with PowerCfg registry optimization? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Exiting. No changes made." -ForegroundColor Cyan
    exit 0
}

Write-Host ""
Write-Host "[INFO] Applying PowerCfg registry values..." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------
function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type
    )

    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        New-ItemProperty `
            -Path $Path `
            -Name $Name `
            -Value $Value `
            -PropertyType $Type `
            -Force `
            -ErrorAction Stop | Out-Null
    }
    catch {
        Add-Content -Path $errorLog -Value $_.Exception.Message
    }
}

# Log file for errors
$errorLog = "$env:TEMP\sigma_powercfg_registry_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

# -----------------------------------------------------------------------------
# 1. Apply PowerCfg registry values
# -----------------------------------------------------------------------------
Write-Host "  > Applying PowerCfg registry values..." -NoNewline

$regPath    = 'HKCU:\Control Panel\PowerCfg'
$globalPath = 'HKCU:\Control Panel\PowerCfg\GlobalPowerPolicy'

# Hex data for:
# [HKEY_CURRENT_USER\Control Panel\PowerCfg\GlobalPowerPolicy]
# "Policies"=hex:...
$policiesHex = @'
01,00,00,00,02,00,00,00,01,00,00,00,00,00,00,00,02,00,00,00,00,
00,00,00,00,00,00,00,00,00,00,00,2c,01,00,00,32,32,03,03,04,00,00,00,04,00,
00,00,00,00,00,00,00,00,00,00,84,03,00,00,2c,01,00,00,00,00,00,00,84,03,00,
00,00,01,64,64,64,64,00,00
'@

$policiesBytes = [byte[]](
    $policiesHex -split ',' |
    ForEach-Object { [Convert]::ToByte($_.Trim(), 16) }
)

if ($policiesBytes.Count -ne 80) {
    Add-Content -Path $errorLog -Value "Policies hex parsed to $($policiesBytes.Count) bytes; expected 80."
}

# [HKEY_CURRENT_USER\Control Panel\PowerCfg]
# "CurrentPowerPolicy"="4"
Set-RegistryValue -Path $regPath -Name 'CurrentPowerPolicy' -Value '4' -Type String

# [HKEY_CURRENT_USER\Control Panel\PowerCfg\GlobalPowerPolicy]
# "Policies"=hex:...
Set-RegistryValue -Path $globalPath -Name 'Policies' -Value $policiesBytes -Type Binary

Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 2. Done – report any errors if present
# -----------------------------------------------------------------------------
Write-Host ""
if (Test-Path $errorLog) {
    $errorCount = (Get-Content $errorLog | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "[WARNING] $errorCount errors occurred. Check log: $errorLog" -ForegroundColor Yellow
    } else {
        Remove-Item $errorLog -Force
    }
}

Write-Host "[SUCCESS] PowerCfg registry values applied." -ForegroundColor Green
Write-Host "[INFO] System reboot required." -ForegroundColor Yellow
Write-Host ""
Write-Host "I hope you created a restore point!" -ForegroundColor Magenta
Write-Host "Have a good day!" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------------
# 3. Reboot prompt
# -----------------------------------------------------------------------------
$rebootChoice = Read-Host "Press R to reboot now, or Q to quit"

if ($rebootChoice -eq "R" -or $rebootChoice -eq "r") {
    shutdown /r /f /t 0
} else {
    exit 0
}
