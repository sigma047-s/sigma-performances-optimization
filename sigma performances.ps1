#Requires -RunAsAdministrator

# =============================================================================
# SIGMA PERFORMANCES - ALL-IN-ONE OPTIMIZATION SUITE
# -----------------------------------------------------------------------------
# Order:
#   1. Windows Defender  -> DISABLE or RESTORE (menu choice)
#   2. Device Cleanup    (Unknown + Ghost devices)
#   3. Telemetry Removal
#   4. PowerCfg Registry
#   5. CPU Optimization  (AC / DC)
#   6. Windows Update    -> DISABLE AUTO or RESTORE (menu choice)
#   7. Search Indexing   -> DISABLE or RESTORE (menu choice)
#
# Single 'Y' confirmation at start. Reboot prompt at end.
# =============================================================================

$script:TotalSteps  = 7
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

function Reset-AllProgress {
    Write-Progress -Id 1 -ParentId 0 -Activity " " -Completed
    Write-Progress -Id 0 -Activity " " -Completed
}

# =============================================================================
# INTRO + SINGLE CONFIRMATION
# =============================================================================
Reset-AllProgress
Clear-Host
Write-Host ""
Write-Host "========== SIGMA PERFORMANCES ==========" -ForegroundColor Green
Write-Host ""
Write-Host "[WARNING] This will apply ALL of the following, in order:" -ForegroundColor Yellow
Write-Host "   1. Windows Defender  -> Disable OR Restore (you choose at runtime)" -ForegroundColor Yellow
Write-Host "   2. Device Cleanup    (Unknown + Ghost devices)" -ForegroundColor Yellow
Write-Host "   3. Telemetry & Tracking Removal" -ForegroundColor Yellow
Write-Host "   4. PowerCfg Registry values" -ForegroundColor Yellow
Write-Host "   5. CPU Optimization  (AC / DC)" -ForegroundColor Yellow
Write-Host "   6. Windows Update    -> Disable Auto OR Restore (you choose at runtime)" -ForegroundColor Yellow
Write-Host "   7. Search Indexing   -> Disable OR Restore (you choose at runtime)" -ForegroundColor Yellow
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

function Disable-DefenderProtection {
    $defenderPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    $rtpPolicy      = "$defenderPolicy\Real-Time Protection"
    $sigPolicy      = "$defenderPolicy\Signature Updates"
    $spynetPolicy   = "$defenderPolicy\Spynet"
    $featuresKey    = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"

    Write-SubProgress -Activity "Defender Disable" -Status "Creating Defender root DWORDs..." -PercentComplete 10
    $rootValues = @(
        "DisableAntiSpyware","DisableRealtimeMonitoring","DisableAntiVirus",
        "DisableSpecialRunningModes","DisableRoutinelyTackingAction","ServiceKeepAlive"
    )
    foreach ($v in $rootValues) { Set-RegDword -Path $defenderPolicy -Name $v -Value 1 }

    Write-SubProgress -Activity "Defender Disable" -Status "Creating Real-Time Protection DWORDs..." -PercentComplete 25
    if (-not (Test-Path $rtpPolicy)) { New-Item -Path $rtpPolicy -Force | Out-Null }
    $rtpValues = @("DisableBehaviorMonitoring","DisableOnAccesProtection","DisableRealtimeMonitoring","DisableScanOnRealtimeEnable")
    foreach ($v in $rtpValues) { Set-RegDword -Path $rtpPolicy -Name $v -Value 1 }

    Write-SubProgress -Activity "Defender Disable" -Status "Creating Signature Updates DWORD..." -PercentComplete 35
    if (-not (Test-Path $sigPolicy)) { New-Item -Path $sigPolicy -Force | Out-Null }
    Set-RegDword -Path $sigPolicy -Name "ForceUpdateFromMU" -Value 1

    Write-SubProgress -Activity "Defender Disable" -Status "Creating Spynet DWORD..." -PercentComplete 45
    if (-not (Test-Path $spynetPolicy)) { New-Item -Path $spynetPolicy -Force | Out-Null }
    Set-RegDword -Path $spynetPolicy -Name "DisableBlockAtFirstSeen" -Value 1

    Write-SubProgress -Activity "Defender Disable" -Status "Turning off Tamper Protection..." -PercentComplete 60
    try {
        if (-not (Test-Path $featuresKey)) { New-Item -Path $featuresKey -Force | Out-Null }
        New-ItemProperty -Path $featuresKey -Name "TamperProtection" -Value 4 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        Set-RegDword -Path $defenderPolicy -Name "DisableTamperProtection" -Value 1
    }
    catch { Add-Content -Path $errorLog -Value "TamperProtection(disable) : $($_.Exception.Message)" }

    Write-SubProgress -Activity "Defender Disable" -Status "Stopping/disabling Defender services..." -PercentComplete 75
    $services = @("WinDefend","WdNisSvc","Sense","SecurityHealthService","wscsvc")
    foreach ($name in $services) {
        try {
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue 2>> $errorLog
            Set-Service  -Name $name -StartupType Disabled -ErrorAction Stop 2>> $errorLog
        }
        catch { Add-Content -Path $errorLog -Value "$name : $($_.Exception.Message)" }
    }
}

