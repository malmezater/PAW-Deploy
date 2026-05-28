
#Requires -Version 5.1
<#
.SYNOPSIS
    Stage 2b — Disable the three PAW Hyper-V firewall rules.
#>

# -------  Bootstrap: load shared settings  -------
Import-Module "$PSScriptRoot\..\..\Settings.psm1" -Force

$SourceFiles = "FirewallRules"
$LogPath     = "$DeployITLogs\$SourceFiles-PS.log"
Start-Transcript -Path $LogPath -Force -Append

Initialize-DeployEnvironment

# -------  Disable firewall rules  -------

Write-Host "========================================================"
Write-Host "            Set Firewall Rules for VM Deploy"
Write-Host "========================================================"

foreach ($Rule in $FirewallRules) {
    $fw = Get-NetFirewallRule -Name $Rule -ErrorAction SilentlyContinue
    if (-not $fw) {
        Write-Warning "Firewall rule '$Rule' not found — skipping."
        continue
    }

    if ($fw.Enabled -eq $false) {
        Write-Host "Rule '$Rule' is already disabled."
    } else {
        Write-Host "Disabling rule '$Rule' ..."
        Set-NetFirewallRule -Name $Rule -Enabled False
    }

    try {
        New-ItemProperty -Path $ApplicationKeyPath -Name $Rule -Value "Disabled" -PropertyType String -Force | Out-Null
        Write-Host "Registry value for '$Rule' written successfully."
    } catch {
        Write-Warning "Failed to write registry value for '$Rule'."
    }
}

Stop-Transcript
exit 0
