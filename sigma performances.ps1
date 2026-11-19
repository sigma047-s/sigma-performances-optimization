#Requires -RunAsAdministrator

# =============================================================================
# SIGMA PERFORMANCES - ALL-IN-ONE OPTIMIZATION SUITE
# -----------------------------------------------------------------------------
# Order:
#   1. Windows Defender  -> DISABLE or RESTORE (menu choice)
#   2. Device Cleanup   (Unknown + Ghost devices)
#   3. Telemetry Removal
#   4. PowerCfg Registry
#   5. CPU Optimization (AC / DC)
#   6. Network Throttle (QoS 1-3000 Mbps)
#
# Single 'Y' confirmation at start. Reboot prompt at end.
# =============================================================================

$script:TotalSteps  = 6
$script:CurrentStep = 0

# -----------------------------------------------------------------------------
# Progress helpers
# -----------------------------------------------------------------------------
function Write-OverallProgress {
    param([string]$Status, [int]$SubPercent = 0)
    $overall = [math]::Round((($script:CurrentStep - 1) + ($SubPercent / 100)) / $script:TotalSteps * 100)
    if ($overall -gt 100) { $overall = 100 }
    if ($overall -lt 0)   { $overall = 0 }
    Write-Progress -Id 0 `
        -Activity "SIGMA PERFORMANCES - All Optimizations" `
        -Status   "Step $($script:CurrentStep)/$($script:TotalSteps): $Status" `
        -PercentComplete $overall
}

function Write-SubProgress {
    param([string]$Activity, [string]$Status, [int]$PercentComplete)
    if ($PercentComplete -gt 100) { $PercentComplete = 100 }
    if ($PercentComplete -lt 0)   { $PercentComplete = 0 }
    Write-Progress -Id 1 -ParentId 0 `
        -Activity $Activity -Status $Status -PercentComplete $PercentComplete
}

function Complete-SubProgress {
    param([string]$Activity)
    Write-Progress -Id 1 -ParentId 0 -Activity $Activity -Completed
}

# =============================================================================
# INTRO + SINGLE CONFIRMATION
# =============================================================================
Clear-Host
Write-Host ""
Write-Host "========== SIGMA PERFORMANCES ==========" -ForegroundColor Green
Write-Host ""
Write-Host "[WARNING] This will apply ALL of the following, in order:" -ForegroundColor Yellow
Write-Host "   1. Windows Defender -> Disable OR Restore (you choose at runtime)" -ForegroundColor Yellow
Write-Host "   2. Device Cleanup (Unknown + Ghost devices)" -ForegroundColor Yellow
Write-Host "   3. Telemetry & Tracking Removal" -ForegroundColor Yellow
Write-Host "   4. PowerCfg Registry values" -ForegroundColor Yellow
Write-Host "   5. CPU Optimization (AC / DC)" -ForegroundColor Yellow
Write-Host "   6. Network Throttle (QoS)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Make sure you have a System Restore point!" -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "Proceed with ALL optimizations? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Exiting. No changes made." -ForegroundColor Cyan
    exit 0
}

Write-Host ""
Write-Host "[INFO] Applying ALL optimizations. Please wait..." -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# STEP 1 - WINDOWS DEFENDER  (DISABLE  OR  RESTORE)
# =============================================================================
$script:CurrentStep = 1
Write-OverallProgress -Status "Windows Defender" -SubPercent 0

$errorLog = "$env:TEMP\sigma_defender_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

# -----------------------------------------------------------------------------
# Helper: silently delete a value if it exists (logs failures)
# -----------------------------------------------------------------------------
function Remove-RegValue {
    param([string]$Path, [string]$Name)
    try {
        if (Test-Path $Path) {
            $prop = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $prop) {
                Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop
            }
        }
    }
    catch {
        Add-Content -Path $errorLog -Value "$Path\$Name : $($_.Exception.Message)"
    }
}