function Restore-DefenderProtection {
    $defenderPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    $rtpPolicy      = "$defenderPolicy\Real-Time Protection"
    $sigPolicy      = "$defenderPolicy\Signature Updates"
    $spynetPolicy   = "$defenderPolicy\Spynet"
    $featuresKey    = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"

    Write-SubProgress -Activity "Defender Restore" -Status "Deleting Defender root DWORDs..." -PercentComplete 10
    $rootValues = @(
        "DisableAntiSpyware","DisableRealtimeMonitoring","DisableAntiVirus",
        "DisableSpecialRunningModes","DisableRoutinelyTackingAction","ServiceKeepAlive","DisableTamperProtection"
    )
    foreach ($v in $rootValues) { Remove-RegValue -Path $defenderPolicy -Name $v }

    Write-SubProgress -Activity "Defender Restore" -Status "Deleting Real-Time Protection DWORDs..." -PercentComplete 40
    $rtpValues = @("DisableBehaviorMonitoring","DisableOnAccesProtection","DisableRealtimeMonitoring","DisableScanOnRealtimeEnable")
    foreach ($v in $rtpValues) { Remove-RegValue -Path $rtpPolicy -Name $v }

    Write-SubProgress -Activity "Defender Restore" -Status "Deleting Signature Updates DWORD..." -PercentComplete 60
    foreach ($v in @("ForceUpdateFromMU")) { Remove-RegValue -Path $sigPolicy -Name $v }

    Write-SubProgress -Activity "Defender Restore" -Status "Deleting Spynet DWORD..." -PercentComplete 75
    foreach ($v in @("DisableBlockAtFirstSeen")) { Remove-RegValue -Path $spynetPolicy -Name $v }

    Write-SubProgress -Activity "Defender Restore" -Status "Deleting TamperProtection DWORD..." -PercentComplete 90
    Remove-RegValue -Path $featuresKey -Name "TamperProtection"
}

Reset-AllProgress
Clear-Host
Write-Host ""
Write-Host "========== STEP 1 - WINDOWS DEFENDER ==========" -ForegroundColor Green
Write-Host ""
Write-Host "Choose what to do with Windows Defender:" -ForegroundColor Yellow
Write-Host ""
Write-Host "   1) DISABLE  - write policy DWORDs = 1 and stop Defender services" -ForegroundColor White
Write-Host "   2) RESTORE  - delete only the DWORD values added by this script" -ForegroundColor White
Write-Host "   3) SKIP     - leave Windows Defender untouched" -ForegroundColor White
Write-Host ""
Write-Host "   Tip: use RESTORE only after you previously ran DISABLE." -ForegroundColor DarkGray
Write-Host ""

$defChoice = Read-Host "Enter 1, 2 or 3"

switch ($defChoice) {
    "1" {
        Write-Host ""
        Write-Host "[WARNING] Disabling Defender removes real-time protection." -ForegroundColor Red
        $verify = Read-Host "Type 'YES' to confirm DISABLE"
        if ($verify -eq "YES") {
            Disable-DefenderProtection
            Write-Host "  [1/7] Windows Defender - DISABLED ............... OK" -ForegroundColor Green
        } else {
            Write-Host "  Defender disable skipped (no confirmation)." -ForegroundColor Yellow
        }
    }
    "2" {
        Write-Host ""
        Write-Host "[INFO] Removing Defender DWORD values..." -ForegroundColor Cyan
        Restore-DefenderProtection
        Write-Host "  [1/7] Windows Defender - RESTORED ............... OK" -ForegroundColor Green
    }
    "3" { Write-Host "  Defender step skipped." -ForegroundColor Yellow }
    default { Write-Host "  Invalid choice. Defender step skipped." -ForegroundColor Yellow }
}

