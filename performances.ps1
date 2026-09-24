#Requires -RunAsAdministrator

# -----------------------------------------------------------------------------
# SIGMA PERFORMANCES - FULL OPTIMIZATION 
# -----------------------------------------------------------------------------

Write-Host "`n========== SIGMA PERFORMANCES ==========" -ForegroundColor Green
Write-Host ""
Write-Host "[WARNING] This will DISABLE:" -ForegroundColor Yellow
Write-Host " - All types of power saving" -ForegroundColor Yellow
Write-Host ""
Write-Host "It will significantly REDUCE battery life." -ForegroundColor Red
Write-Host "Make sure you have a System Restore point!" -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "Proceed with optimization? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Exiting. No changes made." -ForegroundColor Cyan
    exit 0
}

Write-Host ""
Write-Host "[INFO] Applying Complete Performance Optimization..." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------
function Set-PowerSetting {
    param(
        [string]$SubGroup,
        [string]$Setting,
        [int]$Value
    )
    powercfg /setacvalueindex SCHEME_CURRENT $SubGroup $Setting $Value 2>> $errorLog
    powercfg /setdcvalueindex SCHEME_CURRENT $SubGroup $Setting $Value 2>> $errorLog
}

# Log file for errors
$errorLog = "$env:TEMP\sigma_optimization_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

# Save the current active power scheme GUID for potential restore
$originalScheme = (powercfg -getactivescheme) -replace '.*\s([A-F0-9\-]{36}).*', '$1'
Write-Host "[INFO] Original power scheme saved: $originalScheme" -ForegroundColor DarkGray

# -----------------------------------------------------------------------------
# 1. Activate Ultimate Performance power scheme
# -----------------------------------------------------------------------------
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>> $errorLog
powercfg -setactive e9a42b02-d5df-448d-aa00-03f14749eb61 2>> $errorLog

# -----------------------------------------------------------------------------
# 2. CPU / Processor settings (using a hashtable for clarity)
# -----------------------------------------------------------------------------
Write-Host "  > Applying CPU tweaks..." -NoNewline

$cpuSettings = @{
    "PROCTHROTTLEMIN"           = 100
    "PROCTHROTTLEMAX"           = 100
    "PERFBOOSTMODE"             = 5
    "CPMINCORES"                = 100
    "PERFINCTHRESHOLD"          = 1
    "PERFDECREASETHRESHOLD"     = 100
    "PERFINCREASEPOLICY"        = 3
    "PERFDECREASEPOLICY"        = 0
    "RESPONSIVENESS"            = 100
    "PERFORMANCECORES"          = 0
    "PERFEPP"                   = 0
    "IDLEDEMOTE"                = 0
    "IDLEPROMOTE"               = 100
    "PERFBOOSTPOL"              = 100
    "SHORTTHREADBOOST"          = 3
    "HETEROPOLICY"              = 0
    "PERFINCRES"                = 0
    "PERFDECRES"                = 0
    "RESPENABLETHRESHOLD"       = 100
    "RESPPERFFLOOR"             = 100
    "IDLESTATE"                 = 0
    "PERFAUTONOMOUS"            = 0
    "PERFAUTONOMOUSACTIVEWINDOW"= 100
    "CPMAXCORES"                = 100
    "CPEPP"                     = 0
    "CPPARKING"                 = 0
    "CPPARKED"                  = 0
    "CPCONCURRENCY"             = 100
    "CPHEADROOM"                = 100
    "CPLATENCY"                 = 100
    "CPLOAD"                    = 100
    "CPREQUESTS"                = 100
    "CPRANDOM"                  = 0
    "MAXFREQ"                   = 0
    "MINFREQ"                   = 0
    "SCHEDPOLICY"               = 2
    "SHORTTHREADSCHED"          = 2
    "STARTPOLICY"               = 0
    "STOPPOLICY"                = 0
    "HETEROEPP"                 = 0
    "HETEROPROCESSPOLICY"       = 0
    "HETEROTHREADPOLICY"        = 0
    "PERFDUTYCYCLING"           = 100
    "PERFDPC"                   = 1
    "PERFEPPBOOST"              = 100
    "PERFEPPBACKOFF"            = 100
    "PERFHISTORY"               = 0
    "PERFCHECK"                 = 0
    "PERFLATENCY"               = 100
    "PERFAUTONOMOUSFREQUENCY"   = 0
}

foreach ($key in $cpuSettings.Keys) {
    Set-PowerSetting -SubGroup "SUB_PROCESSOR" -Setting $key -Value $cpuSettings[$key]
}