# -----------------------------------------------------------------------------
# Helper: silently write a DWORD (logs failures)
# -----------------------------------------------------------------------------
function Set-RegDword {
    param([string]$Path, [string]$Name, [int]$Value)
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Add-Content -Path $errorLog -Value "$Path\$Name : $($_.Exception.Message)"
    }
}

# =============================================================================
# FUNCTION 1 - DISABLE WINDOWS DEFENDER
#   Creates the DWORDs you specified under:
#     HKLM\SOFTWARE\Policies\Microsoft\Windows Defender
#     \Real-Time Protection  \Signature Updates  \Spynet
#   Then attempts to turn off Tamper Protection and stop/disable services.
# =============================================================================
function Disable-DefenderProtection {
    $defenderPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    $rtpPolicy      = "$defenderPolicy\Real-Time Protection"
    $sigPolicy      = "$defenderPolicy\Signature Updates"
    $spynetPolicy   = "$defenderPolicy\Spynet"
    $featuresKey    = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"

    # --- Root DWORDs = 1 ---
    Write-SubProgress -Activity "Defender Disable" -Status "Creating Defender root DWORDs..." -PercentComplete 10
    $rootValues = @(
        "DisableAntiSpyware",
        "DisableRealtimeMonitoring",
        "DisableAntiVirus",
        "DisableSpecialRunningModes",
        "DisableRoutinelyTackingAction",
        "ServiceKeepAlive"
    )
    foreach ($v in $rootValues) { Set-RegDword -Path $defenderPolicy -Name $v -Value 1 }

    # --- Real-Time Protection DWORDs = 1 ---
    Write-SubProgress -Activity "Defender Disable" -Status "Creating Real-Time Protection DWORDs..." -PercentComplete 25
    if (-not (Test-Path $rtpPolicy)) { New-Item -Path $rtpPolicy -Force | Out-Null }
    $rtpValues = @(
        "DisableBehaviorMonitoring",
        "DisableOnAccesProtection",
        "DisableRealtimeMonitoring",
        "DisableScanOnRealtimeEnable"
    )
    foreach ($v in $rtpValues) { Set-RegDword -Path $rtpPolicy -Name $v -Value 1 }

    # --- Signature Updates DWORD = 1 ---
    Write-SubProgress -Activity "Defender Disable" -Status "Creating Signature Updates DWORD..." -PercentComplete 35
    if (-not (Test-Path $sigPolicy)) { New-Item -Path $sigPolicy -Force | Out-Null }
    Set-RegDword -Path $sigPolicy -Name "ForceUpdateFromMU" -Value 1

    # --- Spynet DWORD = 1 ---
    Write-SubProgress -Activity "Defender Disable" -Status "Creating Spynet DWORD..." -PercentComplete 45
    if (-not (Test-Path $spynetPolicy)) { New-Item -Path $spynetPolicy -Force | Out-Null }
    Set-RegDword -Path $spynetPolicy -Name "DisableBlockAtFirstSeen" -Value 1

    # --- Turn off Tamper Protection (best effort; may be blocked if ON) ---
    Write-SubProgress -Activity "Defender Disable" -Status "Turning off Tamper Protection..." -PercentComplete 60
    try {
        if (-not (Test-Path $featuresKey)) { New-Item -Path $featuresKey -Force | Out-Null }
        New-ItemProperty -Path $featuresKey -Name "TamperProtection" `
            -Value 4 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        Set-RegDword -Path $defenderPolicy -Name "DisableTamperProtection" -Value 1
    }
    catch {
        Add-Content -Path $errorLog -Value "TamperProtection(disable) : $($_.Exception.Message)"
    }

    # --- Stop & disable Defender services ---
    Write-SubProgress -Activity "Defender Disable" -Status "Stopping/disabling Defender services..." -PercentComplete 75
    $services = @("WinDefend", "WdNisSvc", "Sense", "SecurityHealthService", "wscsvc")
    foreach ($name in $services) {
        try {
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue 2>> $errorLog
            Set-Service  -Name $name -StartupType Disabled -ErrorAction Stop 2>> $errorLog
        }
        catch {
            Add-Content -Path $errorLog -Value "$name : $($_.Exception.Message)"
        }
    }
}

# =============================================================================
# FUNCTION 2 - RESTORE / ENABLE WINDOWS DEFENDER
#   Deletes every DWORD created above, re-enables Tamper Protection (=5),
#   and re-starts Defender services.
# =============================================================================
function Restore-DefenderProtection {
    $defenderPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    $rtpPolicy      = "$defenderPolicy\Real-Time Protection"
    $sigPolicy      = "$defenderPolicy\Signature Updates"
    $spynetPolicy   = "$defenderPolicy\Spynet"
    $featuresKey    = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"

    # --- 1a. Root DWORDs ---
    Write-SubProgress -Activity "Defender Restore" -Status "Deleting Defender root DWORDs..." -PercentComplete 10
    $rootValues = @(
        "DisableAntiSpyware",
        "DisableRealtimeMonitoring",
        "DisableAntiVirus",
        "DisableSpecialRunningModes",
        "DisableRoutinelyTackingAction",
        "ServiceKeepAlive",
        "DisableTamperProtection"
    )
    foreach ($v in $rootValues) { Remove-RegValue -Path $defenderPolicy -Name $v }

    # --- 1b. Real-Time Protection DWORDs ---
    Write-SubProgress -Activity "Defender Restore" -Status "Deleting Real-Time Protection DWORDs..." -PercentComplete 25
    $rtpValues = @(
        "DisableBehaviorMonitoring",
        "DisableOnAccesProtection",
        "DisableRealtimeMonitoring",
        "DisableScanOnRealtimeEnable"
    )
    foreach ($v in $rtpValues) { Remove-RegValue -Path $rtpPolicy -Name $v }

    # --- 1c. Signature Updates DWORD ---
    Write-SubProgress -Activity "Defender Restore" -Status "Deleting Signature Updates DWORDs..." -PercentComplete 35
    foreach ($v in @("ForceUpdateFromMU")) { Remove-RegValue -Path $sigPolicy -Name $v }

    # --- 1d. Spynet DWORD ---
    Write-SubProgress -Activity "Defender Restore" -Status "Deleting Spynet DWORDs..." -PercentComplete 45
    foreach ($v in @("DisableBlockAtFirstSeen")) { Remove-RegValue -Path $spynetPolicy -Name $v }

    # --- 1e. Re-enable Tamper Protection (5 = enabled) ---
    Write-SubProgress -Activity "Defender Restore" -Status "Re-enabling Tamper Protection..." -PercentComplete 60
    try {
        if (-not (Test-Path $featuresKey)) { New-Item -Path $featuresKey -Force | Out-Null }
        New-ItemProperty -Path $featuresKey -Name "TamperProtection" `
            -Value 5 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    }
    catch {
        # If Tamper Protection is already ON, this write is blocked by design.
        Add-Content -Path $errorLog -Value "TamperProtection(enable) : $($_.Exception.Message)"
    }

    # --- 1f. Re-enable + start Defender services ---
    Write-SubProgress -Activity "Defender Restore" -Status "Re-enabling Defender services..." -PercentComplete 75
    $services = @(
        @{ Name = "WinDefend";             StartupType = "Automatic" },
        @{ Name = "WdNisSvc";              StartupType = "Manual"    },
        @{ Name = "Sense";                 StartupType = "Manual"    },
        @{ Name = "SecurityHealthService"; StartupType = "Manual"    },
        @{ Name = "wscsvc";                StartupType = "Automatic" }
    )
    foreach ($svc in $services) {
        try {
            Set-Service   -Name $svc.Name -StartupType $svc.StartupType -ErrorAction Stop 2>> $errorLog
            Start-Service -Name $svc.Name -ErrorAction SilentlyContinue 2>> $errorLog
        }
        catch {
            Add-Content -Path $errorLog -Value "$($svc.Name) : $($_.Exception.Message)"
        }
    }

    # --- 1g. Refresh signatures ---
    Write-SubProgress -Activity "Defender Restore" -Status "Refreshing Defender signatures..." -PercentComplete 90
    $mpCmd = Join-Path $env:ProgramFiles "Windows Defender\MpCmdRun.exe"
    if (Test-Path $mpCmd) {
        & $mpCmd -SignatureUpdate 2>> $errorLog | Out-Null
    }
}

