#Requires -RunAsAdministrator

# -----------------------------------------------------------------------------
# SIGMA PERFORMANCES - TELEMETRY & TRACKING REMOVAL ONLY
# -----------------------------------------------------------------------------

Write-Host "`n========== SIGMA PERFORMANCES - PRIVACY EDITION ==========" -ForegroundColor Green
Write-Host ""
Write-Host "[WARNING] This will REMOVE:" -ForegroundColor Yellow
Write-Host " - All Telemetry & Diagnostics (Registry + Services)" -ForegroundColor Yellow
Write-Host " - All Tracking (Background Apps, Error Reporting, History logs)" -ForegroundColor Yellow
Write-Host ""
Write-Host "[SAFETY] Scheduled Tasks are NOT touched except for 7 specific" -ForegroundColor Green
Write-Host "         telemetry tasks (Appraiser, CEIP, etc.)." -ForegroundColor Green
Write-Host ""
Write-Host "Make sure you have a System Restore point!" -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "Proceed with telemetry & tracking removal? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Exiting. No changes made." -ForegroundColor Cyan
    exit 0
}

Write-Host ""
Write-Host "[INFO] Applying Complete Telemetry & Tracking Removal..." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# Log file for errors
# -----------------------------------------------------------------------------
$errorLog = "$env:TEMP\sigma_privacy_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

# -----------------------------------------------------------------------------
# 1. REMOVE TELEMETRY VIA REGISTRY
# -----------------------------------------------------------------------------
Write-Host "  > Removing Telemetry Registry keys..." -NoNewline

$telemetryRegPaths = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
)

foreach ($path in $telemetryRegPaths) {
    New-Item -Path $path -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path $path -Name "AllowTelemetry" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
}

# Disable advertising ID (cross-app tracking)
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

# Disable Wi-Fi Sense & hotspot sharing (network tracking)
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" -Name "value" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" -Name "AutoConnectAllowedOEM" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

# Disable tailored experiences
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 2. DISABLE TELEMETRY SERVICES
# -----------------------------------------------------------------------------
Write-Host "  > Disabling Telemetry Services..." -NoNewline

$telemetryServices = @("DiagTrack", "dmwappushservice")
foreach ($service in $telemetryServices) {
    Stop-Service $service -ErrorAction SilentlyContinue 2>> $errorLog
    Set-Service $service -StartupType Disabled -ErrorAction SilentlyContinue 2>> $errorLog
}

Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 3. DISABLE TELEMETRY-SPECIFIC SCHEDULED TASKS (ONLY these 7 - NOT security)
# -----------------------------------------------------------------------------
Write-Host "  > Disabling Telemetry Scheduled Tasks..." -NoNewline

$telemetryTasks = @(
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "\Microsoft\Windows\Application Experience\StartupAppTask",
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "\Microsoft\Windows\Customer Experience Improvement Program\BthSQM",
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
)

foreach ($task in $telemetryTasks) {
    Disable-ScheduledTask -TaskPath (Split-Path $task -Parent) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue 2>> $errorLog
}

Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 4. REMOVE ALL BACKGROUND APP TASKS (stops app tracking/notifications)
# -----------------------------------------------------------------------------
Write-Host "  > Disabling Background App Tasks (global)..." -NoNewline

New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsRunInBackground" -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 5. DISABLE WINDOWS ERROR REPORTING (sends crash data to Microsoft)
# -----------------------------------------------------------------------------
Write-Host "  > Disabling Windows Error Reporting..." -NoNewline

New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

# Also disable WER service
Set-Service "WerSvc" -StartupType Disabled -ErrorAction SilentlyContinue 2>> $errorLog
Stop-Service "WerSvc" -ErrorAction SilentlyContinue 2>> $errorLog

Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 6. REMOVE TASK SCHEDULER HISTORY LOGGING (stops tracking of task runs)
# -----------------------------------------------------------------------------
Write-Host "  > Disabling Task Scheduler history logging..." -NoNewline

wevtutil set-log "Microsoft-Windows-TaskScheduler/Operational" /enabled:false 2>> $errorLog

Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 7. Done – report any errors if present
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

Write-Host "[SUCCESS] ALL Telemetry and Tracking components have been removed." -ForegroundColor Green
Write-Host "[INFO] Windows Update, Defender, and ALL other system scheduled tasks" -ForegroundColor Cyan
Write-Host "       are STILL ACTIVE and completely untouched." -ForegroundColor Cyan
Write-Host "[INFO] System reboot recommended for all changes to take effect." -ForegroundColor Yellow
Write-Host ""
Write-Host "I hope you created a restore point!" -ForegroundColor Magenta
Write-Host "Have a good day!" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------------
# 8. Reboot prompt
# -----------------------------------------------------------------------------
$rebootChoice = Read-Host "Press R to reboot now, or Q to quit"

if ($rebootChoice -eq "R" -or $rebootChoice -eq "r") {
    shutdown /r /f /t 0
} else {
    exit 0
}