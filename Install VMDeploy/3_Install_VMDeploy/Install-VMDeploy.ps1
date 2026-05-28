
#Requires -Version 5.1
<#
.SYNOPSIS
    Stage 3 — Copy VMDeploy source files and create Start Menu shortcuts.
.NOTES
    Uses Robocopy to deploy the source tree, then writes a version stamp
    to the registry. Idempotent: re-runs update if the version stamp differs.
#>

# -------  Bootstrap: load shared settings  -------
Import-Module "$PSScriptRoot\..\..\Settings.psm1" -Force

$SourceFiles = "VMDeployVersion"
$Date        = Get-Date -Format yyMMdd
$LogPath     = "$DeployITLogs\Install-VMDeploy-$Date.log"
Start-Transcript -Path $LogPath -Force -Append

Initialize-DeployEnvironment

Write-Host "========================================================"
Write-Host "                  Install VM Deploy"
Write-Host "========================================================"

# -------  Helper: create a shortcut (optionally Run-as-admin)  -------
function New-Shortcut {
    param(
        [string]$SourceFile,
        [string]$DestinationFile,
        [string]$Arguments,
        [string]$IconPath = "NA",
        [switch]$RunAsAdmin
    )
    $shell     = New-Object -ComObject WScript.Shell
    $shortcut  = $shell.CreateShortcut($DestinationFile)
    $shortcut.TargetPath = $SourceFile
    $shortcut.Arguments  = $Arguments
    if ($IconPath -ne "NA") { $shortcut.IconLocation = $IconPath }
    $shortcut.Save()

    if ($RunAsAdmin) {
        $bytes = [System.IO.File]::ReadAllBytes($shortcut.FullName)
        $bytes[0x15] = $bytes[0x15] -bor 0x20
        [System.IO.File]::WriteAllBytes($shortcut.FullName, $bytes)
    }
}

# -------  Deploy files  -------
function Install-VMDeployFiles {
    Write-Host "Copying VMDeploy source files ..."
    & Robocopy "$PSScriptRoot\Source" "$env:ProgramData\" /e /it /is /copyall

    $menuDir = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\VMDeploy"
    New-Item -Path $menuDir -ItemType Directory -Force | Out-Null

    $baseArgs = "-ExecutionPolicy Bypass -File C:\ProgramData\VMDeploy"
    $iconBase  = "$env:ProgramData\VMDeploy\Icons"

    New-Shortcut -SourceFile "PowerShell.exe" `
        -DestinationFile "$menuDir\Deploy Windows.lnk" `
        -Arguments "$baseArgs\VMDeploywUI.ps1" `
        -IconPath "$iconBase\VMDeploy.ico" -RunAsAdmin

    New-Shortcut -SourceFile "PowerShell.exe" `
        -DestinationFile "$menuDir\VM Destroy.lnk" `
        -Arguments "$baseArgs\VMRemovewUI.ps1" `
        -IconPath "$iconBase\VMDestroy.ico" -RunAsAdmin

    New-Shortcut -SourceFile "PowerShell.exe" `
        -DestinationFile "$menuDir\Deploy UbuntuServer.lnk" `
        -Arguments "$baseArgs\UbuntuServerDeploy.ps1" `
        -IconPath "$iconBase\DeployUbuntuServer.ico" -RunAsAdmin
}

# -------  Install or update  -------
$installedVersion = Get-ItemPropertyValue -Path $ApplicationKeyPath -Name $SourceFiles -ErrorAction SilentlyContinue

if ($null -eq $installedVersion) {
    Write-Host "VMDeploy not found — performing fresh install."
    Install-VMDeployFiles
    New-ItemProperty -Path $ApplicationKeyPath -Name $SourceFiles -Value $ScriptVersion -PropertyType String -Force | Out-Null
} else {
    Write-Host "Installed version ($installedVersion) differs from current ($ScriptVersion) — updating."
    Install-VMDeployFiles
    Set-ItemProperty -Path $ApplicationKeyPath -Name $SourceFiles -Value $ScriptVersion -Force | Out-Null
}

# -------  Verify  -------
$stamp = Get-ItemPropertyValue -Path $ApplicationKeyPath -Name $SourceFiles -ErrorAction SilentlyContinue
if ($stamp -eq $ScriptVersion) {
    Write-Host "Installation verified successfully."
    Stop-Transcript
    exit 0
} else {
    Write-Error "Version stamp not found or incorrect after install."
    Stop-Transcript
    exit 1
}
