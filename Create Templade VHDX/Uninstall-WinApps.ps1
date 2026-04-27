# ================================
# Windows Full Debloat Script
# ================================

Write-Host "Starting debloat..." -ForegroundColor Cyan

# --- Skydda kritiska komponenter ---
$whitelist = @(
    "Microsoft.WindowsStore",              # Rekommenderas att behålla
    "Microsoft.DesktopAppInstaller",       # behövs för winget
    "Microsoft.SecHealthUI",               # Windows Security UI
    "Microsoft.UI.Xaml",
    "Microsoft.VCLibs",
    "Microsoft.NET.Native",
    "Microsoft.Windows.ShellExperienceHost",
    "Microsoft.Windows.StartMenuExperienceHost"
)

# --- 1. Ta bort Appx för alla användare ---
Write-Host "Removing Appx packages (all users)..." -ForegroundColor Yellow

Get-AppxPackage -AllUsers | ForEach-Object {
    $name = $_.Name
    if ($whitelist -notcontains $name) {
        try {
            Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop
            Write-Host "Removed: $name"
        } catch {
            Write-Host "Failed: $name" -ForegroundColor DarkGray
        }
    }
}

# --- 2. Ta bort provisioned packages (nya användare) ---
Write-Host "Removing provisioned packages..." -ForegroundColor Yellow

Get-AppxProvisionedPackage -Online | ForEach-Object {
    $name = $_.DisplayName
    if ($whitelist -notcontains $name) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop
            Write-Host "Removed provisioned: $name"
        } catch {
            Write-Host "Failed provisioned: $name" -ForegroundColor DarkGray
        }
    }
}

# --- 3. Ta bort OneDrive ---
Write-Host "Removing OneDrive..." -ForegroundColor Yellow

taskkill /f /im OneDrive.exe -ErrorAction SilentlyContinue

$oneDrive32 = "$env:SystemRoot\System32\OneDriveSetup.exe"
$oneDrive64 = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"

if (Test-Path $oneDrive64) {
    Start-Process $oneDrive64 "/uninstall" -NoNewWindow -Wait
} elseif (Test-Path $oneDrive32) {
    Start-Process $oneDrive32 "/uninstall" -NoNewWindow -Wait
}

# Rensa rester
Remove-Item "$env:USERPROFILE\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\Microsoft\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:PROGRAMDATA\Microsoft OneDrive" -Recurse -Force -ErrorAction SilentlyContinue

# --- 4. Ta bort Outlook (nya appen) ---
Write-Host "Removing Outlook (new)..." -ForegroundColor Yellow

Get-AppxPackage -AllUsers *Outlook* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

Get-AppxProvisionedPackage -Online | Where-Object {
    $_.DisplayName -like "*Outlook*"
} | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

# --- 5. (VALFRI) Ta bort Microsoft Store ---
$removeStore = $true   # ändra till $false om du vill behålla Store

if ($removeStore) {
    Write-Host "Removing Microsoft Store..." -ForegroundColor Red

    Get-AppxPackage -AllUsers Microsoft.WindowsStore | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

    Get-AppxProvisionedPackage -Online | Where-Object {
        $_.DisplayName -like "*WindowsStore*"
    } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}

# --- 6. Blockera återinstallation ---
Write-Host "Disabling consumer features..." -ForegroundColor Yellow

New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Force | Out-Null

Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
    -Name "DisableWindowsConsumerFeatures" -Value 1

# --- KLART ---
Write-Host "Debloat complete. Reboot recommended." -ForegroundColor Green