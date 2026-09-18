#Requires -Version 5.1
<#
.SYNOPSIS
    Stage 1 - Enable all required Hyper-V Windows Optional Features.
.NOTES
    Exit 0    - all features enabled, no reboot needed
    Exit 1641 - features enabled but a reboot is required to finish (standard Intune reboot code)
    Exit 1    - one or more features could not be enabled
#>

Import-Module "$PSScriptRoot\..\..\Settings.psm1" -Force
Start-DeployStage -Name "HyperV" -Title "Stage 1 - Install Hyper-V Optional Features"

$rebootRequired = $false
$failed = @()

foreach ($feature in $HyperVFeatures) {
    try {
        $state = (Get-WindowsOptionalFeature -FeatureName $feature -Online -ErrorAction Stop).State

        if ($state -eq "Disabled") {
            Write-Host "Enabling $feature ..."
            $result = Enable-WindowsOptionalFeature -FeatureName $feature -Online -All -LimitAccess -NoRestart -ErrorAction Stop
            if ($result.RestartNeeded) { $rebootRequired = $true }
            $state = (Get-WindowsOptionalFeature -FeatureName $feature -Online -ErrorAction Stop).State
        }

        switch ($state) {
            "Enabled"       { Write-Host "$feature - Enabled"; Set-DeployStamp -Name $feature -Value "Enabled" }
            "EnablePending" { Write-Host "$feature - Enabled (reboot pending)"; $rebootRequired = $true }
            default         { Write-Warning "$feature - state '$state'"; $failed += $feature }
        }
    }
    catch {
        Write-Warning "$feature - $($_.Exception.Message)"
        $failed += $feature
    }
}

if ($failed.Count -gt 0) {
    Write-Warning "Could not enable: $($failed -join ', ')"
    exit (Stop-DeployStage $ExitFailure)
}
if ($rebootRequired) {
    Write-Host "Reboot required to finish enabling Hyper-V - exiting $ExitRebootRequired."
    exit (Stop-DeployStage $ExitRebootRequired)
}

Write-Host "All Hyper-V features are enabled."
exit (Stop-DeployStage $ExitSuccess)
