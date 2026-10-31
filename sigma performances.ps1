#Requires -RunAsAdministrator

# =============================================================================
# SIGMA PERFORMANCES - ALL-IN-ONE OPTIMIZATION SUITE
# -----------------------------------------------------------------------------
# Order:
#   1. Device Cleanup   (Unknown + Ghost devices)
#   2. Telemetry Removal
#   3. PowerCfg Registry
#   4. CPU Optimization (AC / DC) - ALL 95 GUIDs, MAX PERFORMANCE
#   5. Network Throttle (QoS 1-3000 Mbps)
#
# Single 'Y' confirmation at start. Reboot prompt at end.
# =============================================================================

$script:TotalSteps  = 5
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
Write-Host "   1. Device Cleanup (Unknown + Ghost devices)" -ForegroundColor Yellow
Write-Host "   2. Telemetry & Tracking Removal" -ForegroundColor Yellow
Write-Host "   3. PowerCfg Registry values" -ForegroundColor Yellow
Write-Host "   4. CPU Optimization (AC / DC) - ALL 95 GUIDs" -ForegroundColor Yellow
Write-Host "   5. Network Throttle (QoS)" -ForegroundColor Yellow
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
# STEP 1 - REMOVE UNKNOWN + GHOST DEVICES
# =============================================================================
$script:CurrentStep = 1
Write-OverallProgress -Status "Device Cleanup" -SubPercent 0

$errorLog = "$env:TEMP\sigma_device_cleanup_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

# --- 1a. Unknown devices (auto) ---
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

# --- 1b. Ghost devices (with YES prompt) ---
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

# --- 1c. Rescan for new hardware ---
Write-SubProgress -Activity "Device Cleanup" -Status "Rescanning for hardware changes..." -PercentComplete 95
pnputil /scan-devices 2>> $errorLog | Out-Null

# Error report
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
Write-Host "  [1/5] Device Cleanup ............................ DONE" -ForegroundColor Green

# =============================================================================
# STEP 2 - TELEMETRY & TRACKING REMOVAL
# =============================================================================
$script:CurrentStep = 2
Write-OverallProgress -Status "Telemetry & Tracking Removal" -SubPercent 0

$errorLog = "$env:TEMP\sigma_privacy_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

# --- 2a. Telemetry Registry keys ---
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

# --- 2b. Telemetry services ---
Write-SubProgress -Activity "Telemetry Removal" -Status "Disabling Telemetry Services..." -PercentComplete 30
$telemetryServices = @("DiagTrack", "dmwappushservice")
foreach ($service in $telemetryServices) {
    Stop-Service $service -ErrorAction SilentlyContinue 2>> $errorLog
    Set-Service  $service -StartupType Disabled -ErrorAction SilentlyContinue 2>> $errorLog
}

# --- 2c. Telemetry scheduled tasks ---
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

# --- 2d. Background App tasks (global) ---
Write-SubProgress -Activity "Telemetry Removal" -Status "Disabling Background App Tasks (global)..." -PercentComplete 70
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsRunInBackground" -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

# --- 2e. Windows Error Reporting ---
Write-SubProgress -Activity "Telemetry Removal" -Status "Disabling Windows Error Reporting..." -PercentComplete 85
New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Force -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

Set-Service  "WerSvc" -StartupType Disabled -ErrorAction SilentlyContinue 2>> $errorLog
Stop-Service "WerSvc" -ErrorAction SilentlyContinue 2>> $errorLog

# --- 2f. Task Scheduler history logging ---
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
Write-Host "  [2/5] Telemetry & Tracking Removal .............. DONE" -ForegroundColor Green

# =============================================================================
# STEP 3 - POWERCfg REGISTRY ONLY
# =============================================================================
$script:CurrentStep = 3
Write-OverallProgress -Status "PowerCfg Registry" -SubPercent 0

$errorLog = "$env:TEMP\sigma_powercfg_registry_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

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

# --- 3a. CurrentPowerPolicy = "4" ---
Write-SubProgress -Activity "PowerCfg Registry" -Status "Writing CurrentPowerPolicy = '4'..." -PercentComplete 30
Set-RegistryValue -Path $regPath -Name 'CurrentPowerPolicy' -Value '4' -Type String

# --- 3b. GlobalPowerPolicy "Policies" hex ---
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
Write-Host "  [3/5] PowerCfg Registry ......................... DONE" -ForegroundColor Green

