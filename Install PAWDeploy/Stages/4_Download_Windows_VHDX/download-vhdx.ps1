#Requires -Version 5.1
<#
.SYNOPSIS
    Stage 4 - Download the Windows 11 VHDX template.
.DESCRIPTION
    Selects the transfer method from $DownloadUrl:
      Azure Blob / Azure Files  --> AzCopy  (downloaded on demand)
      SMB share / local path    --> Copy-Item
      HTTP / HTTPS web server   --> BITS with Invoke-WebRequest fallback

    The file is downloaded to a temporary name, optionally verified against $VHDXSha256,
    and only then moved over the existing image, so a failed download never leaves a
    broken template behind.
#>

Import-Module "$PSScriptRoot\..\..\Settings.psm1" -Force
Start-DeployStage -Name "download-vhdx" -Title "Stage 4 - Download VHDX $VHDXVersion"

function Get-DownloadMethod {
    param([string]$Source)
    if ($Source -match '^\\\\' -or $Source -match '^[A-Za-z]:\\')                                   { return 'FileCopy' }
    if ($Source -match '\.(blob|file|dfs)\.core\.windows\.net')                                    { return 'AzCopy' }
    if ($Source -match '^https?://')                                                               { return 'BITS' }
    throw "Unsupported source '$Source'. Expected an Azure Storage URL, a UNC/SMB path or an HTTP(S) URL."
}

function Get-AzCopyPath {
    $installPath = Join-Path $DeployPath "Tools\AzCopy"
    $exe = Join-Path $installPath "azcopy.exe"
    if (Test-Path $exe) { return $exe }

    Write-Host "AzCopy not found - downloading ..."
    $zipPath     = Join-Path $env:TEMP "azcopy.zip"
    $extractPath = Join-Path $env:TEMP "azcopy_extract"
    try {
        Invoke-WebRequest -Uri "https://aka.ms/downloadazcopy-v10-windows" -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        $found = Get-ChildItem -Path $extractPath -Recurse -Filter "azcopy.exe" | Select-Object -First 1
        if (-not $found) { throw "azcopy.exe not found in the downloaded archive." }

        # Verify the binary before it is trusted and run - see docs/security/SECURITY-REVIEW.md
        # finding 4 (no integrity/signature check on the AzCopy download).
        $sig = Get-AuthenticodeSignature -FilePath $found.FullName
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
            throw "azcopy.exe failed Authenticode verification (status: $($sig.Status), signer: $($sig.SignerCertificate.Subject))."
        }

        New-Item -ItemType Directory -Path $installPath -Force | Out-Null
        Copy-Item $found.FullName -Destination $exe -Force
    }
    finally {
        Remove-Item $zipPath, $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "AzCopy installed at $exe"
    return $exe
}

$tempPath = "$VHDXDownloadPath.partial"

try {
    New-Item -ItemType Directory -Path (Split-Path $VHDXDownloadPath -Parent) -Force | Out-Null
    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue

    $method = Get-DownloadMethod -Source $DownloadUrl
    $previous = Get-DeployStamp -Name "WindowsVHDX"
    Write-Host "Source type : $method"
    Write-Host "Installed   : $(if ($previous) { $previous } else { 'none' })  ->  $VHDXVersion"

    switch ($method) {
        'AzCopy' {
            $azcopy = Get-AzCopyPath
            & $azcopy copy $DownloadUrl $tempPath --overwrite=true
            if ($LASTEXITCODE -ne 0) { throw "AzCopy exited with code $LASTEXITCODE" }
        }
        'FileCopy' {
            Copy-Item -Path $DownloadUrl -Destination $tempPath -Force -ErrorAction Stop
        }
        'BITS' {
            try {
                Start-BitsTransfer -Source $DownloadUrl -Destination $tempPath -ErrorAction Stop
            }
            catch {
                Write-Warning "BITS transfer failed ($($_.Exception.Message)) - falling back to Invoke-WebRequest ..."
                $ProgressPreference = 'SilentlyContinue'   # the progress bar makes Invoke-WebRequest very slow on large files
                Invoke-WebRequest -Uri $DownloadUrl -OutFile $tempPath -UseBasicParsing -ErrorAction Stop
            }
        }
    }

    if (-not (Test-Path $tempPath)) { throw "Download finished but $tempPath does not exist." }

    if ($VHDXSha256) {
        Write-Host "Verifying SHA256 ..."
        $hash = (Get-FileHash -Path $tempPath -Algorithm SHA256).Hash
        if ($hash -ne $VHDXSha256.Trim().ToUpperInvariant()) {
            throw "SHA256 mismatch. Expected $VHDXSha256, got $hash."
        }
        Write-Host "SHA256 verified."
    }
    else {
        Write-Warning "VHDXSha256 is not set in Settings.psm1 - the image integrity is not verified."
    }

    Move-Item -Path $tempPath -Destination $VHDXDownloadPath -Force
    Write-Host "VHDX saved to $VHDXDownloadPath"
}
catch {
    Write-Warning "Download failed: $($_.Exception.Message)"
    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
    exit (Stop-DeployStage $ExitFailure)
}

Set-DeployStamp -Name "WindowsVHDX" -Value $VHDXVersion
exit (Stop-DeployStage $ExitSuccess)