# -----------------------------------------------------------------------------
# Step 1 – Runtime menu: Disable / Restore / Skip
# -----------------------------------------------------------------------------
Clear-Host
Write-Host ""
Write-Host "========== STEP 1 - WINDOWS DEFENDER ==========" -ForegroundColor Green
Write-Host ""
Write-Host "Choose what to do with Windows Defender:" -ForegroundColor Yellow
Write-Host "   1. DISABLE  Defender (apply policy DWORDs = 1, stop services)" -ForegroundColor White
Write-Host "   2. RESTORE  Defender (delete DWORDs, re-enable Tamper Protection)" -ForegroundColor White
Write-Host "   3. SKIP     (leave Defender untouched)" -ForegroundColor White
Write-Host ""

$defChoice = Read-Host "Enter 1, 2 or 3"

switch ($defChoice) {

    "1" {
        Write-Host ""
        Write-Host "[WARNING] Disabling Defender removes real-time protection." -ForegroundColor Red
        $verify = Read-Host "Type 'YES' to confirm DISABLE"
        if ($verify -eq "YES") {
            Disable-DefenderProtection
            Write-Host "  [1/6] Windows Defender - DISABLED ............... OK" -ForegroundColor Green
        } else {
            Write-Host "  Defender disable skipped (no confirmation)." -ForegroundColor Yellow
        }
    }

    "2" {
        Write-Host ""
        Write-Host "[INFO] Restoring Windows Defender protection..." -ForegroundColor Cyan
        Restore-DefenderProtection
        Write-Host "  [1/6] Windows Defender - RESTORED ............... OK" -ForegroundColor Green
    }

    "3" {
        Write-Host "  Defender step skipped." -ForegroundColor Yellow
    }

    default {
        Write-Host "  Invalid choice. Defender step skipped." -ForegroundColor Yellow
    }
}