if (Test-Path $errorLog) {
    $errorCount = (Get-Content $errorLog | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "  [WARNING] $errorCount errors occurred. Check log: $errorLog" -ForegroundColor Yellow
    } else { Remove-Item $errorLog -Force }
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

Write-SubProgress -Activity "Device Cleanup" -Status "Searching for non-present 'ghost' devices..." -PercentComplete 30
$ghostDevices = @(Get-PnpDevice | Where-Object { $_.Present -eq $false })

if ($ghostDevices.Count -eq 0) {
    Write-SubProgress -Activity "Device Cleanup" -Status "No ghost devices found." -PercentComplete 75
} else {
    Reset-AllProgress
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

Write-SubProgress -Activity "Device Cleanup" -Status "Rescanning for hardware changes..." -PercentComplete 95
pnputil /scan-devices 2>> $errorLog | Out-Null

if (Test-Path $errorLog) {
    $errorCount = (Get-Content $errorLog | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "  [WARNING] $errorCount errors occurred. Check log: $errorLog" -ForegroundColor Yellow
    } else { Remove-Item $errorLog -Force }
}

Complete-SubProgress -Activity "Device Cleanup"
Write-OverallProgress -Status "Device Cleanup complete" -SubPercent 100
Write-Host "  [2/7] Device Cleanup ............................ DONE" -ForegroundColor Green

# =============================================================================
# STEP 3 - TELEMETRY & TRACKING REMOVAL
# =============================================================================
$script:CurrentStep = 3
Write-OverallProgress -Status "Telemetry & Tracking Removal" -SubPercent 0

$errorLog = "$env:TEMP\sigma_privacy_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

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

Write-SubProgress -Activity "Telemetry Removal" -Status "Disabling Telemetry Services..." -PercentComplete 30
$telemetryServices = @("DiagTrack", "dmwappushservice")
foreach ($service in $telemetryServices) {
    Stop-Service $service -ErrorAction SilentlyContinue 2>> $errorLog
    Set-Service  $service -StartupType Disabled -ErrorAction SilentlyContinue 2>> $errorLog
}

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

Write-SubProgress -Activity "Telemetry Removal" -Status "Disabling Background App Tasks (global)..." -PercentComplete 70
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsRunInBackground" -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

Write-SubProgress -Activity "Telemetry Removal" -Status "Disabling Windows Error Reporting..." -PercentComplete 85
New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

Set-Service  "WerSvc" -StartupType Disabled -ErrorAction SilentlyContinue 2>> $errorLog
Stop-Service "WerSvc" -ErrorAction SilentlyContinue 2>> $errorLog

Write-SubProgress -Activity "Telemetry Removal" -Status "Disabling Task Scheduler history logging..." -PercentComplete 95
wevtutil set-log "Microsoft-Windows-TaskScheduler/Operational" /enabled:false 2>> $errorLog

if (Test-Path $errorLog) {
    $errorCount = (Get-Content $errorLog | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "  [WARNING] $errorCount errors occurred. Check log: $errorLog" -ForegroundColor Yellow
    } else { Remove-Item $errorLog -Force }
}

Complete-SubProgress -Activity "Telemetry Removal"
Write-OverallProgress -Status "Telemetry Removal complete" -SubPercent 100
Write-Host "  [3/7] Telemetry & Tracking Removal .............. DONE" -ForegroundColor Green

# =============================================================================
# STEP 4 - POWERCfg REGISTRY ONLY
# =============================================================================
$script:CurrentStep = 4
Write-OverallProgress -Status "PowerCfg Registry" -SubPercent 0

$errorLog = "$env:TEMP\sigma_powercfg_registry_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

function Set-RegistryValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type)
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
    }
    catch { Add-Content -Path $errorLog -Value $_.Exception.Message }
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
    $policiesHex -split ',' | ForEach-Object { [Convert]::ToByte($_.Trim(), 16) }
)

