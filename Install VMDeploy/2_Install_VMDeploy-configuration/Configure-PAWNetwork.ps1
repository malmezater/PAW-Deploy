
#Requires -Version 5.1
<#
.SYNOPSIS
    Stage 2a — Create the Hyper-V external VM switch ("Ethernet Cable").
#>

# -------  Bootstrap: load shared settings  -------
Import-Module "$PSScriptRoot\..\..\Settings.psm1" -Force

$SourceFiles = "PawNetwork"
$LogPath     = "$DeployITLogs\$SourceFiles-PS.log"
Start-Transcript -Path $LogPath -Force -Append

Initialize-DeployEnvironment

# -------  Pre-check: Hyper-V must be enabled  -------

Write-Host "========================================================"
Write-Host "             Configure PAW VM Network Switch"
Write-Host "========================================================"

if ((Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V").State -ne "Enabled") {
    Write-Warning "Hyper-V is not enabled. Cannot configure network. Exiting."
    Stop-Transcript
    exit 1
}

# -------  Create VM switch if missing  -------

if (Get-VMSwitch | Where-Object Name -EQ "Ethernet Cable") {
    Write-Host "VMSwitch 'Ethernet Cable' already exists — skipping creation."
} else {
    $NetAdapter = Get-NetAdapter -Physical | Where-Object Status -EQ "Up" | Select-Object -First 1
    if (-not $NetAdapter) {
        Write-Warning "No active physical network adapter found. Cannot create VM switch."
        Stop-Transcript
        exit 1
    }

    Write-Host "Creating VMSwitch 'Ethernet Cable' on adapter: $($NetAdapter.Name)"
    New-VMSwitch -Name "Ethernet Cable" -NetAdapterName $NetAdapter.Name -AllowManagementOS $true | Out-Null
    Write-Host "VMSwitch created successfully."
}

# -------  Write registry  -------

try {
    New-ItemProperty -Path $ApplicationKeyPath -Name $SourceFiles -Value "True" -PropertyType String -Force | Out-Null
    Write-Host "Registry value '$SourceFiles' written successfully."
} catch {
    Write-Warning "Failed to write registry value for $SourceFiles."
}

Stop-Transcript
exit 0
