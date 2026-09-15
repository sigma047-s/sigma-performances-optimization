#Requires -RunAsAdministrator

# -----------------------------------------------------------------------------
# SIGMA PERFORMANCES - POWERCfg REGISTRY ONLY
# -----------------------------------------------------------------------------
# Applies ONLY:
#   [HKEY_CURRENT_USER\Control Panel\PowerCfg]
#   "CurrentPowerPolicy"="4"
#
#   [HKEY_CURRENT_USER\Control Panel\PowerCfg\GlobalPowerPolicy]
#   "Policies"=hex:...
# -----------------------------------------------------------------------------

Write-Host "`n========== SIGMA PERFORMANCES ==========" -ForegroundColor Green
Write-Host "[INFO] Applying only PowerCfg registry values..." -ForegroundColor Cyan

$regPath    = 'HKCU:\Control Panel\PowerCfg'
$globalPath = 'HKCU:\Control Panel\PowerCfg\GlobalPowerPolicy'

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
    throw "Policies hex parsed to $($policiesBytes.Count) bytes; expected 80."
}

# [HKEY_CURRENT_USER\Control Panel\PowerCfg]
# "CurrentPowerPolicy"="4"
New-Item -Path $regPath -Force | Out-Null
New-ItemProperty `
    -Path $regPath `
    -Name 'CurrentPowerPolicy' `
    -Value '4' `
    -PropertyType String `
    -Force | Out-Null

# [HKEY_CURRENT_USER\Control Panel\PowerCfg\GlobalPowerPolicy]
# "Policies"=hex:...
New-Item -Path $globalPath -Force | Out-Null
New-ItemProperty `
    -Path $globalPath `
    -Name 'Policies' `
    -Value $policiesBytes `
    -PropertyType Binary `
    -Force | Out-Null

Write-Host "[SUCCESS] SIGMA PERFORMANCES - PowerCfg registry values applied." -ForegroundColor Green
Write-Host "[INFO] No CPU or powercfg settings were changed." -ForegroundColor Cyan