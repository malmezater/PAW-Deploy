#Requires -Version 5.1
<#
.SYNOPSIS
    VMDeploy - Main orchestrator script (Intune / ConfigMgr / manual entry point).
.DESCRIPTION
    Runs the installation stages in order. Each stage is skipped when its registry
    stamp shows it is already done, so the script is safe to re-run.

    Exit codes:  0 = success,  1 = failure,  1641 = reboot required (re-run after reboot).
.EXAMPLE
    PowerShell -ExecutionPolicy ByPass -NoProfile -WindowStyle Hidden -File Install-PAWDeploy.ps1
#>

# -------  Relaunch in 64-bit PowerShell  -------
# The Intune Management Extension starts installers from a 32-bit process. DISM (Hyper-V features)
# and the Hyper-V cmdlets do not work under WOW64, so hand over to the native 64-bit PowerShell.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $native = Join-Path $env:SystemRoot "Sysnative\WindowsPowerShell\v1.0\powershell.exe"
    & $native -ExecutionPolicy Bypass -NoProfile -File $PSCommandPath
    exit $LASTEXITCODE
}

Import-Module "$PSScriptRoot\Settings.psm1" -Force

Start-DeployStage -Name "Install-PAWDeploy" -Title "VMDeploy Installer v$ScriptVersion - $CompanyName"
Write-Host "Script : $PSCommandPath"
Write-Host "Context: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"

# -------  Pre-flight  -------

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "The installer must run elevated (local administrator or SYSTEM)."
    exit (Stop-DeployStage $ExitFailure)
}

# Fail before touching the machine if Settings.psm1 still has a placeholder URL ("Download URL", "\\DownloadURLHere").
if (-not $DownloadUrl -or $DownloadUrl -match '^\W*Download\s*URL(\s*Here)?$' -or
    $DownloadUrl -notmatch '^(https?://|\\\\|[A-Za-z]:\\)') {
    Write-Warning "DownloadUrl in Settings.psm1 is not configured ('$DownloadUrl'). Set it to an HTTP(S) URL, Azure Storage URL or UNC path."
    exit (Stop-DeployStage $ExitFailure)
}

# -------  Stage definitions  -------
# IsDone must match the stamps the stage script writes.

$Stages = @(
    @{ Id = "1";  Name = "Install Hyper-V features"
       Script = "Stages\1_Install-Features_for_PAW\Install-Features_for_PAW.ps1"
       IsDone = { Test-DeployStamp -Name $HyperVFeatures -Value "Enabled" } }

    @{ Id = "2a"; Name = "Configure PAW network"
       Script = "Stages\2_Install_VMDeploy-configuration\Configure-PAWNetwork.ps1"
       IsDone = { Test-DeployStamp -Name "PawNetwork" -Value "True" } }

    @{ Id = "2b"; Name = "Set firewall rules"
       Script = "Stages\2_Install_VMDeploy-configuration\Set-FirewallRules.ps1"
       IsDone = { Test-DeployStamp -Name $FirewallRules } }

    @{ Id = "2c"; Name = "Add Hyper-V administrators"
       Script = "Stages\2_Install_VMDeploy-configuration\Add-HyperVAdmin.ps1"
       IsDone = { Test-DeployStamp -Name "HyperV-Admins" -Value "True" } }

    @{ Id = "3";  Name = "Install VMDeploy $ScriptVersion"
       Script = "Stages\3_Install_VMDeploy\Install-VMDeploy.ps1"
       IsDone = { Test-DeployStamp -Name "VMDeployVersion" -Value $ScriptVersion } }

    @{ Id = "4";  Name = "Download Windows VHDX $VHDXVersion"
       Script = "Stages\4_Download_Windows_VHDX\download-vhdx.ps1"
       IsDone = { Test-DeployStamp -Name "WindowsVHDX" -Value $VHDXVersion } }
)

# -------  Run stages  -------

$powershell = Join-Path $PSHOME "powershell.exe"

