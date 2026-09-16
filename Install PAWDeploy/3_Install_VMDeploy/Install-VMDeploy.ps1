#Requires -Version 5.1
<#
.SYNOPSIS
    Stage 3 - Copy the VMDeploy source files and create Start Menu shortcuts.
.NOTES
    Robocopy deploys Source\VMDeploy to C:\ProgramData\VMDeploy, then the version stamp
    VMDeployVersion is written. The orchestrator re-runs this stage whenever the stamp
    differs from $ScriptVersion, which updates an existing installation.
#>

Import-Module "$PSScriptRoot\..\Settings.psm1" -Force
Start-DeployStage -Name "Install-VMDeploy" -Title "Stage 3 - Install VMDeploy $ScriptVersion"

# -------  Copy files  -------

Write-Host "Copying VMDeploy source files to $VMDeployPath ..."
& Robocopy.exe "$PSScriptRoot\Source" "$env:ProgramData" /E /IT /IS /COPYALL /R:2 /W:5 /NP /NFL /NDL
# Robocopy: 0-7 = success (files copied / skipped / extra), 8+ = at least one failure
if ($LASTEXITCODE -ge 8) {
    Write-Warning "Robocopy failed with exit code $LASTEXITCODE."
    exit (Stop-DeployStage $ExitFailure)
}

# -------  Start Menu shortcuts (local installs only)  -------

function New-Shortcut {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Script,
        [Parameter(Mandatory)][string]$Icon,
        [Parameter(Mandatory)][string]$Folder
    )
    $shell    = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path $Folder "$Name.lnk"))
    $shortcut.TargetPath   = "PowerShell.exe"
    $shortcut.Arguments    = "-ExecutionPolicy Bypass -NoProfile -File `"$VMDeployPath\$Script`""
    $shortcut.IconLocation = "$VMDeployPath\Icons\$Icon"
    $shortcut.Save()

    # Set the "Run as administrator" flag (byte 0x15, bit 0x20)
    $bytes = [System.IO.File]::ReadAllBytes($shortcut.FullName)
    $bytes[0x15] = $bytes[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($shortcut.FullName, $bytes)
}

if ($LocalInstall) {
    Write-Host "LocalInstall = true - creating Start Menu shortcuts."
    $menuDir = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\VMDeploy"
    New-Item -Path $menuDir -ItemType Directory -Force | Out-Null

    New-Shortcut -Folder $menuDir -Name "Deploy Windows"      -Script "VMDeploywUI.ps1"        -Icon "VMDeploy.ico"
    New-Shortcut -Folder $menuDir -Name "VM Destroy"          -Script "VMRemovewUI.ps1"        -Icon "VMDestroy.ico"
    New-Shortcut -Folder $menuDir -Name "Deploy UbuntuServer" -Script "UbuntuServerDeploy.ps1" -Icon "DeployUbuntuServer.ico"
}
else {
    Write-Host "LocalInstall = false - skipping Start Menu shortcuts (Intune/ConfigMgr deployment)."
}

# -------  Verify and stamp  -------

if (-not (Test-Path "$VMDeployPath\VMDeploywUI.ps1")) {
    Write-Warning "VMDeploywUI.ps1 not found in $VMDeployPath after copy."
    exit (Stop-DeployStage $ExitFailure)
}

Set-DeployStamp -Name "VMDeployVersion" -Value $ScriptVersion
exit (Stop-DeployStage $ExitSuccess)
