#Requires -RunAsAdministrator

# -----------------------------------------------------------------------------
# SIGMA PERFORMANCES - REMOVE UNKNOWN + GHOST DEVICES
# -----------------------------------------------------------------------------

Write-Host "`n========== SIGMA PERFORMANCES DEVICE CLEANUP ==========" -ForegroundColor Green
Write-Host ""
Write-Host "[WARNING] This will REMOVE:" -ForegroundColor Yellow
Write-Host " - Phase 1 (Auto): All 'Unknown' status devices (safe)" -ForegroundColor Yellow
Write-Host " - Phase 2 (Prompt): ALL non-present 'ghost' devices (deep clean)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Make sure you have a System Restore point!" -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "Proceed with device cleanup? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Exiting. No changes made." -ForegroundColor Cyan
    exit 0
}

Write-Host ""
Write-Host "[INFO] Applying Device Cleanup..." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# Log file for errors
# -----------------------------------------------------------------------------
$errorLog = "$env:TEMP\sigma_device_cleanup_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

# -----------------------------------------------------------------------------
# 1. REMOVE UNKNOWN DEVICES (SAFE - AUTO)
# -----------------------------------------------------------------------------
Write-Host "  > Searching for 'Unknown' status devices..." -NoNewline

$unknownDevices = Get-PnpDevice | Where-Object { $_.Status -eq 'Unknown' }

if ($unknownDevices.Count -eq 0) {
    Write-Host " None found." -ForegroundColor Green
} else {
    Write-Host " Found $($unknownDevices.Count). Removing..." -ForegroundColor Yellow
    foreach ($dev in $unknownDevices) {
        Write-Host "    Removing: $($dev.FriendlyName)" -ForegroundColor Gray
        pnputil /remove-device $dev.InstanceId 2>> $errorLog | Out-Null
    }
    Write-Host "  [DONE] Unknown devices removed." -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 2. REMOVE ALL GHOST DEVICES (DEEP - WITH PROMPT)
# -----------------------------------------------------------------------------
Write-Host "  > Searching for all non-present 'ghost' devices..." -NoNewline

$ghostDevices = Get-PnpDevice -PresentOnly $false

if ($ghostDevices.Count -eq 0) {
    Write-Host " None found." -ForegroundColor Green
} else {
    Write-Host " Found $($ghostDevices.Count)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Ghost devices found:" -ForegroundColor Cyan
    foreach ($dev in $ghostDevices) {
        Write-Host "    - $($dev.FriendlyName) (Status: $($dev.Status))" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "[WARNING] Removing ghost devices can break old configurations." -ForegroundColor Red
    $ghostConfirm = Read-Host "Proceed with ghost device removal? (Type 'YES' to confirm)"

    if ($ghostConfirm -eq "YES") {
        Write-Host "  Removing ghost devices..." -NoNewline
        foreach ($dev in $ghostDevices) {
            Write-Host "    Removing: $($dev.FriendlyName)" -ForegroundColor Gray
            pnputil /remove-device $dev.InstanceId 2>> $errorLog | Out-Null
        }
        Write-Host "  [DONE] Ghost devices removed." -ForegroundColor Green
    } else {
        Write-Host "  Ghost device removal skipped." -ForegroundColor Yellow
    }
}

# -----------------------------------------------------------------------------
# 3. Rescan for new hardware
# -----------------------------------------------------------------------------
Write-Host "  > Rescanning for hardware changes..." -NoNewline
pnputil /scan-devices 2>> $errorLog | Out-Null
Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 4. Done – report any errors if present
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

Write-Host "[SUCCESS] Device Cleanup completed." -ForegroundColor Green
Write-Host "[INFO] A reboot is recommended for all changes to take effect." -ForegroundColor Yellow
Write-Host ""
Write-Host "I hope you created a restore point!" -ForegroundColor Magenta
Write-Host "Have a good day!" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------------
# 5. Reboot prompt
# -----------------------------------------------------------------------------
$rebootChoice = Read-Host "Press R to reboot now, or Q to quit"

if ($rebootChoice -eq "R" -or $rebootChoice -eq "r") {
    shutdown /r /f /t 0
} else {
    exit 0
}