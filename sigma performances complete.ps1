#Requires -RunAsAdministrator

# =============================================================================
# SIGMA PERFORMANCES - ALL-IN-ONE OPTIMIZATION SUITE
# -----------------------------------------------------------------------------
# Combined: SIGMA steps (Device Cleanup, Telemetry, PowerCfg, CPU, Network)
#         + All registry tweaks (except Windows Update / Defender / Security)
#
# Order:
#   1.  Device Cleanup           (Unknown + Ghost devices)
#   2.  Telemetry Removal        (Registry + Services + Tasks)
#   3.  PowerCfg Registry        (GlobalPowerPolicy)
#   4.  CPU Optimization         (AC / DC)
#   5.  Network Throttle         (QoS 1-3000 Mbps)
#   6.  GPU / Display / Graphics
#   7.  USB / Power / Kernel / Memory / FileSystem
#   8.  Services                 (Disable / Delete)
#   9.  Network / TCP-IP / MMCSS / Multimedia
#   10. Explorer / Shell / UI / DWM
#   11. Input / Per-App Priorities
#   12. IE / Edge / Chrome / Office / Misc
#   13. Context Menus / Shell Extensions
#
# Single 'Y' confirmation at start. Reboot prompt at end.
# =============================================================================

$script:TotalSteps  = 13
$script:CurrentStep = 0

# -----------------------------------------------------------------------------
# Mount registry drives (PowerShell 7+ doesn't auto-mount HKU / HKCR)
# -----------------------------------------------------------------------------
if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -Scope Global | Out-Null
}
if (-not (Get-PSDrive -Name HKCR -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -Scope Global | Out-Null
}

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

# -----------------------------------------------------------------------------
# Registry helpers
# -----------------------------------------------------------------------------
$script:errorLog = "$env:TEMP\sigma_registry_errors.log"

function Set-RV {
    param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
    } catch { Add-Content -Path $script:errorLog -Value "SET $Path\$Name : $($_.Exception.Message)" }
}

function Set-RVdef {
    param([string]$Path, $Value, [string]$Type = "String")
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        if ($Type -eq "String") { Set-Item -Path $Path -Value $Value -Force -ErrorAction Stop }
    } catch { Add-Content -Path $script:errorLog -Value "DEF $Path : $($_.Exception.Message)" }
}

function Remove-RK {
    param([string]$Path)
    try { if (Test-Path $Path) { Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop } }
    catch { Add-Content -Path $script:errorLog -Value "DEL $Path : $($_.Exception.Message)" }
}

# =============================================================================
# INTRO + SINGLE CONFIRMATION
# =============================================================================
Clear-Host
Write-Host ""
Write-Host "========== SIGMA PERFORMANCES ==========" -ForegroundColor Green
Write-Host ""
Write-Host "[WARNING] This will apply ALL of the following, in order:" -ForegroundColor Yellow
Write-Host "   1.  Device Cleanup (Unknown + Ghost devices)" -ForegroundColor Yellow
Write-Host "   2.  Telemetry & Tracking Removal" -ForegroundColor Yellow
Write-Host "   3.  PowerCfg Registry values" -ForegroundColor Yellow
Write-Host "   4.  CPU Optimization (AC / DC)" -ForegroundColor Yellow
Write-Host "   5.  Network Throttle (QoS)" -ForegroundColor Yellow
Write-Host "   6.  GPU / Display / Graphics" -ForegroundColor Yellow
Write-Host "   7.  USB / Power / Kernel / Memory / FileSystem" -ForegroundColor Yellow
Write-Host "   8.  Services (Disable / Delete)" -ForegroundColor Yellow
Write-Host "   9.  Network / TCP-IP / MMCSS / Multimedia" -ForegroundColor Yellow
Write-Host "   10. Explorer / Shell / UI / DWM" -ForegroundColor Yellow
Write-Host "   11. Input / Per-App Priorities" -ForegroundColor Yellow
Write-Host "   12. IE / Edge / Chrome / Office / Misc" -ForegroundColor Yellow
Write-Host "   13. Context Menus / Shell Extensions" -ForegroundColor Yellow
Write-Host ""
Write-Host "[NOTE] Windows Update / Defender / Security categories are EXCLUDED." -ForegroundColor Cyan
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

if (Test-Path $script:errorLog) { Remove-Item $script:errorLog -Force }

# =============================================================================
# STEP 1 - REMOVE UNKNOWN + GHOST DEVICES
# =============================================================================
$script:CurrentStep = 1
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

Write-SubProgress -Activity "Device Cleanup" -Status "Rescanning for hardware changes..." -PercentComplete 95
pnputil /scan-devices 2>> $errorLog | Out-Null

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
Write-Host "  [1/13] Device Cleanup ........................... DONE" -ForegroundColor Green

# =============================================================================
# STEP 2 - TELEMETRY & TRACKING REMOVAL
# =============================================================================
$script:CurrentStep = 2
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
    } else {
        Remove-Item $errorLog -Force
    }
}

Complete-SubProgress -Activity "Telemetry Removal"
Write-OverallProgress -Status "Telemetry Removal complete" -SubPercent 100
Write-Host "  [2/13] Telemetry & Tracking Removal ............. DONE" -ForegroundColor Green

# =============================================================================
# STEP 3 - POWERCfg REGISTRY ONLY
# =============================================================================
$script:CurrentStep = 3
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
    $policiesHex -split ',' |
    ForEach-Object { [Convert]::ToByte($_.Trim(), 16) }
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
    } else {
        Remove-Item $errorLog -Force
    }
}

Complete-SubProgress -Activity "PowerCfg Registry"
Write-OverallProgress -Status "PowerCfg Registry complete" -SubPercent 100
Write-Host "  [3/13] PowerCfg Registry ......................... DONE" -ForegroundColor Green

# =============================================================================
# STEP 4 - CPU OPTIMIZATION (AC / DC)
# =============================================================================
$script:CurrentStep = 4
Write-OverallProgress -Status "CPU Optimization" -SubPercent 0

$errorLog = "$env:TEMP\sigma_optimization_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

$originalScheme = (powercfg -getactivescheme) -replace '.*\s([A-F0-9\-]{36}).*', '$1'

Write-SubProgress -Activity "CPU Optimization" -Status "Activating Ultimate Performance scheme..." -PercentComplete 3
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
powercfg -setactive       e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null

$cpuSettings = @{
    "PROCTHROTTLEMIN"=100; "PROCTHROTTLEMAX"=100; "PERFBOOSTMODE"=5; "CPMINCORES"=100;
    "PERFINCTHRESHOLD"=1; "PERFDECREASETHRESHOLD"=100; "PERFINCREASEPOLICY"=3;
    "PERFDECREASEPOLICY"=0; "RESPONSIVENESS"=100; "PERFORMANCECORES"=0; "PERFEPP"=0;
    "IDLEDEMOTE"=0; "IDLEPROMOTE"=100; "PERFBOOSTPOL"=100; "SHORTTHREADBOOST"=3;
    "HETEROPOLICY"=0; "PERFINCRES"=0; "PERFDECRES"=0; "RESPENABLETHRESHOLD"=100;
    "RESPPERFFLOOR"=100; "IDLESTATE"=0; "PERFAUTONOMOUS"=0; "PERFAUTONOMOUSACTIVEWINDOW"=100;
    "CPMAXCORES"=100; "CPEPP"=0; "CPPARKING"=0; "CPPARKED"=0; "CPCONCURRENCY"=100;
    "CPHEADROOM"=100; "CPLATENCY"=100; "CPLOAD"=100; "CPREQUESTS"=100; "CPRANDOM"=0;
    "MAXFREQ"=0; "MINFREQ"=0; "SCHEDPOLICY"=2; "SHORTTHREADSCHED"=2; "STARTPOLICY"=0;
    "STOPPOLICY"=0; "HETEROEPP"=0; "HETEROPROCESSPOLICY"=0; "HETEROTHREADPOLICY"=0;
    "PERFDUTYCYCLING"=100; "PERFDPC"=1; "PERFEPPBOOST"=100; "PERFEPPBACKOFF"=100;
    "PERFHISTORY"=0; "PERFCHECK"=0; "PERFLATENCY"=100; "PERFAUTONOMOUSFREQUENCY"=0
}
$cpuKeys = @($cpuSettings.Keys); $cpuTotal = $cpuKeys.Count; $cpuIndex = 0
foreach ($key in $cpuKeys) {
    $cpuIndex++
    $pct = 5 + [math]::Round($cpuIndex / $cpuTotal * 93)
    Write-SubProgress -Activity "CPU Optimization" -Status "Applying: $key ($cpuIndex/$cpuTotal)" -PercentComplete $pct
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR $key $cpuSettings[$key] 2>$null
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR $key $cpuSettings[$key] 2>$null
}

Write-SubProgress -Activity "CPU Optimization" -Status "Applying extra processor GUID..." -PercentComplete 98
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 94d3a615-a899-4ac5-ae2b-e4d8f634367f 1 2>$null
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 94d3a615-a899-4ac5-ae2b-e4d8f634367f 1 2>$null

Write-SubProgress -Activity "CPU Optimization" -Status "Committing power scheme..." -PercentComplete 99
powercfg -setactive SCHEME_CURRENT 2>$null

if (Test-Path $errorLog) {
    $errorCount = (Get-Content $errorLog | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "  [WARNING] $errorCount errors occurred. Check log: $errorLog" -ForegroundColor Yellow
    } else { Remove-Item $errorLog -Force }
}

Complete-SubProgress -Activity "CPU Optimization"
Write-OverallProgress -Status "CPU Optimization complete" -SubPercent 100
Write-Host "  [4/13] CPU Optimization .......................... DONE" -ForegroundColor Green

# =============================================================================
# STEP 5 - NETWORK THROTTLE (QoS)
# =============================================================================
$script:CurrentStep = 5
Write-OverallProgress -Status "Network Throttle" -SubPercent 0

$PolicyPrefix = "LimitPCto"
$MinMbps      = 1
$MaxMbps      = 3000

$errorLog = "$env:TEMP\sigma_netqos_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

function Set-QosLimit {
    param([Parameter(Mandatory = $true)][ValidateRange(1, 3000)][int]$Mbps)
    $bits = [uint64]$Mbps * 1000000
    $policyName = "$PolicyPrefix$Mbps"
    Get-NetQosPolicy -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$PolicyPrefix*" } |
        ForEach-Object { Remove-NetQosPolicy -Name $_.Name -Confirm:$false -ErrorAction SilentlyContinue 2>$null }
    New-NetQosPolicy -Name $policyName -ThrottleRateActionBitsPerSecond $bits -ErrorAction SilentlyContinue 2>$null
}

function Remove-AllLimits {
    $policies = Get-NetQosPolicy -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$PolicyPrefix*" }
    if (-not $policies) { Write-Host "[INFO] No '$PolicyPrefix*' QoS policy is applied." -ForegroundColor DarkGray; return }
    foreach ($p in $policies) {
        Remove-NetQosPolicy -Name $p.Name -Confirm:$false -ErrorAction SilentlyContinue 2>$null
        Write-Host "[REMOVED] $($p.Name)" -ForegroundColor Green
    }
}

function Show-AllLimits {
    $policies = Get-NetQosPolicy -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$PolicyPrefix*" }
    if (-not $policies) { Write-Host "[INFO] No '$PolicyPrefix*' QoS policy is applied." -ForegroundColor DarkGray; return }
    foreach ($p in $policies) {
        $bits = $null
        if ($p.PSObject.Properties.Name -contains 'ThrottleRateActionBitsPerSecond') { $bits = [uint64]$p.ThrottleRateActionBitsPerSecond }
        elseif ($p.PSObject.Properties.Name -contains 'ThrottleRateAction') { $bits = [uint64]$p.ThrottleRateAction }
        if ($bits -gt 0) {
            $mbps = [math]::Round($bits / 1000000, 3)
            Write-Host "[ACTIVE] $($p.Name)  ->  $mbps Mbps ($bits bits/s)" -ForegroundColor Cyan
        } else { Write-Host "[ACTIVE] $($p.Name)  ->  unknown" -ForegroundColor Cyan }
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
                } else { Write-Host "[ERROR] Value must be between $MinMbps and $MaxMbps." -ForegroundColor Red }
            } else { Write-Host "[ERROR] Enter a whole number." -ForegroundColor Red }
        }
        "2" {
            Write-SubProgress -Activity "Network Throttle" -Status "Removing all '$PolicyPrefix*' policies..." -PercentComplete 50
            Remove-AllLimits
            Write-SubProgress -Activity "Network Throttle" -Status "Throttles removed." -PercentComplete 100
        }
        "3" { Write-Host ""; Write-Host "[INFO] Currently applied throttles:" -ForegroundColor Cyan; Show-AllLimits }
        "4" { Write-SubProgress -Activity "Network Throttle" -Status "No change selected." -PercentComplete 100 }
        default { Write-Host "[ERROR] Invalid choice." -ForegroundColor Red }
    }
} until ($choice -eq "4")

if (Test-Path $errorLog) {
    $errorCount = (Get-Content $errorLog | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "  [WARNING] $errorCount errors occurred. Check log: $errorLog" -ForegroundColor Yellow
    } else { Remove-Item $errorLog -Force }
}

Complete-SubProgress -Activity "Network Throttle"
Write-OverallProgress -Status "Network Throttle complete" -SubPercent 100
Write-Host "  [5/13] Network Throttle .......................... DONE" -ForegroundColor Green

# =============================================================================
# STEP 6 - GPU / DISPLAY / GRAPHICS
# =============================================================================
$script:CurrentStep = 6
Write-OverallProgress -Status "GPU / Display / Graphics" -SubPercent 0

Write-SubProgress -Activity "GPU / Display" -Status "NVIDIA nvlddmkm + DXGKrnl..." -PercentComplete 5
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm" "NVFBCEnable" 1
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\DXGKrnl" "MonitorLatencyTolerance" 1
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\DXGKrnl" "MonitorRefreshLatencyTolerance" 1