if ($policiesBytes.Count -ne 80) {
    Add-Content -Path $errorLog -Value "Policies hex parsed to $($policiesBytes.Count) bytes; expected 80."
}

Write-SubProgress -Activity "PowerCfg Registry" -Status "Writing CurrentPowerPolicy = '4'..." -PercentComplete 30
Set-RegistryValue -Path $regPath -Name 'CurrentPowerPolicy' -Value '4' -Type String

Write-SubProgress -Activity "PowerCfg Registry" -Status "Writing GlobalPowerPolicy 'Policies' hex..." -PercentComplete 70
Set-RegistryValue -Path $globalPath -Name 'Policies' -Value $policiesBytes -Type Binary

if (Test-Path $errorLog) {
    $errorCount = (Get-Content $errorLog | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "  [WARNING] $errorCount errors occurred. Check log: $errorLog" -ForegroundColor Yellow
    } else { Remove-Item $errorLog -Force }
}

Complete-SubProgress -Activity "PowerCfg Registry"
Write-OverallProgress -Status "PowerCfg Registry complete" -SubPercent 100
Write-Host "  [4/7] PowerCfg Registry ......................... DONE" -ForegroundColor Green

# =============================================================================
# STEP 5 - CPU OPTIMIZATION (AC / DC)
# =============================================================================
$script:CurrentStep = 5
Write-OverallProgress -Status "CPU Optimization" -SubPercent 0

$errorLog = "$env:TEMP\sigma_optimization_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

$originalScheme = (powercfg -getactivescheme) -replace '.*\s([A-F0-9\-]{36}).*', '$1'

Write-SubProgress -Activity "CPU Optimization" -Status "Activating Ultimate Performance scheme..." -PercentComplete 3
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>> $errorLog
powercfg -setactive       e9a42b02-d5df-448d-aa00-03f14749eb61 2>> $errorLog

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

Write-SubProgress -Activity "CPU Optimization" -Status "Applying extra processor GUID..." -PercentComplete 98
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 94d3a615-a899-4ac5-ae2b-e4d8f634367f 1 2>> $errorLog
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 94d3a615-a899-4ac5-ae2b-e4d8f634367f 1 2>> $errorLog

Write-SubProgress -Activity "CPU Optimization" -Status "Committing power scheme..." -PercentComplete 99
powercfg -setactive SCHEME_CURRENT 2>> $errorLog

if (Test-Path $errorLog) {
    $errorCount = (Get-Content $errorLog | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "  [WARNING] $errorCount errors occurred. Check log: $errorLog" -ForegroundColor Yellow
    } else { Remove-Item $errorLog -Force }
}

Complete-SubProgress -Activity "CPU Optimization"
Write-OverallProgress -Status "CPU Optimization complete" -SubPercent 100
Write-Host "  [5/7] CPU Optimization .......................... DONE" -ForegroundColor Green

# =============================================================================
# STEP 6 - WINDOWS UPDATE  (DISABLE AUTO  OR  RESTORE)
# =============================================================================
$script:CurrentStep = 6
Write-OverallProgress -Status "Windows Update" -SubPercent 0

$errorLog = "$env:TEMP\sigma_windows_update_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

# Shared paths / lists used by Disable & Restore
$wuPolicy    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$wuAuPolicy  = "$wuPolicy\AU"
$wuTaskPaths = @(
    "\Microsoft\Windows\UpdateOrchestrator\",
    "\Microsoft\Windows\WindowsUpdate\",
    "\Microsoft\Windows\InstallService\"
)
$wuServices        = @("wuauserv", "UsoSvc", "BITS", "DoSvc", "WaaSMedicSvc")
$wuServiceSnapshot = "$env:TEMP\sigma_wu_services_snapshot.json"

