
#Requires -Version 5.1
<#
.SYNOPSIS
    Stage 4 - Download the Windows 11 VHDX template.
.DESCRIPTION
    Selects the download method automatically based on the configured source URL/path:
      Azure Blob / Azure Files  --> AzCopy  (auto-installed if missing)
      SMB share  (\\server\...) --> Copy-Item
      HTTP / HTTPS web server   --> BITS with Invoke-WebRequest fallback
#>

# -------  Bootstrap: load shared settings  -------
Import-Module "$PSScriptRoot\..\Settings.psm1" -Force

$SourceFiles = "WindowsVHDX"
$Date        = Get-Date -Format yyMMdd
$LogPath     = "$DeployITLogs\download-vhdx-$Date.log"
Start-Transcript -Path $LogPath -Force -Append

Initialize-DeployEnvironment

Write-Host "========================================================"
Write-Host "                   Download VHDX"
Write-Host "========================================================"

# -------  Download helpers  -------

function Get-DownloadMethod {
    param([string]$Source)

    if ($Source -match '^\\\\' -or $Source -match '^[A-Za-z]:\\') {
        return 'FileCopy'
    }
    elseif ($Source -match '\.blob\.core\.windows\.net|\.file\.core\.windows\.net|\.dfs\.core\.windows\.net') {
        return 'AzCopy'
    }
    elseif ($Source -match '^https?://') {
        return 'BITS'
    }
    else {
        throw "Unsupported source: '$Source'. Expected an Azure Storage URL, a UNC/SMB path, or an HTTP(S) URL."
    }
}

function Get-AzCopyPath {
    param ([string]$InstallPath = "$env:LOCALAPPDATA\AzCopy")

    $exe = Join-Path $InstallPath "azcopy.exe"
    if (Test-Path $exe) { return $exe }

    Write-Host "AzCopy not found - downloading ..."
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

function Invoke-VHDXDownload {
    param(
        [string]$SourceUrl,
        [string]$DestinationPath
    )

    $method = Get-DownloadMethod -Source $SourceUrl
    Write-Host "Source type detected : $method"

    switch ($method) {
        'AzCopy' {
            $azcopy = Get-AzCopyPath
            Write-Host "Starting AzCopy download ..."
            & $azcopy copy $SourceUrl $DestinationPath --overwrite=true
            if ($LASTEXITCODE -ne 0) { throw "AzCopy exited with code $LASTEXITCODE" }
        }
        'FileCopy' {
            Write-Host "Copying from SMB / file share ..."
            Copy-Item -Path $SourceUrl -Destination $DestinationPath -Force
        }
        'BITS' {
            Write-Host "Starting BITS download ..."
            try {
                Start-BitsTransfer -Source $SourceUrl -Destination $DestinationPath -ErrorAction Stop
            }
            catch {
                Write-Warning "BITS transfer failed ($($_.Exception.Message)) - falling back to Invoke-WebRequest ..."
                Invoke-WebRequest -Uri $SourceUrl -OutFile $DestinationPath
            }
        }
    }

    Write-Host "Download completed successfully."
}

# -------  Ensure destination folder exists  -------

$imageDir = Split-Path $VHDXDownloadPath -Parent
if (-not (Test-Path $imageDir)) {
    New-Item -ItemType Directory -Path $imageDir -Force | Out-Null
}

# -------  Pre-flight check  -------

$downloadMethod = Get-DownloadMethod -Source $DownloadUrl
Write-Host "Configured download method: $downloadMethod"

if ($downloadMethod -eq 'AzCopy') {
    try { Get-AzCopyPath | Out-Null }
    catch {
        Write-Warning "Could not obtain AzCopy: $_"
        Stop-Transcript
        exit 1
    }
}

# -------  Download logic  -------

$installedVHDX = Get-ItemPropertyValue -Path $ApplicationKeyPath -Name $SourceFiles -ErrorAction SilentlyContinue

try {
    if ($null -eq $installedVHDX) {
        Write-Host "No VHDX stamp found - downloading fresh copy."
        Invoke-VHDXDownload -SourceUrl $DownloadUrl -DestinationPath $VHDXDownloadPath
        New-ItemProperty -Path $ApplicationKeyPath -Name $SourceFiles -Value $VHDXVersion -PropertyType String -Force | Out-Null
    } else {
        Write-Host "VHDX version mismatch ($installedVHDX → $VHDXVersion) - re-downloading."
        Invoke-VHDXDownload -SourceUrl $DownloadUrl -DestinationPath $VHDXDownloadPath
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
