#Requires -RunAsAdministrator
# ================================
# Windows Full Debloat Script (template/sysprep-safe)
# Run in Windows PowerShell 5.1 (the Appx module is unreliable in PS7)
# ================================

if ($PSVersionTable.PSVersion.Major -ne 5) {
    Write-Host "Run this script in Windows PowerShell 5.1 (powershell.exe), not pwsh." -ForegroundColor Red
    return
}

Write-Host "Starting debloat..." -ForegroundColor Cyan

$removeStore = $true   # $false = keep Microsoft Store (winget works without the Store)

# --- Packages to keep (wildcards allowed) ---
$keep = @(
    # winget and its dependencies
    "Microsoft.DesktopAppInstaller",
    "Microsoft.WindowsAppRuntime*",        # newer winget requires Windows App Runtime
    "Microsoft.UI.Xaml*",
    "Microsoft.VCLibs*",
    "Microsoft.NET.Native*",
    "Microsoft.Services.Store.Engagement",

    # Security, language, sign-in
    "Microsoft.SecHealthUI",
    "Microsoft.LanguageExperiencePack*",   # removing it drops the display language (e.g. Swedish UI)
    "Microsoft.AAD.BrokerPlugin",          # Entra ID / WAM-inloggning
    "Microsoft.AccountsControl",

    # Apps to keep
    "Microsoft.WindowsNotepad",
    "Microsoft.WindowsTerminal",
    "Microsoft.Windows.Photos"
    # "Microsoft.WindowsCalculator",
    # "Microsoft.ScreenSketch",            # Snipping Tool
    # "MicrosoftCorporationII.QuickAssist" # remote support
)
if (-not $removeStore) { $keep += "Microsoft.WindowsStore", "Microsoft.StorePurchaseApp" }

function Test-Keep([string]$Name) {
    foreach ($k in $keep) { if ($Name -like $k) { return $true } }
    return $false
}

# --- 1. Provisioned packages first (otherwise sysprep may fail) ---
Write-Host "Removing provisioned packages..." -ForegroundColor Yellow
Get-AppxProvisionedPackage -Online | Where-Object { -not (Test-Keep $_.DisplayName) } | ForEach-Object {
    try {
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop | Out-Null
        Write-Host "Removed provisioned: $($_.DisplayName)"
    } catch {
        Write-Host "Failed provisioned: $($_.DisplayName)" -ForegroundColor DarkGray
    }
}

# --- 2. Installed packages, all users ---
# Skips system apps, frameworks and non-removable packages (shell, Start, search, OOBE etc.)
Write-Host "Removing Appx packages (all users)..." -ForegroundColor Yellow
Get-AppxPackage -AllUsers | Where-Object {
    -not $_.NonRemovable -and
    -not $_.IsFramework -and
    $_.SignatureKind -ne 'System' -and
    -not (Test-Keep $_.Name)
} | ForEach-Object {
    try {
        Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop
        Write-Host "Removed: $($_.Name)"
    } catch {
        Write-Host "Failed: $($_.Name)" -ForegroundColor DarkGray
    }
}

# --- 3. OneDrive: uninstall + remove from the Default profile ---
Write-Host "Removing OneDrive..." -ForegroundColor Yellow
Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force
foreach ($p in "$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") {
    if (Test-Path $p) { Start-Process $p -ArgumentList "/uninstall" -Wait }
}
# New users (after sysprep) should not get OneDriveSetup at first logon
reg load HKU\DefaultUser "C:\Users\Default\NTUSER.DAT" | Out-Null
reg delete "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Run" /v OneDriveSetup /f 2>$null | Out-Null
[gc]::Collect()
reg unload HKU\DefaultUser | Out-Null
Get-ScheduledTask -TaskName "OneDrive*" -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null

# --- 4. Block reinstall of consumer apps (Enterprise/Education only) ---
Write-Host "Disabling consumer features..." -ForegroundColor Yellow
$cc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
New-Item -Path $cc -Force | Out-Null
Set-ItemProperty -Path $cc -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord
Set-ItemProperty -Path $cc -Name "DisableCloudOptimizedContent" -Value 1 -Type DWord

# --- 5. Check: is App Installer (winget) still present? ---
# NOTE: do not run winget here - it installs Microsoft.Winget.Source per user and makes sysprep fail
if (Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq "Microsoft.DesktopAppInstaller") {
    Write-Host "App Installer (winget) is present." -ForegroundColor Green
} else {
    Write-Host "App Installer is missing - install winget offline before sysprep." -ForegroundColor Red
}

# --- 6. Sysprep prep: packages installed per user only ---
# Microsoft.Winget.Source is added per user when winget runs; it is re-downloaded automatically
Get-AppxPackage -AllUsers Microsoft.Winget.Source* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
$prov = (Get-AppxProvisionedPackage -Online).DisplayName
$orphans = Get-AppxPackage -AllUsers | Where-Object {
    -not $_.NonRemovable -and -not $_.IsFramework -and
    $_.SignatureKind -ne 'System' -and $_.Name -notin $prov
}
if ($orphans) {
    Write-Host "These packages are not provisioned and may block sysprep:" -ForegroundColor Red
    $orphans | Select-Object Name, PackageFullName | Format-Table -AutoSize
}

Write-Host "Debloat complete. Reboot recommended." -ForegroundColor Green
