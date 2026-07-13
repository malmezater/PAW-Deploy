#Requires -Version 5.1
<#
.SYNOPSIS
    Install AutoPilot module and initialise the Desktop App Installer (winget).
.DESCRIPTION
    Step 1 - Installs the required PowerShell modules and scripts used during
    image preparation (AutoPilot).

    Step 2 - Initialises the winget COM server by running it once. Winget uses
    a COM-based server that must be activated before sysprep. If this step is
    skipped, all winget package installations on deployed VMs will fail with
    exit code 0x8A150002.
.NOTES
    Run as Administrator inside the VHDX template, after Uninstall-WinApps.ps1
    and before Remove-TempFiles.ps1 / sysprep.
#>

# -------  PowerShell modules and scripts  -------

$Modules = @(
    "WindowsAutoPilotIntune"
)

$Scripts = @(
    "Get-WindowsAutoPilotInfo"
)

Write-Host "=== Installing PowerShell modules ===" -ForegroundColor Cyan

foreach ($item in $Modules) {
    Write-Host "Installing module: $item"
    Install-Module -Name $item -Scope AllUsers -Force
}

foreach ($item in $Scripts) {
    Write-Host "Installing script: $item"
    Install-Script -Name $item -Scope AllUsers -Force
}

# -------  Winget initialisation  -------

Write-Host ""
Write-Host "=== Initialising winget (Desktop App Installer) ===" -ForegroundColor Cyan

# Running 'winget --info' activates the COM server and registers the App Execution
# Alias infrastructure without installing or changing anything.
Write-Host "Activating winget COM server ..."
winget --info

Write-Host "Updating winget sources (downloads initial index) ..."
winget source update

Write-Host ""
Write-Host "Done. You can now run Remove-TempFiles.ps1 and sysprep the image." -ForegroundColor Green
Write-Host "VMDeploy will run 'winget source reset --force' on each new VM to ensure fresh source data."
