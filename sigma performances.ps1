#Requires -RunAsAdministrator

# =============================================================================
# SIGMA PERFORMANCES - ALL-IN-ONE OPTIMIZATION SUITE
# -----------------------------------------------------------------------------
# Runs all 5 optimizations sequentially:
#   1. CPU Optimization (AC / DC)
#   2. Remove Unknown + Ghost Devices
#   3. PowerCfg Registry Only
#   4. Telemetry & Tracking Removal
#   5. Network Throttle (QoS 1-3000 Mbps)
#
# Single 'Y' confirmation + Progress Bars throughout.
# =============================================================================

$script:TotalSteps  = 5
$script:CurrentStep = 0

# -----------------------------------------------------------------------------
# Progress helpers
# -----------------------------------------------------------------------------
function Write-OverallProgress {
    param(
        [string]$Status,
        [int]$SubPercent = 0
    )
    $overall = [math]::Round((($script:CurrentStep - 1) + ($SubPercent / 100)) / $script:TotalSteps * 100)
    if ($overall -gt 100) { $overall = 100 }
    if ($overall -lt 0)   { $overall = 0 }
    Write-Progress -Id 0 `
        -Activity "SIGMA PERFORMANCES - Applying All Optimizations" `
        -Status   "Step $($script:CurrentStep)/$($script:TotalSteps): $Status" `
        -PercentComplete $overall
}

function Write-SubProgress {
    param(
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete
    )
    if ($PercentComplete -gt 100) { $PercentComplete = 100 }
    if ($PercentComplete -lt 0)   { $PercentComplete = 0 }
    Write-Progress -Id 1 -ParentId 0 `
        -Activity $Activity `
        -Status   $Status `
        -PercentComplete $PercentComplete
}

function Complete-SubProgress {
    param([string]$Activity)
    Write-Progress -Id 1 -ParentId 0 -Activity $Activity -Completed
}

# -----------------------------------------------------------------------------
# INTRO + SINGLE CONFIRMATION
# -----------------------------------------------------------------------------
Clear-Host
Write-Host ""
Write-Host "========== SIGMA PERFORMANCES ==========" -ForegroundColor Green
Write-Host ""
Write-Host "[WARNING] This will apply ALL of the following:" -ForegroundColor Yellow
Write-Host "   1. CPU Optimization (disables all CPU power saving)" -ForegroundColor Yellow
Write-Host "   2. Remove Unknown + Ghost Devices" -ForegroundColor Yellow
Write-Host "   3. PowerCfg Registry values" -ForegroundColor Yellow
Write-Host "   4. Telemetry & Tracking Removal" -ForegroundColor Yellow
Write-Host "   5. Network Throttle (QoS)" -ForegroundColor Yellow
Write-Host ""
Write-Host "[CAUTION] CPU optimization will significantly REDUCE battery life." -ForegroundColor Red
Write-Host "[CAUTION] Removing ghost devices can break old configurations."   -ForegroundColor Red
Write-Host ""
Write-Host "Make sure you have a System Restore point!" -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "Proceed with ALL optimizations? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Exiting. No changes made." -ForegroundColor Cyan
    exit 0
}

# -----------------------------------------------------------------------------
# ASK FOR NETWORK THROTTLE (1-3000 Mbps)
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "[INFO] Network Throttle configuration" -ForegroundColor Cyan
$netMbps = 0
do {
    $netInput = Read-Host "Enter desired network speed limit in Mbps (1-3000)"
    $netValid = $false
    if ($netInput -match '^\d+$') {
        $netMbps = [int]$netInput
        if ($netMbps -ge 1 -and $netMbps -le 3000) {
            $netValid = $true
        }
    }
    if (-not $netValid) {
        Write-Host "[ERROR] Enter a whole number between 1 and 3000." -ForegroundColor Red
    }
} while (-not $netValid)

Write-Host ""
Write-Host "[INFO] Applying ALL optimizations. Please wait..." -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# STEP 1 - CPU OPTIMIZATION (AC / DC)
# =============================================================================
$script:CurrentStep = 1
Write-OverallProgress -Status "CPU Optimization" -SubPercent 0