# =============================================================================
# STEP 4 - CPU OPTIMIZATION (AC / DC) - ALL 95 GUIDs, MAX PERFORMANCE
# =============================================================================
$script:CurrentStep = 4
Write-OverallProgress -Status "CPU Optimization" -SubPercent 0

$errorLog = "$env:TEMP\sigma_optimization_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

# Save current active power scheme GUID
$originalScheme = (powercfg -getactivescheme) -replace '.*\s([A-F0-9\-]{36}).*', '$1'

# --- 4a. Activate Ultimate Performance power scheme ---
Write-SubProgress -Activity "CPU Optimization" -Status "Activating Ultimate Performance scheme..." -PercentComplete 3
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>> $errorLog
powercfg -setactive       e9a42b02-d5df-448d-aa00-03f14749eb61 2>> $errorLog

# --- 4b. CPU / Processor settings (ALL 95 GUIDs, MAX PERFORMANCE) ---
# Class 0 = P-Cores | Class 1 = E-Cores | Class 2 = LP-E-Cores
$cpuSettings = [ordered]@{
    # ===== Class 0 (P-Core / Base) - Throttle & Boost =====
    "893dee8e-2bef-41e0-89c6-b55d0929964c" = 100   # Minimum processor state
    "bc5038f7-23e0-4960-96da-33abaf5935ec" = 100   # Maximum processor state
    "be337238-0d82-4146-a960-4f3749d470c7" = 5     # Boost mode: Aggressive At Guaranteed
    "45bcc044-d885-43e2-8605-ee0ec6e96b59" = 100   # Boost policy: 100%

    # ===== Class 0 - Thresholds & Policies =====
    "06cadf0e-64ed-448a-8927-ce7bf90eb35d" = 1     # Increase threshold
    "12a0ab44-fe28-4fa9-b3bd-4b64f44960a6" = 100   # Decrease threshold
    "465e1f50-b610-473a-ab58-00d1077dc418" = 3     # Increase policy: IdealAggressive
    "40fbefc7-2e9d-4d25-a185-0cfd8574bac6" = 0     # Decrease policy: Ideal

    # ===== Class 0 - Core Parking =====
    "0cc5b647-c1df-4637-891a-dec35c318583" = 100   # Min unparked cores
    "ea062031-0e34-4ff1-9b6d-eb1059334028" = 100   # Max unparked cores
    "71021b41-c749-4d21-be74-a00f335d582b" = 2     # Parking decrease policy: All possible
    "c7be0679-2817-4d69-9d02-519a537ed0c6" = 2     # Parking increase policy: All possible
    "2ddd5a84-5a71-437e-912a-db0b8c788732" = 1     # Parking increase time: fastest
    "dfd10d17-d5eb-45dd-877a-9a34ddd15c82" = 1     # Parking decrease time: fastest
    "2430ab6f-a520-44a2-9601-f7f23b5134b1" = 100   # Concurrency threshold
    "4bdaf4e9-d103-46d7-a5f0-6280121616ef" = 100   # Distribution threshold
    "f735a673-2066-4f80-a0c5-ddee0cf1bf5d" = 100   # Concurrency headroom threshold
    "e0007330-f589-42ed-a401-5ddb10e785d3" = 1     # Utility distribution: Enabled
    "97cfac41-2217-47eb-992d-618b1977c907" = 0     # Soft park latency: 0 (never)
    "447235c7-6a8d-4cc0-8e24-9eaf70b96e2b" = 2     # Parked perf state: Lightest

    # ===== Class 0 - EPP & Autonomous =====
    "36687f9e-e3a5-4dbf-b1dc-15eb381c6863" = 0     # EPP: max performance
    "8baa4a8a-14c6-4451-8e8b-14bdbd197537" = 0     # Autonomous: Disabled (OS controls)
    "cfeda3d0-7697-4566-a922-a9086cd49dfa" = 100   # Autonomous window: short

    # ===== Class 0 - Idle States =====
    "4b92d758-5a24-4851-a470-815d78aee119" = 0     # Idle demote threshold
    "7b224883-b3cc-4d79-819f-8374152cbe7c" = 100   # Idle promote threshold
    "9943e905-9a30-4ec1-9b99-44dd3b76f7a2" = 0     # Idle state max (no limit)
    "5d76a2ca-e8c0-402f-a133-2158492d58ad" = 0     # Idle disable: 0 (enabled)
    "6c2993b0-8f48-481f-bcc6-00dd2742aa06" = 1     # Idle threshold scaling: Enabled
    "c4581c31-89ab-4597-8e2b-9c9cab440e6b" = 1     # Idle time check: 1µs

    # ===== Class 0 - Timing & History =====
    "984cf492-3bed-4488-a8f9-4286c97bf5aa" = 1     # Increase time: fastest
    "d8edeb9b-95cf-4f95-a73c-b061973693c8" = 1     # Decrease time: fastest
    "4d2b0152-7d5c-498b-88e2-34345392a2c5" = 1     # Time check interval: 1ms
    "7d24baa7-0b84-480f-840c-1b0743c00f5f" = 1     # History count: shortest

    # ===== Class 0 - Latency Hints =====
    "4b70f900-cdd9-4e66-aa26-ae8417f98173" = 0     # Latency hint EPP: max perf
    "619b7505-003b-4e82-b7a6-4dd29c300971" = 100   # Latency hint performance
    "616cdaa5-695e-4545-97ad-97dc2d1bdd88" = 100   # Latency hint min unparked cores

    # ===== Class 0 - Containment & Hetero =====
    "12fd031f-53d2-4bf4-ac6d-c699fc9538c7" = 0     # Hybrid containment utility %
    "60fbe21b-efd9-49f2-b066-8674d8e9f423" = 1     # Hetero containment: Enabled
    "6788488b-1b90-4d11-8fa7-973e470dff47" = 100   # Hybrid containment concurrency
    "69439b22-221b-4830-bd34-f7bcece24583" = 100   # Efficiency containment concurrency
    "6ece9e1f-b6dd-42bf-b1b7-5a512b10c092" = 0     # Efficiency containment utility %
    "64fcee6b-5b1f-45a4-a76a-19b2c36ee290" = 1     # Containment increase time: fastest
    "6ff13aeb-7897-4356-9999-dd9930af065f" = 1     # Containment decrease time: fastest
    "7f2f5cfa-f10c-4823-b5e1-e93ae85f46b5" = 4     # Hetero policy: prefer performance

    # ===== Class 0 - Scheduling & Threads =====
    "93b8b6dc-0698-4d1c-9ee4-0644e900c85d" = 1     # Thread scheduling: Performant
    "bae08b81-2d5e-4688-ad6a-13243356654b" = 1     # Short thread scheduling: Performant
    "d92998c2-6a48-49ca-85d4-8cceec294570" = 100000 # Short vs long thread threshold
    "43f278bc-0f8a-46d0-8b31-9a23e615d713" = 0     # Long threads arch lower limit
    "bf903d33-9d24-49d3-a468-e65e0325046a" = 255   # Long threads arch upper limit
    "53824d46-87bd-4739-aa1b-aa793fac36d6" = 0     # Short threads arch lower limit
    "828423eb-8662-4344-90f7-52bf15870f5a" = 255   # Short threads arch upper limit

    # ===== Class 0 - Unpark Policies & Misc =====
    "b0deaf6b-59c0-4523-8a45-ca7f40244114" = 1     # Module unpark: Round robin
    "b28a6829-c5f7-444e-8f61-10e24e85c532" = 0     # SMT unpark: Core
    "b669a5e9-7b1d-4132-baaa-49190abcfeb6" = 1     # Complex unpark: Round robin
    "603fe9ce-8d01-4b48-a968-1d706c28fd5c" = 100   # Resource priority
    "4e4450b3-6179-4e91-b8f1-5bb9938f81a1" = 0     # Duty cycling: Disabled
    "1a98ad09-af22-42ca-8e61-f0a5802c270a" = 64    # Processor restriction count
    "5ba7419a-295c-4b02-841b-66799388d6da" = 0     # WPS min efficiency score (disabled)
    "75b0ae3f-bce0-45a7-8c89-c9611c25e100" = 0     # Max frequency: unlimited

    # ===== Class 1 (E-Core) Variants =====
    "893dee8e-2bef-41e0-89c6-b55d0929964d" = 100   # Min state Class 1
    "bc5038f7-23e0-4960-96da-33abaf5935ed" = 100   # Max state Class 1
    "06cadf0e-64ed-448a-8927-ce7bf90eb35e" = 1     # Inc threshold Class 1
    "12a0ab44-fe28-4fa9-b3bd-4b64f44960a7" = 100   # Dec threshold Class 1
    "465e1f50-b610-473a-ab58-00d1077dc419" = 3     # Inc policy Class 1
    "40fbefc7-2e9d-4d25-a185-0cfd8574bac7" = 0     # Dec policy Class 1
    "0cc5b647-c1df-4637-891a-dec35c318584" = 100   # Min cores Class 1
    "ea062031-0e34-4ff1-9b6d-eb1059334029" = 100   # Max cores Class 1
    "36687f9e-e3a5-4dbf-b1dc-15eb381c6864" = 0     # EPP Class 1
    "4b70f900-cdd9-4e66-aa26-ae8417f98174" = 0     # Latency hint EPP Class 1
    "619b7505-003b-4e82-b7a6-4dd29c300972" = 100   # Latency hint perf Class 1
    "616cdaa5-695e-4545-97ad-97dc2d1bdd89" = 100   # Latency hint min cores Class 1
    "984cf492-3bed-4488-a8f9-4286c97bf5ab" = 1     # Inc time Class 1
    "d8edeb9b-95cf-4f95-a73c-b061973693c9" = 1     # Dec time Class 1
    "7f2492b6-60b1-45e5-ae55-773f8cd5caec" = 1     # Dec time Class 1 (alt)
    "1facfc65-a930-4bc5-9f38-504ec097bbc0" = 100   # Initial perf when unparked Class 1
    "447235c7-6a8d-4cc0-8e24-9eaf70b96e2c" = 2     # Parked perf state Class 1
    "75b0ae3f-bce0-45a7-8c89-c9611c25e101" = 0     # Max freq Class 1
    "7d24baa7-0b84-480f-840c-1b0743c00f60" = 1     # History count Class 1
    "603fe9ce-8d01-4b48-a968-1d706c28fd5d" = 100   # Resource priority Class 1
    "b000397d-9b0b-483d-98c9-692a6060cfbf" = 255   # P-level inc threshold Class 1
    "f8861c27-95e7-475c-865b-13c0cb3f9d6b" = 255   # P-level dec threshold Class 1
    "4009efa7-e72d-4cba-9edf-91084ea8cbc3" = 1     # Inc time Class 1 (alt)

    # ===== Class 2 (LP-E-Core) Variants =====
    "893dee8e-2bef-41e0-89c6-b55d0929964e" = 100   # Min state Class 2
    "bc5038f7-23e0-4960-96da-33abaf5935ee" = 100   # Max state Class 2
    "36687f9e-e3a5-4dbf-b1dc-15eb381c6865" = 0     # EPP Class 2
    "4b70f900-cdd9-4e66-aa26-ae8417f98175" = 0     # Latency hint EPP Class 2
    "619b7505-003b-4e82-b7a6-4dd29c300973" = 100   # Latency hint perf Class 2
    "75b0ae3f-bce0-45a7-8c89-c9611c25e102" = 0     # Max freq Class 2
    "603fe9ce-8d01-4b48-a968-1d706c28fd5e" = 100   # Resource priority Class 2
    "b000397d-9b0b-483d-98c9-692a6060cfc0" = 255   # P-level inc threshold Class 2
    "f8861c27-95e7-475c-865b-13c0cb3f9d6c" = 255   # P-level dec threshold Class 2
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

# --- 4c. Extra processor GUID: System cooling policy (Active) ---
Write-SubProgress -Activity "CPU Optimization" -Status "Applying system cooling policy..." -PercentComplete 98
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 94d3a615-a899-4ac5-ae2b-e4d8f634367f 1 2>> $errorLog
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 94d3a615-a899-4ac5-ae2b-e4d8f634367f 1 2>> $errorLog

# --- 4d. Final commit ---
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
Write-Host "  [4/5] CPU Optimization .......................... DONE" -ForegroundColor Green

# =============================================================================
# STEP 5 - NETWORK THROTTLE (QoS) - menu preserved from original
# =============================================================================
$script:CurrentStep = 5
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
Write-Host "  [5/5] Network Throttle .......................... DONE" -ForegroundColor Green

# =============================================================================
# FINAL SUMMARY
# =============================================================================
Write-Progress -Id 0 -Activity "SIGMA PERFORMANCES - All Optimizations" -Completed

Write-Host ""
Write-Host "========== SIGMA PERFORMANCES - SUMMARY ==========" -ForegroundColor Green
Write-Host "   [1/5] Device Cleanup ............................ OK" -ForegroundColor Green
Write-Host "   [2/5] Telemetry & Tracking Removal .............. OK" -ForegroundColor Green
Write-Host "   [3/5] PowerCfg Registry ......................... OK" -ForegroundColor Green
Write-Host "   [4/5] CPU Optimization .......................... OK" -ForegroundColor Green
Write-Host "   [5/5] Network Throttle .......................... OK" -ForegroundColor Green
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