# Extra processor GUID 
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 94d3a615-a899-4ac5-ae2b-e4d8f634367f 1 2>> $errorLog
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 94d3a615-a899-4ac5-ae2b-e4d8f634367f 1 2>> $errorLog

Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 3. Disk settings
# -----------------------------------------------------------------------------
Write-Host "  > Applying Disk tweaks..." -NoNewline

Set-PowerSetting -SubGroup "SUB_DISK" -Setting "DISKIDLE" -Value 0
Set-PowerSetting -SubGroup "SUB_DISK" -Setting "DISKBURSTIGNORETIME" -Value 0

# These GUIDs control various disk power management policies
$diskGuids = @(
    "0b2d69d7-a2a1-449c-9680-f91c70521c60",
    "dab60367-53fe-4fbc-825e-521d069d2456",
    "d639518a-e56d-4345-8af2-b9f32fb26109",
    "d3d55efd-c1ff-424e-9dc3-441be7833010",
    "fc95af4d-40e7-4b6d-835a-56d131dbc80e",
    "dbc9e238-6de9-49e3-92cd-8c2b4946b472",
    "fc7372b6-ab2d-43ee-8797-15e9841f2cca"
)
foreach ($g in $diskGuids) {
    powercfg /setacvalueindex SCHEME_CURRENT SUB_DISK $g 0 2>> $errorLog
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_DISK $g 0 2>> $errorLog
}

# This specific GUID affect disk performance
powercfg /setacvalueindex SCHEME_CURRENT SUB_DISK 51dea550-bb38-4bc4-991b-eacf37be5ec8 100 2>> $errorLog
powercfg /setdcvalueindex SCHEME_CURRENT SUB_DISK 51dea550-bb38-4bc4-991b-eacf37be5ec8 100 2>> $errorLog

Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 4. Sleep / Hibernation timers
# -----------------------------------------------------------------------------
Write-Host "  > Disabling Sleep/Hibernation timers..." -NoNewline

Set-PowerSetting -SubGroup "SUB_SLEEP" -Setting "STANDBYIDLE" -Value 0
Set-PowerSetting -SubGroup "SUB_SLEEP" -Setting "HIBERNATEIDLE" -Value 0
Set-PowerSetting -SubGroup "SUB_SLEEP" -Setting "UNATTENDEDSLEEPTIMEOUT" -Value 0
Set-PowerSetting -SubGroup "SUB_SLEEP" -Setting "HYBRIDSLEEP" -Value 0
Set-PowerSetting -SubGroup "SUB_SLEEP" -Setting "RTCWAKE" -Value 0

$sleepGuids = @(
    "25dfa149-5dd1-4736-b5ab-e8a37b5b8187",
    "a4b195f5-8225-47d8-8012-9d41369786e2",
    "d4c1d4c8-d5cc-43d3-b83e-fc51215cb04d",
    "abfc2519-3608-4c2a-94ea-171b0ed546ab",
    "1a34bdc3-7e6b-442e-a9d0-64b6ef378e84"
)
foreach ($g in $sleepGuids) {
    powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP $g 0 2>> $errorLog
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP $g 0 2>> $errorLog
}

Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 5. Buttons (Lid, Power button)
# -----------------------------------------------------------------------------
Write-Host "  > Disabling Lid/Power button actions..." -NoNewline

Set-PowerSetting -SubGroup "SUB_BUTTONS" -Setting "LIDACTION" -Value 0
Set-PowerSetting -SubGroup "SUB_BUTTONS" -Setting "LIDOPENACTION" -Value 0
Set-PowerSetting -SubGroup "SUB_BUTTONS" -Setting "PBUTTONACTION" -Value 0
Set-PowerSetting -SubGroup "SUB_BUTTONS" -Setting "SBUTTONACTION" -Value 0

$btnGuids = @("a7066653-8d6c-40a8-910e-a1f54b84c7e5", "833a6b62-dfa4-46d1-82f8-e09e34d029d6")
foreach ($g in $btnGuids) {
    powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS $g 0 2>> $errorLog
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS $g 0 2>> $errorLog
}

Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 6. Display / Video / GPU
# -----------------------------------------------------------------------------
Write-Host "  > Applying Display/GPU tweaks..." -NoNewline

Set-PowerSetting -SubGroup "SUB_VIDEO" -Setting "VIDEOIDLE" -Value 0
Set-PowerSetting -SubGroup "SUB_VIDEO" -Setting "VIDEODIM" -Value 0