$script:errorLog = "$env:TEMP\sigma_optimization_errors.log"
if (Test-Path $script:errorLog) { Remove-Item $script:errorLog -Force }

# Save current active power scheme GUID
$originalScheme = (powercfg -getactivescheme) -replace '.*\s([A-F0-9\-]{36}).*', '$1'

# Activate Ultimate Performance power scheme
Write-SubProgress -Activity "CPU Optimization" -Status "Activating Ultimate Performance scheme..." -PercentComplete 3
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>> $script:errorLog
powercfg -setactive       e9a42b02-d5df-448d-aa00-03f14749eb61 2>> $script:errorLog

# CPU / Processor settings
$cpuSettings = @{
    "PROCTHROTTLEMIN"            = 100
    "PROCTHROTTLEMAX"            = 100
    "PERFBOOSTMODE"              = 5
    "CPMINCORES"                 = 100
    "PERFINCTHRESHOLD"           = 1
    "PERFDECREASETHRESHOLD"      = 100
    "PERFINCREASEPOLICY"         = 3
    "PERFDECREASEPOLICY"         = 0
    "RESPONSIVENESS"             = 100
    "PERFORMANCECORES"           = 0
    "PERFEPP"                    = 0
    "IDLEDEMOTE"                 = 0
    "IDLEPROMOTE"                = 100
    "PERFBOOSTPOL"               = 100
    "SHORTTHREADBOOST"           = 3
    "HETEROPOLICY"               = 0
    "PERFINCRES"                 = 0
    "PERFDECRES"                 = 0
    "RESPENABLETHRESHOLD"        = 100
    "RESPPERFFLOOR"              = 100
    "IDLESTATE"                  = 0
    "PERFAUTONOMOUS"             = 0
    "PERFAUTONOMOUSACTIVEWINDOW" = 100
    "CPMAXCORES"                 = 100
    "CPEPP"                      = 0
    "CPPARKING"                  = 0
    "CPPARKED"                   = 0
    "CPCONCURRENCY"              = 100
    "CPHEADROOM"                 = 100
    "CPLATENCY"                  = 100
    "CPLOAD"                     = 100
    "CPREQUESTS"                 = 100
    "CPRANDOM"                   = 0
    "MAXFREQ"                    = 0
    "MINFREQ"                    = 0
    "SCHEDPOLICY"                = 2
    "SHORTTHREADSCHED"           = 2
    "STARTPOLICY"                = 0
    "STOPPOLICY"                 = 0
    "HETEROEPP"                  = 0
    "HETEROPROCESSPOLICY"        = 0
    "HETEROTHREADPOLICY"         = 0
    "PERFDUTYCYCLING"            = 100
    "PERFDPC"                    = 1
    "PERFEPPBOOST"               = 100
    "PERFEPPBACKOFF"             = 100
    "PERFHISTORY"                = 0
    "PERFCHECK"                  = 0
    "PERFLATENCY"                = 100
    "PERFAUTONOMOUSFREQUENCY"    = 0
}

$cpuKeys  = @($cpuSettings.Keys)
$cpuTotal = $cpuKeys.Count
$cpuIndex = 0

foreach ($key in $cpuKeys) {
    $cpuIndex++
    # Reserve 5%-98% of the CPU section for the settings sweep
    $pct = 5 + [math]::Round($cpuIndex / $cpuTotal * 93)
    Write-SubProgress -Activity "CPU Optimization" -Status "Applying: $key ($cpuIndex/$cpuTotal)" -PercentComplete $pct

    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR $key $cpuSettings[$key] 2>> $script:errorLog
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR $key $cpuSettings[$key] 2>> $script:errorLog
}

# Extra processor GUID
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 94d3a615-a899-4ac5-ae2b-e4d8f634367f 1 2>> $script:errorLog
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 94d3a615-a899-4ac5-ae2b-e4d8f634367f 1 2>> $script:errorLog