# =============================================================================
# FUNCTION - DISABLE WINDOWS UPDATE (auto only, manual still works)
# =============================================================================
function Disable-WindowsUpdateAuto {
    Write-SubProgress -Activity "Windows Update Disable" -Status "Saving service startup snapshot..." -PercentComplete 5
    try {
        $snap = @{}
        foreach ($svc in $wuServices) {
            $wmi = Get-CimInstance Win32_Service -Filter "Name='$svc'" -ErrorAction SilentlyContinue
            if ($wmi) { $snap[$svc] = $wmi.StartMode }
        }
        $snap | ConvertTo-Json | Set-Content -Path $wuServiceSnapshot -Force
    }
    catch { Add-Content -Path $errorLog -Value "Service snapshot : $($_.Exception.Message)" }

    Write-SubProgress -Activity "Windows Update Disable" -Status "Writing NoAutoUpdate policy..." -PercentComplete 20
    try {
        if (-not (Test-Path $wuAuPolicy)) { New-Item -Path $wuAuPolicy -Force | Out-Null }
        New-ItemProperty -Path $wuAuPolicy -Name "NoAutoUpdate" -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $wuAuPolicy -Name "AUOptions"    -Value 2 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    }
    catch { Add-Content -Path $errorLog -Value "AU policy : $($_.Exception.Message)" }

    Write-SubProgress -Activity "Windows Update Disable" -Status "Disabling UpdateOrchestrator tasks..." -PercentComplete 45
    foreach ($path in $wuTaskPaths) {
        try {
            Get-ScheduledTask -TaskPath $path -ErrorAction SilentlyContinue |
                Disable-ScheduledTask -ErrorAction SilentlyContinue 2>> $errorLog | Out-Null
        }
        catch { Add-Content -Path $errorLog -Value "Tasks($path) : $($_.Exception.Message)" }
    }

    Write-SubProgress -Activity "Windows Update Disable" -Status "Setting update services to Manual..." -PercentComplete 75
    foreach ($svc in $wuServices) {
        try {
            if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue 2>> $errorLog
                Set-Service  -Name $svc -StartupType Manual -ErrorAction Stop 2>> $errorLog
            }
        }
        catch { Add-Content -Path $errorLog -Value "$svc : $($_.Exception.Message)" }
    }
}

# =============================================================================
# FUNCTION - RESTORE WINDOWS UPDATE
# =============================================================================
function Restore-WindowsUpdateAuto {
    Write-SubProgress -Activity "Windows Update Restore" -Status "Removing NoAutoUpdate / AUOptions..." -PercentComplete 20
    foreach ($v in @("NoAutoUpdate", "AUOptions")) {
        Remove-RegValue -Path $wuAuPolicy -Name $v
    }

    Write-SubProgress -Activity "Windows Update Restore" -Status "Re-enabling update tasks..." -PercentComplete 50
    foreach ($path in $wuTaskPaths) {
        try {
            Get-ScheduledTask -TaskPath $path -ErrorAction SilentlyContinue |
                Enable-ScheduledTask -ErrorAction SilentlyContinue 2>> $errorLog | Out-Null
        }
        catch { Add-Content -Path $errorLog -Value "Tasks($path) : $($_.Exception.Message)" }
    }

    Write-SubProgress -Activity "Windows Update Restore" -Status "Restoring service startup types..." -PercentComplete 80
    $snap = @{}
    if (Test-Path $wuServiceSnapshot) {
        try { $snap = Get-Content $wuServiceSnapshot -Raw | ConvertFrom-Json } catch { $snap = @{} }
    }
    $defaults = @{
        "wuauserv"     = "Manual"
        "UsoSvc"       = "Automatic"
        "BITS"         = "Manual"
        "DoSvc"        = "Automatic"
        "WaaSMedicSvc" = "Manual"
    }
    foreach ($svc in $wuServices) {
        if (-not (Get-Service -Name $svc -ErrorAction SilentlyContinue)) { continue }
        $target = $null
        if ($snap.PSObject.Properties.Name -contains $svc) { $target = $snap.$svc }
        elseif ($defaults.ContainsKey($svc))              { $target = $defaults[$svc] }
        if (-not $target) { continue }

        switch ($target) {
            "Auto"     { $target = "Automatic" }
            "Manual"   { $target = "Manual" }
            "Disabled" { $target = "Disabled" }
        }
        try {
            Set-Service -Name $svc -StartupType $target -ErrorAction Stop 2>> $errorLog
            if ($svc -in @("wuauserv", "UsoSvc", "BITS")) {
                Start-Service -Name $svc -ErrorAction SilentlyContinue 2>> $errorLog
            }
        }
        catch { Add-Content -Path $errorLog -Value "$svc : $($_.Exception.Message)" }
    }
}

