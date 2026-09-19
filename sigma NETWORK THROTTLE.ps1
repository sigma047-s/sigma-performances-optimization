#Requires -RunAsAdministrator

# -----------------------------------------------------------------------------
# SIGMA PERFORMANCES - NETWORK THROTTLE (QoS 1-3000 Mbps)
# -----------------------------------------------------------------------------

Write-Host "`n========== SIGMA PERFORMANCES ==========" -ForegroundColor Green
Write-Host ""
Write-Host "[WARNING] This will LIMIT your outbound network speed." -ForegroundColor Yellow
Write-Host "Make sure you have a System Restore point!" -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "Proceed with network throttle? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Exiting. No changes made." -ForegroundColor Cyan
    exit 0
}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
$PolicyPrefix = "LimitPCto"
$MinMbps      = 1
$MaxMbps      = 3000

# Log file for errors
$errorLog = "$env:TEMP\sigma_netqos_errors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog -Force }

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------
function Set-QosLimit {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 3000)]
        [int]$Mbps
    )

    $bits       = [uint64]$Mbps * 1000000
    $policyName = "$PolicyPrefix$Mbps"

    # Remove any existing LimitPCto* policy so only one is active
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

# -----------------------------------------------------------------------------
# Menu
# -----------------------------------------------------------------------------
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
                    Write-Host ""
                    Write-Host "[INFO] Applying network throttle: $mbpsInt Mbps..." -ForegroundColor Cyan
                    Set-QosLimit -Mbps $mbpsInt
                    Write-Host " Done." -ForegroundColor Green
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
            Write-Host ""
            Write-Host "[INFO] Removing all '$PolicyPrefix*' policies..." -ForegroundColor Cyan
            Remove-AllLimits
            Write-Host " Done." -ForegroundColor Green
        }

        "3" {
            Write-Host ""
            Write-Host "[INFO] Currently applied throttles:" -ForegroundColor Cyan
            Show-AllLimits
        }

        "4" {
            # exit
        }

        default {
            Write-Host "[ERROR] Invalid choice." -ForegroundColor Red
        }
    }

} until ($choice -eq "4")

# -----------------------------------------------------------------------------
# Done - report any errors if present
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

Write-Host "[SUCCESS] Network throttle session finished." -ForegroundColor Green
Write-Host "[INFO] Reboot not required for QoS changes." -ForegroundColor Yellow
Write-Host ""
Write-Host "I hope you created a restore point!" -ForegroundColor Magenta
Write-Host "Have a good day!" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------------
# Reboot prompt
# -----------------------------------------------------------------------------
$rebootChoice = Read-Host "Press R to reboot now, or Q to quit"

if ($rebootChoice -eq "R" -or $rebootChoice -eq "r") {
    shutdown /r /f /t 0
} else {
    exit 0
}