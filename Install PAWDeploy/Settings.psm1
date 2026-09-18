#Requires -Version 5.1
##*=============================================
##* VMDeploy - Settings Module
##* Imported by the orchestrator and by every stage script:
##*   Import-Module "$PSScriptRoot\..\..\Settings.psm1" -Force   (from a script under Stages\)
##*=============================================

#region -------  USER-CONFIGURABLE ATTRIBUTES  -------
##*=============================================
##* Edit these values before deploying
##*=============================================

#  -------  BRANDING  -------
#  What the operator sees in the VM Deploy windows. Change these two to rebrand the tool.
#  ProductName  - shown in the window title and the banner, e.g. "Contoso Secure Workstation".
#  BrandingLogo - file name of the banner logo, placed in the "Branding" folder next to this file.
#                 A wide-ish PNG works best; it is scaled to fit a 64x64 box.
#  These are cosmetic only - they do not affect install paths, the registry or Intune detection
#  (those follow CompanyName / SoftwareName below).
$Script:ProductName    = "Privileged Access Workstation"
$Script:BrandingLogo   = "PAWDeploy.png"

$Script:CompanyName    = "DeployIT"            # Name of the company deploying the software / Default name is "DeployIT"
$Script:DownloadUrl    = "https://DownloadURLHere"   # Full URL / UNC path to the VHDX file
$Script:VHDXVersion    = "Win11-25H2"          # Version tag for the VHDX file
$Script:VHDXSha256     = ""                    # Optional SHA256 of the VHDX. When set, the download is verified before it is used.

# Set to $true for a direct/local install (Start Menu shortcuts will be created).
# Set to $false when deploying via Intune or Configuration Manager (no shortcuts).
$Script:LocalInstall   = $true

# Hyper-V external switch used by the guest VMs (must match <VMSwitch> in Config.xml).
$Script:VMSwitchName        = "Ethernet Cable"
$Script:VMSwitchAdapterName = ""               # Physical adapter to bind to. Empty = first physical adapter that is Up.

# Optional: instead of disabling $FirewallRules outright (opening WMI/RPC and enhanced-session RDP
# listeners on the PAW host to the whole network), scope them to a trusted management subnet, e.g.
# "10.0.5.0/24". Leave empty to keep the current disable-outright behavior.
$Script:FirewallScopeSubnet = ""

# Create the local "Hypervuser" account (member of Hyper-V Administrators).
# The password is prompted for, so the account is only created in an interactive session.
$Script:CreateHyperVUser = $true

#endregion

#region -------  STATIC / DERIVED ATTRIBUTES  -------
##*=============================================
##* Do not edit below unless you know what
##* you are doing.
##*=============================================

$Script:ScriptVersion = "2.3.1"
$Script:SoftwareName  = "VMDeploy"

# Where the operator drops a replacement logo (see BrandingLogo above).
$Script:BrandingPath  = "$PSScriptRoot\Branding"

# Paths
$Script:DeployPath        = "$env:ProgramData\$Script:CompanyName"
$Script:DeployITLogs      = "$Script:DeployPath\Logs"
$Script:VMDeployPath      = "$env:ProgramData\$Script:SoftwareName"
$Script:VHDXDownloadPath  = "$Script:VMDeployPath\Images\Windows11.vhdx"

# Registry
$Script:RegistryPath         = ("HKLM:\SOFTWARE\$Script:CompanyName") -replace ' ', ''
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

# Stage 2b - Firewall rules to disable for PAW
$Script:FirewallRules = @(
    "VIRT-WMI-RPCSS-In-TCP-NoScope"
    "VIRTCL-WMI-RPCSS-In-TCP-NoScope"
    "VIRT-REMOTEDESKTOP-In-TCP-NoScope"
)

# Exit codes shared by all stages
$Script:ExitSuccess        = 0
$Script:ExitFailure        = 1
$Script:ExitRebootRequired = 1641

#endregion

#region -------  SHARED HELPER FUNCTIONS  -------