# -----------------------------------------------------------------------------
# Step 6 – Runtime menu: Disable Auto / Restore / Skip
# -----------------------------------------------------------------------------
Reset-AllProgress
Clear-Host
Write-Host ""
Write-Host "========== STEP 6 - WINDOWS UPDATE ==========" -ForegroundColor Green
Write-Host ""
Write-Host "Choose what to do with Windows Update:" -ForegroundColor Yellow
Write-Host ""
Write-Host "   1) DISABLE AUTO  - NoAutoUpdate=1, disable WU tasks, services -> Manual" -ForegroundColor White
Write-Host "   2) RESTORE       - undo the changes above (policy, tasks, services)" -ForegroundColor White
Write-Host "   3) SKIP          - leave Windows Update untouched" -ForegroundColor White
Write-Host ""
Write-Host "   Tip: services are set to Manual (not Disabled), so 'Check for updates'" -ForegroundColor DarkGray
Write-Host "        in Settings still works for manual installs after DISABLE AUTO." -ForegroundColor DarkGray
Write-Host ""

$wuChoice = Read-Host "Enter 1, 2 or 3"

switch ($wuChoice) {
    "1" {
        Write-Host ""
        Write-Host "[WARNING] Automatic updates will be blocked (manual install still works)." -ForegroundColor Red
        $verify = Read-Host "Type 'YES' to confirm DISABLE AUTO"
        if ($verify -eq "YES") {
            Disable-WindowsUpdateAuto
            Write-Host "  [6/7] Windows Update - AUTO DISABLED ............ OK" -ForegroundColor Green
        } else {
            Write-Host "  Windows Update disable skipped (no confirmation)." -ForegroundColor Yellow
        }
    }
    "2" {
        Write-Host ""
        Write-Host "[INFO] Restoring Windows Update..." -ForegroundColor Cyan
        Restore-WindowsUpdateAuto
        Write-Host "  [6/7] Windows Update - RESTORED ................. OK" -ForegroundColor Green
    }
    "3" { Write-Host "  Windows Update step skipped." -ForegroundColor Yellow }
    default { Write-Host "  Invalid choice. Windows Update step skipped." -ForegroundColor Yellow }
}

if (Test-Path $errorLog) {
    $errorCount = (Get-Content $errorLog | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "  [WARNING] $errorCount errors occurred. Check log: $errorLog" -ForegroundColor Yellow
    } else { Remove-Item $errorLog -Force }
}

Complete-SubProgress -Activity "Windows Update"
Write-OverallProgress -Status "Windows Update step complete" -SubPercent 100

# =============================================================================
# STEP 7 - SEARCH INDEXING  (DISABLE  OR  RESTORE)
# =============================================================================
$script:CurrentStep = 7
Write-OverallProgress -Status "Search Indexing" -SubPercent 0

$errorLog = "$env:TEMP\sigma_search_index_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

$searchSnapshot = "$env:TEMP\sigma_search_service_snapshot.json"

# =============================================================================
# FUNCTION - DISABLE SEARCH INDEXING
# =============================================================================
function Disable-SearchIndexing {
    Write-SubProgress -Activity "Search Indexing Disable" -Status "Saving WSearch service snapshot..." -PercentComplete 10
    try {
        $svc = Get-CimInstance Win32_Service -Filter "Name='WSearch'" -ErrorAction SilentlyContinue
        if ($svc) {
            @{ WSearch = $svc.StartMode } | ConvertTo-Json | Set-Content -Path $searchSnapshot -Force
        }
    }
    catch { Add-Content -Path $errorLog -Value "Snapshot : $($_.Exception.Message)" }

    Write-SubProgress -Activity "Search Indexing Disable" -Status "Stopping and disabling WSearch service..." -PercentComplete 50
    try {
        Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue 2>> $errorLog
        Set-Service  -Name "WSearch" -StartupType Disabled -ErrorAction Stop 2>> $errorLog
    }
    catch { Add-Content -Path $errorLog -Value "WSearch : $($_.Exception.Message)" }
}