# Specific video GUIDs (values: 0, 1, 100)
$videoGuids = @{
    "90959d22-d6a1-49b9-af93-bce885ad335b" = 0
    "8ec4b3a5-6868-48c2-be75-4f3044be88a7" = 0
    "684c3e69-a4f7-4014-8754-d45179a56167" = 1
    "aded5e82-b909-4619-9949-f5d71dac0bcb" = 100
    "f1fbfde2-a960-4165-9f88-50667911ce96" = 100
    "fbd9aa66-9553-4097-ba44-ed6e9d65eab8" = 0
    "a9ceb8da-cd46-44fb-a98b-02af69de4623" = 1
}
foreach ($g in $videoGuids.Keys) {
    powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO $g $videoGuids[$g] 2>> $errorLog
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_VIDEO $g $videoGuids[$g] 2>> $errorLog
}

# GPU policy
Set-PowerSetting -SubGroup "SUB_GRAPHICS" -Setting "GPUPREFERENCEPOLICY" -Value 0

Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 7. PCIe, USB, Battery
# -----------------------------------------------------------------------------
Write-Host "  > Disabling PCIe ASPM..." -NoNewline
Set-PowerSetting -SubGroup "SUB_PCIEXPRESS" -Setting "ASPM" -Value 0
Write-Host " Done." -ForegroundColor Green

Write-Host "  > Disabling USB Selective Suspend..." -NoNewline
Set-PowerSetting -SubGroup "SUB_USB" -Setting "USBSELECTIVESUSPEND" -Value 0
$usbGuids = @("0853a681-27c8-4100-a2fd-82013e970683", "d4e98f31-5ffe-4ce1-be31-1b38b384c009", "498c044a-201b-4631-a522-5c744ed4e678")
foreach ($g in $usbGuids) {
    powercfg /setacvalueindex SCHEME_CURRENT SUB_USB $g 0 2>> $errorLog
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_USB $g 0 2>> $errorLog
}
Write-Host " Done." -ForegroundColor Green

Write-Host "  > Disabling Battery Critical/Low actions..." -NoNewline
Set-PowerSetting -SubGroup "SUB_BATTERY" -Setting "BATACTIONCRIT" -Value 0
Set-PowerSetting -SubGroup "SUB_BATTERY" -Setting "BATACTIONLOW" -Value 0
Set-PowerSetting -SubGroup "SUB_BATTERY" -Setting "BATNOTIFYCRIT" -Value 0
Set-PowerSetting -SubGroup "SUB_BATTERY" -Setting "BATNOTIFYLOW" -Value 0
Set-PowerSetting -SubGroup "SUB_BATTERY" -Setting "BATLEVELLOW" -Value 0
Set-PowerSetting -SubGroup "SUB_BATTERY" -Setting "BATLEVELCRIT" -Value 0
powercfg /setacvalueindex SCHEME_CURRENT SUB_BATTERY F3C5027D-CD16-4930-AA6B-90DB844A8F00 0 2>> $errorLog
powercfg /setdcvalueindex SCHEME_CURRENT SUB_BATTERY F3C5027D-CD16-4930-AA6B-90DB844A8F00 0 2>> $errorLog
Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 8. Extra kernel/system tweaks 
# -----------------------------------------------------------------------------
Write-Host "  > Applying extra kernel/system tweaks..." -NoNewline

# These affect processor performance and C‑state policies
$extraSubGroups = @{
    "e276e160-7cb0-43c6-b20b-73f5dce39954\a1662ab2-9d34-4e53-ba8b-2639b9e20857" = 4
    "c763b4ec-0e50-4b6b-9bed-2b92a6ee884e\38cab4d5-db09-449f-9db5-1c91c909b6d4" = 3
    "c763b4ec-0e50-4b6b-9bed-2b92a6ee884e\7ec1751b-60ed-4588-afb5-9819d3d77d90" = 3
    "9596FB26-9850-41fd-AC3E-F7C3C00AFD4B\03680956-93BC-4294-BBA6-4E0F09BB717F" = 1
    "9596FB26-9850-41fd-AC3E-F7C3C00AFD4B\10778347-1370-4ee0-8bbd-33bdacaade49" = 1
    "9596FB26-9850-41fd-AC3E-F7C3C00AFD4B\34C7B99F-9A6D-4b3c-8DC7-B6693B78CEF4" = 0
}
foreach ($key in $extraSubGroups.Keys) {
    powercfg /setacvalueindex SCHEME_CURRENT $key $extraSubGroups[$key] 2>> $errorLog
    powercfg /setdcvalueindex SCHEME_CURRENT $key $extraSubGroups[$key] 2>> $errorLog
}

# CPU sub‑GUIDs (core parking and scheduling)
$cpuSubGuids = @("3166bc41-7e98-4e03-b34e-ec0f5f2b218e", "c36f0eb4-2988-4a70-8eee-0884fc2c2433", "c42b79aa-aa3a-484b-a98f-2cf32aa90a28", "d502f7ee-1dc7-4efd-a55d-f04b6f5c0545")
foreach ($g in $cpuSubGuids) {
    powercfg /setacvalueindex SCHEME_CURRENT SUB_CPU $g 0 2>> $errorLog
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_CPU $g 0 2>> $errorLog
}

