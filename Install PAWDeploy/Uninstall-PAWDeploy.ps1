#Requires -Version 5.1
<#
.SYNOPSIS
    VMDeploy - Uninstaller (Intune / ConfigMgr / manual entry point).
.DESCRIPTION
    Removes everything Install-PAWDeploy.ps1 puts on the machine: the VMDeploy program folder,
    Start Menu shortcuts, DeployIT check/marker files, and the registry key used for Intune
    detection. Safe to run more than once and safe to run when nothing is installed.

    Some changes are shared with the rest of the machine (Hyper-V itself, the VM switch, VMs and
    their disks, the "Hypervuser" account) and are therefore left in place unless you opt in with
    a switch - removing them could affect things that have nothing to do with PAWDeploy.

    Exit codes: 0 = success, 1 = failure, 1641 = reboot required (only with -DisableHyperVFeatures).
.PARAMETER RemoveVMs
    Also stop and delete any Hyper-V VM stored under C:\ProgramData\VMDeploy\VMs, including its
    virtual disks. Without this switch, if such VMs exist, they (and only they) are left in place
    and a warning is written; everything else is still removed.
.PARAMETER RemoveVMSwitch
    Also remove the Hyper-V external switch created by Stage 2a ($VMSwitchName in Settings.psm1).
    Skipped with a warning if any VM on the host (not just PAWDeploy's) still uses it.
.PARAMETER RemoveHyperVUser
    Also remove the local "Hypervuser" account created by Stage 2c. Its profile folder, if any, is
    left in place. The signed-in user that was added to Hyper-V Administrators during install is
    intentionally NOT removed from that group - there is no reliable way to tell whether they need
    Hyper-V access for something unrelated to PAWDeploy.
.PARAMETER DisableHyperVFeatures
    Also disable the Windows Optional Features enabled by Stage 1 (Hyper-V and its management
    tools). This affects every VM on the computer, not only PAWDeploy's, and normally requires a
    reboot. Off by default.
.PARAMETER SkipFirewallRestore
    Do not restore the firewall rules Stage 2b disabled/scoped back to Enabled + unscoped. By
    default they ARE restored, since that is a cheap, fully reversible step.
.PARAMETER RemoveLogs
    Also delete C:\ProgramData\<CompanyName>\Logs. Kept by default so this run's own log survives.
.PARAMETER Full
    Shorthand for -RemoveVMs -RemoveVMSwitch -RemoveHyperVUser -DisableHyperVFeatures. Use when you
    want a complete teardown, including reverting Hyper-V itself.
.EXAMPLE
    PowerShell -ExecutionPolicy Bypass -NoProfile -File "Uninstall-PAWDeploy.ps1"
    Default, safe cleanup: program files, shortcuts, registry, restores firewall rules. Leaves
    Hyper-V, the VM switch, VMs/disks and the Hypervuser account untouched.
.EXAMPLE
    PowerShell -ExecutionPolicy Bypass -NoProfile -File "Uninstall-PAWDeploy.ps1" -Full
    Complete teardown, including deleting VMs/disks and disabling Hyper-V (reboot likely).
.NOTES
    Intune uninstall command:
      PowerShell.exe -ExecutionPolicy ByPass -NoProfile -WindowStyle Hidden -File Uninstall-PAWDeploy.ps1
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$RemoveVMs,
    [switch]$RemoveVMSwitch,
    [switch]$RemoveHyperVUser,
    [switch]$DisableHyperVFeatures,
    [switch]$SkipFirewallRestore,
    [switch]$RemoveLogs,
    [switch]$Full
)

if ($Full) {
    $RemoveVMs = $true
    $RemoveVMSwitch = $true
    $RemoveHyperVUser = $true
    $DisableHyperVFeatures = $true
}

# -------  Relaunch in 64-bit PowerShell  -------
# Same reason as Install-PAWDeploy.ps1: Intune starts installers from a 32-bit process, and DISM /
# the Hyper-V cmdlets do not work under WOW64. Switches are forwarded so behaviour matches.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $native = Join-Path $env:SystemRoot "Sysnative\WindowsPowerShell\v1.0\powershell.exe"
    $argList = @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', $PSCommandPath)
    foreach ($key in $PSBoundParameters.Keys) {
        if ($PSBoundParameters[$key] -is [switch] -or $PSBoundParameters[$key] -is [bool]) {
            if ($PSBoundParameters[$key]) { $argList += "-$key" }
        }
    }
    & $native @argList
    exit $LASTEXITCODE
}

Import-Module "$PSScriptRoot\Settings.psm1" -Force

# -------  Pre-flight  -------

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "The uninstaller must run elevated (local administrator or SYSTEM)."
    exit $ExitFailure
}

