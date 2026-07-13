
#Requires -Version 5.1
##*=============================================
##* VMDeploy - Settings Module
##* Import this module in every child script:
##*   Import-Module "$PSScriptRoot\..\Settings.psm1" -Force
##*=============================================

#region -------  USER-CONFIGURABLE ATTRIBUTES  -------
##*=============================================
##* Edit these values before deploying
##*=============================================

$Script:CompanyName    = "DeployIT"            # Name of the company deploying the software / Default name is "DeployIT"
$Script:DownloadUrl    = "Download URL"        # Full URL to the VHDX file
$Script:VHDXVersion    = "Win11-25H2"          # Version tag for the VHDX file

# Set to $true for a direct/local install (Start Menu shortcuts will be created).
# Set to $false when deploying via Intune or Configuration Manager (no shortcuts).
$Script:LocalInstall   = $true

#endregion

#region -------  STATIC / DERIVED ATTRIBUTES  -------
##*=============================================
##* Do not edit below unless you know what
##* you are doing.
##*=============================================

$Script:ScriptVersion = "2.2.3"
$Script:SoftwareName  = "VMDeploy"

# Paths
$Script:DeployPath        = "$env:ProgramData\$Script:CompanyName"
$Script:DeployITLogs      = "$Script:DeployPath\Logs"
$Script:DeployITDownload  = "$Script:DeployPath\Download"
$Script:VHDXDownloadPath  = "$env:ProgramData\$Script:SoftwareName\Images\Windows11.vhdx"

# Registry
$Script:RegistryPath        = ("HKLM:\SOFTWARE\$Script:CompanyName") -replace ' ', ''
$Script:RegistrySoftwareName = ("$Script:RegistryPath\$Script:SoftwareName") -replace ' ', ''
$Script:ApplicationKeyPath   = $Script:RegistrySoftwareName

# Stage 1 - Hyper-V features to enable
$Script:HyperVFeatures = @(
    "Microsoft-Hyper-V-All"
    "Microsoft-Hyper-V"
    "Microsoft-Hyper-V-Tools-All"
    "Microsoft-Hyper-V-Management-PowerShell"
    "Microsoft-Hyper-V-Hypervisor"
    "Microsoft-Hyper-V-Services"
    "Microsoft-Hyper-V-Management-Clients"
    "HostGuardian"
)

# Stage 2 - Firewall rules to disable for PAW
$Script:FirewallRules = @(
    "VIRT-WMI-RPCSS-In-TCP-NoScope"
    "VIRTCL-WMI-RPCSS-In-TCP-NoScope"
    "VIRT-REMOTEDESKTOP-In-TCP-NoScope"
)

#endregion

#region -------  SHARED HELPER FUNCTION  -------

function Initialize-DeployEnvironment {
    <#
    .SYNOPSIS
        Creates required log/download directories and the registry key for VMDeploy.
        Call this once at the top of every child script after importing Settings.psm1.
    #>
    [CmdletBinding()]
    param()

    # --- Directories ---
    foreach ($dir in @($Script:DeployITLogs, $Script:DeployITDownload)) {
        if (-not (Test-Path $dir)) {
            Write-Host "Creating directory: $dir"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        } else {
            Write-Host "Directory already exists: $dir"
        }
    }

    # --- Registry key ---
    if (-not (Test-Path $Script:RegistrySoftwareName)) {
        Write-Host "Creating registry key: $Script:RegistrySoftwareName"
        New-Item -Path $Script:RegistrySoftwareName -Force | Out-Null
    } else {
        Write-Host "Registry key already exists: $Script:RegistrySoftwareName"
    }
}

#endregion

# Export everything so dot-sourced or Import-Module callers both work
Export-ModuleMember -Function Initialize-DeployEnvironment -Variable `
    CompanyName, ScriptVersion, SoftwareName, DownloadUrl, VHDXVersion, `
    LocalInstall, `
    DeployPath, DeployITLogs, DeployITDownload, VHDXDownloadPath, `
    RegistryPath, RegistrySoftwareName, ApplicationKeyPath, `
    HyperVFeatures, FirewallRules