# Commit
Write-SubProgress -Activity "CPU Optimization" -Status "Committing power scheme..." -PercentComplete 99
powercfg -setactive SCHEME_CURRENT 2>> $script:errorLog

Complete-SubProgress -Activity "CPU Optimization"
Write-OverallProgress -Status "CPU Optimization complete" -SubPercent 100
Write-Host "  [1/5] CPU Optimization .......................... DONE" -ForegroundColor Green

# =============================================================================
# STEP 2 - REMOVE UNKNOWN + GHOST DEVICES
# =============================================================================
$script:CurrentStep = 2
Write-OverallProgress -Status "Device Cleanup" -SubPercent 0

$script:errorLog = "$env:TEMP\sigma_device_cleanup_errors.log"
if (Test-Path $script:errorLog) { Remove-Item $script:errorLog -Force }

# --- 2a. Unknown devices (first ~45% of this step) ---
Write-SubProgress -Activity "Device Cleanup" -Status "Searching for 'Unknown' status devices..." -PercentComplete 5
$unknownDevices = @(Get-PnpDevice | Where-Object { $_.Status -eq 'Unknown' })
$unknownTotal   = $unknownDevices.Count

if ($unknownTotal -gt 0) {
    $i = 0
    foreach ($dev in $unknownDevices) {
        $i++
        $pct = 5 + [math]::Round($i / $unknownTotal * 40)
        Write-SubProgress -Activity "Device Cleanup" -Status "Removing unknown: $($dev.FriendlyName)" -PercentComplete $pct
        pnputil /remove-device $dev.InstanceId 2>> $script:errorLog | Out-Null
    }
}

# --- 2b. Ghost devices (next ~50%) ---
Write-SubProgress -Activity "Device Cleanup" -Status "Searching for non-present 'ghost' devices..." -PercentComplete 50
$ghostDevices = @(Get-PnpDevice | Where-Object { $_.Present -eq $false })
$ghostTotal   = $ghostDevices.Count

if ($ghostTotal -gt 0) {
    $i = 0
    foreach ($dev in $ghostDevices) {
        $i++
        $pct = 50 + [math]::Round($i / $ghostTotal * 45)
        Write-SubProgress -Activity "Device Cleanup" -Status "Removing ghost: $($dev.FriendlyName)" -PercentComplete $pct
        pnputil /remove-device $dev.InstanceId 2>> $script:errorLog | Out-Null
    }
}

# --- 2c. Rescan ---
Write-SubProgress -Activity "Device Cleanup" -Status "Rescanning for hardware changes..." -PercentComplete 97
pnputil /scan-devices 2>> $script:errorLog | Out-Null

Complete-SubProgress -Activity "Device Cleanup"
Write-OverallProgress -Status "Device Cleanup complete" -SubPercent 100
Write-Host "  [2/5] Device Cleanup ............................ DONE" -ForegroundColor Green

# =============================================================================
# STEP 3 - POWERCfg REGISTRY ONLY
# =============================================================================
$script:CurrentStep = 3
Write-OverallProgress -Status "PowerCfg Registry" -SubPercent 0

$script:errorLog = "$env:TEMP\sigma_powercfg_registry_errors.log"
if (Test-Path $script:errorLog) { Remove-Item $script:errorLog -Force }

$regPath    = 'HKCU:\Control Panel\PowerCfg'
$globalPath = 'HKCU:\Control Panel\PowerCfg\GlobalPowerPolicy'

# --- 3a. CurrentPowerPolicy = "4" ---
Write-SubProgress -Activity "PowerCfg Registry" -Status "Writing CurrentPowerPolicy..." -PercentComplete 25
try {
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    New-ItemProperty -Path $regPath -Name 'CurrentPowerPolicy' -Value '4' `
        -PropertyType String -Force -ErrorAction Stop | Out-Null
} catch {
    Add-Content -Path $script:errorLog -Value $_.Exception.Message
}

# --- 3b. GlobalPowerPolicy "Policies" hex ---
Write-SubProgress -Activity "PowerCfg Registry" -Status "Writing GlobalPowerPolicy..." -PercentComplete 65

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
    Add-Content -Path $script:errorLog -Value "Policies hex parsed to $($policiesBytes.Count) bytes; expected 80."
}

try {
    if (-not (Test-Path $globalPath)) { New-Item -Path $globalPath -Force | Out-Null }
    New-ItemProperty -Path $globalPath -Name 'Policies' -Value $policiesBytes `
        -PropertyType Binary -Force -ErrorAction Stop | Out-Null
} catch {
    Add-Content -Path $script:errorLog -Value $_.Exception.Message
}