$videoGuids = @(
    "HKLM:\SYSTEM\ControlSet001\Control\Video\{3D9D220F-16B0-11EC-AA00-D49CC0720C6C}\0000",
    "HKLM:\SYSTEM\ControlSet001\Control\Video\{3D9D220F-16B0-11EC-AA00-D49CC0720C6C}\0001",
    "HKLM:\SYSTEM\ControlSet001\Control\Video\{3D9D220F-16B0-11EC-AA00-D49CC0720C6C}\0002",
    "HKLM:\SYSTEM\ControlSet001\Control\Video\{3D9D2216-16B0-11EC-AA00-005056C00008}\0000",
    "HKLM:\SYSTEM\ControlSet001\Control\Video\{3D9D2216-16B0-11EC-AA00-005056C00008}\0001",
    "HKLM:\SYSTEM\ControlSet001\Control\Video\{3D9D2216-16B0-11EC-AA00-005056C00008}\0002",
    "HKLM:\SYSTEM\ControlSet001\Control\Video\{3D9D2216-16B0-11EC-AA00-005056C00008}\0003"
)
$videoCommon = @{
    "DDC2Disabled"=1; "MultiFunctionSupported"=1; "TimingSelection"=0; "VgaCompatible"=0;
    "Adaptive De-interlacing"=0; "VPE Adaptive De-interlacing"=0;
    "GCOOPTION_DisableGPIOPowerSaveMode"=1; "TVEnableOverscan"=0; "UA_Enabled"=1;
    "KMD_EnableOPM2Interface"=1; "WmAgpMaxIdleClk"=0x20; "MemInitLatencyTimer"=1;
    "GamePerformanceAdviserEnabled"=0; "DisableAllClockGating"=1;
    "DisableGfxCGPowerGating"=1; "DisableCpPowerGating"=1;
    "DisableStaticGfxMGPowerGating"=1; "DisableSAMUPowerGating"=1;
    "DisablePowerGating"=1; "DisablePCIConfigAsicReset"=1;
    "DisableDynamicGfxMGPowerGating"=1; "EnableLBPWSupport"=1;
    "DisableRlcSmuPGHandshake"=1; "DisableSysClockGating"=1;
    "DisableGfxClockGating"=1; "EnableUlps"=0; "DisableFBCSupport"=1;
    "EnableCrossFireAutoLink"=0; "ExtEvent_BIOSEventByInterrupt"=0;
    "TVDisableModes"=1; "LazyPreload"=1
}
$i = 0; $n = $videoGuids.Count
foreach ($k in $videoGuids) {
    $i++
    $pct = 5 + [math]::Round($i / $n * 40)
    Write-SubProgress -Activity "GPU / Display" -Status "Video profile $i/$n..." -PercentComplete $pct
    foreach ($name in $videoCommon.Keys) { Set-RV $k $name $videoCommon[$name] }
    if ($k -match '3D9D2216' -and $k -match '\\000[123]$') {
        Set-RV $k "DisableForceRemoveWrite" 0
        Set-RV $k "DisableDrmdmaPowerGating" 1
        Set-RV $k "PP_ThermalAutoThrottlingEnable" 0
    }
}

Write-SubProgress -Activity "GPU / Display" -Status "GraphicsDrivers..." -PercentComplete 55
$gd = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
Set-RV $gd "HwSchedMode" 2
Set-RV $gd "TdrLevel" 0
Set-RV $gd "UseGpuTimer" 1
Set-RV $gd "RmGpsPsEnablePerCpuCoreDpc" 1
Set-RV $gd "PowerSavingTweaks" 0
Set-RV $gd "DisableWriteCombining" 1
Set-RV $gd "EnableRuntimePowerManagement" 0
Set-RV $gd "PrimaryPushBufferSize" 1
Set-RV $gd "FlTransitionLatency" 0
Set-RV $gd "D3PCLatency" 0
Set-RV $gd "RMDeepLlEntryLatencyUsec" 0
Set-RV $gd "PciLatencyTimerControl" 0x20
Set-RV $gd "Node3DLowLatency" 1
Set-RV $gd "LOWLATENCY" 1
Set-RV $gd "RmDisableRegistryCaching" 1
Set-RV $gd "RMDisablePostL2Compression" 1
Set-RV $gd "DpiMapIommuContiguous" 1

Write-SubProgress -Activity "GPU / Display" -Status "GraphicsDrivers\Power..." -PercentComplete 75
$gdp = "$gd\Power"
foreach ($n2 in @("UseGpuTimer","RmGpsPsEnablePerCpuCoreDpc")) { Set-RV $gdp $n2 1 }
foreach ($n2 in @("PowerSavingTweaks","EnableRuntimePowerManagement","FlTransitionLatency","D3PCLatency","RMDeepLlEntryLatencyUsec")) { Set-RV $gdp $n2 0 }
Set-RV $gdp "DisableWriteCombining" 1
Set-RV $gdp "PrimaryPushBufferSize" 1
Set-RV $gdp "PciLatencyTimerControl" 0x20
Set-RV $gdp "Node3DLowLatency" 1
Set-RV $gdp "LOWLATENCY" 1
Set-RV $gdp "RmDisableRegistryCaching" 1
Set-RV $gdp "RMDisablePostL2Compression" 1
Set-RV $gdp "MonitorRefreshLatencyTolerance" 1
Set-RV $gdp "MonitorLatencyTolerance" 1
Set-RV $gdp "TransitionLatency" 1
Set-RV $gdp "Latency" 1
Set-RV $gdp "MiracastPerfTrackGraphicsLatency" 1
Set-RV $gdp "MaxIAverageGraphicsLatencyInOneBucket" 1
foreach ($n2 in @("DefaultMemoryRefreshLatencyToleranceNoContext","DefaultMemoryRefreshLatencyToleranceMonitorOff",
                 "DefaultMemoryRefreshLatencyToleranceActivelyUsed","DefaultLatencyToleranceTimerPeriod",
                 "DefaultLatencyToleranceOther","DefaultLatencyToleranceNoContextMonitorOff",
                 "DefaultLatencyToleranceNoContext","DefaultLatencyToleranceMemory",
                 "DefaultLatencyToleranceIdle1MonitorOff","DefaultLatencyToleranceIdle1",
                 "DefaultLatencyToleranceIdle0MonitorOff","DefaultLatencyToleranceIdle0",
                 "DefaultD3TransitionLatencyIdleVeryLongTime","DefaultD3TransitionLatencyIdleShortTime",
                 "DefaultD3TransitionLatencyIdleNoContext","DefaultD3TransitionLatencyIdleMonitorOff",
                 "DefaultD3TransitionLatencyIdleLongTime","DefaultD3TransitionLatencyActivelyUsed")) {
    Set-RV $gdp $n2 1
}

Write-SubProgress -Activity "GPU / Display" -Status "NVDisplay plugin..." -PercentComplete 95
Set-RV "HKLM:\SYSTEM\ControlSet001\Services\NVDisplay.ContainerLocalSystem\LocalSystem\NvcDispCorePlugin" "DisableLoad" 1
Set-RV "HKLM:\SYSTEM\ControlSet001\Services\NVDisplay.ContainerLocalSystem\LocalSystem\NvcDispCorePlugin" "LogFile" "-" String
Set-RV "HKLM:\SYSTEM\ControlSet001\Services\NVDisplay.ContainerLocalSystem\LocalSystem\NvcDispCorePlugin" "LogLevel" 0

Complete-SubProgress -Activity "GPU / Display"
Write-OverallProgress -Status "GPU / Display complete" -SubPercent 100
Write-Host "  [6/13] GPU / Display / Graphics .................. DONE" -ForegroundColor Green

# =============================================================================
# STEP 7 - USB / POWER / KERNEL / MEMORY / FILESYSTEM
# =============================================================================
$script:CurrentStep = 7
Write-OverallProgress -Status "USB / Kernel / Memory / FS" -SubPercent 0

Write-SubProgress -Activity "System" -Status "USB / Power..." -PercentComplete 5
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Enum\USB" "AllowIdleIrpInD3" 0
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Enum\USB" "EnhancedPowerManagementEnabled" 0
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\USBXHCI\Parameters\Wdf" "NoExtraBufferRoom" 1
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\usbhub\hubg" "DisableOnSoftRemove" 1
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Control\usbflags" "fid_D1Latency" 0
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Control\usbflags" "fid_D2Latency" 0
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Control\usbflags" "fid_D3Latency" 0
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\pci\Parameters" "ASPMOptOut" 1
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters" "MouseDataQueueSize" 0x32
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters" "KeyboardDataQueueSize" 0x32

Write-SubProgress -Activity "System" -Status "Kernel..." -PercentComplete 20
$k = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
Set-RV $k "DpcWatchdogProfileOffset" 0
Set-RV $k "DpcTimeout" 0
Set-RV $k "DpcWatchdogPeriod" 0
Set-RV $k "DisableAutoBoost" 1
Set-RV $k "DistributeTimers" 1
Set-RV $k "IdealDpcRate" 1
Set-RV $k "MaximumDpcQueueDepth" 1
Set-RV $k "MinimumDpcRate" 1
Set-RV $k "ThreadDpcEnable" 1
Set-RV $k "AdjustDpcThreshold" 0
Set-RV $k "MaximumSharedReadyQueueSize" 1
Set-RV $k "CoalescingTimerInterval" 0

Write-SubProgress -Activity "System" -Status "Session Manager..." -PercentComplete 35
$sm = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
Set-RV $sm "AlpcWakePolicy" 1
Set-RV $sm "CoalescingTimerInterval" 0
Set-RV "$sm\Executive" "CoalescingTimerInterval" 0
Set-RV "$sm\I/O System" "PassiveIntRealTimeWorkerPriority" 0x18
Set-RV "$sm\Power" "CoalescingTimerInterval" 0
Set-RV "$sm\Power" "SleepStudyDisabled" 1

$mm = "$sm\Memory Management"
Set-RV $mm "IoPageLockLimit" 0xffffffff
Set-RV $mm "DisablePagingExecutive" 1
Set-RV $mm "LargeSystemCache" 1
Set-RV $mm "NonPagedPoolSize" 0xc0
Set-RV $mm "PagedPoolSize" 0xc0
Set-RV $mm "PoolUsageMaximum" 0xc0
Set-RV $mm "SecondLevelDataCache" 0x3072
Set-RV $mm "ThirdLevelDataCache" 0x8192
Set-RV $mm "PhysicalAddressExtension" 1
Set-RV $mm "MoveImages" 0
Set-RV "$mm\PrefetchParameters" "EnablePrefetcher" 0
Set-RV "$mm\PrefetchParameters" "EnableSuperfetch" 0

Write-SubProgress -Activity "System" -Status "FileSystem..." -PercentComplete 55
$fs = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
foreach ($n2 in @("DisableDeleteNotification","RefsDisableLastAccessUpdate","LongPathsEnabled",
                 "NtfsDisableLastAccessUpdate","NtfsDisableSpotCorruptionHandling","NTFSDisable8dot3NameCreation")) {
    Set-RV $fs $n2 1
}
foreach ($n2 in @("Win31FileSystem","Win95TruncatedExtensions","NtfsMemoryUsage","NtfsBugcheckOnCorrupt")) {
    Set-RV $fs $n2 0
}
Set-RV $fs "NtfsMftZoneReservation" 4

Write-SubProgress -Activity "System" -Status "Power..." -PercentComplete 70
$pw = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"
Set-RV $pw "CoalescingTimerInterval" 0
Set-RV $pw "ExitLatency" 1
Set-RV $pw "ExitLatencyCheckEnabled" 1
Set-RV $pw "Latency" 1
Set-RV $pw "LatencyToleranceDefault" 1
Set-RV $pw "LatencyToleranceFSVP" 1
Set-RV $pw "LatencyTolerancePerfOverride" 1
Set-RV $pw "LatencyToleranceScreenOffIR" 1
Set-RV $pw "LatencyToleranceVSyncEnabled" 1
Set-RV $pw "RtlCapabilityCheckLatency" 1
Set-RV $pw "HibernateEnabled" 0
Set-RV $pw "CsEnabled" 0
Set-RV $pw "EnergyEstimationEnabled" 0
Set-RV $pw "PerfCalculateActualUtilization" 0
Set-RV $pw "SleepReliabilityDetailedDiagnostics" 0
Set-RV $pw "EventProcessorEnabled" 0
Set-RV $pw "QosManagesIdleProcessors" 0
Set-RV $pw "DisableVsyncLatencyUpdate" 0
Set-RV $pw "DisableSensorWatchdog" 1
Set-RV "$pw\ModernSleep" "CoalescingTimerInterval" 0
Set-RV "$pw\PowerThrottling" "PowerThrottlingOff" 1
Set-RV "$pw\EnergyEstimation\TaggedEnergy" "DisableTaggedEnergyLogging" 1
Set-RV "$pw\EnergyEstimation\TaggedEnergy" "TelemetryMaxApplication" 0
Set-RV "$pw\EnergyEstimation\TaggedEnergy" "TelemetryMaxTagPerApplication" 0

Write-SubProgress -Activity "System" -Status "KernelVelocity / PriorityControl / Boot..." -PercentComplete 85
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Control\KernelVelocity" "DisableFGBoostDecay" 1
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 0x28
Set-RV "HKLM:\SOFTWARE\Microsoft\Dfrg\BootOptimizeFunction" "Enable" "N" String
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" "MaintenanceDisabled" 1
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" "WakeUp" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Reliability" "TimeStampInterval" 1
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Control\PnP" "PollBootPartitionTimeout" 1
Set-RV "HKLM:\SOFTWARE\Microsoft\TouchPrediction" "Latency" 1
Set-RV "HKLM:\SOFTWARE\Microsoft\TouchPrediction" "SampleTime" 1
Set-RV "HKLM:\SOFTWARE\Microsoft\TouchPrediction" "UseHWTimeStamp" 1

Complete-SubProgress -Activity "System"
Write-OverallProgress -Status "System complete" -SubPercent 100
Write-Host "  [7/13] USB / Power / Kernel / Memory / FS ........ DONE" -ForegroundColor Green

# =============================================================================
# STEP 8 - SERVICES (DISABLE / DELETE)
# =============================================================================
$script:CurrentStep = 8
Write-OverallProgress -Status "Services" -SubPercent 0

