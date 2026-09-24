#Requires -Version 5.1
<#
.SYNOPSIS
    Writes VMDeploy activity to the Windows Event Log, readable without local admin rights.
.DESCRIPTION
    Transcript logs under C:\ProgramData\VMDeploy\logs are SYSTEM-only on Intune/ConfigMgr installs
    (see docs/setup/INSTALLATION.md#permissions-intune--configmgr-only) - an operator with only
    Hyper-V Administrators rights, not local admin, can no longer read them. Event Log channel
    permissions are separate from NTFS permissions: a custom log created this way defaults to
    granting read+write to "Interactive Users" (any interactively logged-on account, admin or not),
    so this is readable from Event Viewer > Applications and Services Logs > VMDeploy > Operational,
    or `Get-WinEvent -LogName "VMDeploy/Operational"`, without local admin rights or takeown.exe.
#>

$Script:VIAEventLogName = "VMDeploy/Operational"

function Initialize-VIAEventLogSource {
    <#
    .SYNOPSIS
        Registers an event source under the VMDeploy/Operational log if it doesn't exist yet.
    .NOTES
        Registering a new source needs local admin rights (writes under
        HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\...). Safe to call every time - it's a
        no-op once the source exists, which it normally will after the first run.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Source)

    if ([System.Diagnostics.EventLog]::SourceExists($Source)) { return }
    try {
        New-EventLog -LogName $Script:VIAEventLogName -Source $Source -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not create event log source '$Source': $($_.Exception.Message)"
    }
}

function Write-VIAEvent {
    <#
    .SYNOPSIS
        Writes one entry to the VMDeploy/Operational event log. Never throws - a logging failure
        must not break a deployment or removal.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Information', 'Warning', 'Error')][string]$EntryType = 'Information',
        [int]$EventId = 1000
    )
    Initialize-VIAEventLogSource -Source $Source
    try {
        Write-EventLog -LogName $Script:VIAEventLogName -Source $Source -EntryType $EntryType -EventId $EventId -Message $Message -ErrorAction Stop
    }
    catch {
        # Best-effort only - e.g. the source registration above failed, or the log was deleted.
    }
}

Export-ModuleMember -Function Write-VIAEvent