Complete-SubProgress -Activity "PowerCfg Registry"
Write-OverallProgress -Status "PowerCfg Registry complete" -SubPercent 100
Write-Host "  [3/5] PowerCfg Registry ......................... DONE" -ForegroundColor Green

# =============================================================================
# STEP 4 - TELEMETRY & TRACKING REMOVAL
# =============================================================================
$script:CurrentStep = 4
Write-OverallProgress -Status "Telemetry & Tracking Removal" -SubPercent 0

$script:errorLog = "$env:TEMP\sigma_privacy_errors.log"
if (Test-Path $script:errorLog) { Remove-Item $script:errorLog -Force }

# --- 4a. Telemetry Registry keys ---
Write-SubProgress -Activity "Telemetry Removal" -Status "Removing Telemetry Registry keys..." -PercentComplete 10

$telemetryRegPaths = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
)
foreach ($path in $telemetryRegPaths) {
    New-Item -Path $path -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path $path -Name "AllowTelemetry" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
}

New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" -Name "value" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" -Name "AutoConnectAllowedOEM" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

# --- 4b. Telemetry services ---
Write-SubProgress -Activity "Telemetry Removal" -Status "Disabling Telemetry Services..." -PercentComplete 35
$telemetryServices = @("DiagTrack", "dmwappushservice")
foreach ($service in $telemetryServices) {
    Stop-Service $service -ErrorAction SilentlyContinue 2>> $script:errorLog
    Set-Service  $service -StartupType Disabled -ErrorAction SilentlyContinue 2>> $script:errorLog
}

# --- 4c. Telemetry scheduled tasks ---
Write-SubProgress -Activity "Telemetry Removal" -Status "Disabling Telemetry Scheduled Tasks..." -PercentComplete 55
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
    Disable-ScheduledTask -TaskPath (Split-Path $task -Parent) -TaskName (Split-Path $task -Leaf) `
        -ErrorAction SilentlyContinue 2>> $script:errorLog
}

# --- 4d. Background apps ---
Write-SubProgress -Activity "Telemetry Removal" -Status "Disabling Background App Tasks (global)..." -PercentComplete 75
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsRunInBackground" `
    -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

# --- 4e. Windows Error Reporting ---
Write-SubProgress -Activity "Telemetry Removal" -Status "Disabling Windows Error Reporting..." -PercentComplete 88
New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" `
    -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

Set-Service  "WerSvc" -StartupType Disabled -ErrorAction SilentlyContinue 2>> $script:errorLog
Stop-Service "WerSvc" -ErrorAction SilentlyContinue 2>> $script:errorLog

# --- 4f. Task Scheduler history log ---
Write-SubProgress -Activity "Telemetry Removal" -Status "Disabling Task Scheduler history logging..." -PercentComplete 97
wevtutil set-log "Microsoft-Windows-TaskScheduler/Operational" /enabled:false 2>> $script:errorLog

Complete-SubProgress -Activity "Telemetry Removal"
Write-OverallProgress -Status "Telemetry Removal complete" -SubPercent 100
Write-Host "  [4/5] Telemetry & Tracking Removal .............. DONE" -ForegroundColor Green

# =============================================================================
# STEP 5 - NETWORK THROTTLE (QoS)
# =============================================================================
$script:CurrentStep = 5
Write-OverallProgress -Status "Network Throttle ($netMbps Mbps)" -SubPercent 0

$script:errorLog = "$env:TEMP\sigma_netqos_errors.log"
if (Test-Path $script:errorLog) { Remove-Item $script:errorLog -Force }

