#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Offline cleanup of the sysprepped template VHDX (mounted read/write on the host).
.EXAMPLE
    .\Remove-TempFiles.ps1 -Drive E:
#>
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z]:$')][string]$Drive
)

if (-not (Test-Path "$Drive\Windows\System32")) { Write-Host "$Drive does not look like a Windows volume." -ForegroundColor Red; return }

Write-Host "Starting cleanup on $Drive..." -ForegroundColor Cyan
function Clear-Path([string]$Path) { Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue }

# Page/swap/hibernation files - Windows recreates them at first boot
foreach ($f in 'pagefile.sys','swapfile.sys','hiberfil.sys') {
    if (Test-Path "$Drive\$f") { Remove-Item "$Drive\$f" -Force -ErrorAction SilentlyContinue; Write-Host "Removed $f" }
}

# Windows Update / Delivery Optimization (offline - does not touch host services)
Clear-Path "$Drive\Windows\SoftwareDistribution\Download\*"
Clear-Path "$Drive\Windows\SoftwareDistribution\DeliveryOptimization\*"
Clear-Path "$Drive\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache\*"
Clear-Path "$Drive\`$WinREAgent"

# Temp
Clear-Path "$Drive\Windows\Temp\*"
Get-ChildItem "$Drive\Users" -Directory -Force | ForEach-Object {
    Clear-Path "$($_.FullName)\AppData\Local\Temp\*"
    Clear-Path "$($_.FullName)\AppData\Local\Microsoft\Windows\INetCache\*"
}

# Prefetch, logs, error reports
Clear-Path "$Drive\Windows\Prefetch\*"
Clear-Path "$Drive\Windows\Logs\*"
Clear-Path "$Drive\Windows\System32\winevt\Logs\*"
Clear-Path "$Drive\ProgramData\Microsoft\Windows\WER\*"
Clear-Path "$Drive\Windows\LiveKernelReports\*"
Clear-Path "$Drive\Windows\Minidump\*"

# Recycle Bin
Get-ChildItem "$Drive\`$Recycle.Bin" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Running offline DISM component cleanup..." -ForegroundColor Cyan
DISM /Image:$Drive\ /Cleanup-Image /StartComponentCleanup /ResetBase

Write-Host "All done! Next: defrag, Dismount-VHD, then Mount-VHD -ReadOnly + Optimize-VHD -Mode Full." -ForegroundColor Green