# Error report
if (Test-Path $errorLog) {
    $errorCount = (Get-Content $errorLog | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "  [WARNING] $errorCount errors occurred. Check log: $errorLog" -ForegroundColor Yellow
    } else {
        Remove-Item $errorLog -Force
    }
}

Complete-SubProgress -Activity "Windows Defender"
Write-OverallProgress -Status "Windows Defender step complete" -SubPercent 100

# =============================================================================
# STEP 2 - REMOVE UNKNOWN + GHOST DEVICES
# =============================================================================
$script:CurrentStep = 2
Write-OverallProgress -Status "Device Cleanup" -SubPercent 0

$errorLog = "$env:TEMP\sigma_device_cleanup_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

# --- 2a. Unknown devices (auto) ---
Write-SubProgress -Activity "Device Cleanup" -Status "Searching for 'Unknown' status devices..." -PercentComplete 5
$unknownDevices = @(Get-PnpDevice | Where-Object { $_.Status -eq 'Unknown' })

if ($unknownDevices.Count -eq 0) {
    Write-SubProgress -Activity "Device Cleanup" -Status "No unknown devices found." -PercentComplete 25
} else {
    $i = 0; $n = $unknownDevices.Count
    foreach ($dev in $unknownDevices) {
        $i++
        $pct = 5 + [math]::Round($i / $n * 20)
        Write-SubProgress -Activity "Device Cleanup" -Status "Removing unknown: $($dev.FriendlyName) ($i/$n)" -PercentComplete $pct
        pnputil /remove-device $dev.InstanceId 2>> $errorLog | Out-Null
    }
}

