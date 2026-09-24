#Requires -Version 5.1
<#
.SYNOPSIS
    Stage 2a - Create the Hyper-V external VM switch used by guest VMs.
.NOTES
    Switch name and adapter come from Settings.psm1 ($VMSwitchName, $VMSwitchAdapterName).
#>

Import-Module "$PSScriptRoot\..\..\Settings.psm1" -Force
Start-DeployStage -Name "PawNetwork" -Title "Stage 2a - Configure PAW VM Network Switch"

if ((Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V").State -ne "Enabled") {
    Write-Warning "Hyper-V is not enabled (a reboot may still be pending). Cannot configure network."
    exit (Stop-DeployStage $ExitFailure)
}

if (Get-VMSwitch -Name $VMSwitchName -ErrorAction SilentlyContinue) {
    Write-Host "VMSwitch '$VMSwitchName' already exists."
}
else {
    if ($VMSwitchAdapterName) {
        $adapter = Get-NetAdapter -Name $VMSwitchAdapterName -Physical -ErrorAction SilentlyContinue
        if (-not $adapter) {
            Write-Warning "Configured adapter '$VMSwitchAdapterName' was not found."
            exit (Stop-DeployStage $ExitFailure)
        }
    }
    else {
        $upAdapters = @(Get-NetAdapter -Physical | Where-Object Status -EQ "Up")
        if ($upAdapters.Count -eq 0) {
            Write-Warning "No active physical network adapter found. Cannot create VM switch."
            exit (Stop-DeployStage $ExitFailure)
        }
        if ($upAdapters.Count -gt 1) {
            Write-Warning "Several active adapters found ($($upAdapters.Name -join ', ')). Using the first one - set `$VMSwitchAdapterName in Settings.psm1 to choose explicitly."
        }
        $adapter = $upAdapters[0]
    }

    Write-Host "Creating VMSwitch '$VMSwitchName' on adapter: $($adapter.Name)"
    try {
        New-VMSwitch -Name $VMSwitchName -NetAdapterName $adapter.Name -AllowManagementOS $true -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Warning "Could not create VMSwitch: $($_.Exception.Message)"
        exit (Stop-DeployStage $ExitFailure)
    }
}

Set-DeployStamp -Name "PawNetwork" -Value "True"
exit (Stop-DeployStage $ExitSuccess)
