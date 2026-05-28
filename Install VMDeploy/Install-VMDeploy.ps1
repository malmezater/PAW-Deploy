
#Requires -Version 5.1
<#
.SYNOPSIS
    VMDeploy — Main orchestrator script (Intune entry point).
.DESCRIPTION
    Runs all four installation stages in sequence, tracking state via
    registry flags written by each child script.
.EXAMPLE
    PowerShell -ExecutionPolicy ByPass -NoProfile -WindowStyle Hidden -File Install-VMDeploy.ps1
#>

# -------  Bootstrap: load shared settings  -------
Import-Module "$PSScriptRoot\Settings.psm1" -Force

$Date    = Get-Date -Format yyMMdd
$LogPath = "$DeployITLogs\$($MyInvocation.MyCommand.Name)-$Date.log"
Start-Transcript -Path $LogPath -Force -Append

Initialize-DeployEnvironment

Write-Host "========================================================"
Write-Host "   VMDeploy Installer v$ScriptVersion — $CompanyName"
Write-Host "========================================================"
Write-Host "Script: $($MyInvocation.MyCommand.Source)"
Write-Host ""

# -------  Helper: run a child script and check exit code  -------
function Invoke-Stage {
    param(
        [string]$Label,
        [string]$ScriptPath
    )
    Write-Host "========================================================"
    Write-Host "  $Label"
    Write-Host "========================================================"

    PowerShell.exe -ExecutionPolicy Bypass -NoProfile -File $ScriptPath
    $ec = $LASTEXITCODE

    # 1641 = reboot required (Hyper-V feature install) — treat as success for flow
    if ($ec -eq 0 -or $ec -eq 1641) {
        Write-Host "$Label completed (exit $ec)."
        return $ec
    } else {
        Write-Warning "$Label failed with exit code $ec."
        Stop-Transcript
        exit 1
    }
}

# -------  Stage 1: Install Hyper-V features  -------

$hyperVStamp = Get-ItemProperty -Path $RegistrySoftwareName -Name "Microsoft-Hyper-V-All" -ErrorAction SilentlyContinue
if ($hyperVStamp) {
    Write-Host "Stage 1: Hyper-V features already installed — skipping."
} else {
    $ec = Invoke-Stage -Label "Stage 1 — Install Hyper-V Features" `
        -ScriptPath "$PSScriptRoot\1_Install-Features_for_PAW\Install-Features_for_PAW.ps1"

    if ($ec -eq 1641) {
        Write-Host "Reboot required after Hyper-V feature install. Exiting 1641."
        Stop-Transcript
        exit 1641
    }
}

# -------  Stage 2a: Configure PAW network  -------

$pawStamp = Get-ItemProperty -Path $RegistrySoftwareName -Name "PawNetwork" -ErrorAction SilentlyContinue
if ($pawStamp) {
    Write-Host "Stage 2a: PAW network already configured — skipping."
} else {
    Invoke-Stage -Label "Stage 2a — Configure PAW Network" `
        -ScriptPath "$PSScriptRoot\2_Install_VMDeploy-configuration\Configure-PAWNetwork.ps1"
}

# -------  Stage 2b: Set firewall rules  -------

$fwStamp = Get-ItemProperty -Path $RegistrySoftwareName -Name $FirewallRules[0] -ErrorAction SilentlyContinue
if ($fwStamp) {
    Write-Host "Stage 2b: Firewall rules already configured — skipping."
} else {
    Invoke-Stage -Label "Stage 2b — Set Firewall Rules" `
        -ScriptPath "$PSScriptRoot\2_Install_VMDeploy-configuration\Set-FirewallRules.ps1"
}

# -------  Stage 2c: Add Hyper-V admin  -------

$adminStamp = Get-ItemProperty -Path $RegistrySoftwareName -Name "HyperV-Admins" -ErrorAction SilentlyContinue
if ($adminStamp) {
    Write-Host "Stage 2c: Hyper-V admin already configured — skipping."
} else {
    Invoke-Stage -Label "Stage 2c — Add Hyper-V Admin" `
        -ScriptPath "$PSScriptRoot\2_Install_VMDeploy-configuration\Add-HyperVAdmin.ps1"
}

# -------  Stage 3: Install VMDeploy  -------

$appStamp = Get-ItemPropertyValue -Path $ApplicationKeyPath -Name "VMDeployVersion" -ErrorAction SilentlyContinue
if ($appStamp -eq $ScriptVersion) {
    Write-Host "Stage 3: VMDeploy $ScriptVersion already installed — skipping."
} else {
    Invoke-Stage -Label "Stage 3 — Install VMDeploy" `
        -ScriptPath "$PSScriptRoot\3_Install_VMDeploy\Install-VMDeploy.ps1"
}

# -------  Stage 4: Download VHDX  -------

$vhdxStamp = Get-ItemPropertyValue -Path $ApplicationKeyPath -Name "WindowsVHDX" -ErrorAction SilentlyContinue
if ($vhdxStamp -eq $VHDXVersion) {
    Write-Host "Stage 4: VHDX $VHDXVersion already downloaded — skipping."
} else {
    Invoke-Stage -Label "Stage 4 — Download Windows VHDX" `
        -ScriptPath "$PSScriptRoot\4_Download_Windows_VHDX\download-vhdx.ps1"
}

# -------  Post-install verification  -------

Write-Host "========================================================"
Write-Host "                Post-Install Verification"
Write-Host "========================================================"

$vmDeployDir = "$env:ProgramData\VMDeploy"
if (Test-Path $vmDeployDir) {
    Write-Host "VMDeploy directory found: $vmDeployDir"

    try {
        Set-ItemProperty -Path $ApplicationKeyPath -Name "(Default)" -Value "True" -Force
        Write-Host "Registry default value set."
    } catch {
        Write-Warning "Could not set registry default value."
    }

    Write-Host "========================================================"
    Write-Host "          Installation completed successfully."
    Write-Host "========================================================"
    Stop-Transcript
    exit 0
} else {
    Write-Warning "VMDeploy directory not found — installation may have failed."
    Stop-Transcript
    exit 1
}
