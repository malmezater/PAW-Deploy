
#Requires -Version 5.1
<#
.SYNOPSIS
    Stage 4 — Download the Windows 11 VHDX template via AzCopy.
.NOTES
    AzCopy is auto-installed to %LOCALAPPDATA%\AzCopy if not present.
    Falls back gracefully if AzCopy cannot be installed.
#>

# -------  Bootstrap: load shared settings  -------
Import-Module "$PSScriptRoot\..\..\Settings.psm1" -Force

$SourceFiles = "WindowsVHDX"
$Date        = Get-Date -Format yyMMdd
$LogPath     = "$DeployITLogs\download-vhdx-$Date.log"
Start-Transcript -Path $LogPath -Force -Append

Initialize-DeployEnvironment

Write-Host "========================================================"
Write-Host "                   Download VHDX"
Write-Host "========================================================"

# -------  AzCopy helpers  -------

function Get-AzCopyPath {
    param ([string]$InstallPath = "$env:LOCALAPPDATA\AzCopy")

    $exe = Join-Path $InstallPath "azcopy.exe"
    if (Test-Path $exe) { return $exe }

    Write-Host "AzCopy not found — downloading ..."
    $zipPath     = Join-Path $env:TEMP "azcopy.zip"
    $extractPath = Join-Path $env:TEMP "azcopy_extract"

    Invoke-WebRequest -Uri "https://aka.ms/downloadazcopy-v10-windows" -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    $found = Get-ChildItem -Path $extractPath -Recurse -Filter "azcopy.exe" | Select-Object -First 1
    if (-not $found) { throw "azcopy.exe not found after extraction." }

    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Copy-Item $found.FullName -Destination $exe -Force
    Write-Host "AzCopy installed at $exe"
    return $exe
}

function Invoke-AzCopyDownload {
    param(
        [string]$SourceUrl,
        [string]$DestinationPath
    )
    $azcopy = Get-AzCopyPath
    Write-Host "Starting AzCopy download ..."
    & $azcopy copy $SourceUrl $DestinationPath --overwrite=true
    if ($LASTEXITCODE -ne 0) {
        throw "AzCopy exited with code $LASTEXITCODE"
    }
    Write-Host "Download completed successfully."
}

# -------  Ensure destination folder exists  -------

$imageDir = Split-Path $VHDXDownloadPath -Parent
if (-not (Test-Path $imageDir)) {
    New-Item -ItemType Directory -Path $imageDir -Force | Out-Null
}

# -------  Pre-flight AzCopy check  -------

try { Get-AzCopyPath | Out-Null }
catch {
    Write-Warning "Could not obtain AzCopy: $_"
    Stop-Transcript
    exit 1
}

# -------  Download logic  -------

$installedVHDX = Get-ItemPropertyValue -Path $ApplicationKeyPath -Name $SourceFiles -ErrorAction SilentlyContinue

try {
    if ($null -eq $installedVHDX) {
        Write-Host "No VHDX stamp found — downloading fresh copy."
        Invoke-AzCopyDownload -SourceUrl $DownloadUrl -DestinationPath $VHDXDownloadPath
        New-ItemProperty -Path $ApplicationKeyPath -Name $SourceFiles -Value $VHDXVersion -PropertyType String -Force | Out-Null
    } else {
        Write-Host "VHDX version mismatch ($installedVHDX → $VHDXVersion) — re-downloading."
        Invoke-AzCopyDownload -SourceUrl $DownloadUrl -DestinationPath $VHDXDownloadPath
        Set-ItemProperty -Path $ApplicationKeyPath -Name $SourceFiles -Value $VHDXVersion -Force | Out-Null
    }
} catch {
    Write-Error "Download failed: $_"
    Stop-Transcript
    exit 1
}

# -------  Verify  -------

$stamp = Get-ItemPropertyValue -Path $ApplicationKeyPath -Name $SourceFiles -ErrorAction SilentlyContinue
if ($stamp -eq $VHDXVersion) {
    Write-Host "VHDX download verified successfully."
    Stop-Transcript
    exit 0
} else {
    Write-Error "VHDX version stamp missing or incorrect after download."
    Stop-Transcript
    exit 1
}
