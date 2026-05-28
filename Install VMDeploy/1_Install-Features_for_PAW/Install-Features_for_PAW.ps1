
#Requires -Version 5.1
<#
.SYNOPSIS
    Stage 1 — Enable all required Hyper-V Windows Optional Features.
.NOTES
    Exits 1641 when a reboot is required (standard Intune reboot code).
    Exits 0 if no reboot is needed (should not normally happen for a first install).
    Exits 1 if features could not be enabled after all retries.
#>

# -------  Bootstrap: load shared settings  -------
Import-Module "$PSScriptRoot\..\..\Settings.psm1" -Force

$SourceFiles = "HyperV"
$LogPath     = "$DeployITLogs\$SourceFiles-PS.log"
Start-Transcript -Path $LogPath -Force -Append

Initialize-DeployEnvironment

# -------  Enable features  -------

Write-Host "========================================================"
Write-Host "           Install Hyper-V Optional Features"
Write-Host "========================================================"

foreach ($Feature in $HyperVFeatures) {
    $state = (Get-WindowsOptionalFeature -FeatureName $Feature -Online).State
    if ($state -eq "Enabled") {
        Write-Host "$Feature is already enabled."
    } else {
        Write-Host "Enabling $Feature ..."
        Enable-WindowsOptionalFeature -FeatureName $Feature -LimitAccess -NoRestart -Online | Out-Null
    }
}

# -------  Verify (up to 3 attempts)  -------

$MaxAttempts       = 3
$RemainingAttempts = $MaxAttempts
$AllEnabled        = $false

Write-Host "Verifying feature state (up to $MaxAttempts attempts)..."

do {
    $AllEnabled = $true

    foreach ($Feature in $HyperVFeatures) {
        $state = (Get-WindowsOptionalFeature -FeatureName $Feature -Online).State

        if ($state -eq "Enabled") {
            Write-Host "$Feature — Enabled"
            try {
                New-ItemProperty -Path $ApplicationKeyPath -Name $Feature -Value "Enabled" -PropertyType String -Force | Out-Null
            } catch {
                Write-Warning "Could not write registry value for $Feature."
            }
        } else {
            Write-Host "$Feature — NOT enabled"
            $AllEnabled = $false
        }
    }

    if ($AllEnabled) { break }

    $RemainingAttempts--
    if ($RemainingAttempts -gt 0) {
        Write-Host "Retrying in 10 seconds... ($RemainingAttempts attempts left)"
        Start-Sleep -Seconds 10
    }

} while ($RemainingAttempts -gt 0)

# -------  Exit  -------

Stop-Transcript

if ($AllEnabled) {
    Write-Host "All features enabled. Reboot required — exiting 1641."
    exit 1641
} else {
    Write-Warning "Not all features could be enabled. Exiting 1."
    exit 1
}