# --- 2b. Ghost devices (with YES prompt - preserved from original) ---
Write-SubProgress -Activity "Device Cleanup" -Status "Searching for non-present 'ghost' devices..." -PercentComplete 30
$ghostDevices = @(Get-PnpDevice | Where-Object { $_.Present -eq $false })

if ($ghostDevices.Count -eq 0) {
    Write-SubProgress -Activity "Device Cleanup" -Status "No ghost devices found." -PercentComplete 75
} else {
    Complete-SubProgress -Activity "Device Cleanup"
    Write-Host ""
    Write-Host "  Ghost devices found:" -ForegroundColor Cyan
    foreach ($dev in $ghostDevices) {
        Write-Host "    - $($dev.FriendlyName) (Status: $($dev.Status))" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "[WARNING] Removing ghost devices can break old configurations." -ForegroundColor Red
    $ghostConfirm = Read-Host "Proceed with ghost device removal? (Type 'YES' to confirm)"

    if ($ghostConfirm -eq "YES") {
        $i = 0; $n = $ghostDevices.Count
        foreach ($dev in $ghostDevices) {
            $i++
            $pct = 30 + [math]::Round($i / $n * 45)
            Write-SubProgress -Activity "Device Cleanup" -Status "Removing ghost: $($dev.FriendlyName) ($i/$n)" -PercentComplete $pct
            pnputil /remove-device $dev.InstanceId 2>> $errorLog | Out-Null
        }
    } else {
        Write-Host "  Ghost device removal skipped." -ForegroundColor Yellow
    }
}

# --- 2c. Rescan for new hardware ---
Write-SubProgress -Activity "Device Cleanup" -Status "Rescanning for hardware changes..." -PercentComplete 95
pnputil /scan-devices 2>> $errorLog | Out-Null

# Error report (preserved from original script)
if (Test-Path $errorLog) {
    $errorCount = (Get-Content $errorLog | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "  [WARNING] $errorCount errors occurred. Check log: $errorLog" -ForegroundColor Yellow
    } else {
        Remove-Item $errorLog -Force
    }
}

Complete-SubProgress -Activity "Device Cleanup"
Write-OverallProgress -Status "Device Cleanup complete" -SubPercent 100
Write-Host "  [2/6] Device Cleanup ............................ DONE" -ForegroundColor Green

# =============================================================================
# STEP 3 - TELEMETRY & TRACKING REMOVAL
# =============================================================================
$script:CurrentStep = 3
Write-OverallProgress -Status "Telemetry & Tracking Removal" -SubPercent 0

$errorLog = "$env:TEMP\sigma_privacy_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

# --- 3a. Telemetry Registry keys ---
Write-SubProgress -Activity "Telemetry Removal" -Status "Removing Telemetry Registry keys..." -PercentComplete 5

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

# --- 3b. Telemetry services ---
Write-SubProgress -Activity "Telemetry Removal" -Status "Disabling Telemetry Services..." -PercentComplete 30
$telemetryServices = @("DiagTrack", "dmwappushservice")
foreach ($service in $telemetryServices) {
    Stop-Service $service -ErrorAction SilentlyContinue 2>> $errorLog
    Set-Service  $service -StartupType Disabled -ErrorAction SilentlyContinue 2>> $errorLog
}

# --- 3c. Telemetry scheduled tasks ---
Write-SubProgress -Activity "Telemetry Removal" -Status "Disabling Telemetry Scheduled Tasks..." -PercentComplete 50
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

# --- 3d. Background App tasks (global) ---
Write-SubProgress -Activity "Telemetry Removal" -Status "Disabling Background App Tasks (global)..." -PercentComplete 70
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsRunInBackground" -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

# --- 3e. Windows Error Reporting ---
Write-SubProgress -Activity "Telemetry Removal" -Status "Disabling Windows Error Reporting..." -PercentComplete 85
New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

Set-Service  "WerSvc" -StartupType Disabled -ErrorAction SilentlyContinue 2>> $errorLog
Stop-Service "WerSvc" -ErrorAction SilentlyContinue 2>> $errorLog

# --- 3f. Task Scheduler history logging ---
Write-SubProgress -Activity "Telemetry Removal" -Status "Disabling Task Scheduler history logging..." -PercentComplete 95
wevtutil set-log "Microsoft-Windows-TaskScheduler/Operational" /enabled:false 2>> $errorLog

# Error report
if (Test-Path $errorLog) {
    $errorCount = (Get-Content $errorLog | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "  [WARNING] $errorCount errors occurred. Check log: $errorLog" -ForegroundColor Yellow
    } else {
        Remove-Item $errorLog -Force
    }
}

Complete-SubProgress -Activity "Telemetry Removal"
Write-OverallProgress -Status "Telemetry Removal complete" -SubPercent 100
Write-Host "  [3/6] Telemetry & Tracking Removal .............. DONE" -ForegroundColor Green

# =============================================================================
# STEP 4 - POWERCfg REGISTRY ONLY
# =============================================================================
$script:CurrentStep = 4
Write-OverallProgress -Status "PowerCfg Registry" -SubPercent 0

$errorLog = "$env:TEMP\sigma_powercfg_registry_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

# Helper (preserved from original script)
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
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Add-Content -Path $errorLog -Value $_.Exception.Message
    }
}

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
    Add-Content -Path $errorLog -Value "Policies hex parsed to $($policiesBytes.Count) bytes; expected 80."
}