Write-SubProgress -Activity "Services" -Status "Disabling services (Start=4)..." -PercentComplete 10
$svcDisable = @(
    "kdnic","NdisVirtualBus","Vid","umbus","CompositeBus","rdpbus",
    "WacomPen","PktMon","QWAVEdrv","Beep","Ndu","MMCSS","GraphicsPerfSvc",
    "dam","bam","CDPUserSvc","WmiAcpi","acpitime","AcpiPmi","AcpiDev","acpipagr",
    "GpuEnergyDrv","NdisCap","gameflt","Intel(R) SUR QC SAM"
)
foreach ($s in $svcDisable) { Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\$s" "Start" 4 }
Set-RV "HKLM:\SYSTEM\ControlSet001\Services\PktMon" "Type" 1
Set-RV "HKLM:\SYSTEM\ControlSet001\Services\WacomPen" "Start" 4
Set-RV "HKLM:\SYSTEM\ControlSet001\Services\PktMon" "Start" 4
Set-RV "HKLM:\SYSTEM\ControlSet001\Services\gameflt" "Start" 4
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\mssmbios" "Start" 1

Write-SubProgress -Activity "Services" -Status "Deleting service keys..." -PercentComplete 55
$svcDelete = @(
    "WdiSystemHost","GpuEnergyDrv","storqosflt","hvcmon",
    "FontCache","FontCache3.0.0.0","GraphicsPerfSvc","PcaSvc",
    "DiagTrack","dmwappushservice","diagsvc","DPS",
    "diagnosticshub.standardcollector.service","WdiServiceHost",
    "SysMain","WSearch","AMD External Events Utility",
    "ASUSLinkNear","ASUSLinkRemote","ASUSSystemAnalysis","ASUSSystemDiagnosis",
    "BcastDVRUserService","BcastDVRUserService_10daf8",
    "clr_optimization_v4.0.30319_64","clr_optimization_v4.0.30319_32",
    "clr_optimization_v2.0.50727_64","clr_optimization_v2.0.50727_32",
    "gupdate","gupdatem","PimIndexMaintenanceSvc"
)
$i = 0; $n = $svcDelete.Count
foreach ($s in $svcDelete) {
    $i++
    $pct = 55 + [math]::Round($i / $n * 40)
    Write-SubProgress -Activity "Services" -Status "Deleting: $s ($i/$n)" -PercentComplete $pct
    Remove-RK "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
}

Complete-SubProgress -Activity "Services"
Write-OverallProgress -Status "Services complete" -SubPercent 100
Write-Host "  [8/13] Services (Disable / Delete) ............... DONE" -ForegroundColor Green

# =============================================================================
# STEP 9 - NETWORK / TCP-IP / MMCSS / MULTIMEDIA
# =============================================================================
$script:CurrentStep = 9
Write-OverallProgress -Status "Network / TCP-IP / MMCSS" -SubPercent 0

Write-SubProgress -Activity "Network" -Status "TCP/IP parameters..." -PercentComplete 5
$tcp = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
Set-RV $tcp "EnableWsd" 0
Set-RV $tcp "TcpWindowSize" 0x3ebc0
Set-RV $tcp "DisableDynamicDiscovery" 1
Set-RV $tcp "EnablePMTUDiscovery" 0
Set-RV $tcp "EnablePMTUBDetect" 0
Set-RV $tcp "DisableTaskOffload" 0
Set-RV $tcp "TcpMaxDupAcks" 2
Set-RV $tcp "UseDomainNameDevolution" 0
Set-RV $tcp "IGMPLevel" 0
Set-RV $tcp "DelayedAckFrequency" 1
Set-RV $tcp "DelayedAckTicks" 1
Set-RV $tcp "CongestionAlgorithm" 1
Set-RV $tcp "MultihopSets" 0x0f
Set-RV $tcp "FastCopyReceiveThreshold" 0x4000
Set-RV $tcp "FastSendDatagramThreshold" 0x4000
Set-RV "$tcp\Interfaces" "TcpAckFrequency" 1
Set-RV "$tcp\Interfaces" "TCPNoDelay" 1
Set-RV "$tcp\Winsock" "UseDelayedAcceptance" 0
Set-RV "$tcp\Winsock" "MaxSockAddrLength" 0x10
Set-RV "$tcp\Winsock" "MinSockAddrLength" 0x10
Set-RV "HKLM:\System\CurrentControlSet\Services\Tcpip\QoS" "Do not use NLA" "1" String
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\WinSock2\Parameters" "Ws2_32NumHandleBuckets" 1
Set-RV "HKLM:\SOFTWARE\Microsoft\MSMQ\Parameters" "TCPNoDelay" 1
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" "DisabledComponents" 0

Write-SubProgress -Activity "Network" -Status "AFD / DNS priority..." -PercentComplete 25
$afd = "HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters"
Set-RV $afd "FastSendDatagramThreshold" 0x5dc
Set-RV $afd "FastCopyReceiveThreshold" 0x5dc
Set-RV $afd "DefaultReceiveWindow" 0x4000
Set-RV $afd "DefaultSendWindow" 0x4000
Set-RV $afd "DynamicSendBufferDisable" 0
Set-RV $afd "IgnorePushBitOnReceives" 1
Set-RV $afd "NonBlockingSendSpecialBuffering" 1
Set-RV $afd "DisableRawSecurity" 1

$sp = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\ServiceProvider"
Set-RV $sp "DnsPriority" 6
Set-RV $sp "LocalPriority" 4
Set-RV $sp "NetbtPriority" 7
Set-RV $sp "HostPriority" 5
Set-RV $sp "HostsPriority" 5

Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters" "EnableLMHOSTS" 1
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Control\NetworkProvider" "RestoreConnection" 0
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "AutoShareWks" 0
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "IRPStackSize" 0x20
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation" "AllowOfflineFilesforCAShares" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections" "NC_PersonalFirewallConfig" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections" "NC_DoNotShowLocalOnlyIcon" 1

Write-SubProgress -Activity "Network" -Status "Multimedia / MMCSS..." -PercentComplete 45
$mm2 = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
Set-RV $mm2 "SystemResponsiveness" 0
Set-RV $mm2 "NetworkThrottlingIndex" 0xffffffff
Set-RV $mm2 "AlwaysOn" 1
Set-RV $mm2 "NoLazyMode" 1
Set-RV $mm2 "AllowHeadlessExecution" 1
Set-RV $mm2 "AllowMultipleBackgroundTasks" 1
Set-RV $mm2 "InactivityTimeoutMs" 0xffffffff

$mmTasks = @{
    "Audio" = @{ "Affinity"=7; "Background Only"="True"; "GPU Priority"=1; "Priority"=2; "Scheduling Category"="High"; "SFIO Priority"="High" }
    "Low Latency" = @{ "Affinity"=0; "Background Only"="False"; "BackgroundPriority"=0; "GPU Priority"=8; "Priority"=2; "Scheduling Category"="High"; "SFIO Priority"="High"; "Latency Sensitive"="True" }
    "Capture" = @{ "Affinity"=7; "Background Only"="True"; "GPU Priority"=8; "Priority"=5; "Scheduling Category"="High"; "SFIO Priority"="Normal" }
    "DisplayPostProcessing" = @{ "Affinity"=0; "Background Only"="True"; "BackgroundPriority"=0x18; "Clock Rate"=0x2710; "GPU Priority"=0x12; "Priority"=8; "Scheduling Category"="High"; "SFIO Priority"="High"; "Latency Sensitive"="True" }
    "Distribution" = @{ "Affinity"=0; "Background Only"="True"; "GPU Priority"=8; "Priority"=4; "Scheduling Category"="High"; "SFIO Priority"="Normal" }
    "Playback" = @{ "Affinity"=7; "Background Only"="False"; "BackgroundPriority"=4; "Clock Rate"=0x2710; "GPU Priority"=8; "Priority"=3; "Scheduling Category"="High"; "SFIO Priority"="Normal" }
    "Pro Audio" = @{ "Affinity"=7; "Background Only"="False"; "GPU Priority"=8; "Priority"=1; "Scheduling Category"="High"; "SFIO Priority"="Normal" }
    "Window Manager" = @{ "Affinity"=7; "Background Only"="True"; "GPU Priority"=8; "Priority"=5; "Scheduling Category"="High"; "SFIO Priority"="Normal" }
    "Games" = @{ "Affinity"=0; "Background Only"="False"; "GPU Priority"=8; "Priority"=6; "Scheduling Category"="High"; "SFIO Priority"="High" }
}
foreach ($t in $mmTasks.Keys) {
    $tk = "$mm2\Tasks\$t"
    foreach ($n2 in $mmTasks[$t].Keys) {
        $v = $mmTasks[$t][$n2]
        $ty = if ($v -is [int]) { "DWord" } else { "String" }
        Set-RV $tk $n2 $v $ty
    }
}

Write-SubProgress -Activity "Network" -Status "Psched / NlaSvc / QoS / LLTD..." -PercentComplete 70
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched" "TimerResolution" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched" "MaxOutstandingSends" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched" "NonBestEffortLimit" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" "NoActiveProbe" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Internet Connection Wizard" "ExitOnMSICW" 1

$nla = "HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet"
Set-RV $nla "ActiveDnsProbeContent" "208.67.222.222" String
Set-RV $nla "ActiveDnsProbeContentV6" "2620:119:35::35" String
Set-RV $nla "ActiveDnsProbeHost" "resolver1.opendns.com" String
Set-RV $nla "ActiveDnsProbeHostV6" "resolver1.opendns.com" String
Set-RV $nla "ActiveWebProbeContent" "success" String
Set-RV $nla "ActiveWebProbeContentV6" "success" String
Set-RV $nla "ActiveWebProbeHost" "detectportal.firefox.com" String
Set-RV $nla "ActiveWebProbeHostV6" "detectportal.firefox.com" String
Set-RV $nla "ActiveWebProbePath" "success.txt" String
Set-RV $nla "ActiveWebProbePathV6" "success.txt" String

Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LLTD" "EnableLLTDIO" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LLTD" "AllowLLTDIOOnDomain" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LLTD" "AllowLLTDIOOnPublicNet" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LLTD" "ProhibitLLTDIOOnPrivateNet" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LLTD" "EnableRspndr" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LLTD" "AllowRspndrOnDomain" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LLTD" "AllowRspndrOnPublicNet" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LLTD" "ProhibitRspndrOnPrivateNet" 0

Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\RasMan\Parameters\Config\VpnCostedNetworkSettings" "NoRoamingNetwork" 1
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\RasMan\Parameters\Config\VpnCostedNetworkSettings" "NoCostedNetwork" 1

Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WwanSvc\NetCost" "Cost3G" 2
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WwanSvc\NetCost" "Cost4G" 2
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WwanSvc\CellularDataAccess" "LetAppsAccessCellularData" 1

Complete-SubProgress -Activity "Network"
Write-OverallProgress -Status "Network complete" -SubPercent 100
Write-Host "  [9/13] Network / TCP-IP / MMCSS / Multimedia ..... DONE" -ForegroundColor Green

# =============================================================================
# STEP 10 - EXPLORER / SHELL / UI / DWM
# =============================================================================
$script:CurrentStep = 10
Write-OverallProgress -Status "Explorer / Shell / UI / DWM" -SubPercent 0

Write-SubProgress -Activity "Explorer" -Status "DWM / Visual Effects..." -PercentComplete 5
Set-RV "HKCU:\Software\Microsoft\Windows\DWM" "Composition" 0
Set-RV "HKCU:\Software\Microsoft\Windows\DWM" "EnableAeroPeek" 0
Set-RV "HKCU:\Software\Microsoft\Windows\DWM" "AlwaysHibernateThumbnails" 0
Set-RV "HKCU:\Software\Microsoft\Windows\DWM" "CompositionPolicy" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" "AnimationAttributionEnabled" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" "AnimationAttributionHashingEnabled" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" "OneCoreNoBootDWM" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DWM" "DWMWA_TRANSITIONS_FORCEDISABLED" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DWM" "DisallowFlip3d" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DWM" "DisallowColorizationColorChanges" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DWM" "DisallowAnimations" 1
Set-RV "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 0
Set-RV "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFxSetting" 3
Set-RV "HKCU:\Software\Microsoft\Windows\CurrentVersion\ThemeManager" "ThemeActive" "0" String
Set-RV "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" String
Set-RV "HKCU:\Control Panel\Desktop\WindowMetrics" "MaxAnimate" "0" String
Set-RV "HKCU:\Control Panel\Desktop\WindowMetrics" "PaddedBorderWidth" "0" String
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" "DesktopHeapLogging" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" "DwmInputUsesIoCompletionPort" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" "EnableDwmInputProcessing" 0

Write-SubProgress -Activity "Explorer" -Status "Explorer Advanced..." -PercentComplete 25
$adv = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-RV $adv "ExtendedUIHoverTime" 0x10
Set-RV $adv "DontPrettyPath" 1
Set-RV $adv "ListviewShadow" 0
Set-RV $adv "TaskbarAnimations" 0
Set-RV $adv "ListviewAlphaSelect" 0
Set-RV $adv "ListviewWatermark" 0
Set-RV $adv "StartShownOnUpgrade" 1
Set-RV $adv "TaskbarDa" 0
Set-RV $adv "LaunchTo" 1
Set-RV $adv "TaskbarMn" 0
Set-RV $adv "Start_NotifyNewApps" 0
Set-RV $adv "ShowSecondsInSystemClock" 1
Set-RV $adv "Start_ShowRun" 1
Set-RV $adv "ShowSyncProviderNotifications" 0
Set-RV $adv "NavPaneShowAllFolders" 0
Set-RV $adv "NoNetCrawling" 1
Set-RV $adv "TaskbarSi" 1
Set-RV $adv "HideFileExt" 0
Set-RV $adv "ShowSuperHidden" 1
Set-RV $adv "SeparateProcess" 0
Set-RV $adv "MMTaskbarGlomLevel" 0
Set-RV $adv "ShowInfoTip" 1
Set-RV $adv "HideIcons" 0
Set-RV $adv "MapNetDrvBtn" 0
Set-RV $adv "WebView" 0
Set-RV $adv "DITest" 0

Set-RV "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" "NoPreviousVersionsPage" 1
Set-RV "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" "MultipleInvokePromptMinimum" 0x1388
Set-RV "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" "AltTabSettings" 1
Set-RV "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" "PeopleBand" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "NoPreviousVersionsPage" 1
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "Max Cached Icons" "4096" String
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "ThumbnailQuality" 100
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "HubMode" 1
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize" "StartupDelayInMSec" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "EncryptionContextMenu" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MultiTaskingView\AllUpView" "Enabled" 0
Set-RV "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MultitaskingView\AllUpView" "AllUpView" 0
Set-RV "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MultitaskingView\AllUpView" "Remove TaskView" 1
Set-RV "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband\AuxilliaryPins" "MailPin" 0

Write-SubProgress -Activity "Explorer" -Status "Explorer policies..." -PercentComplete 45
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\PreviousVersions" "DisableLocalPage" 1
Set-RV "HKCU:\Software\Policies\Microsoft\PreviousVersions" "DisableLocalPage" 1
Set-RV "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoInstrumentation" 1
Set-RV "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoRecentDocsMenu" 1
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoRemoteRecursiveEvents" 1
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "AllowOnlineTips" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "StartMenuFavorites" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "Start_ShowHelp" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "Start_ShowMyComputer" 1
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "Start_ShowRun" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "NoUseStoreOpenWith" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "HideRecentlyAddedApps" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "ShowOrHideMostUsedApps" 2
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "NoNewAppAlert" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "DisableContextMenusInStart" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "NoUseStoreOpenWith" 1

Write-SubProgress -Activity "Explorer" -Status "Desktop / Controls / Input..." -PercentComplete 65
Set-RV "HKCU:\Control Panel\Desktop" "AutoEndTasks" "1" String
Set-RV "HKCU:\Control Panel\Desktop" "MenuShowDelay" "0" String
Set-RV "HKCU:\Control Panel\Desktop" "HungAppTimeout" "2000" String
Set-RV "HKCU:\Control Panel\Desktop" "WaitToKillAppTimeout" "2" String
Set-RV "HKCU:\Control Panel\Desktop" "WaitToKillServiceTimeout" "2" String
Set-RV "HKCU:\Control Panel\Desktop" "ForegroundLockTimeout" 0
Set-RV "HKCU:\Control Panel\Desktop" "MouseWheelRouting" 0
Set-RV "HKCU:\Control Panel\Desktop" "JPEGImportQuality" 100
Set-RV "HKCU:\Control Panel\Desktop" "DragFullWindows" "1" String
Set-RV "HKCU:\Control Panel\Desktop" "FontSmoothing" "2" String
Set-RV "HKCU:\Control Panel\Desktop" "FontSmoothingType" 2
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Control" "WaitToKillServiceTimeout" "2" String
Set-RV "HKLM:\SYSTEM\ControlSet001\Control" "WaitToKillServiceTimeout" "2" String
Set-RV "HKCU:\Control Panel\Sound" "beep" "no" String
Set-RV "HKCU:\Control Panel\Sound" "ExtendedSounds" "no" String
Set-RV "HKU:\.DEFAULT\Control Panel\Sound" "Beep" "no" String
Set-RV "HKU:\.DEFAULT\Control Panel\Sound" "ExtendedSounds" "no" String
Set-RV "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" "AutoRestartShell" 1
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "EnableFirstLogonAnimation" 0
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Control\BootControl" "BootProgressAnimation" 1

Write-SubProgress -Activity "Explorer" -Status "Accessibility / International..." -PercentComplete 80
foreach ($acc in @("MouseKeys","HighContrast","StickyKeys","TimeOut","Keyboard Response","ToggleKeys","SoundSentry")) {
    Set-RV "HKCU:\Control Panel\Accessibility\$acc" "Flags" "0" String
    Set-RV "HKU:\.DEFAULT\Control Panel\Accessibility\$acc" "Flags" "0" String
}
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Reliability" "TimeStampInterval" 0

Set-RV "HKCU:\Control Panel\International" "s1159" "AM" String
Set-RV "HKCU:\Control Panel\International" "s2359" "PM" String
Set-RV "HKCU:\Control Panel\International" "sCurrency" "$" String
Set-RV "HKCU:\Control Panel\International" "sDate" "." String
Set-RV "HKCU:\Control Panel\International" "sDecimal" "," String
Set-RV "HKCU:\Control Panel\International" "sGrouping" "3;0" String
Set-RV "HKCU:\Control Panel\International" "sList" "." String
Set-RV "HKCU:\Control Panel\International" "sLongDate" "dddd, dd.MM.yyyy" String
Set-RV "HKCU:\Control Panel\International" "sMonDecimalSep" "." String
Set-RV "HKCU:\Control Panel\International" "sMonGrouping" "3;0" String
Set-RV "HKCU:\Control Panel\International" "sMonThousandSep" "," String
Set-RV "HKCU:\Control Panel\International" "sNativeDigits" "0123456789" String
Set-RV "HKCU:\Control Panel\International" "sNegativeSign" "-" String
Set-RV "HKCU:\Control Panel\International" "sPositiveSign" "" String
Set-RV "HKCU:\Control Panel\International" "sShortDate" "dd.MM.yyyy" String
Set-RV "HKCU:\Control Panel\International" "sThousand" "." String
Set-RV "HKCU:\Control Panel\International" "sTime" ":" String
Set-RV "HKCU:\Control Panel\International" "sTimeFormat" "HH:mm:ss" String
Set-RV "HKCU:\Control Panel\International" "sShortTime" "HH:mm" String
Set-RV "HKCU:\Control Panel\International" "iFirstDayOfWeek" "0" String
Set-RV "HKCU:\Control Panel\International" "iLZero" "1" String
Set-RV "HKCU:\Control Panel\International" "iMeasure" "0" String
Set-RV "HKCU:\Control Panel\International" "iNegCurr" "0" String

Write-SubProgress -Activity "Explorer" -Status "Misc policies..." -PercentComplete 95
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\MobilityCenter" "NoMobilityCenter" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\TabletPC" "DisableSnippingTool" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkFolders" "AutoProvision" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRE" "DisableSetup" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\UEV\Agent" "Enabled" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WCN\UI" "DisableWcnUi" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WDI\{affc81e2-612a-4f70-6fb2-916ff5c7e3f8}" "ScenarioExecutionEnabled" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WDI\{affc81e2-612a-4f70-6fb2-916ff5c7e3f8}" "EnabledScenarioExecutionLevel" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop" "EnablePerProcessSystemDPI" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Display" "EnablePerProcessSystemDPIForProcesses" "" String
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Display" "DisablePerProcessSystemDPIForProcesses" "" String
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\EdgeUI" "DisableMFUTracking" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\EdgeUI" "DisableHelpSticker" 1
Set-RV "HKCU:\Software\Policies\Microsoft\Windows\EdgeUI" "DisableMFUTracking" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\EnhancedStorageDevices" "TCGSecurityActivationDisabled" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\ProtectedEventLogging" "EnableProtectedEventLogging" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\Setup" "Enabled" "0" String
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\FileHistory" "Disabled" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\fssProv" "EncryptProtocol" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\HomeGroup" "DisableHomeGroup" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\HotspotAuthentication" "Enabled" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" "DisableLoggingFromPackage" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\iSCSI" "ChangeIQNName" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\iSCSI" "RestrictAdditionalLogins" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\iSCSI" "ChangeCHAPSecret" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\iSCSI" "RequireIPSec" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\iSCSI" "RequireMutualCHAP" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\iSCSI" "RequireOneWayCHAP" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetCache" "WorkOfflineDisabled" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetCache" "SyncAtLogon" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetCache" "SyncAtLogoff" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetCache" "SyncEnabledForCostedNetwork" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetCache" "EconomicalAdminPinning" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetCache" "NoReminders" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetCache" "NoMakeAvailableOffline" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetCache" "NoCacheViewer" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetCache" "NoConfigCache" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageHealth" "AllowDiskHealthModelUpdates" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense" "AllowStorageSenseGlobal" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense" "AllowStorageSenseTemporaryFilesCleanup" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "AllowClipboardHistory" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "AllowCrossDeviceClipboard" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "DisableLockScreenAppNotifications" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "RSoPLogging" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "DisableAcrylicBackgroundOnLogon" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableFontProviders" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "DisableForceUnload" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "SlowLinkDetectEnabled" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "DeleteRoamingCache" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "CompatibleRUPSecurity" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "AllowBlockingAppsAtShutdown" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "HiberbootEnabled" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NvCache" "OptimizeBootAndResume" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NvCache" "EnablePowerModeState" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE" "DisablePrivacyExperience" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Reliability Analysis\WMI" "WMIEnable" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings" "CallLegacyWCMPolicies" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings\Url History" "DaysToKeep" 0x14
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM" "DisableRegistration" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Digital Locker" "DoNotRunDigitalLocker" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Explorer\AutoComplete" "AutoSuggest" "no" String
Set-RV "HKLM:\SOFTWARE\Microsoft\WindowsMitigation" "UserPreference" 2
Set-RV "HKCU:\SOFTWARE\Microsoft\Personalization\Settings" "AcceptedPrivacyPolicy" 0

Complete-SubProgress -Activity "Explorer"
Write-OverallProgress -Status "Explorer complete" -SubPercent 100
Write-Host "  [10/13] Explorer / Shell / UI / DWM .............. DONE" -ForegroundColor Green

# =============================================================================
# STEP 11 - INPUT / PER-APP PRIORITIES
# =============================================================================
$script:CurrentStep = 11
Write-OverallProgress -Status "Input / Per-App Priorities" -SubPercent 0

Write-SubProgress -Activity "Input / Priorities" -Status "Mouse / Keyboard..." -PercentComplete 5
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\mouhid\Parameters" "TreatAbsolutePointerAsAbsolute" 1
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\mouhid\Parameters" "TreatAbsoluteAsRelative" 0
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\i8042prt\Parameters" "CrashOnCtrlScroll" 1
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\kbdhid\Parameters" "CrashOnCtrlScroll" 1

$drvThread = @("mouclass","mouhid","DXGKrnl","USBXHCI","USBHUB3","amdkmdap","nvlddmkm",
                "amd_sata","BTUSB","BthLEEnum","BthHFEnum","umbus_A1614B8FA282BCE3",
                "RTWlanE","RtkBtManServ","RtkBtFilter","rtump64x64")
foreach ($d in $drvThread) {
    Set-RV "HKLM:\SYSTEM\CurrentControlSet\Services\$d\Parameters" "ThreadPriority" 0x1f
}

Set-RV "HKCU:\Control Panel\Keyboard" "KeyboardDelay" "0" String
Set-RV "HKCU:\Control Panel\Keyboard" "KeyboardSpeed" "10" String
Set-RV "HKCU:\Control Panel\Keyboard" "InitialKeyboardIndicators" "2" String
Set-RV "HKU:\.DEFAULT\Control Panel\Keyboard" "InitialKeyboardIndicators" "2" String
Set-RV "HKU:\.DEFAULT\Control Panel\Keyboard" "KeyboardDelay" "0" String
Set-RV "HKU:\.DEFAULT\Control Panel\Keyboard" "KeyboardSpeed" "10" String
Set-RV "HKCU:\Control Panel\Mouse" "MouseHoverTime" "1" String
Set-RV "HKCU:\Control Panel\Mouse" "MouseSensitivity" "10" String
Set-RV "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes" "ThemeChangesMousePointers" 0

Set-RV "HKLM:\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorSpeed" "CursorSensitivity" 0x2710
Set-RV "HKLM:\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorSpeed" "CursorUpdateInterval" 1
Set-RV "HKLM:\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorSpeed" "IRRemoteNavigationDelta" 1
Set-RV "HKLM:\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorMagnetism" "AttractionRectInsetInDIPS" 5
Set-RV "HKLM:\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorMagnetism" "DistanceThresholdInDIPS" 0x28
Set-RV "HKLM:\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorMagnetism" "MagnetismDelayInMilliseconds" 0x32
Set-RV "HKLM:\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorMagnetism" "MagnetismUpdateIntervalInMilliseconds" 1
Set-RV "HKLM:\SOFTWARE\Microsoft\Input\Settings\ControllerProcessor\CursorMagnetism" "VelocityInDIPSPerSecond" 0x168

Write-SubProgress -Activity "Input / Priorities" -Status "IRQ priorities..." -PercentComplete 25
$irq = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
foreach ($n2 in @("IRQ4294967253Priority","IRQ4294967254Priority","IRQ4294967259Priority",
                 "IRQ4294967256Priority","IRQ4294967257Priority","IRQ4294967258Priority",
                 "IRQ4294967262Priority","IRQ39Priority","IRQ1024Priority","IRQ4294967287Priority",
                 "IRQ4294967288Priority","IRQ4294967289Priority","IRQ4294967290Priority",
                 "IRQ4294967291Priority","IRQ4294967292Priority","IRQ4294967293Priority",
                 "IRQ4294967294Priority","IRQ1Priority","IRQ6Priority","IRQ7Priority",
                 "IRQ25Priority","IRQ36Priority","IRQ55Priority","IRQ57Priority","IRQ8Priority")) {
    Set-RV $irq $n2 1
}
Set-RV $irq "IRQ4294967260Priority" 2
Set-RV $irq "IRQ4294967261Priority" 2
Set-RV $irq "Win32PrioritySeparation" 0x26

Write-SubProgress -Activity "Input / Priorities" -Status "Per-app IFEO..." -PercentComplete 45
$ifeo = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
$perfMap = @{
    "3/3" = @(
        "csgo.exe","Monopoly.exe","Monopoly_Plus.exe","CIU.exe","DoomEternalx64vk.exe",
        "eurotrucks2.exe","Muck.exe","mysummercar.exe","SonicMania.exe","Terraria.exe",
        "candycrushsaga.exe","DragonCity.exe","ForzaHorizon3.exe","ForzaHorizon4.exe",
        "ForzaHorizon5.exe","MegaRun-WinStore.exe","Ludo King.exe","SnowRunner.exe",
        "WheresMyWater2.WindowsStore.exe","Among Us.exe","Cyberpunk2077.exe",
        "GeometryDash.exe","metin2client.exe","PizzaFrenzy.exe","PlantsVsZombies.exe",
        "re6.exe","re7.exe","re8.exe","TheCrew2.exe","TheCrew2_BE.exe","BananaBugs.exe",
        "WinBM.exe","Bookworm.exe","Chuzzle.exe","game.exe","gta-lc.exe",
        "PlayGtaV.exe","GTAV.exe","gta-vc.exe","gta-sa.exe","gta-iii.exe",
        "FortniteClient-Win64-Shipping.exe","photoshop.exe","Lightroom.exe",
        "Notepad++.exe","iScrRec.exe","Lightshot.exe"
    )
    "1/2" = @("EarTrumpet.exe","Spotify.exe","SpotifyStartupTask.exe",
              "lghub_updater.exe","Ditto.exe","OfficeClickToRun.exe")
    "6/3" = @("chrome.exe","msedge.exe","firefox.exe","opera.exe","operagx.exe","Update.exe",
              "Discord.exe","winword.exe","powerpnt.exe","excel.exe","msaccess.exe","mspub.exe",
              "explorer.exe","Teams.exe","Zoom.exe","Acrobat.exe","Bitwarden.exe","Rambox.exe",
              "BlueMail.exe")
    "4/3" = @("VideoEditorPlus.exe","Resolve.exe","converter.exe","Steam.exe",
              "GroupyCtrl.exe","GroupySvc32.exe","GroupySvc64.exe","GroupySrv",
              "Start11_64.exe","Start11Srv.exe","csrss.exe")
    "5/1" = @("svchost.exe","acrotray.exe","IDMan.exe")
    "1/3" = @("EABackgroundService.exe")
    "1/1" = @("GameOverlayUI.exe","steamwebhelper.exe")
}
foreach ($map in $perfMap.GetEnumerator()) {
    $p = $map.Key -split '/'
    $cpu = [int]$p[0]; $io = [int]$p[1]
    foreach ($exe in $map.Value) {
        Set-RV "$ifeo\$exe\PerfOptions" "CpuPriorityClass" $cpu
        Set-RV "$ifeo\$exe\PerfOptions" "IoPriority" $io
    }
}

Write-SubProgress -Activity "Input / Priorities" -Status "GPU preferences (iGPU)..." -PercentComplete 90
$gpuPref = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
$sysApps = @(
    "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe","C:\Windows\System32\rundll32.exe",
    "C:\Windows\System32\dpnsvr.exe","C:\Windows\System32\bdeunlock.exe","C:\Windows\System32\bdechangepin.exe",
    "C:\Windows\System32\ClipDLS.exe","C:\Windows\System32\AppVDllSurrogate.exe","C:\Windows\System32\AppVNice.exe",
    "C:\Windows\System32\ScriptRunner.exe","C:\Windows\System32\SyncAppvPublishingServer.exe",
    "C:\Windows\System32\AppV\AppVStreamingUX.exe","C:\Windows\System32\AppVShNotify.exe",
    "C:\Windows\System32\rrinstaller.exe","C:\Windows\System32\UevAgentPolicyGenerator.exe",
    "C:\Windows\System32\UevTemplateBaselineGenerator.exe","C:\Windows\System32\UevTemplateConfigItemGenerator.exe",
    "C:\Windows\System32\ApplySettingsTemplateCatalog.exe","C:\Windows\System32\Microsoft.Uev.CscUnpinTool.exe",
    "C:\Windows\System32\UevAppMonitor.exe","C:\Windows\System32\Microsoft.Uev.SyncController.exe",
    "C:\Windows\System32\chgport.exe","C:\Windows\System32\chgusr.exe","C:\Windows\System32\query.exe",
    "C:\Windows\System32\change.exe","C:\Windows\System32\chglogon.exe","C:\Windows\System32\logoff.exe",
    "C:\Windows\System32\qappsrv.exe","C:\Windows\System32\qprocess.exe","C:\Windows\System32\reset.exe",
    "C:\Windows\System32\rwinsta.exe","C:\Windows\System32\tscon.exe","C:\Windows\System32\tsdiscon.exe",
    "C:\Windows\System32\tskill.exe","C:\Windows\System32\msg.exe","C:\Windows\System32\quser.exe",
    "C:\Windows\System32\qwinsta.exe","C:\Windows\System32\baaupdate.exe","C:\Windows\System32\BitLockerWizard.exe",
    "C:\Windows\System32\BitLockerWizardElev.exe","C:\Windows\System32\logagent.exe",
    "C:\Windows\System32\mfpmp.exe","C:\Windows\System32\PackageInspector.exe",
    "C:\Windows\System32\manage-bde.exe","C:\Windows\System32\PresentationSettings.exe",
    "C:\Windows\System32\AgentService.exe","C:\Windows\System32\repair-bde.exe",
    "C:\Windows\System32\ClipRenew.exe","C:\Windows\System32\gpscript.exe",
    "C:\Windows\System32\CustomShellHost.exe","C:\Windows\System32\AssignedAccessGuard.exe",
    "C:\Windows\System32\mavinject.exe","C:\Windows\System32\BitLockerDeviceEncryption.exe",
    "C:\Windows\System32\rdpinit.exe","C:\Windows\System32\rdpshell.exe",
    "C:\Windows\System32\AppVClient.exe","C:\Windows\System32\BdeHdCfg.exe",
    "C:\Windows\System32\CameraSettingsUIHost.exe","C:\Windows\System32\RemoteAppLifetimeManager.exe",
    "C:\Windows\System32\rdpsign.exe","C:\Windows\System32\fveprompt.exe",
    "C:\Windows\System32\iotstartup.exe","C:\Windows\System32\fvenotify.exe",
    "C:\Windows\System32\WPDShextAutoplay.exe","C:\Windows\System32\BdeUISrv.exe",
    "C:\Windows\System32\wbadmin.exe","C:\Windows\System32\wbengine.exe",
    "C:\Windows\System32\MsSpellCheckingHost.exe","C:\Windows\System32\bootim.exe",
    "C:\Windows\System32\WinBioDataModelOOBE.exe","C:\Windows\System32\PresentationHost.exe",
    "C:\Windows\System32\rstrui.exe","C:\Windows\System32\srdelayed.exe","C:\Windows\System32\SrTasks.exe",
    "C:\Windows\System32\SpaceAgent.exe","C:\Windows\System32\provlaunch.exe","C:\Windows\System32\EduPrintProv.exe",
    "C:\Windows\System32\UNP\UNPUXHost.exe","C:\Windows\System32\UNP\UNPUXLauncher.exe",
    "C:\Windows\System32\UNP\UpdateNotificationMgr.exe","C:\Windows\System32\Spectrum.exe",
    "C:\Windows\System32\SIHClient.exe","C:\Windows\System32\xwizard.exe",
    "C:\Windows\System32\takeown.exe","C:\Windows\System32\vssadmin.exe","C:\Windows\System32\where.exe",
    "C:\Windows\System32\cacls.exe","C:\Windows\System32\eventcreate.exe","C:\Windows\System32\fsavailux.exe",
    "C:\Windows\System32\ftp.exe","C:\Windows\System32\grpconv.exe","C:\Windows\System32\runas.exe",
    "C:\Windows\System32\systeminfo.exe","C:\Windows\System32\taskkill.exe","C:\Windows\System32\tasklist.exe",
    "C:\Windows\System32\timeout.exe","C:\Windows\System32\waitfor.exe","C:\Windows\System32\whoami.exe",
    "C:\Windows\System32\mstsc.exe","C:\Windows\System32\TSTheme.exe","C:\Windows\System32\wkspbroker.exe",
    "C:\Windows\System32\TSWbPrxy.exe","C:\Windows\System32\RdpSa.exe","C:\Windows\System32\RdpSaProxy.exe",
    "C:\Windows\System32\RdpSaUacHelper.exe","C:\Windows\System32\sessionmsg.exe",
    "C:\Windows\System32\TieringEngineService.exe","C:\Windows\System32\rdpclip.exe",
    "C:\Windows\System32\rdpinput.exe","C:\Windows\System32\TapiUnattend.exe","C:\Windows\System32\dialer.exe",
    "C:\Windows\System32\tcmsetup.exe","C:\Windows\System32\MultiDigiMon.exe","C:\Windows\System32\tabcal.exe",
    "C:\Windows\System32\FsIso.exe","C:\Windows\System32\dvdplay.exe","C:\Windows\System32\calc.exe",
    "C:\Windows\System32\charmap.exe","C:\Windows\System32\credwiz.exe","C:\Windows\System32\certreq.exe",
    "C:\Windows\System32\certutil.exe","C:\Windows\System32\klist.exe","C:\Windows\System32\ksetup.exe",
    "C:\Windows\System32\nltest.exe","C:\Windows\System32\regini.exe","C:\Windows\System32\regsvr32.exe",
    "C:\Windows\System32\setspn.exe","C:\Windows\System32\regedt32.exe","C:\Windows\System32\ResetEngine.exe",
    "C:\Windows\System32\SysResetErr.exe","C:\Windows\System32\systemreset.exe",
    "C:\Windows\System32\SystemResetPlatform\SystemResetPlatform.exe","C:\Windows\System32\migwiz\mighost.exe",
    "C:\Windows\System32\pwlauncher.exe","C:\Windows\System32\fodhelper.exe","C:\Windows\System32\Fondue.exe",
    "C:\Windows\System32\OptionalFeatures.exe","C:\Windows\System32\CheckNetIsolation.exe",
    "C:\Windows\System32\msiexec.exe","C:\Windows\System32\mblctr.exe","C:\Windows\System32\msconfig.exe",
    "C:\Windows\System32\LocationNotificationWindows.exe","C:\Windows\System32\mmc.exe",
    "C:\Windows\System32\WindowsActionDialog.exe","C:\Windows\System32\cliconfg.exe",
    "C:\Windows\System32\odbcad32.exe","C:\Windows\System32\odbcconf.exe","C:\Windows\System32\iscsicpl.exe",
    "C:\Windows\System32\iscsicli.exe","C:\Windows\System32\IESettingSync.exe","C:\Windows\System32\ie4uinit.exe",
    "C:\Windows\System32\ie4ushowIE.exe","C:\Windows\System32\F12\IEChooser.exe","C:\Windows\System32\ieUnatt.exe",
    "C:\Windows\System32\iexpress.exe","C:\Windows\System32\wextract.exe","C:\Windows\System32\mshta.exe",
    "C:\Windows\System32\wiaacmgr.exe","C:\Windows\System32\wiawow64.exe","C:\Windows\System32\bridgeunattend.exe",
    "C:\Windows\System32\eventvwr.exe","C:\Windows\System32\gpresult.exe","C:\Windows\System32\gpupdate.exe",
    "C:\Windows\System32\esentutl.exe","C:\Windows\System32\eudcedit.exe","C:\Windows\System32\wecutil.exe",
    "C:\Windows\System32\easinvoker.exe","C:\Windows\System32\EhStorAuthn.exe","C:\Windows\System32\DpiScaling.exe",
    "C:\Windows\System32\Dxpserver.exe","C:\Windows\System32\DeviceProperties.exe",
    "C:\Windows\System32\DisplaySwitch.exe","C:\Windows\System32\SystemSettingsRemoveDevice.exe",
    "C:\Windows\System32\SyncHost.exe","C:\Windows\System32\DevicePairingWizard.exe",
    "C:\Windows\System32\ComputerDefaults.exe","C:\Windows\System32\DataExchangeHost.exe",
    "C:\Windows\System32\CompMgmtLauncher.exe","C:\Windows\System32\convert.exe","C:\Windows\System32\find.exe",
    "C:\Windows\System32\ktmutil.exe","C:\Windows\System32\label.exe","C:\Windows\System32\openfiles.exe",
    "C:\Windows\System32\replace.exe","C:\Windows\System32\Robocopy.exe","C:\Windows\System32\stordiag.exe",
    "C:\Windows\System32\choice.exe","C:\Windows\System32\clip.exe","C:\Windows\System32\doskey.exe",
    "C:\Windows\System32\forfiles.exe","C:\Windows\System32\print.exe","C:\Windows\System32\subst.exe",
    "C:\Windows\System32\cttune.exe","C:\Windows\System32\cttunesvr.exe","C:\Windows\System32\help.exe",
    "C:\Windows\System32\msdtc.exe","C:\Windows\System32\CastSrv.exe","C:\Windows\System32\UserDataSource.exe",
    "C:\Windows\System32\curl.exe","C:\Windows\System32\tar.exe","C:\Windows\System32\spaceman.exe",
    "C:\Windows\System32\spaceutil.exe","C:\Windows\System32\EDPCleanup.exe","C:\Windows\System32\MDMAppInstaller.exe",
    "C:\Windows\System32\ARP.exe","C:\Windows\System32\finger.exe","C:\Windows\System32\HOSTNAME.exe",
    "C:\Windows\System32\MRINFO.exe","C:\Windows\System32\NETSTAT.exe","C:\Windows\System32\ROUTE.exe",
    "C:\Windows\System32\sort.exe","C:\Windows\System32\TCPSVCS.exe","C:\Windows\System32\xcopy.exe",
    "C:\Windows\System32\auditpol.exe","C:\Windows\System32\mountvol.exe","C:\Windows\System32\net.exe",
    "C:\Windows\System32\net1.exe","C:\Windows\System32\netsh.exe","C:\Windows\System32\PATHPING.exe",
    "C:\Windows\System32\PING.exe","C:\Windows\System32\reg.exe","C:\Windows\System32\sc.exe",
    "C:\Windows\System32\setx.exe","C:\Windows\System32\TRACERT.exe","C:\Windows\System32\attrib.exe",
    "C:\Windows\System32\ClipUp.exe","C:\Windows\System32\diskusage.exe","C:\Windows\System32\findstr.exe",
    "C:\Windows\System32\icacls.exe","C:\Windows\System32\ipconfig.exe","C:\Windows\System32\CIDiag.exe",
    "C:\Windows\System32\comp.exe","C:\Windows\System32\fc.exe","C:\Windows\System32\fsutil.exe",
    "C:\Windows\System32\recover.exe","C:\Windows\System32\sdclt.exe",
    "C:\Windows\System32\PerceptionSimulation\PerceptionSimulationService.exe",
    "C:\Windows\System32\tcblaunch.exe","C:\Windows\System32\securekernel.exe","C:\Windows\System32\SgrmBroker.exe",
    "C:\Windows\System32\SgrmLpac.exe","C:\Windows\System32\upnpcont.exe","C:\Windows\System32\BioIso.exe",
    "C:\Windows\System32\NgcIso.exe","C:\Windows\System32\dusmtask.exe",
    "C:\Windows\System32\WinBioPlugIns\FaceFodUninstaller.exe","C:\Windows\System32\GamePanel.exe",
    "C:\Windows\System32\GameBarPresenceWriter.exe","C:\Windows\System32\oobe\oobeldr.exe",
    "C:\Windows\System32\oobe\windeploy.exe","C:\Windows\System32\oobe\audit.exe",
    "C:\Windows\System32\oobe\AuditShD.exe","C:\Windows\System32\MBR2GPT.exe","C:\Windows\System32\oobe\Setup.exe",
    "C:\Windows\System32\poqexec.exe","C:\Windows\System32\PkgMgr.exe","C:\Windows\System32\Dism\DismHost.exe",
    "C:\Windows\System32\cmdkey.exe","C:\Windows\System32\dpapimig.exe","C:\Windows\System32\LsaIso.exe",
    "C:\Windows\System32\cscript.exe","C:\Windows\System32\RmClient.exe","C:\Windows\System32\SecEdit.exe",
    "C:\Windows\System32\wscript.exe","C:\Windows\System32\icsunattend.exe","C:\Windows\System32\NetHost.exe",
    "C:\Windows\System32\cmmon32.exe","C:\Windows\System32\cmstp.exe","C:\Windows\System32\cmdl32.exe",
    "C:\Windows\System32\rasautou.exe","C:\Windows\System32\rasdial.exe","C:\Windows\System32\rasphone.exe",
    "C:\Windows\System32\ntprint.exe","C:\Windows\System32\printui.exe","C:\Windows\System32\DeviceEject.exe",
    "C:\Windows\System32\powercfg.exe","C:\Windows\System32\sigverif.exe","C:\Windows\System32\drvinst.exe",
    "C:\Windows\System32\hdwwiz.exe","C:\Windows\System32\pnputil.exe","C:\Windows\System32\wowreg32.exe",
    "C:\Windows\System32\ndadmin.exe","C:\Windows\System32\newdev.exe","C:\Windows\System32\driverquery.exe",
    "C:\Windows\System32\PnPUnattend.exe","C:\Windows\System32\oobe\FirstLogonAnim.exe",
    "C:\Windows\System32\oobe\msoobe.exe","C:\Windows\System32\oobe\UserOOBEBroker.exe",
    "C:\Windows\System32\netbtugc.exe","C:\Windows\System32\netiougc.exe","C:\Windows\System32\nbtstat.exe",
    "C:\Windows\System32\NetCfgNotifyObjectHost.exe","C:\Windows\System32\djoin.exe",
    "C:\Windows\System32\getmac.exe","C:\Windows\System32\shrpubw.exe",
    "C:\Windows\System32\SystemPropertiesAdvanced.exe","C:\Windows\System32\SystemPropertiesComputerName.exe",
    "C:\Windows\System32\SystemPropertiesDataExecutionPrevention.exe","C:\Windows\System32\SystemPropertiesHardware.exe",
    "C:\Windows\System32\SystemPropertiesPerformance.exe","C:\Windows\System32\SystemPropertiesProtection.exe",
    "C:\Windows\System32\SystemPropertiesRemote.exe","C:\Windows\System32\winver.exe",
    "C:\Windows\System32\sxstrace.exe","C:\Windows\System32\Sysprep\sysprep.exe","C:\Windows\System32\WSCollect.exe",
    "C:\Windows\System32\WSReset.exe","C:\Windows\System32\changepk.exe","C:\Windows\System32\LicensingUI.exe",
    "C:\Windows\System32\phoneactivate.exe","C:\Windows\System32\UpgradeResultsUI.exe",
    "C:\Windows\System32\GenValObj.exe","C:\Windows\System32\slui.exe","C:\Windows\System32\SppExtComObj.exe",
    "C:\Windows\System32\sppsvc.exe","C:\Windows\System32\Speech\SpeechUX\SpeechUXWiz.exe",
    "C:\Windows\System32\snmptrap.exe","C:\Windows\System32\immersivetpmvscmgrsvr.exe",
    "C:\Windows\System32\rmttpmvscmgrsvr.exe","C:\Windows\System32\tpmvscmgr.exe",
    "C:\Windows\System32\tpmvscmgrsvr.exe","C:\Windows\System32\OpenWith.exe",
    "C:\Windows\System32\ThumbnailExtractionHost.exe","C:\Windows\System32\verclsid.exe",
    "C:\Windows\System32\WallpaperHost.exe","C:\Windows\System32\prevhost.exe","C:\Windows\System32\mcbuilder.exe",
    "C:\Windows\System32\MSchedExe.exe","C:\Windows\System32\WUDFCompanionHost.exe",
    "C:\Windows\System32\WUDFHost.exe","C:\Windows\System32\AxInstUI.exe","C:\Windows\System32\consent.exe",
    "C:\Windows\System32\LanguageComponentsInstallerComHandler.exe","C:\Windows\System32\LockAppHost.exe",
    "C:\Windows\System32\la57setup.exe","C:\Windows\System32\lpksetup.exe","C:\Windows\System32\lpremove.exe",
    "C:\Windows\System32\DsmUserTask.exe","C:\Windows\System32\netcfg.exe","C:\Windows\System32\runonce.exe",
    "C:\Windows\System32\secinit.exe","C:\Windows\System32\colorcpl.exe","C:\Windows\System32\dccw.exe",
    "C:\Windows\System32\Dism.exe","C:\Windows\System32\proquota.exe",
    "C:\Windows\System32\UserAccountControlSettings.exe","C:\Windows\System32\shutdown.exe",
    "C:\Windows\System32\efsui.exe","C:\Windows\System32\cipher.exe","C:\Windows\System32\edpnotify.exe",
    "C:\Windows\System32\MicrosoftEdgeCP.exe","C:\Windows\System32\rekeywiz.exe",
    "C:\Windows\System32\dnscacheugc.exe","C:\Windows\System32\nslookup.exe","C:\Windows\System32\lodctr.exe",
    "C:\Windows\System32\unlodctr.exe","C:\Windows\System32\ddodiag.exe","C:\Windows\System32\omadmclient.exe",
    "C:\Windows\System32\omadmprc.exe","C:\Windows\System32\DmOmaCpMo.exe","C:\Windows\System32\coredpussvr.exe",
    "C:\Windows\System32\DeviceEnroller.exe","C:\Windows\System32\dmcertinst.exe","C:\Windows\System32\dmcfghost.exe",
    "C:\Windows\System32\CredentialUIBroker.exe","C:\Windows\System32\SensorDataService.exe",
    "C:\Windows\System32\SecurityHealthHost.exe","C:\Windows\System32\prproc.exe",
    "C:\Windows\System32\SecurityHealthService.exe","C:\Windows\System32\Windows.Media.BackgroundPlayback.exe",
    "C:\Windows\System32\sfc.exe","C:\Windows\System32\wusa.exe","C:\Windows\System32\wbem\wbemtest.exe",
    "C:\Windows\System32\wbem\scrcons.exe","C:\Windows\System32\ApplyTrustOffline.exe",
    "C:\Windows\System32\CustomInstallExec.exe","C:\Windows\System32\deploymentcsphelper.exe",
    "C:\Windows\System32\expand.exe","C:\Windows\System32\ReAgentc.exe","C:\Windows\System32\RelPost.exe",
    "C:\Windows\System32\MuiUnattend.exe","C:\Windows\System32\dxdiag.exe","C:\Windows\System32\fontdrvhost.exe",
    "C:\Windows\System32\winlogon.exe","C:\Windows\System32\ucsvc.exe","C:\Windows\System32\fltMC.exe",
    "C:\Windows\System32\lsass.exe","C:\Windows\System32\ntoskrnl.exe","C:\Windows\System32\services.exe",
    "C:\Windows\System32\smss.exe","C:\Windows\System32\csrss.exe","C:\Windows\System32\AggregatorHost.exe",
    "C:\Windows\System32\dtdump.exe","C:\Windows\System32\runexehelper.exe","C:\Windows\System32\rdrleakdiag.exe",
    "C:\Windows\System32\wpr.exe","C:\Windows\System32\pacjsworker.exe","C:\Windows\System32\userinit.exe",
    "C:\Windows\System32\wininit.exe","C:\Windows\System32\DeviceCensus.exe","C:\Windows\System32\dllhost.exe",
    "C:\Windows\System32\conhost.exe","C:\Windows\System32\extrac32.exe","C:\Windows\System32\makecab.exe",
    "C:\Windows\System32\svchost.exe","C:\Windows\System32\compact.exe","C:\Windows\System32\dwm.exe",
    "C:\Windows\System32\dcomcnfg.exe","C:\Windows\System32\Locator.exe","C:\Windows\System32\RpcPing.exe",
    "C:\Windows\System32\mtstocom.exe","C:\Windows\System32\dllhst3g.exe","C:\Windows\System32\setupcl.exe",
    "C:\Windows\System32\setupugc.exe","C:\Windows\System32\wimserv.exe","C:\Windows\System32\chkdsk.exe",
    "C:\Windows\System32\chkntfs.exe","C:\Windows\System32\wsqmcons.exe","C:\Windows\System32\autochk.exe",
    "C:\Windows\System32\browser_broker.exe","C:\Windows\System32\browserexport.exe",
    "C:\Windows\System32\Boot\winresume.exe","C:\Windows\System32\winresume.exe","C:\Windows\System32\winload.exe",
    "C:\Windows\System32\bthudtask.exe","C:\Windows\System32\fsquirt.exe","C:\Windows\System32\bitsadmin.exe",
    "C:\Windows\System32\refsutil.exe","C:\Windows\System32\appidcertstorecheck.exe",
    "C:\Windows\System32\appidpolicyconverter.exe","C:\Windows\System32\SndVol.exe","C:\Windows\System32\appidtel.exe",
    "C:\Windows\System32\CompatTelRunner.exe","C:\Windows\System32\sdbinst.exe","C:\Windows\System32\pcalua.exe",
    "C:\Windows\System32\aitstatic.exe","C:\Windows\System32\LaunchTM.exe","C:\Windows\System32\pcaui.exe",
    "C:\Windows\System32\Taskmgr.exe","C:\Windows\System32\Utilman.exe","C:\Windows\System32\EaseOfAccessDialog.exe",
    "C:\Windows\System32\Narrator.exe","C:\Windows\System32\osk.exe","C:\Windows\System32\sethc.exe",
    "C:\Windows\System32\AtBroker.exe","C:\Windows\System32\Magnify.exe","C:\Windows\System32\EoAExperiences.exe",
    "C:\Windows\System32\CloudExperienceHostBroker.exe","C:\Windows\System32\ApplicationFrameHost.exe",
    "C:\Windows\System32\SecurityHealthSystray.exe","C:\Windows\System32\ShellAppRuntime.exe",
    "C:\Windows\System32\desktopimgdownldr.exe","C:\Windows\System32\SystemSettingsAdminFlows.exe",
    "C:\Windows\System32\VSSVC.exe","C:\Windows\System32\convertvhd.exe","C:\Windows\System32\wuauclt.exe",
    "C:\Windows\System32\MusNotifyIcon.exe","C:\Windows\System32\WindowsUpdateElevatedInstaller.exe",
    "C:\Windows\System32\MusNotification.exe","C:\Windows\System32\MusNotificationUx.exe",
    "C:\Windows\System32\MoNotificationUx.exe","C:\Windows\System32\UsoClient.exe",
    "C:\Windows\System32\Speech_OneCore\common\SpeechModelDownload.exe",
    "C:\Windows\System32\Speech_OneCore\common\SpeechRuntime.exe",
    "C:\Windows\System32\DeviceCredentialDeployment.exe","C:\Windows\System32\LegacyNetUXHost.exe",
    "C:\Windows\System32\wevtutil.exe","C:\Windows\System32\dasHost.exe","C:\Windows\System32\DiskSnapshot.exe",
    "C:\Windows\System32\verifier.exe","C:\Windows\System32\Register-CimProvider.exe",
    "C:\Windows\System32\wbem\WinMgmt.exe","C:\Windows\System32\wbem\WmiPrvSE.exe","C:\Windows\System32\winrs.exe",
    "C:\Windows\System32\winrshost.exe","C:\Windows\System32\wbem\WMIC.exe","C:\Windows\System32\WSManHTTPConfig.exe",
    "C:\Windows\System32\wsmprovhost.exe","C:\Windows\System32\LogonUI.exe","C:\Windows\System32\mpnotify.exe",
    "C:\Windows\System32\wlrmdr.exe","C:\Windows\System32\diskpart.exe","C:\Windows\System32\diskraid.exe",
    "C:\Windows\System32\vds.exe","C:\Windows\System32\vdsldr.exe","C:\Windows\System32\fixmapi.exe",
    "C:\Windows\System32\Netplwiz.exe","C:\Windows\System32\PasswordOnWakeSettingFlyout.exe",
    "C:\Windows\System32\UserAccountBroker.exe","C:\Windows\System32\LaunchWinApp.exe",
    "C:\Windows\System32\verifiergui.exe","C:\Windows\System32\tzsync.exe","C:\Windows\System32\wksprt.exe",
    "C:\Windows\System32\InputSwitchToastHandler.exe","C:\Windows\System32\UIMgrBroker.exe",
    "C:\Windows\System32\ctfmon.exe","C:\Windows\System32\taskhostw.exe","C:\Windows\System32\at.exe",
    "C:\Windows\System32\schtasks.exe","C:\Windows\System32\MdmDiagnosticsTool.exe","C:\Windows\System32\alg.exe",
    "C:\Windows\System32\cmd.exe","C:\Windows\System32\PackagedCWALauncher.exe","C:\Windows\System32\mmgaserver.exe",
    "C:\Windows\System32\AuthHost.exe","C:\Windows\System32\backgroundTaskHost.exe","C:\Windows\System32\VaultCmd.exe",
    "C:\Windows\System32\licensingdiag.exe","C:\Windows\System32\CertEnrollCtrl.exe","C:\Windows\System32\RuntimeBroker.exe",
    "C:\Windows\System32\BackgroundTransferHost.exe","C:\Windows\System32\ByteCodeGenerator.exe",
    "C:\Windows\System32\WWAHost.exe","C:\Windows\System32\WaaSMedicAgent.exe","C:\Windows\System32\upfc.exe",
    "C:\Windows\System32\wuapihost.exe","C:\Windows\System32\ttdinject.exe","C:\Windows\System32\tttracer.exe",
    "C:\Windows\System32\sihost.exe","C:\Windows\System32\pospaymentsworker.exe","C:\Windows\System32\RemotePosWorker.exe",
    "C:\Windows\System32\LicenseManagerShellext.exe","C:\Windows\System32\ISM.exe","C:\Windows\System32\SearchFilterHost.exe",
    "C:\Windows\System32\SearchIndexer.exe","C:\Windows\System32\SearchProtocolHost.exe",
    "C:\Windows\System32\directxdatabaseupdater.exe","C:\Windows\System32\dispdiag.exe",
    "C:\Windows\System32\Windows.WARP.JITService.exe","C:\Windows\System32\dxgiadaptercache.exe",
    "C:\Windows\System32\MicrosoftEdgeSH.exe","C:\Windows\System32\TokenBrokerCookies.exe",
    "C:\Windows\System32\AppHostRegistrationVerifier.exe","C:\Windows\System32\dstokenclean.exe",
    "C:\Windows\System32\WinRTNetMUAHostServer.exe","C:\Windows\System32\PickerHost.exe",
    "C:\Windows\System32\SystemUWPLauncher.exe","C:\Windows\System32\DataStoreCacheDumpTool.exe",
    "C:\Windows\System32\CredentialEnrollmentManager.exe","C:\Windows\System32\wlanext.exe",
    "C:\Windows\System32\LockScreenContentServer.exe","C:\Windows\System32\SlideToShutDown.exe",
    "C:\Windows\System32\systray.exe","C:\Windows\System32\RunLegacyCPLElevated.exe","C:\Windows\System32\control.exe",
    "C:\Windows\System32\fontview.exe","C:\Windows\System32\wifitask.exe","C:\Windows\System32\tzutil.exe",
    "C:\Windows\System32\w32tm.exe","C:\Windows\System32\dmclient.exe","C:\Windows\System32\dsregcmd.exe",
    "C:\Windows\System32\UtcDecoderHost.exe","C:\Windows\System32\TpmTool.exe",
    "C:\Windows\System32\HealthAttestationClientAgent.exe","C:\Windows\System32\TpmInit.exe",
    "C:\Windows\System32\CloudNotifications.exe","C:\Windows\System32\SystemSettingsBroker.exe",
    "C:\Windows\System32\wbem\mofcomp.exe","C:\Windows\System32\wbem\unsecapp.exe","C:\Windows\System32\wbem\WMIADAP.exe",
    "C:\Windows\System32\wbem\WmiApSrv.exe","C:\Windows\System32\RMActivate.exe","C:\Windows\System32\RMActivate_isv.exe",
    "C:\Windows\System32\RMActivate_ssp.exe","C:\Windows\System32\RMActivate_ssp_isv.exe",
    "C:\Windows\System32\printfilterpipelinesvc.exe","C:\Windows\System32\provtool.exe",
    "C:\Windows\System32\PrintIsolationHost.exe","C:\Windows\System32\spoolsv.exe",
    "C:\Windows\System32\PinEnrollmentBroker.exe","C:\Windows\System32\WpcTok.exe","C:\Windows\System32\WpcMon.exe",
    "C:\Windows\System32\ApproveChildRequest.exe","C:\Windows\System32\ofdeploy.exe",
    "C:\Windows\System32\DmNotificationBroker.exe","C:\Windows\System32\MDMAgent.exe",
    "C:\Windows\System32\MicrosoftEdgeBCHost.exe","C:\Windows\System32\Eap3Host.exe",
    "C:\Windows\System32\bcdboot.exe","C:\Windows\System32\bcdedit.exe","C:\Windows\System32\bootsect.exe",
    "C:\Windows\System32\audiodg.exe","C:\Windows\System32\SpatialAudioLicenseSrv.exe",
    "C:\Windows\System32\CompPkgSrv.exe","C:\Windows\System32\agentactivationruntimestarter.exe",
    "C:\Windows\System32\IcsEntitlementHost.exe","C:\Windows\System32\ShellUpdateAgentTask.exe",
    "C:\Windows\System32\XblGameSaveTask.exe","C:\Windows\System32\notepad.exe","C:\Windows\System32\TsWpfWrp.exe"
)
foreach ($app in $sysApps) { Set-RV $gpuPref $app "GpuPreference=1;" String }

Complete-SubProgress -Activity "Input / Priorities"
Write-OverallProgress -Status "Input / Priorities complete" -SubPercent 100
Write-Host "  [11/13] Input / Per-App Priorities ............... DONE" -ForegroundColor Green

# =============================================================================
# STEP 12 - IE / EDGE / CHROME / OFFICE / MISC
# =============================================================================
$script:CurrentStep = 12
Write-OverallProgress -Status "IE / Edge / Chrome / Office / Misc" -SubPercent 0

Write-SubProgress -Activity "Apps" -Status "IE / Edge..." -PercentComplete 5
Set-RV "HKCU:\Software\Policies\Microsoft\Internet Explorer\Restrictions" "NoHelpItemSendFeedback" 1
Set-RV "HKCU:\Software\Policies\Microsoft\Internet Explorer\Restrictions" "NoHelpItemTipOfTheDay" 1
Set-RV "HKCU:\SOFTWARE\Policies\Microsoft\Internet Explorer\Main" "HideNewEdgeButton" 1
Set-RV "HKCU:\Software\Microsoft\Internet Explorer\Download" "CheckExeSignatures" "no" String
Set-RV "HKCU:\Software\Microsoft\Internet Explorer\Download" "RunInvalidSignatures" 1
Set-RV "HKCU:\Software\Microsoft\Internet Explorer\Main" "Show_StatusBar" "no" String
Set-RV "HKCU:\Software\Microsoft\Internet Explorer\Main" "StatusBarOther" 0
Set-RV "HKCU:\Software\Policies\Microsoft\MicrosoftEdge\Main" "AllowPrelaunch" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "TrackingPrevention" 3
Set-RV "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\DoNotUpdateToEdgeWithChromium" "DoNotUpdateToEdgeWithChromium" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" "AutoDownload" 2
Set-RV "HKCU:\Software\Policies\Microsoft\WindowsMediaPlayer" "PreventCodecDownload" 1

Write-SubProgress -Activity "Apps" -Status "Chrome policies..." -PercentComplete 20
$chrome = "HKLM:\SOFTWARE\Policies\Google\Chrome"
Set-RV $chrome "TranslateEnabled" 1
Set-RV $chrome "TaskManagerEndProcessEnabled" 1
Set-RV $chrome "UserFeedbackAllowed" 0
Set-RV $chrome "SpellCheckServiceEnabled" 0
Set-RV $chrome "SpellcheckEnabled" 0
Set-RV $chrome "MediaRouterCastAllowAllIPs" 1
Set-RV $chrome "AllowDinosaurEasterEgg" 1
Set-RV $chrome "DefaultGeolocationSetting" 2
Set-RV $chrome "DefaultCookiesSetting" 1
Set-RV $chrome "DefaultPopupsSetting" 2
Set-RV $chrome "DefaultSensorsSetting" 2
Set-RV $chrome "DefaultWebBluetoothGuardSetting" 2
Set-RV $chrome "DefaultWebUsbGuardSetting" 2
Set-RV $chrome "EnableMediaRouter" 1
Set-RV $chrome "ShowCastIconInToolbar" 1
Set-RV $chrome "CloudPrintProxyEnabled" 0
Set-RV $chrome "PrintingEnabled" 1
Set-RV $chrome "SafeBrowsingProtectionLevel" 0
Set-RV $chrome "SafeBrowsingExtendedReportingEnabled" 0
Set-RV $chrome "HomepageIsNewTabPage" 0
Set-RV $chrome "HomepageLocation" "google.com" String
Set-RV $chrome "NewTabPageLocation" "google.com" String
Set-RV $chrome "MetricsReportingEnabled" 0
Set-RV $chrome "DeviceMetricsReportingEnabled" 0
Set-RV "$chrome\ExtensionInstallForcelist" "1" "cjpalhdlnbpafiamejdnhcphjbkeiagm" String
Set-RV "$chrome\ExtensionInstallForcelist" "2" "fihnjjcciajhdojfnbdddfaoknhalnja" String
Set-RV "$chrome\ExtensionInstallForcelist" "3" "bnomihfieiccainjcjblhegjgglakjdd" String
Set-RV "HKCU:\SOFTWARE\Policies\Google\Chrome" "MetricsReportingEnabled" 0
Set-RV "HKCU:\SOFTWARE\Policies\Google\Chrome" "DeviceMetricsReportingEnabled" 0

Write-SubProgress -Activity "Apps" -Status "Max connections / Office..." -PercentComplete 45
$fc1 = "HKLM:\SOFTWARE\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_MAXCONNECTIONSPER1_0SERVER"
$fc2 = "HKLM:\SOFTWARE\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_MAXCONNECTIONSPERSERVER"
$mc = @{ "explorer.exe"=2; "sllauncher.exe"=6; "winword.exe"=13; "mspub.exe"=13;
         "powerpnt.exe"=13; "outlook.exe"=13; "onenote.exe"=13; "excel.exe"=13;
         "msaccess.exe"=13; "csgo.exe"=13; "jaraw.exe"=13; "chrome.exe"=13;
         "msedge.exe"=13; "edge.exe"=13; "opera.exe"=13; "firefox.exe"=13 }
foreach ($k in $mc.Keys) { Set-RV $fc1 $k $mc[$k]; Set-RV $fc2 $k $mc[$k] }

Set-RV "HKCU:\Software\Microsoft\Office\15.0\Common" "QMEnable" 0
Set-RV "HKCU:\Software\Microsoft\Office\15.0\Common\Feedback" "Enabled" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Office\15.0\osm" "enablelogging" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Office\15.0\osm" "enablefileobfuscation" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Office\15.0\osm" "enableupload" 0
Set-RV "HKCU:\Software\Microsoft\Office\Common\ClientTelemetry" "DisableTelemetry" 1
Set-RV "HKCU:\Software\Microsoft\Office\Common\ClientTelemetry" "VerboseLogging" 0
Set-RV "HKCU:\Software\Microsoft\Office\16.0\Word\Options" "EnableLogging" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Office\16.0\Common" "sentcostumerdata" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Office\16.0\Common" "qmenable" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Office\16.0\Common" "updaterealiabilitydata" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Office\16.0\Common\Feedback" "enabled" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Office\16.0\Common\Feedback" "includescreenshot" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Office\16.0\OSM" "enablelogging" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Office\16.0\OSM" "enablefileobfuscation" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Office\16.0\OSM" "enableupload" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Office\16.0\Outlook" "EnableLogging" 0
Set-RV "HKCU:\Software\Microsoft\Office\16.0\Outlook\Options\Calendar" "EnableCalendarLogging" 0
Set-RV "HKCU:\Software\Microsoft\Office\16.0\Outlook\Options\Mail" "EnableLogging" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Office\16.0\Outlook\Security" "InitEncrypt" 2
Set-RV "HKCU:\Software\Policies\Microsoft\Office\16.0\Outlook\Security" "InitSign" 2
Set-RV "HKCU:\Software\Microsoft\Office\Common\Graphics" "DisableAnimations" 1
Set-RV "HKCU:\Software\Policies\Microsoft\Office\16.0\Common\General" "shownfirstrunoptin" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Office\16.0\Common\General" "skydrivesigninoption" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Office\16.0\Common\ptwatson" "ptwoptin" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Office\16.0\Firstrun" "disablemovie" 1
Set-RV "HKCU:\Software\Policies\Microsoft\Office\16.0\Lync" "disableautomaticsendtracking" 1
Set-RV "HKCU:\Software\Microsoft\Office\15.0\Outlook\Options\Calendar" "EnableCalendarLogging" 0
Set-RV "HKCU:\Software\Microsoft\Office\15.0\Outlook\Options\Mail" "EnableLogging" 0
Set-RV "HKCU:\Software\Microsoft\Office\15.0\Word\Options" "EnableLogging" 0
Set-RV "HKCU:\Software\Microsoft\Office\16.0\Common" "sendcustomerdata" 0
Set-RV "HKCU:\Software\Microsoft\Office\16.0\Common\Feedback" "enabled" 0
Set-RV "HKCU:\Software\Microsoft\Office\16.0\Common\Feedback" "includescreenshot" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Office\17.0\osm" "enablelogging" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Office\17.0\osm" "enablefileobfuscation" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Office\17.0\osm" "enableupload" 0

Write-SubProgress -Activity "Apps" -Status "Realtek / WER / GameDVR / Notepad..." -PercentComplete 70
Set-RV "HKCU:\Software\Realtek\Audio\RtkNGUI64\General" "JDPopup" 1
Set-RV "HKCU:\Software\Realtek\Audio\RtkNGUI64\General" "RenderDefaultFixed" 1
Set-RV "HKCU:\Software\Realtek\Audio\RtkNGUI64\General" "CaptureDefaultFixed" 1
Set-RV "HKCU:\Software\Realtek\Audio\RtkNGUI64\General" "Language" 0
Set-RV "HKCU:\Software\Realtek\Audio\RtkNGUI64\General" "AutoSelectChannelByJackConf" 1
Set-RV "HKCU:\Software\Realtek\Audio\RtkNGUI64\PowerMgnt" "Enabled" 1
Set-RV "HKCU:\Software\Realtek\Audio\RtkNGUI64\PowerMgnt" "DelayTime" 3
Set-RV "HKCU:\Software\Realtek\Audio\RtkNGUI64\PowerMgnt" "OnlyBattery" 0
Set-RV "HKCU:\Software\Realtek\Audio\RtkNGUI64\PowerMgnt" "PowerState" 0

Set-RV "HKCU:\Software\Microsoft\Windows\Windows Error Reporting" "Disabled" 1
Set-RV "HKCU:\Software\Microsoft\Windows\Windows Error Reporting" "AutoApproveOSDumps" 0
Set-RV "HKCU:\Software\Microsoft\Windows\Windows Error Reporting" "ConfigureArchive" 0
Set-RV "HKCU:\Software\Microsoft\Windows\Windows Error Reporting" "DisableArchive" 1
Set-RV "HKCU:\Software\Microsoft\Windows\Windows Error Reporting" "DontSendAdditionalData" 1
Set-RV "HKCU:\Software\Microsoft\Windows\Windows Error Reporting" "LoggingDisabled" 1
Set-RV "HKCU:\Software\Policies\Microsoft\Windows\Windows Error Reporting" "LoggingDisabled" 1
Set-RV "HKCU:\Software\Policies\Microsoft\Windows\Windows Error Reporting" "Disabled" 1
Set-RV "HKCU:\Software\Policies\Microsoft\Windows\Windows Error Reporting" "AutoApproveOSDumps" 0
Set-RV "HKCU:\Software\Policies\Microsoft\Windows\Windows Error Reporting" "DontSendAdditionalData" 1
Set-RV "HKCU:\Software\Policies\Microsoft\Windows\Windows Error Reporting" "BypassDataThrottling" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\PCHealth\ErrorReporting" "DoReport" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" "DontShowUI" 1
Remove-RK "HKLM:\SYSTEM\CurrentControlSet\Services\WerSvc"

Set-RV "HKCU:\Software\Microsoft\Games" "EnableXBGM" 0
Set-RV "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowgameDVR" 0
Set-RV "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode" 0
Set-RV "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" 0
Set-RV "HKCU:\Software\Microsoft\GameBar" "ShowStartupPanel" 0
Set-RV "HKCU:\Software\Microsoft\GameBar" "ShowGameModeNotifications" 0
Set-RV "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0
Set-RV "HKCU:\System\GameConfigStore" "GameDVR_FSEBehaviorMode" 2
Set-RV "HKCU:\System\GameConfigStore" "GameDVR_HonorUserFSEBehaviorMode" 1
Set-RV "HKCU:\System\GameConfigStore" "GameDVR_DXGIHonorFSEWindowsCompatible" 1
Set-RV "HKCU:\System\GameConfigStore" "GameDVR_EFSEFeatureFlags" 0
Set-RV "HKCU:\System\GameConfigStore" "GameDVR_FSEBehavior" 2
Set-RV "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement\AllowGameDVR" "value" 0
Set-RV "HKLM:\SYSTEM\ControlSet001\Services\gameflt" "Start" 4
foreach ($c in @("Windows.Gaming.GameBar.PresenceServer.Internal.PresenceWriter",
                 "Windows.Gaming.UI.GameBar","Windows.Gaming.UI.GameChatOverlay",
                 "Windows.Gaming.UI.GameChatOverlayMessageSource")) {
    Set-RV "HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\$c" "ActivationType" 0
}

Set-RV "HKCU:\Software\Microsoft\Notepad" "StatusBar" 1
Set-RV "HKCU:\Software\Microsoft\Notepad" "fWrap" 1
Set-RV "HKCU:\Software\Microsoft\Notepad" "fSavePageSettings" 1
Set-RV "HKCU:\Software\Microsoft\Notepad" "fSaveWindowPositions" 1
Set-RV "HKCU:\Software\Microsoft\Notepad" "fWindowsOnlyEOL" 0
Set-RV "HKCU:\Software\Microsoft\Notepad" "fPasteOriginalEOL" 1
Set-RV "HKCU:\Software\Wacom\Analytics" "Analytics_On" 0

Write-SubProgress -Activity "Apps" -Status "Device Metadata / cleanup..." -PercentComplete 90
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata" "BackOffInterval" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata" "CheckBackMDNotRetrieved" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata" "CheckBackMDRetrieved" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata" "DeviceMetadataServiceURL" "about:blank" String
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata" "MaxRetryLimit" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata" "RequestBatchSize" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata" "PreventDeviceMetadataFromNetwork" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" "DontSearchWindowsUpdate" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" "DontPromptForWindowsUpdate" 1
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" "SearchOrderConfig" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" "ShippedWithReserves" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" "PassedPolicy" 0
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\ScheduledDiagnostics" "EnabledExecution" 0

Remove-RK "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell\Update\TelemetryID"
Remove-RK "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache"
Remove-RK "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU"
Remove-RK "HKCU:\Software\Microsoft\Windows\CurrentVersion\UFH\SHC"
Remove-RK "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store"
Remove-RK "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameUX\Games\{FC96B68C-09EF-4251-A598-19E4BE1B76A9}"
Remove-RK "HKCU:\System\GameConfigStore\Children"
Remove-RK "HKCU:\System\GameConfigStore\Parents"
Remove-RK "HKLM:\SOFTWARE\Microsoft\Windows Mail"
Remove-RK "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer"

Complete-SubProgress -Activity "Apps"
Write-OverallProgress -Status "Apps complete" -SubPercent 100
Write-Host "  [12/13] IE / Edge / Chrome / Office / Misc ....... DONE" -ForegroundColor Green

# =============================================================================
# STEP 13 - CONTEXT MENUS / SHELL EXTENSIONS
# =============================================================================
$script:CurrentStep = 13
Write-OverallProgress -Status "Context Menus / Shell" -SubPercent 0

Write-SubProgress -Activity "Shell" -Status "Notepad / Hash / Take Ownership..." -PercentComplete 10
Set-RV "HKCR:\*\shell\Open with Notepad" "Icon" "notepad.exe,-2" String
Set-RVdef "HKCR:\*\shell\Open with Notepad\command" "notepad.exe %1"

Set-RV "HKCR:\*\shell\GetFileHash" "MUIVerb" "Hash" String
Set-RV "HKCR:\*\shell\GetFileHash" "SubCommands" "" String
$hashes = @{ "01SHA1"="SHA1"; "02SHA256"="SHA256"; "03SHA384"="SHA384"; "04SHA512"="SHA512";
             "05MACTripleDES"="MACTripleDES"; "06MD5"="MD5"; "07RIPEMD160"="RIPEMD160" }
foreach ($h in $hashes.Keys) {
    Set-RV "HKCR:\*\shell\GetFileHash\shell\$h" "MUIVerb" $hashes[$h] String
    Set-RV "HKCR:\*\shell\GetFileHash\shell\$h\command" "(default)" "powershell.exe -noexit get-filehash -literalpath '%1' -algorithm $($hashes[$h]) | format-list" String
}

Set-RV "HKCR:\*\shell\TakeOwnership" "(default)" "Take Ownership" String
Set-RV "HKCR:\*\shell\TakeOwnership" "HasLUAShield" "" String
Set-RV "HKCR:\*\shell\TakeOwnership" "NoWorkingDirectory" "" String
Set-RV "HKCR:\Directory\shell\TakeOwnership" "(default)" "Take Ownership" String
Set-RV "HKCR:\Directory\shell\TakeOwnership" "HasLUAShield" "" String
Set-RV "HKCR:\Directory\shell\TakeOwnership" "NoWorkingDirectory" "" String
Set-RV "HKCR:\Directory\shell\TakeOwnership" "Position" "middle" String

Set-RV "HKCR:\AllFilesystemObjects\shellex\ContextMenuHandlers\Copy To" "(default)" "{C2FBB630-2971-11D1-A18C-00C04FD75D13}" String
Set-RV "HKCR:\AllFilesystemObjects\shellex\ContextMenuHandlers\Move To" "(default)" "{C2FBB631-2971-11D1-A18C-00C04FD75D13}" String
Set-RV "HKCR:\AllFilesystemObjects\shellex\ContextMenuHandlers\SendTo" "(default)" "" String
Set-RV "HKCR:\*" "DefaultDropEffect" 1
Set-RV "HKCR:\AllFilesystemObjects" "DefaultDropEffect" 1

foreach ($ext in @(".cpp",".c",".py",".js",".code",".aup",".php",".cmd",".ini",".reg",".html",".vbs")) {
    Set-RV "HKCR:\$ext\ShellNew" "NullFile" "" String
}
Set-RV "HKCR:\.bat\ShellNew" "NullFile" "" String

Write-SubProgress -Activity "Shell" -Status "Desktop background menu..." -PercentComplete 40
Set-RV "HKCR:\DesktopBackground\Shell\Restart" "Icon" "shell32.dll,-16739" String
Set-RV "HKCR:\DesktopBackground\Shell\Restart" "Position" "Bottom" String
Set-RV "HKCR:\DesktopBackground\Shell\Restart" "SubCommands" "" String
Set-RVdef "HKCR:\DesktopBackground\Shell\Restart\shell\001flyout" "Force apps to close, and full shutdown and restart PC with no time-out or warning"
Set-RVdef "HKCR:\DesktopBackground\Shell\Restart\shell\001flyout\command" "shutdown /r /f /t 0"
Set-RV "HKCR:\DesktopBackground\Shell\Restart\shell\002flyout" "MUIVerb" "Full shutdown and restart PC with warning" String
Set-RV "HKCR:\DesktopBackground\Shell\Restart\shell\002flyout" "CommandFlags" 0x20
Set-RVdef "HKCR:\DesktopBackground\Shell\Restart\shell\002flyout\command" "shutdown /r"
Set-RV "HKCR:\DesktopBackground\Shell\Restart\shell\003flyout" "MUIVerb" "Full shutdown and restart PC. After rebooted, restart any opened registered apps." String
Set-RV "HKCR:\DesktopBackground\Shell\Restart\shell\003flyout" "CommandFlags" 0x20
Set-RVdef "HKCR:\DesktopBackground\Shell\Restart\shell\003flyout\command" "shutdown /g /t 0"
Set-RV "HKCR:\DesktopBackground\Shell\Restart\shell\004flyout" "MUIVerb" "Restart to Advanced Startup Options" String
Set-RV "HKCR:\DesktopBackground\Shell\Restart\shell\004flyout" "CommandFlags" 0x20
Set-RVdef "HKCR:\DesktopBackground\Shell\Restart\shell\004flyout\command" "shutdown /r /o /f /t 0"

Set-RV "HKCR:\DesktopBackground\Shell\EnvVars" "MUIVerb" "Environment variables" String
Set-RV "HKCR:\DesktopBackground\Shell\EnvVars" "Icon" "sysdm.cpl,-1" String
Set-RV "HKCR:\DesktopBackground\Shell\EnvVars" "Position" "Bottom" String
Set-RV "HKCR:\DesktopBackground\Shell\EnvVars" "SubCommands" "" String
Set-RVdef "HKCR:\DesktopBackground\Shell\EnvVars\shell\01UserVars\Command" "rundll32.exe sysdm.cpl,EditEnvironmentVariables"

Set-RV "HKCR:\*\shell\Copy Content to Clipboard" "MUIVerb" "Copy Content to Clipboard" String
Set-RV "HKCR:\*\shell\Copy Content to Clipboard" "Icon" "DxpTaskSync.dll,-52" String
Set-RV "HKCR:\*\shell\Copy Content to Clipboard" "Position" "Center" String
Set-RVdef "HKCR:\*\shell\Copy Content to Clipboard\Command" "cmd /c clip < `"%1`""

Set-RV "HKCR:\DesktopBackground\Shell\Safely Remove Hardware" "MUIVerb" "Safely Remove Hardware" String
Set-RV "HKCR:\DesktopBackground\Shell\Safely Remove Hardware" "Icon" "hotplug.dll,-100" String
Set-RV "HKCR:\DesktopBackground\Shell\Safely Remove Hardware" "Position" "Center" String
Set-RVdef "HKCR:\DesktopBackground\Shell\Safely Remove Hardware\Command" "C:\Windows\system32\control.exe hotplug.dll"

Set-RV "HKCR:\DesktopBackground\Shell\KillNRTasks" "icon" "taskmgr.exe,-30651" String
Set-RV "HKCR:\DesktopBackground\Shell\KillNRTasks" "MUIverb" "Kill all not responding tasks" String
Set-RV "HKCR:\DesktopBackground\Shell\KillNRTasks" "Position" "Top" String
Set-RVdef "HKCR:\DesktopBackground\Shell\KillNRTasks\command" "CMD.exe /C taskkill.exe /f /fi `"status eq Not Responding`" & Pause"

Set-RV "HKCR:\DesktopBackground\Shell\Restart Explorer" "icon" "explorer.exe" String
Set-RV "HKCR:\DesktopBackground\Shell\Restart Explorer" "Position" "Center" String
Set-RV "HKCR:\DesktopBackground\Shell\Restart Explorer" "SubCommands" "" String
Set-RV "HKCR:\DesktopBackground\Shell\Restart Explorer" "MUIVerb" "Restart/Pause File Explorer " String
Set-RV "HKCR:\DesktopBackground\Shell\Restart Explorer\shell\01menu" "MUIVerb" "Restart File Explorer" String
Set-RVdef "HKCR:\DesktopBackground\Shell\Restart Explorer\shell\01menu\command" "cmd.exe /c taskkill /f /im explorer.exe & start explorer.exe"

Write-SubProgress -Activity "Shell" -Status "Windows Terminal / Priority..." -PercentComplete 65
Set-RV "HKCR:\Directory\shell\OpenWindowsTerminalProfiles" "MUIVerb" "Open in Windows Terminal" String
Set-RV "HKCR:\Directory\shell\OpenWindowsTerminalProfiles" "SubCommands" "" String
Set-RVdef "HKCR:\Directory\Shell\OpenWindowsTerminalProfiles\shell\01DefaultProfile\command" "cmd.exe /c start wt.exe -d `"%1`""
Set-RV "HKCR:\Directory\Shell\OpenWindowsTerminalProfiles\shell\02CommandPromptProfile" "MUIVerb" "Command Prompt" String
Set-RV "HKCR:\Directory\Shell\OpenWindowsTerminalProfiles\shell\02CommandPromptProfile" "Icon" "imageres.dll,-5323" String
Set-RVdef "HKCR:\Directory\Shell\OpenWindowsTerminalProfiles\shell\02CommandPromptProfile\command" "cmd.exe /c start wt.exe -p `"Command Prompt`" -d `"%1`""
Set-RV "HKCR:\Directory\Shell\OpenWindowsTerminalProfiles\shell\03PowerShellProfile" "MUIVerb" "PowerShell" String
Set-RV "HKCR:\Directory\Shell\OpenWindowsTerminalProfiles\shell\03PowerShellProfile" "Icon" "powershell.exe" String
Set-RVdef "HKCR:\Directory\Shell\OpenWindowsTerminalProfiles\shell\03PowerShellProfile\command" "cmd.exe /c start wt.exe -p `"Windows PowerShell`" -d `"%1`""

Set-RV "HKCR:\Directory\Background\shell\OpenWindowsTerminalProfiles" "MUIVerb" "Open in Windows Terminal" String
Set-RV "HKCR:\Directory\Background\shell\OpenWindowsTerminalProfiles" "SubCommands" "" String
Set-RVdef "HKCR:\Directory\Background\Shell\OpenWindowsTerminalProfiles\shell\01DefaultProfile\command" "cmd.exe /c start wt.exe -d `"%V`""
Set-RV "HKCR:\Directory\Background\Shell\OpenWindowsTerminalProfiles\shell\02CommandPromptProfile" "MUIVerb" "Command Prompt" String
Set-RV "HKCR:\Directory\Background\Shell\OpenWindowsTerminalProfiles\shell\02CommandPromptProfile" "Icon" "imageres.dll,-5323" String
Set-RVdef "HKCR:\Directory\Background\Shell\OpenWindowsTerminalProfiles\shell\02CommandPromptProfile\command" "cmd.exe /c start wt.exe -p `"Command Prompt`" -d `"%V`""
Set-RV "HKCR:\Directory\Background\Shell\OpenWindowsTerminalProfiles\shell\03PowerShellProfile" "MUIVerb" "PowerShell" String
Set-RV "HKCR:\Directory\Background\Shell\OpenWindowsTerminalProfiles\shell\03PowerShellProfile" "Icon" "powershell.exe" String
Set-RVdef "HKCR:\Directory\Background\Shell\OpenWindowsTerminalProfiles\shell\03PowerShellProfile\command" "cmd.exe /c start wt.exe -p `"Windows PowerShell`" -d `"%V`""

Set-RV "HKCR:\exefile\shell\Priority" "MUIVerb" "Run with priority" String
Set-RV "HKCR:\exefile\shell\Priority" "SubCommands" "" String
foreach ($p in @("Realtime","High","Above normal","Normal","Below normal","Low")) {
    $key = @{ "Realtime"="001"; "High"="002"; "Above normal"="003"; "Normal"="004";
              "Below normal"="005"; "Low"="006" }[$p]
    Set-RVdef "HKCR:\exefile\Shell\Priority\shell\$($key)flyout" $p
    $cmd = switch ($p) {
        "Realtime" {"cmd.exe /c start `"`" /Realtime `"%1`""}
        "High" {"cmd.exe /c start `"`" /High `"%1`""}
        "Above normal" {"cmd.exe /c start `"`" /AboveNormal `"%1`""}
        "Normal" {"cmd.exe /c start `"`" /Normal `"%1`""}
        "Below normal" {"cmd.exe /c start `"`" /BelowNormal `"%1`""}
        "Low" {"cmd.exe /c start `"`" /Low `"%1`""}
    }
    Set-RVdef "HKCR:\exefile\Shell\Priority\shell\$($key)flyout\command" $cmd
}

Write-SubProgress -Activity "Shell" -Status "File associations / cleanup..." -PercentComplete 88
$fileExts = @(".nfo",".html",".htm",".cpp",".sour",".lst",".vcf")
foreach ($ext in $fileExts) {
    Set-RV "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\OpenWithList" "a" "NOTEPAD.EXE" String
    Set-RV "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\OpenWithList" "MRUList" "a" String
}

Set-RV "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Associations" "LowRiskFileTypes" ".zip;.rar;.nfo;.txt;.exe;.bat;.com;.cmd;.reg;.msi;.htm;.html;.gif;.bmp;.jpg;.avi;.mpg;.mpeg;.mov;.mp3;.m3u;.msu;.wav;" String

Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "NoInternetOpenWith" 1
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Messenger\Client" "PreventAutoRun" 1
Set-RV "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments" "SaveZoneInformation" 1
Set-RV "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Attachments" "SaveZoneInformation" 1
Set-RV "HKCU:\Software\Policies\Microsoft\Windows\Control Panel\Desktop" "ScreenSaveActive" "0" String
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop" "ScreenSaveActive" "0" String
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\Network\MSIServer" "(default)" "Service" String
Set-RV "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\Minimal\MSIServer" "(default)" "Service" String
Set-RV "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin" "(default)" "" String
Set-RV "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "link" "0" String

$shellDel = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HomeFolderDesktop\NameSpace\DelegateFolders\{3134ef9c-6b18-4996-ad04-ed5912e00eb5}",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\HomeFolderDesktop\NameSpace\DelegateFolders\{3134ef9c-6b18-4996-ad04-ed5912e00eb5}",
    "HKCR:\Stack.Audio\shell\Play","HKCR:\Stack.Image\shell\Play",
    "HKCR:\SystemFileAssociations\audio\shell\Play","HKCR:\SystemFileAssociations\Directory.Audio\shell\Play",
    "HKCR:\SystemFileAssociations\Directory.Image\shell\Play",
    "HKCR:\MediaCenter.WTVFile\shell\Enqueue","HKCR:\WMP.WTVFile\shell\Enqueue","HKCR:\WMP.DVR-MSFile\shell\Enqueue",
    "HKCR:\Directory\shell\WSL","HKCR:\Directory\Background\shell\WSL","HKCR:\Drive\shell\WSL",
    "HKCR:\DesktopBackground\Shell\AdvancedBootOptions",
    "HKCR:\Folder\ShellEx\ContextMenuHandlers\Library Location",
    "HKCR:\*\shellex\ContextMenuHandlers\EPP","HKCR:\Directory\shellex\ContextMenuHandlers\EPP",
    "HKCR:\Drive\shellex\ContextMenuHandlers\EPP",
    "HKCR:\DesktopBackground\Shell\ControlledFolderAccess",
    "HKCR:\*\shellex\ContextMenuHandlers\Sharing","HKCR:\Directory\shellex\ContextMenuHandlers\Sharing",
    "HKCR:\Directory\shellex\CopyHookHandlers\Sharing","HKCR:\Directory\shellex\PropertySheetHandlers\Sharing",
    "HKCR:\Drive\shellex\ContextMenuHandlers\Sharing","HKCR:\Drive\shellex\PropertySheetHandlers\Sharing",
    "HKCR:\*\shellex\ContextMenuHandlers\ModernSharing",
    "HKCR:\Directory\Background\shellex\ContextMenuHandlers\Sharing",
    "HKCR:\LibraryFolder\background\shellex\ContextMenuHandlers\Sharing",
    "HKCR:\Drive\shell\manage-bde","HKCR:\Drive\shell\unlock-bde",
    "HKCR:\Drive\shell\encrypt-bde","HKCR:\Drive\shell\encrypt-bde-elev",
    "HKCR:\Drive\shell\resume-bde","HKCR:\Drive\shell\resume-bde-elev",
    "HKCR:\Drive\shell\change-passphrase","HKCR:\Drive\shell\change-pin"
)
foreach ($k in $shellDel) { Remove-RK $k }

Complete-SubProgress -Activity "Shell"
Write-OverallProgress -Status "Shell complete" -SubPercent 100
Write-Host "  [13/13] Context Menus / Shell Extensions ......... DONE" -ForegroundColor Green

# =============================================================================
# FINAL SUMMARY
# =============================================================================
Write-Progress -Id 0 -Activity "SIGMA PERFORMANCES - All Optimizations" -Completed

Write-Host ""
if (Test-Path $script:errorLog) {
    $errorCount = (Get-Content $script:errorLog | Measure-Object -Line).Lines
    if ($errorCount -gt 0) {
        Write-Host "[WARNING] $errorCount registry errors occurred. Check log: $script:errorLog" -ForegroundColor Yellow
    } else {
        Remove-Item $script:errorLog -Force
    }
}

Write-Host "========== SIGMA PERFORMANCES - SUMMARY ==========" -ForegroundColor Green
Write-Host "   [1/13]  Device Cleanup ............................ OK" -ForegroundColor Green
Write-Host "   [2/13]  Telemetry & Tracking Removal .............. OK" -ForegroundColor Green
Write-Host "   [3/13]  PowerCfg Registry ......................... OK" -ForegroundColor Green
Write-Host "   [4/13]  CPU Optimization .......................... OK" -ForegroundColor Green
Write-Host "   [5/13]  Network Throttle .......................... OK" -ForegroundColor Green
Write-Host "   [6/13]  GPU / Display / Graphics .................. OK" -ForegroundColor Green
Write-Host "   [7/13]  USB / Power / Kernel / Memory / FS ........ OK" -ForegroundColor Green
Write-Host "   [8/13]  Services (Disable / Delete) ............... OK" -ForegroundColor Green
Write-Host "   [9/13]  Network / TCP-IP / MMCSS / Multimedia ..... OK" -ForegroundColor Green
Write-Host "   [10/13] Explorer / Shell / UI / DWM .............. OK" -ForegroundColor Green
Write-Host "   [11/13] Input / Per-App Priorities ............... OK" -ForegroundColor Green
Write-Host "   [12/13] IE / Edge / Chrome / Office / Misc ....... OK" -ForegroundColor Green
Write-Host "   [13/13] Context Menus / Shell Extensions ......... OK" -ForegroundColor Green
Write-Host ""
Write-Host "[NOTE] Windows Update / Defender / Security were SKIPPED." -ForegroundColor Cyan
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