# =============================================================================
# FUNCTION - RESTORE SEARCH INDEXING
# =============================================================================
function Restore-SearchIndexing {
    Write-SubProgress -Activity "Search Indexing Restore" -Status "Restoring WSearch service..." -PercentComplete 30

    $target = "Automatic"
    if (Test-Path $searchSnapshot) {
        try {
            $snap = Get-Content $searchSnapshot -Raw | ConvertFrom-Json
            if ($snap.WSearch) {
                switch ($snap.WSearch) {
                    "Auto"     { $target = "Automatic" }
                    "Manual"   { $target = "Manual" }
                    "Disabled" { $target = "Manual" }
                }
            }
        } catch { }
    }

    try {
        Set-Service -Name "WSearch" -StartupType $target -ErrorAction Stop 2>> $errorLog
        Start-Service -Name "WSearch" -ErrorAction SilentlyContinue 2>> $errorLog
    }
    catch { Add-Content -Path $errorLog -Value "WSearch restore : $($_.Exception.Message)" }
}

# -----------------------------------------------------------------------------
# Step 7 – Runtime menu: Disable / Restore / Skip
# -----------------------------------------------------------------------------
Reset-AllProgress
Clear-Host
Write-Host ""
Write-Host "========== STEP 7 - SEARCH INDEXING ==========" -ForegroundColor Green
Write-Host ""
Write-Host "Choose what to do with Windows Search Indexing:" -ForegroundColor Yellow
Write-Host ""
Write-Host "   1) DISABLE  - stop and disable the WSearch service (no indexing)" -ForegroundColor White
Write-Host "   2) RESTORE  - set WSearch back to its original startup type and start it" -ForegroundColor White
Write-Host "   3) SKIP     - leave Search Indexing untouched" -ForegroundColor White
Write-Host ""
Write-Host "   Tip: use RESTORE only after you previously ran DISABLE." -ForegroundColor DarkGray
Write-Host ""

$searchChoice = Read-Host "Enter 1, 2 or 3"

switch ($searchChoice) {
    "1" {
        Write-Host ""
        Write-Host "[WARNING] Disabling search indexing will slow down file searches." -ForegroundColor Red
        $verify = Read-Host "Type 'YES' to confirm DISABLE"
        if ($verify -eq "YES") {
            Disable-SearchIndexing
            Write-Host "  [7/7] Search Indexing - DISABLED ................ OK" -ForegroundColor Green
        } else {
            Write-Host "  Search Indexing disable skipped (no confirmation)." -ForegroundColor Yellow
        }
    }
    "2" {
        Write-Host ""
        Write-Host "[INFO] Restoring Search Indexing..." -ForegroundColor Cyan
        Restore-SearchIndexing
        Write-Host "  [7/7] Search Indexing - RESTORED ................ OK" -ForegroundColor Green
    }
    "3" { Write-Host "  Search Indexing step skipped." -ForegroundColor Yellow }
    default { Write-Host "  Invalid choice. Search Indexing step skipped." -ForegroundColor Yellow }
}

if (Test-Path $errorLog) {
    $errorCount = (Get-Content $errorLog | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "  [WARNING] $errorCount errors occurred. Check log: $errorLog" -ForegroundColor Yellow
    } else { Remove-Item $errorLog -Force }
}

Complete-SubProgress -Activity "Search Indexing"
Write-OverallProgress -Status "Search Indexing complete" -SubPercent 100

# =============================================================================
# FINAL SUMMARY
# =============================================================================
Reset-AllProgress

Write-Host ""
Write-Host "========== SIGMA PERFORMANCES - SUMMARY ==========" -ForegroundColor Green
Write-Host "   [1/7] Windows Defender (disable / restore) ...... OK" -ForegroundColor Green
Write-Host "   [2/7] Device Cleanup ............................ OK" -ForegroundColor Green
Write-Host "   [3/7] Telemetry & Tracking Removal .............. OK" -ForegroundColor Green
Write-Host "   [4/7] PowerCfg Registry ......................... OK" -ForegroundColor Green
Write-Host "   [5/7] CPU Optimization .......................... OK" -ForegroundColor Green
Write-Host "   [6/7] Windows Update (disable auto / restore) ... OK" -ForegroundColor Green
Write-Host "   [7/7] Search Indexing (disable / restore) ....... OK" -ForegroundColor Green
Write-Host ""
Write-Host "[SUCCESS] All optimizations applied." -ForegroundColor Green
Write-Host "[INFO] System reboot required." -ForegroundColor Yellow
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
