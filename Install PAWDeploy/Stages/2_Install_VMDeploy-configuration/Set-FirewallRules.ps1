#Requires -Version 5.1
<#
.SYNOPSIS
    Stage 2b - Disable the PAW Hyper-V firewall rules listed in Settings.psm1 ($FirewallRules).
.NOTES
    Every rule gets a stamp: "Disabled", or "NotFound" when the rule does not exist on this build,
    so the orchestrator does not re-run the stage forever.
#>

Import-Module "$PSScriptRoot\..\..\Settings.psm1" -Force
Start-DeployStage -Name "FirewallRules" -Title "Stage 2b - Set Firewall Rules for VM Deploy"

$failed = $false

foreach ($rule in $FirewallRules) {
    $fw = Get-NetFirewallRule -Name $rule -ErrorAction SilentlyContinue
    if (-not $fw) {
        Write-Warning "Firewall rule '$rule' not found - skipping."
        Set-DeployStamp -Name $rule -Value "NotFound"
        continue
    }

    try {
        if ($FirewallScopeSubnet) {
            Write-Host "Scoping rule '$rule' to $FirewallScopeSubnet (kept enabled) ..."
            Set-NetFirewallRule -Name $rule -Enabled True -RemoteAddress $FirewallScopeSubnet -ErrorAction Stop
            Set-DeployStamp -Name $rule -Value "Scoped:$FirewallScopeSubnet"
        }
        elseif ($fw.Enabled -eq "False") {
            Write-Host "Rule '$rule' is already disabled."
            Set-DeployStamp -Name $rule -Value "Disabled"
        } else {
            Write-Warning "Disabling rule '$rule' - open to the whole network. Set `$FirewallScopeSubnet in Settings.psm1 to scope it to a management subnet instead."
            Set-NetFirewallRule -Name $rule -Enabled False -ErrorAction Stop
            Set-DeployStamp -Name $rule -Value "Disabled"
        }
    }
    catch {
        Write-Warning "Could not update '$rule': $($_.Exception.Message)"
        $failed = $true
    }
}

exit (Stop-DeployStage $(if ($failed) { $ExitFailure } else { $ExitSuccess }))