# --- 4a. CurrentPowerPolicy = "4" ---
Write-SubProgress -Activity "PowerCfg Registry" -Status "Writing CurrentPowerPolicy = '4'..." -PercentComplete 30
Set-RegistryValue -Path $regPath -Name 'CurrentPowerPolicy' -Value '4' -Type String

# --- 4b. GlobalPowerPolicy "Policies" hex ---
Write-SubProgress -Activity "PowerCfg Registry" -Status "Writing GlobalPowerPolicy 'Policies' hex..." -PercentComplete 70
Set-RegistryValue -Path $globalPath -Name 'Policies' -Value $policiesBytes -Type Binary

# Error report
if (Test-Path $errorLog) {
    $errorCount = (Get-Content $errorLog | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "  [WARNING] $errorCount errors occurred. Check log: $errorLog" -ForegroundColor Yellow
    } else {
        Remove-Item $errorLog -Force
    }
}

Complete-SubProgress -Activity "PowerCfg Registry"
Write-OverallProgress -Status "PowerCfg Registry complete" -SubPercent 100
Write-Host "  [4/6] PowerCfg Registry ......................... DONE" -ForegroundColor Green

# =============================================================================
# STEP 5 - CPU OPTIMIZATION (AC / DC)
# =============================================================================
$script:CurrentStep = 5
Write-OverallProgress -Status "CPU Optimization" -SubPercent 0

$errorLog = "$env:TEMP\sigma_optimization_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

# Save current active power scheme GUID (preserved)
$originalScheme = (powercfg -getactivescheme) -replace '.*\s([A-F0-9\-]{36}).*', '$1'

# --- 5a. Activate Ultimate Performance power scheme ---
Write-SubProgress -Activity "CPU Optimization" -Status "Activating Ultimate Performance scheme..." -PercentComplete 3
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>> $errorLog
powercfg -setactive       e9a42b02-d5df-448d-aa00-03f14749eb61 2>> $errorLog

# --- 5b. CPU / Processor settings ---
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
    $pct = 5 + [math]::Round($cpuIndex / $cpuTotal * 93)
    Write-SubProgress -Activity "CPU Optimization" -Status "Applying: $key ($cpuIndex/$cpuTotal)" -PercentComplete $pct
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR $key $cpuSettings[$key] 2>> $errorLog
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR $key $cpuSettings[$key] 2>> $errorLog
}

