#Requires -RunAsAdministrator
# ================================
# Optimize-Template.ps1 - shrink the Win11 template before sysprep
# Run in Windows PowerShell 5.1, AFTER Windows Update and debloat.
# Step 5 in README - then run Invoke-SysprepPrep.ps1.
# ================================

if ($PSVersionTable.PSVersion.Major -ne 5) { Write-Host "Run in Windows PowerShell 5.1" -ForegroundColor Red; return }

$removeWinRE     = $false   # $true = disables WinRE (remove the partition on the host separately)

function Show-Used { $v = Get-Volume C; "{0:N1} GB used" -f (($v.Size - $v.SizeRemaining)/1GB) }
Write-Host "Before: $(Show-Used)" -ForegroundColor Cyan

# --- 1. Features on Demand not needed in a VM ---
$capPatterns = @(
    'App.StepsRecorder*', 'Browser.InternetExplorer*', 'Hello.Face*',
    'Language.Handwriting*', 'Language.OCR*', 'Language.Speech*', 'Language.TextToSpeech*',
    'MathRecognizer*', 'Media.WindowsMediaPlayer*', 'Microsoft.Windows.WordPad*',
    'Microsoft.Windows.PowerShell.ISE*', 'Print.Fax.Scan*', 'OneCoreUAP.OneSync*',
    'Microsoft.Wallpapers.Extended*', 'Microsoft.Windows.Wifi.Client*', 'VBSCRIPT*'
)
Write-Host "Removing capabilities..." -ForegroundColor Yellow
Get-WindowsCapability -Online | Where-Object State -eq Installed | ForEach-Object {
    $c = $_
    if ($capPatterns | Where-Object { $c.Name -like $_ }) {
        try { Remove-WindowsCapability -Online -Name $c.Name -ErrorAction Stop | Out-Null; Write-Host "Removed: $($c.Name)" }
        catch { Write-Host "Failed: $($c.Name)" -ForegroundColor DarkGray }
    }
}

# --- 2. Optional features - disable AND remove payload from WinSxS ---
$features = @('WorkFolders-Client','Printing-XPSServices-Features','MediaPlayback',
              'WindowsMediaPlayer','Recall','SMB1Protocol','MicrosoftWindowsPowerShellV2Root')
Write-Host "Removing optional features..." -ForegroundColor Yellow
foreach ($f in $features) {
    $o = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
    if ($o -and $o.State -ne 'DisabledWithPayloadRemoved') {
        Disable-WindowsOptionalFeature -Online -FeatureName $f -Remove -NoRestart -ErrorAction SilentlyContinue | Out-Null
        Write-Host "Removed feature: $f"
    }
}

# --- 3. Reserved storage, hibernation ---
# (pagefile.sys/swapfile.sys are deleted offline by Remove-TempFiles.ps1 - Windows recreates them at boot)
Write-Host "Disabling reserved storage / hibernation..." -ForegroundColor Yellow
DISM /Online /Set-ReservedStorageState /State:Disabled | Out-Null
powercfg /h off
if ($removeWinRE) { reagentc /disable }

# --- 4. Component store (takes 10-30 min) ---
Write-Host "Cleaning component store (WinSxS)..." -ForegroundColor Yellow
DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase

# --- 5. Caches, logs, temp ---
Write-Host "Clearing caches and logs..." -ForegroundColor Yellow
Stop-Service wuauserv, bits, dosvc -Force -ErrorAction SilentlyContinue
Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue
$paths = @(
    "C:\Windows\SoftwareDistribution\Download\*",
    "C:\Windows\Temp\*", "$env:TEMP\*",
    "C:\Windows\Logs\CBS\*", "C:\Windows\Logs\DISM\*",
    "C:\ProgramData\Microsoft\Windows\WER\*",
    "C:\Windows\Prefetch\*", "C:\Windows\LiveKernelReports\*",
    "C:\Windows\Downloaded Program Files\*", "C:\temp\*"
)
foreach ($p in $paths) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
Get-ChildItem C:\Users -Directory | ForEach-Object {
    Remove-Item "$($_.FullName)\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
}
wevtutil el | ForEach-Object { wevtutil cl "$_" 2>$null }

# --- 6. Sysprep safety: the winget source must not exist per user ---
Get-AppxPackage -AllUsers Microsoft.Winget.Source* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

# --- 7. Compress OS files ---
Write-Host "Compacting OS (CompactOS)..." -ForegroundColor Yellow
compact.exe /CompactOS:always | Out-Null

# --- 8. TRIM so Hyper-V can release blocks in the VHDX ---
Optimize-Volume -DriveLetter C -ReTrim

Write-Host "After: $(Show-Used)" -ForegroundColor Green
Write-Host "REBOOT NOW (feature/capability removal leaves pending operations), then run Invoke-SysprepPrep.ps1. Do NOT run winget in between." -ForegroundColor Green

<#
  ON THE HOST after sysprep (VM shut down) - Full requires a read-only mount:
    Mount-VHD  -Path D:\VMs\Win11-Template.vhdx -ReadOnly
    Optimize-VHD -Path D:\VMs\Win11-Template.vhdx -Mode Full
    Dismount-VHD -Path D:\VMs\Win11-Template.vhdx
#>