foreach ($stage in $Stages) {
    $label = "Stage $($stage.Id) - $($stage.Name)"

    if (& $stage.IsDone) {
        Write-Host "$label : already done - skipping."
        continue
    }

    Write-Host ""
    Write-Host ">>> $label"
    & $powershell -ExecutionPolicy Bypass -NoProfile -File (Join-Path $PSScriptRoot $stage.Script)
    $ec = $LASTEXITCODE

    switch ($ec) {
        $ExitSuccess {
            Write-Host "<<< $label completed."
        }
        $ExitRebootRequired {
            Write-Host "<<< $label requires a reboot. Exiting $ExitRebootRequired - run the installer again after the restart."
            exit (Stop-DeployStage $ExitRebootRequired)
        }
        default {
            Write-Warning "$label failed with exit code $ec. See the stage log in $DeployITLogs."
            exit (Stop-DeployStage $ExitFailure)
        }
    }
}

# -------  Post-install verification  -------

Write-Host ""
Write-Host "========================================================"
Write-Host "  Post-install verification"
Write-Host "========================================================"

$incomplete = @($Stages | Where-Object { -not (& $_.IsDone) } | ForEach-Object { "Stage $($_.Id)" })

if ($incomplete.Count -gt 0) {
    Write-Warning "Stages not confirmed complete: $($incomplete -join ', ')"
    exit (Stop-DeployStage $ExitFailure)
}
if (-not (Test-Path $VMDeployPath)) {
    Write-Warning "VMDeploy directory not found: $VMDeployPath"
    exit (Stop-DeployStage $ExitFailure)
}

# -------  Restrict VMDeploy folder to SYSTEM (Intune / ConfigMgr only)  -------
# When LocalInstall = $false, nobody signs in and runs VMDeploy interactively as themselves - the
# Intune Management Extension (or ConfigMgr) drives everything as SYSTEM, including the "Run
# VMDeploy" / "Remove VM" helper apps. Neither local Administrators nor ordinary Users (inherited
# read access from C:\ProgramData's own default ACL) has a legitimate need to read or write VM
# configs, virtual disks or the downloaded VHDX here, so both are removed to reduce the attack
# surface against deployed VMs; SYSTEM keeps full control. Done last, after every stage has finished
# writing into this folder - locking it earlier would break a stage's own writes unless it also runs
# as SYSTEM.
#
# /inheritance:d converts inherited ACEs to explicit ones first (a safe no-op on the effective
# permissions), then /remove:g drops just Administrators/Users/Authenticated Users by well-known SID
# (locale-independent). Ownership is deliberately left alone - changing it needs
# SeTakeOwnershipPrivilege to be explicitly enabled, which is unreliable for icacls /setowner even
# from an elevated admin token, and risks leaving the folder in a half-locked, inaccessible state if
# it fails partway. This is defense in depth, not a hard boundary either way: a local Administrator
# can always run takeown.exe on their own machine to reclaim access, so it stops casual/automated
# access rather than a deliberate, fully-privileged local admin.
if (-not $LocalInstall) {
    Write-Host "LocalInstall = false - restricting $VMDeployPath to SYSTEM only."
    try {
        & icacls.exe "$VMDeployPath" /inheritance:d /T /C /Q | Out-Null
        & icacls.exe "$VMDeployPath" /remove:g "*S-1-5-32-544" "*S-1-5-32-545" "*S-1-5-11" /T /C /Q | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "icacls exited with code $LASTEXITCODE" }
        Write-Host "Permissions restricted: only SYSTEM can access $VMDeployPath."
        Write-DeployEvent -Message "Restricted $VMDeployPath to SYSTEM only (LocalInstall = false)." -EventId 1010
    }
    catch {
        Write-Warning "Could not restrict permissions on $VMDeployPath`: $($_.Exception.Message)"
        Write-DeployEvent -Message "Could not restrict permissions on $VMDeployPath`: $($_.Exception.Message)" -EntryType Warning -EventId 1011
    }
}

Set-ItemProperty -Path $ApplicationKeyPath -Name "(Default)" -Value "True" -Force
Write-Host "Installation completed successfully."
exit (Stop-DeployStage $ExitSuccess)