# --- 5c. Extra processor GUID ---
Write-SubProgress -Activity "CPU Optimization" -Status "Applying extra processor GUID..." -PercentComplete 98
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 94d3a615-a899-4ac5-ae2b-e4d8f634367f 1 2>> $errorLog
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 94d3a615-a899-4ac5-ae2b-e4d8f634367f 1 2>> $errorLog

# --- 5d. Final commit ---
Write-SubProgress -Activity "CPU Optimization" -Status "Committing power scheme..." -PercentComplete 99
powercfg -setactive SCHEME_CURRENT 2>> $errorLog

# Error report
if (Test-Path $errorLog) {
    $errorCount = (Get-Content $errorLog | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "  [WARNING] $errorCount errors occurred. Check log: $errorLog" -ForegroundColor Yellow
    } else {
        Remove-Item $errorLog -Force
    }
}

Complete-SubProgress -Activity "CPU Optimization"
Write-OverallProgress -Status "CPU Optimization complete" -SubPercent 100
Write-Host "  [5/6] CPU Optimization .......................... DONE" -ForegroundColor Green

# =============================================================================
# STEP 6 - NETWORK THROTTLE (QoS) - menu preserved from original
# =============================================================================
$script:CurrentStep = 6
Write-OverallProgress -Status "Network Throttle" -SubPercent 0

$PolicyPrefix = "LimitPCto"
$MinMbps      = 1
$MaxMbps      = 3000

$errorLog = "$env:TEMP\sigma_netqos_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

function Set-QosLimit {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 3000)]
        [int]$Mbps
    )
    $bits       = [uint64]$Mbps * 1000000
    $policyName = "$PolicyPrefix$Mbps"

    Get-NetQosPolicy -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$PolicyPrefix*" } |
        ForEach-Object {
            Remove-NetQosPolicy -Name $_.Name -Confirm:$false -ErrorAction SilentlyContinue 2>> $errorLog
        }

    New-NetQosPolicy -Name $policyName `
        -ThrottleRateActionBitsPerSecond $bits `
        -ErrorAction SilentlyContinue 2>> $errorLog
}

function Remove-AllLimits {
    $policies = Get-NetQosPolicy -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$PolicyPrefix*" }

    if (-not $policies) {
        Write-Host "[INFO] No '$PolicyPrefix*' QoS policy is applied." -ForegroundColor DarkGray
        return
    }

    foreach ($p in $policies) {
        Remove-NetQosPolicy -Name $p.Name -Confirm:$false -ErrorAction SilentlyContinue 2>> $errorLog
        Write-Host "[REMOVED] $($p.Name)" -ForegroundColor Green
    }
}

function Show-AllLimits {
    $policies = Get-NetQosPolicy -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$PolicyPrefix*" }

    if (-not $policies) {
        Write-Host "[INFO] No '$PolicyPrefix*' QoS policy is applied." -ForegroundColor DarkGray
        return
    }

    foreach ($p in $policies) {
        $bits = $null
        if ($p.PSObject.Properties.Name -contains 'ThrottleRateActionBitsPerSecond') {
            $bits = [uint64]$p.ThrottleRateActionBitsPerSecond
        }
        elseif ($p.PSObject.Properties.Name -contains 'ThrottleRateAction') {
            $bits = [uint64]$p.ThrottleRateAction
        }

        if ($bits -gt 0) {
            $mbps = [math]::Round($bits / 1000000, 3)
            Write-Host "[ACTIVE] $($p.Name)  ->  $mbps Mbps ($bits bits/s)" -ForegroundColor Cyan
        } else {
            Write-Host "[ACTIVE] $($p.Name)  ->  unknown" -ForegroundColor Cyan
        }
    }
}

