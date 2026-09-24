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
$Script:VHDXVersion    = "Win11-2609"          # Version tag for the VHDX file
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

# Create the local "Hypervuser" account (member of Hyper-V Administrators), for operators who want
# a dedicated account to RDP into the host with rather than using their own sign-in. The signed-in
# user is always added to Hyper-V Administrators regardless of this setting - it is required to use
# VMs at all - this only controls the extra "Hypervuser" account.
# The password is prompted for, so the account is only created in an interactive session.
$Script:CreateHyperVUser = $true

#endregion

#region -------  STATIC / DERIVED ATTRIBUTES  -------
##*=============================================
##* Do not edit below unless you know what
##* you are doing.
##*=============================================

$Script:ScriptVersion = "2.3.2"
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

# Event Log entries are readable without local admin rights - unlike the transcript logs under
# $DeployITLogs / $VMDeployPath\logs, which are SYSTEM-only on Intune/ConfigMgr installs (see
# docs/setup/INSTALLATION.md#permissions-intune--configmgr-only). A custom log created this way
# defaults to granting read+write to "Interactive Users" (any interactively logged-on account, admin
# or not), so Event Viewer > Applications and Services Logs > VMDeploy > Operational (or
# `Get-WinEvent -LogName "VMDeploy/Operational"`) works without local admin or takeown.exe.
$Script:EventLogName = "VMDeploy/Operational"
$Script:EventLogSource = "VMDeploy-Setup"

function Initialize-DeployEventLog {
    <#
    .SYNOPSIS
        Registers the install/uninstall event source if it doesn't exist yet. Safe to call every
        time - a no-op once it exists, which it normally will after the first run.
    #>
    [CmdletBinding()]
    param()
    if ([System.Diagnostics.EventLog]::SourceExists($Script:EventLogSource)) { return }
    try {
        New-EventLog -LogName $Script:EventLogName -Source $Script:EventLogSource -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not create event log source '$($Script:EventLogSource)': $($_.Exception.Message)"
    }
}

function Write-DeployEvent {
    <#
    .SYNOPSIS
        Writes one entry to the VMDeploy/Operational event log. Never throws - a logging failure
        must not break an install or uninstall.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Information', 'Warning', 'Error')][string]$EntryType = 'Information',
        [int]$EventId = 1000
    )
    Initialize-DeployEventLog
    try {
        Write-EventLog -LogName $Script:EventLogName -Source $Script:EventLogSource -EntryType $EntryType -EventId $EventId -Message $Message -ErrorAction Stop
    }
    catch {
        # Best-effort only.
    }
}

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
    Initialize-DeployEventLog
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

    $Script:CurrentStageName = $Name
    Write-DeployEvent -Message "Starting: $Title" -EventId 1000
}

function Stop-DeployStage {
    <#
    .SYNOPSIS
        Common end of every stage. Returns the exit code so the caller can do: exit (Stop-DeployStage 0)
    #>
    [CmdletBinding()]
    param([int]$ExitCode = 0)

    $entryType = if ($ExitCode -eq $Script:ExitSuccess) { 'Information' } else { 'Warning' }
    Write-DeployEvent -Message "$($Script:CurrentStageName) finished with exit code $ExitCode." -EntryType $entryType -EventId 1001

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
    Get-DeployStamp, Set-DeployStamp, Test-DeployStamp, Test-InteractiveSession, `
    Initialize-DeployEventLog, Write-DeployEvent -Variable `
    CompanyName, ScriptVersion, SoftwareName, DownloadUrl, VHDXVersion, VHDXSha256, `
    ProductName, BrandingLogo, BrandingPath, `
    LocalInstall, VMSwitchName, VMSwitchAdapterName, CreateHyperVUser, FirewallScopeSubnet, `
    DeployPath, DeployITLogs, VMDeployPath, VHDXDownloadPath, `
    RegistryPath, RegistrySoftwareName, ApplicationKeyPath, `
    HyperVFeatures, FirewallRules, ExitSuccess, ExitFailure, ExitRebootRequired