# Nothing to do on a clean machine - and importantly, don't let Start-DeployStage recreate the
# registry key / log folder below just to tell you that.
$alreadyGone = -not (Test-Path $VMDeployPath) -and -not (Test-Path $RegistrySoftwareName) -and -not (Test-Path $DeployPath)
if ($alreadyGone) {
    Write-Host "PAWDeploy does not appear to be installed on this computer - nothing to do."
    exit $ExitSuccess
}

Start-DeployStage -Name "Uninstall-PAWDeploy" -Title "VMDeploy Uninstaller v$ScriptVersion - $CompanyName"
Write-Host "Script : $PSCommandPath"
Write-Host "Context: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"

$rebootRequired = $false

# -------  VMs stored under VMDeploy  -------

$vmsRoot = Join-Path $VMDeployPath "VMs"
$pawVMs = @()
if (Get-Command Get-VM -ErrorAction SilentlyContinue) {
    try { $pawVMs = @(Get-VM -ErrorAction Stop | Where-Object { $_.Path -like "$vmsRoot*" }) }
    catch { Write-Warning "Could not query Hyper-V VMs: $($_.Exception.Message)" }
}

$skipVMsFolder = $false
if ($pawVMs.Count -gt 0) {
    if ($RemoveVMs) {
        foreach ($vm in $pawVMs) {
            if ($PSCmdlet.ShouldProcess($vm.Name, "Stop and remove Hyper-V VM (deletes its virtual disks)")) {
                Write-Host "Removing VM '$($vm.Name)' ..."
                try {
                    if ($vm.State -ne 'Off') { Stop-VM -VM $vm -TurnOff -Force -ErrorAction Stop }
                    Remove-VM -VM $vm -Force -ErrorAction Stop
                }
                catch { Write-Warning "Could not remove VM '$($vm.Name)': $($_.Exception.Message)" }
            }
        }
    }
    else {
        Write-Warning "Found $($pawVMs.Count) Hyper-V VM(s) under $vmsRoot`: $(($pawVMs.Name) -join ', '). Left in place - re-run with -RemoveVMs (or -Full) to delete them and their virtual disks. Everything else is still removed."
        $skipVMsFolder = $true
    }
}

# -------  VM switch  -------

if ($RemoveVMSwitch) {
    $sw = Get-VMSwitch -Name $VMSwitchName -ErrorAction SilentlyContinue
    if ($sw) {
        $inUse = @(Get-VM -ErrorAction SilentlyContinue | Get-VMNetworkAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.SwitchName -eq $VMSwitchName })
        if ($inUse.Count -gt 0) {
            Write-Warning "VMSwitch '$VMSwitchName' is still used by $($inUse.Count) VM network adapter(s) - not removed."
        }
        elseif ($PSCmdlet.ShouldProcess($VMSwitchName, "Remove Hyper-V VM switch")) {
            try {
                Remove-VMSwitch -Name $VMSwitchName -Force -ErrorAction Stop
                Write-Host "Removed VMSwitch '$VMSwitchName'."
            }
            catch { Write-Warning "Could not remove VMSwitch '$VMSwitchName': $($_.Exception.Message)" }
        }
    }
}

# -------  Firewall rules  -------

if (-not $SkipFirewallRestore) {
    foreach ($rule in $FirewallRules) {
        $stamp = Get-DeployStamp -Name $rule
        if (-not $stamp -or $stamp -eq "NotFound") { continue }
        if (-not (Get-NetFirewallRule -Name $rule -ErrorAction SilentlyContinue)) { continue }

        if ($PSCmdlet.ShouldProcess($rule, "Restore firewall rule (Enabled, unscoped)")) {
            try {
                Set-NetFirewallRule -Name $rule -Enabled True -RemoteAddress Any -ErrorAction Stop
                Write-Host "Restored firewall rule '$rule'."
            }
            catch { Write-Warning "Could not restore firewall rule '$rule': $($_.Exception.Message)" }
        }
    }
}

# -------  Hypervuser account  -------

if ($RemoveHyperVUser) {
    $hyperVUser = Get-LocalUser -Name "Hypervuser" -ErrorAction SilentlyContinue
    if ($hyperVUser) {
        if ($PSCmdlet.ShouldProcess("Hypervuser", "Remove local user account")) {
            try {
                Remove-LocalUser -Name "Hypervuser" -ErrorAction Stop
                Write-Host "Removed local user 'Hypervuser' (its profile folder under C:\Users, if any, was left in place)."
            }
            catch { Write-Warning "Could not remove local user 'Hypervuser': $($_.Exception.Message)" }
        }
    }
}

# -------  Hyper-V optional features  -------