$PolicyPrefix = "LimitPCto"

# --- 5a. Remove existing LimitPCto* policies ---
Write-SubProgress -Activity "Network Throttle" -Status "Removing existing LimitPCto* policies..." -PercentComplete 30
Get-NetQosPolicy -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "$PolicyPrefix*" } |
    ForEach-Object {
        Remove-NetQosPolicy -Name $_.Name -Confirm:$false -ErrorAction SilentlyContinue 2>> $script:errorLog
    }

# --- 5b. Apply new throttle ---
Write-SubProgress -Activity "Network Throttle" -Status "Applying throttle: $netMbps Mbps..." -PercentComplete 70
$bits       = [uint64]$netMbps * 1000000
$policyName = "$PolicyPrefix$netMbps"

New-NetQosPolicy -Name $policyName `
    -ThrottleRateActionBitsPerSecond $bits `
    -ErrorAction SilentlyContinue 2>> $script:errorLog

Complete-SubProgress -Activity "Network Throttle"
Write-OverallProgress -Status "Network Throttle complete" -SubPercent 100
Write-Host "  [5/5] Network Throttle ($netMbps Mbps) ........... DONE" -ForegroundColor Green

# =============================================================================
# FINAL SUMMARY - collect any errors from all step logs
# =============================================================================
Write-Progress -Id 0 -Activity "SIGMA PERFORMANCES - Applying All Optimizations" -Completed

Write-Host ""
Write-Host "========== SIGMA PERFORMANCES - SUMMARY ==========" -ForegroundColor Green

$logs = @{
    "CPU Optimization"   = "$env:TEMP\sigma_optimization_errors.log"
    "Device Cleanup"     = "$env:TEMP\sigma_device_cleanup_errors.log"
    "PowerCfg Registry"  = "$env:TEMP\sigma_powercfg_registry_errors.log"
    "Telemetry Removal"  = "$env:TEMP\sigma_privacy_errors.log"
    "Network Throttle"   = "$env:TEMP\sigma_netqos_errors.log"
}

$totalErrors = 0
foreach ($name in $logs.Keys) {
    $log = $logs[$name]
    if (Test-Path $log) {
        $errorCount = (Get-Content $log | Measure-Object -Line).Lines
        if ($errorCount -gt 0) {
            Write-Host ("  [WARN] {0,-20} : {1} errors -> {2}" -f $name, $errorCount, $log) -ForegroundColor Yellow
            $totalErrors += $errorCount
        } else {
            Remove-Item $log -Force -ErrorAction SilentlyContinue
            Write-Host ("  [ OK ] {0,-20} : clean" -f $name) -ForegroundColor Green
        }
    } else {
        Write-Host ("  [ OK ] {0,-20} : clean" -f $name) -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "[SUCCESS] ALL optimizations applied:" -ForegroundColor Green
Write-Host "   - CPU Performance Optimization" -ForegroundColor Green
Write-Host "   - Unknown + Ghost Device Cleanup" -ForegroundColor Green
Write-Host "   - PowerCfg Registry values" -ForegroundColor Green
Write-Host "   - Telemetry & Tracking Removal" -ForegroundColor Green
Write-Host "   - Network Throttle: $netMbps Mbps" -ForegroundColor Green
Write-Host ""
if ($totalErrors -gt 0) {
    Write-Host "[WARNING] $totalErrors total error lines were logged. See paths above." -ForegroundColor Yellow
} else {
    Write-Host "[INFO] No errors were reported during any step." -ForegroundColor Cyan
}
Write-Host "[INFO] System reboot is required for all changes to take effect." -ForegroundColor Yellow
Write-Host ""
Write-Host "I hope you created a restore point!" -ForegroundColor Magenta
Write-Host "Have a good day!" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# REBOOT PROMPT
# =============================================================================
$rebootChoice = Read-Host "Press R to reboot now, or Q to quit"

if ($rebootChoice -eq "R" -or $rebootChoice -eq "r") {
    shutdown /r /f /t 0
} else {
    exit 0
}