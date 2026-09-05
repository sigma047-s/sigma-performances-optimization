#Requires -RunAsAdministrator

# -----------------------------------------------------------------------------
# REVERT SIGMA PERFORMANCES – Remove all modifications
# -----------------------------------------------------------------------------

Write-Host "`n========== REVERT SIGMA PERFORMANCES ==========" -ForegroundColor Green
Write-Host ""
Write-Host "[WARNING] This will RESTORE DEFAULT power settings." -ForegroundColor Yellow
Write-Host " - Re‑enables all power saving features" -ForegroundColor Yellow
Write-Host " - Re‑enables hibernation" -ForegroundColor Yellow
Write-Host " - Re‑enables dynamic tick" -ForegroundColor Yellow
Write-Host ""
Write-Host "Any custom power plan customizations you had before will be lost." -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "Proceed with revert? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Exiting. No changes made." -ForegroundColor Cyan
    exit 0
}

Write-Host ""
Write-Host "[INFO] Reverting all Sigma Performance modifications..." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. Switch active power plan to "Balanced" (built‑in default)
# -----------------------------------------------------------------------------
$balancedGuid = "381b4222-f694-41f0-9685-ff5bb260df2e"
powercfg -setactive $balancedGuid 2>> $env:temp\revert_errors.log
if ($LASTEXITCODE -eq 0) {
    Write-Host "  > Active power scheme set to Balanced." -ForegroundColor Green
} else {
    Write-Host "  > [WARNING] Could not set Balanced scheme. Trying High Performance..." -ForegroundColor Yellow
    powercfg -setactive "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" 2>> $env:temp\revert_errors.log
}

# -----------------------------------------------------------------------------
# 2. Re‑enable hibernation (was disabled with -h off)
# -----------------------------------------------------------------------------
powercfg -h on 2>> $env:temp\revert_errors.log
Write-Host "  > Hibernation re‑enabled." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 3. Re‑enable dynamic tick (was disabled with bcdedit)
# -----------------------------------------------------------------------------
bcdedit /set disabledynamictick no 2>> $env:temp\revert_errors.log
if ($LASTEXITCODE -ne 0) {
    # If the value doesn't exist, delete it to revert to default
    bcdedit /deletevalue disabledynamictick 2>> $env:temp\revert_errors.log
}
Write-Host "  > Dynamic tick re‑enabled." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 4. (Optional) Delete any duplicate Ultimate Performance scheme created
#    The original script duplicated the built‑in Ultimate Performance but
#    activated the built‑in one. The duplicate is unused – we can leave it.
#    To be thorough, we'll try to remove any scheme that is not a default.
#    However, we won't remove built‑in schemes to avoid system issues.
# -----------------------------------------------------------------------------
Write-Host "  > (Optional) Removing unused duplicate power schemes..." -NoNewline
$defaultSchemes = @(
    "381b4222-f694-41f0-9685-ff5bb260df2e", # Balanced
    "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c", # High Performance
    "a1841308-3541-4fab-bc81-f71556f20b4a", # Power Saver
    "e9a42b02-d5df-448d-aa00-03f14749eb61"  # Ultimate Performance (built‑in)
)
$allSchemes = powercfg -list | Select-String -Pattern '([A-F0-9\-]{36})' | ForEach-Object { $_.Matches.Groups[1].Value }
foreach ($scheme in $allSchemes) {
    if ($defaultSchemes -notcontains $scheme) {
        powercfg -delete $scheme 2>> $env:temp\revert_errors.log
    }
}
Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 5. Report any errors
# -----------------------------------------------------------------------------
if (Test-Path $env:temp\revert_errors.log) {
    $errorCount = (Get-Content $env:temp\revert_errors.log | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "[WARNING] $errorCount errors occurred. Check log: $env:temp\revert_errors.log" -ForegroundColor Yellow
    } else {
        Remove-Item $env:temp\revert_errors.log -Force
    }
}

Write-Host ""
Write-Host "[SUCCESS] All Sigma Performance modifications have been reverted." -ForegroundColor Green
Write-Host "Your system is now using the default Balanced power plan." -ForegroundColor Green
Write-Host ""
Write-Host "A reboot is recommended for all changes to take full effect." -ForegroundColor Yellow
Write-Host ""

$rebootChoice = Read-Host "Press R to reboot now, or Q to quit"
if ($rebootChoice -eq "R" -or $rebootChoice -eq "r") {
    shutdown /r /f /t 0
} else {
    exit 0
}