function Show-Menu {
    Write-Host ""
    Write-Host "1. Apply throttle ($MinMbps-$MaxMbps Mbps)" -ForegroundColor White
    Write-Host "2. Remove all throttles" -ForegroundColor White
    Write-Host "3. Show applied throttles" -ForegroundColor White
    Write-Host "4. Quit" -ForegroundColor White
    Write-Host ""
}

do {
    Show-Menu
    $choice = Read-Host "Choose an option (1-4)"

    switch ($choice) {
        "1" {
            $inputMbps = Read-Host "Enter Mbps ($MinMbps-$MaxMbps)"
            if ($inputMbps -match '^\d+$') {
                $mbpsInt = [int]$inputMbps
                if ($mbpsInt -ge $MinMbps -and $mbpsInt -le $MaxMbps) {
                    Write-SubProgress -Activity "Network Throttle" -Status "Applying throttle: $mbpsInt Mbps..." -PercentComplete 50
                    Set-QosLimit -Mbps $mbpsInt
                    Write-SubProgress -Activity "Network Throttle" -Status "Throttle applied." -PercentComplete 100
                }
                else {
                    Write-Host "[ERROR] Value must be between $MinMbps and $MaxMbps." -ForegroundColor Red
                }
            }
            else {
                Write-Host "[ERROR] Enter a whole number." -ForegroundColor Red
            }
        }

        "2" {
            Write-SubProgress -Activity "Network Throttle" -Status "Removing all '$PolicyPrefix*' policies..." -PercentComplete 50
            Remove-AllLimits
            Write-SubProgress -Activity "Network Throttle" -Status "Throttles removed." -PercentComplete 100
        }

        "3" {
            Write-Host ""
            Write-Host "[INFO] Currently applied throttles:" -ForegroundColor Cyan
            Show-AllLimits
        }

        "4" {
            Write-SubProgress -Activity "Network Throttle" -Status "No change selected." -PercentComplete 100
        }

        default {
            Write-Host "[ERROR] Invalid choice." -ForegroundColor Red
        }
    }
} until ($choice -eq "4")

# Error report
if (Test-Path $errorLog) {
    $errorCount = (Get-Content $errorLog | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "  [WARNING] $errorCount errors occurred. Check log: $errorLog" -ForegroundColor Yellow
    } else {
        Remove-Item $errorLog -Force
    }
}

Complete-SubProgress -Activity "Network Throttle"
Write-OverallProgress -Status "Network Throttle complete" -SubPercent 100
Write-Host "  [6/6] Network Throttle .......................... DONE" -ForegroundColor Green

# =============================================================================
# FINAL SUMMARY
# =============================================================================
Write-Progress -Id 0 -Activity "SIGMA PERFORMANCES - All Optimizations" -Completed

Write-Host ""
Write-Host "========== SIGMA PERFORMANCES - SUMMARY ==========" -ForegroundColor Green
Write-Host "   [1/6] Windows Defender (disable / restore) ...... OK" -ForegroundColor Green
Write-Host "   [2/6] Device Cleanup ............................ OK" -ForegroundColor Green
Write-Host "   [3/6] Telemetry & Tracking Removal .............. OK" -ForegroundColor Green
Write-Host "   [4/6] PowerCfg Registry ......................... OK" -ForegroundColor Green
Write-Host "   [5/6] CPU Optimization .......................... OK" -ForegroundColor Green
Write-Host "   [6/6] Network Throttle .......................... OK" -ForegroundColor Green
Write-Host ""
Write-Host "[SUCCESS] All optimizations applied." -ForegroundColor Green
Write-Host "[INFO] System reboot required." -ForegroundColor Yellow
Write-Host ""
Write-Host "I hope you created a restore point!" -ForegroundColor Magenta
Write-Host "Have a good day!" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# REBOOT PROMPT (single, at the end)
# =============================================================================
$rebootChoice = Read-Host "Press R to reboot now, or Q to quit"

if ($rebootChoice -eq "R" -or $rebootChoice -eq "r") {
    shutdown /r /f /t 0
} else {
    exit 0
}
