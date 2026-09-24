#Requires -RunAsAdministrator

# -----------------------------------------------------------------------------
# SIGMA PERFORMANCES - FULL REVERT (REMOVE ALL MODIFICATIONS)
# -----------------------------------------------------------------------------

$errorLog = "$env:TEMP\sigma_revert_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

Write-Host "`n========== SIGMA PERFORMANCES - FULL REVERT ==========" -ForegroundColor Green
Write-Host ""
Write-Host "[WARNING] This will remove ALL optimizations applied by the Sigma script:" -ForegroundColor Yellow
Write-Host " - Restore default power schemes"
Write-Host " - Set power plan to Balanced"
Write-Host " - Delete Ultimate Performance plan(s)"
Write-Host " - Re-enable hibernation"
Write-Host " - Re-enable dynamic tick"
Write-Host ""
Write-Host "A reboot is recommended after this." -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Proceed with full revert? (Y/N)"
if ($confirm -notmatch '^[Yy]$') {
    Write-Host "Exiting. No changes made." -ForegroundColor Cyan
    exit 0
}

Write-Host ""
Write-Host "[INFO] Reverting all modifications..." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. Restore default power schemes (resets every powercfg setting)
# -----------------------------------------------------------------------------
Write-Host "  > Restoring default power schemes..." -NoNewline
powercfg -restoredefaultschemes 2>> $errorLog
Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 2. Set active scheme to Balanced
# -----------------------------------------------------------------------------
Write-Host "  > Setting active scheme to Balanced..." -NoNewline
powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>> $errorLog
Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 3. Delete Ultimate Performance scheme(s)
# -----------------------------------------------------------------------------
Write-Host "  > Removing Ultimate Performance scheme(s)..." -NoNewline

# Delete known Ultimate Performance GUID
powercfg -delete e9a42b02-d5df-448d-aa00-03f14749eb61 2>> $errorLog

# Delete any scheme whose name contains "Ultimate Performance"
$schemes = powercfg /list
foreach ($line in $schemes) {
    if ($line -match 'Ultimate Performance') {
        if ($line -match '([A-F0-9\-]{36})') {
            $guid = $matches[1]
            powercfg -delete $guid 2>> $errorLog
        }
    }
}
Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 4. Re-enable hibernation
# -----------------------------------------------------------------------------
Write-Host "  > Re-enabling hibernation..." -NoNewline
powercfg -h on 2>> $errorLog
Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 5. Re-enable dynamic tick
# -----------------------------------------------------------------------------
Write-Host "  > Re-enabling dynamic tick..." -NoNewline
bcdedit /deletevalue disabledynamictick 2>> $errorLog
Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 6. Final commit
# -----------------------------------------------------------------------------
powercfg -setactive SCHEME_CURRENT 2>> $errorLog

# -----------------------------------------------------------------------------
# 7. Report errors if any
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

Write-Host "[SUCCESS] Full revert complete. All Sigma Performance modifications removed." -ForegroundColor Green
Write-Host "[INFO] Reboot recommended to fully apply changes." -ForegroundColor Yellow
Write-Host ""

# -----------------------------------------------------------------------------
# 8. Reboot prompt
# -----------------------------------------------------------------------------
$rebootChoice = Read-Host "Press R to reboot now, or Q to quit"
if ($rebootChoice -match '^[Rr]$') {
    shutdown /r /f /t 0
} else {
    exit 0
}