if ($DisableHyperVFeatures) {
    Write-Warning "Disabling Hyper-V affects every VM on this computer, not only ones created by PAWDeploy."
    foreach ($feature in $HyperVFeatures) {
        try {
            $state = (Get-WindowsOptionalFeature -FeatureName $feature -Online -ErrorAction Stop).State
            if ($state -in @("Enabled", "EnablePending")) {
                if ($PSCmdlet.ShouldProcess($feature, "Disable Windows Optional Feature")) {
                    Write-Host "Disabling $feature ..."
                    $result = Disable-WindowsOptionalFeature -FeatureName $feature -Online -NoRestart -ErrorAction Stop
                    if ($result.RestartNeeded) { $rebootRequired = $true }
                }
            }
        }
        catch { Write-Warning "$feature - $($_.Exception.Message)" }
    }
}

# -------  Start Menu shortcuts  -------

$menuDir = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\VMDeploy"
if (Test-Path $menuDir) {
    if ($PSCmdlet.ShouldProcess($menuDir, "Remove Start Menu shortcuts")) {
        Remove-Item -Path $menuDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Removed Start Menu shortcuts."
    }
}

# -------  VMDeploy program folder  -------

if (Test-Path $VMDeployPath) {
    # Install-PAWDeploy.ps1 restricts this folder to SYSTEM only when LocalInstall = $false - make
    # sure whoever is running this uninstaller (SYSTEM or an elevated local admin) can delete it.
    # takeown.exe is used rather than "icacls /setowner" - the latter needs
    # SeTakeOwnershipPrivilege to be explicitly enabled, which is unreliable even from an elevated
    # admin token, while takeown.exe reliably reclaims access in that same situation.
    try {
        & takeown.exe /F "$VMDeployPath" /R /D Y | Out-Null
        & icacls.exe "$VMDeployPath" /grant "*S-1-5-32-544:(OI)(CI)F" /T /C /Q | Out-Null
    }
    catch { }

    if ($skipVMsFolder) {
        Get-ChildItem -Path $VMDeployPath -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $vmsRoot } |
            ForEach-Object {
                if ($PSCmdlet.ShouldProcess($_.FullName, "Remove")) {
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        Write-Host "Removed VMDeploy program files. Left $vmsRoot in place (still holds VM data)."
    }
    else {
        if ($PSCmdlet.ShouldProcess($VMDeployPath, "Remove directory tree")) {
            Remove-Item -Path $VMDeployPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Removed $VMDeployPath."
        }
    }
}

# -------  DeployIT check markers and tools  -------

$checkDir = Join-Path $DeployPath "Check"
if (Test-Path $checkDir) {
    Remove-Item -Path (Join-Path $checkDir "Run-PAWDeploy.txt") -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $checkDir "Remove-PAWDeploy.txt") -Force -ErrorAction SilentlyContinue
    if (-not (Get-ChildItem -Path $checkDir -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -Path $checkDir -Force -ErrorAction SilentlyContinue
    }
}

$toolsDir = Join-Path $DeployPath "Tools"
if (Test-Path $toolsDir) {
    Remove-Item -Path $toolsDir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($RemoveLogs) {
    try { Stop-Transcript | Out-Null } catch { }
    if (Test-Path $DeployITLogs) {
        Remove-Item -Path $DeployITLogs -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (Test-Path $DeployPath) {
    if (-not (Get-ChildItem -Path $DeployPath -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -Path $DeployPath -Force -ErrorAction SilentlyContinue
    }
}

# -------  Registry (this is also the Intune detection key)  -------

if (Test-Path $RegistrySoftwareName) {
    if ($PSCmdlet.ShouldProcess($RegistrySoftwareName, "Remove registry key")) {
        Remove-Item -Path $RegistrySoftwareName -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Removed registry key $RegistrySoftwareName."
    }
}

if (Test-Path $RegistryPath) {
    $hasSubkeys = [bool](Get-ChildItem -Path $RegistryPath -ErrorAction SilentlyContinue)
    $hasValues = [bool]((Get-Item -Path $RegistryPath -ErrorAction SilentlyContinue).Property)
    if (-not $hasSubkeys -and -not $hasValues) {
        Remove-Item -Path $RegistryPath -Force -ErrorAction SilentlyContinue
        Write-Host "Removed now-empty registry key $RegistryPath."
    }
}

# -------  Done  -------

Write-Host ""
Write-Host "PAWDeploy uninstall finished."
if ($skipVMsFolder) {
    Write-Host "Note: VM data under $vmsRoot was kept - re-run with -RemoveVMs (or -Full) to delete it."
}

if ($rebootRequired) {
    Write-Host "A reboot is required to finish disabling Hyper-V - exiting $ExitRebootRequired."
    exit (Stop-DeployStage $ExitRebootRequired)
}

exit (Stop-DeployStage $ExitSuccess)
