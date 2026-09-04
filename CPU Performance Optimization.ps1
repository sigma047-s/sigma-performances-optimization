#Requires -RunAsAdministrator

# -----------------------------------------------------------------------------
# SIGMA PERFORMANCES - CPU OPTIMIZATION (AC / DC)
# -----------------------------------------------------------------------------

Write-Host "`n========== SIGMA PERFORMANCES ==========" -ForegroundColor Green
Write-Host ""
Write-Host "[WARNING] This will DISABLE all CPU power saving." -ForegroundColor Yellow
Write-Host "It will significantly REDUCE battery life." -ForegroundColor Red
Write-Host "Make sure you have a System Restore point!" -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "Proceed with CPU optimization? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Exiting. No changes made." -ForegroundColor Cyan
    exit 0
}

Write-Host ""
Write-Host "[INFO] Applying CPU Performance Optimization..." -ForegroundColor Cyan

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
# 3. Final commit
# -----------------------------------------------------------------------------
powercfg -setactive SCHEME_CURRENT 2>> $errorLog

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

Write-Host "[SUCCESS] CPU Performance Optimization applied." -ForegroundColor Green
Write-Host "[INFO] System reboot required." -ForegroundColor Yellow
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