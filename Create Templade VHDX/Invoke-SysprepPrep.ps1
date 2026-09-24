#Requires -Version 5.1
<#
.SYNOPSIS
    Pre-sysprep cleanup and generalisation. Run this as the very last step before sysprep.
.DESCRIPTION
    The Microsoft.Winget.Source package is a per-user source index cache created the
    first time winget updates its sources. Because it is created after system provisioning
    it exists only for the current user and is NOT provisioned for all users. Sysprep
    refuses to generalise an image that contains such packages.

    This script:
      1. Removes all per-user Microsoft.Winget.Source packages (for all users).
      2. Disables all network adapters so no background task can re-trigger a source
         update between this cleanup and the sysprep shutdown.
      3. Runs sysprep /generalize /oobe /shutdown.

.NOTES
    Run as Administrator inside the VHDX template.
    Run AFTER Remove-TempFiles.ps1 and as the very last action before the VM shuts down.
    Do NOT run winget between this script and sysprep.
#>

# -------  1. Remove Microsoft.Winget.Source per-user cache  -------

Write-Host "=== Removing Microsoft.Winget.Source packages ===" -ForegroundColor Cyan

$sourcePkgs = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like 'Microsoft.Winget.Source*' }

if ($sourcePkgs) {
    foreach ($pkg in $sourcePkgs) {
        Write-Host "  Removing: $($pkg.PackageFullName) (user: $($pkg.PackageUserInformation.UserSecurityId))"
        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }
    Write-Host "Microsoft.Winget.Source packages removed." -ForegroundColor Green
} else {
    Write-Host "No Microsoft.Winget.Source packages found - nothing to remove." -ForegroundColor Green
}

# -------  1b. Remove leftover defaultuser0  -------
# Pressing CTRL+Shift+F3 in OOBE leaves the temporary OOBE account 'defaultuser0' behind.
# If it stays in the image it shows up on every deployed VM's logon screen and gets in the
# way of the Administrator autologon.

Write-Host ""
Write-Host "=== Removing leftover defaultuser0 ===" -ForegroundColor Cyan
if (Get-LocalUser -Name 'defaultuser0' -ErrorAction SilentlyContinue) {
    Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPath -like '*\defaultuser0*' } |
        Remove-CimInstance -ErrorAction SilentlyContinue
    Remove-LocalUser -Name 'defaultuser0' -ErrorAction SilentlyContinue
    Write-Host "defaultuser0 removed." -ForegroundColor Green
} else {
    Write-Host "No defaultuser0 account found." -ForegroundColor Green
}

# -------  2. Disconnect network  -------

Write-Host ""
Write-Host "=== Disabling network adapters ===" -ForegroundColor Cyan

Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
    Write-Host "  Disabling: $($_.Name)"
    Disable-NetAdapter -Name $_.Name -Confirm:$false -ErrorAction SilentlyContinue
}

Write-Host "Network adapters disabled." -ForegroundColor Green

# -------  3. Sysprep  -------

Write-Host ""
Write-Host "=== Starting sysprep ===" -ForegroundColor Cyan
Write-Host "The machine will shut down when sysprep completes."

Start-Process -FilePath 'C:\Windows\System32\Sysprep\sysprep.exe' `
    -ArgumentList '/generalize /oobe /shutdown /quiet' -Wait