# Core parking related GUIDs (under 8619b916...)
$coreParkingGuids = @(
    "0a7d6ab6-ac83-4ad1-8282-eca5b58308f3", "468fe7e5-1158-46ec-88bc-5b96c9e44fd0",
    "49cb11a5-56e2-4afb-9d38-3df47872e21b", "5adbbfbc-074e-4da1-ba38-db8b36b2c8f3",
    "60c07fe1-0556-45cf-9903-d56e32210242", "61f45dfe-1919-4180-bb46-8cc70e0b38f1",
    "82011705-fb95-4d46-8d35-4042b1d20def", "9fe527be-1b70-48da-930d-7bcf17b44990",
    "a79c8e0e-f271-482d-8f8a-5db9a18312de", "aca8648e-c4b1-4baa-8cce-9390ad647f8c",
    "c763ee92-71e8-4127-84eb-f6ed043a3e3d", "cf8c6097-12b8-4279-bbdd-44601ee5209d",
    "ee16691e-6ab3-4619-bb48-1c77c9357e5a"
)
foreach ($g in $coreParkingGuids) {
    powercfg /setacvalueindex SCHEME_CURRENT "8619b916-e004-4dd8-9b66-dae86f806698\$g" 0 2>> $errorLog
    powercfg /setdcvalueindex SCHEME_CURRENT "8619b916-e004-4dd8-9b66-dae86f806698\$g" 0 2>> $errorLog
}

# Additional power policy GUIDs (under 48672f38...)
$powerPolicyGuids = @("2bfc24f9-5ea2-4801-8213-3dbae01aa39d", "73cde64d-d720-4bb2-a860-c755afe77ef2", "d6ba4903-386f-4c2c-8adb-5c21b3328d25")
foreach ($g in $powerPolicyGuids) {
    powercfg /setacvalueindex SCHEME_CURRENT "48672f38-7a9a-4bb2-8bf8-3d85be19de4e\$g" 0 2>> $errorLog
    powercfg /setdcvalueindex SCHEME_CURRENT "48672f38-7a9a-4bb2-8bf8-3d85be19de4e\$g" 0 2>> $errorLog
}

# Single GUIDs with specific values
$singleGuids = @{
    "4faab71a-92e5-4726-b531-224559672d19" = 0
    "f15576e8-98b7-4186-b944-eafa664402d9" = 1
    "19cbb8fa-5279-450e-9fac-8a3d5fedd0c1\12bbebe6-58d6-4636-95bb-3217ef867c1a" = 0
    "de830923-a562-41af-a086-e3a2c6bad2da\13d09884-f74e-474a-a852-b6bde8ad03a8" = 100
    "de830923-a562-41af-a086-e3a2c6bad2da\5c5bb349-ad29-4ee2-9d0b-2b25270f7a81" = 0
    "de830923-a562-41af-a086-e3a2c6bad2da\e69653ca-cf7f-4f05-aa73-cb833fa90ad4" = 0
    "0e796bdb-100d-47d6-a2d5-f7d2daa51f51" = 0
    "68afb2d9-ee95-47a8-8f50-4115088073b1" = 0
}
foreach ($g in $singleGuids.Keys) {
    powercfg /setacvalueindex SCHEME_CURRENT $g $singleGuids[$g] 2>> $errorLog
    powercfg /setdcvalueindex SCHEME_CURRENT $g $singleGuids[$g] 2>> $errorLog
}

Write-Host " Done." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 9. Final commits & Hibernate off
# -----------------------------------------------------------------------------
powercfg -setactive SCHEME_CURRENT 2>> $errorLog
powercfg -h off 2>> $errorLog
bcdedit /set disabledynamictick yes 2>> $errorLog

# -----------------------------------------------------------------------------
# 10. Done – report any errors if present
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

Write-Host "[SUCCESS] Complete Performance Optimization applied." -ForegroundColor Green
Write-Host "[INFO] System reboot required for some changes (dynamic tick)." -ForegroundColor Yellow
Write-Host ""
Write-Host "I hope you created a restore point!" -ForegroundColor Magenta
Write-Host "Have a good day!" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------------
# 11. Reboot prompt 
# -----------------------------------------------------------------------------
$rebootChoice = Read-Host "Press R to reboot now, or Q to quit"

if ($rebootChoice -eq "R" -or $rebootChoice -eq "r") {
    shutdown /r /f /t 0
} else {
    exit 0
}