function Initialize-DeployEnvironment {
    <#
    .SYNOPSIS
        Creates the log directory and the registry key for VMDeploy.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Path $Script:DeployITLogs)) {
        New-Item -ItemType Directory -Path $Script:DeployITLogs -Force | Out-Null
    }
    if (-not (Test-Path $Script:RegistrySoftwareName)) {
        New-Item -Path $Script:RegistrySoftwareName -Force | Out-Null
    }
}

function Start-DeployStage {
    <#
    .SYNOPSIS
        Common start of every stage: environment, transcript and banner.
    .PARAMETER Name
        Log file base name. The log is written to <Logs>\<Name>-<yyMMdd>.log
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Title
    )

    Initialize-DeployEnvironment
    $logPath = Join-Path $Script:DeployITLogs ("{0}-{1}.log" -f $Name, (Get-Date -Format yyMMdd))
    Start-Transcript -Path $logPath -Force -Append | Out-Null

    Write-Host "========================================================"
    Write-Host "  $Title"
    Write-Host "========================================================"
}

function Stop-DeployStage {
    <#
    .SYNOPSIS
        Common end of every stage. Returns the exit code so the caller can do: exit (Stop-DeployStage 0)
    #>
    [CmdletBinding()]
    param([int]$ExitCode = 0)

    try { Stop-Transcript | Out-Null } catch { }
    return $ExitCode
}

function Get-DeployStamp {
    <#
    .SYNOPSIS
        Returns the stamp's value, or $null when it doesn't exist yet.
    .NOTES
        Get-ItemPropertyValue throws a *terminating* error for a missing property -
        -ErrorAction SilentlyContinue only suppresses non-terminating errors, so it would still
        print "Property ... does not exist" in red on every not-yet-stamped check (i.e. on every
        first-time-through-a-stage check during a fresh install). try/catch actually suppresses it.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    try {
        Get-ItemPropertyValue -Path $Script:ApplicationKeyPath -Name $Name -ErrorAction Stop
    }
    catch {
        $null
    }
}

function Set-DeployStamp {
    <#
    .SYNOPSIS
        Writes a REG_SZ stamp under the VMDeploy key (creates or overwrites).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )
    try {
        New-ItemProperty -Path $Script:ApplicationKeyPath -Name $Name -Value $Value -PropertyType String -Force -ErrorAction Stop | Out-Null
        Write-Host "Registry stamp: $Name = $Value"
    } catch {
        Write-Warning "Could not write registry stamp '$Name': $($_.Exception.Message)"
    }
}

function Test-DeployStamp {
    <#
    .SYNOPSIS
        True when every named stamp exists (and equals -Value when given).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Name,
        [string]$Value
    )
    foreach ($n in $Name) {
        $current = Get-DeployStamp -Name $n
        if ($null -eq $current) { return $false }
        if ($PSBoundParameters.ContainsKey('Value') -and $current -ne $Value) { return $false }
    }
    return $true
}

function Test-InteractiveSession {
    <#
    .SYNOPSIS
        False when running as SYSTEM (Intune/ConfigMgr) or without a desktop, where GUI prompts can't be answered.
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Environment]::UserInteractive -and -not $identity.IsSystem)
}

#endregion

Export-ModuleMember -Function Initialize-DeployEnvironment, Start-DeployStage, Stop-DeployStage, `
    Get-DeployStamp, Set-DeployStamp, Test-DeployStamp, Test-InteractiveSession -Variable `
    CompanyName, ScriptVersion, SoftwareName, DownloadUrl, VHDXVersion, VHDXSha256, `
    ProductName, BrandingLogo, BrandingPath, `
    LocalInstall, VMSwitchName, VMSwitchAdapterName, CreateHyperVUser, FirewallScopeSubnet, `
    DeployPath, DeployITLogs, VMDeployPath, VHDXDownloadPath, `
    RegistryPath, RegistrySoftwareName, ApplicationKeyPath, `
    HyperVFeatures, FirewallRules, ExitSuccess, ExitFailure, ExitRebootRequired
