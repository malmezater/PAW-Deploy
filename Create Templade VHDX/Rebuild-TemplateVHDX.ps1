#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Rebuilds a sysprepped template VHDX into a new, minimal dynamic VHDX.
.DESCRIPTION
    Optimize-VHD can only reclaim whole VHDX blocks (default 32 MB). Free space that is
    scattered across partially used blocks is never returned, so the file stays much
    larger than the data inside it.

    This script:
      1. Mounts the source VHDX read-only and captures the Windows volume to a WIM
      2. Creates a new dynamic VHDX with 1 MB blocks (GPT: EFI + MSR + Windows)
      3. Applies the WIM and writes UEFI boot files with bcdboot

    The result contains only the files, laid out contiguously. The sysprepped
    (generalized) state is preserved. The WIM is kept as a compact backup.
.EXAMPLE
    .\Rebuild-TemplateVHDX.ps1 -Source D:\VMs\Win11-Template.vhdx -Destination D:\VMs\Win11-Template-small.vhdx
#>
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Destination,
    [string]$WimPath   = ([IO.Path]::ChangeExtension($Destination, '.wim')),
    [uint64]$SizeBytes = 64GB,
    [uint32]$BlockSizeBytes = 1MB
)

$ErrorActionPreference = 'Stop'
if (Test-Path $Destination) { throw "Destination already exists: $Destination" }

function Get-FreeLetter {
    # Query live (Get-PSDrive does not refresh within the session after new mounts)
    $used = @(@((Get-Volume).DriveLetter) + @((Get-Partition).DriveLetter) +
              @((Get-CimInstance Win32_LogicalDisk).DeviceID | ForEach-Object { $_.TrimEnd(':') })) |
            Where-Object { $_ } | ForEach-Object { ([string]$_).ToUpper() }
    [char[]](70..90) | Where-Object { $used -notcontains [string]$_ } | Select-Object -First 1
}

# --- 1. Capture source Windows volume to WIM ---
Write-Host "Mounting source read-only..." -ForegroundColor Cyan
$srcDisk = Mount-VHD -Path $Source -ReadOnly -Passthru | Get-Disk
try {
    $srcPart = Get-Partition -DiskNumber $srcDisk.Number |
               Where-Object Type -eq 'Basic' | Sort-Object Size -Descending | Select-Object -First 1
    if (-not $srcPart.DriveLetter -or $srcPart.DriveLetter -eq [char]0) {
        $l = Get-FreeLetter
        Add-PartitionAccessPath -DiskNumber $srcDisk.Number -PartitionNumber $srcPart.PartitionNumber -AccessPath "$($l):\"
        $srcLetter = $l
    } else { $srcLetter = $srcPart.DriveLetter }

    if (-not (Test-Path "$($srcLetter):\Windows\System32")) { throw "No Windows installation found on $($srcLetter):" }

    if (Test-Path $WimPath) { Remove-Item $WimPath -Force }
    Write-Host "Capturing $($srcLetter):\ to $WimPath (Compress:max, takes a while)..." -ForegroundColor Cyan
    dism /Capture-Image /ImageFile:"$WimPath" /CaptureDir:"$($srcLetter):\" /Name:"Win11-Template" /Compress:max /CheckIntegrity
    if ($LASTEXITCODE -ne 0) { throw "DISM capture failed ($LASTEXITCODE)" }
}
finally {
    Dismount-VHD -Path $Source
}

# --- 2. Create new VHDX ---
Write-Host "Creating new VHDX ($([math]::Round($SizeBytes/1GB)) GB max, $($BlockSizeBytes/1MB) MB blocks)..." -ForegroundColor Cyan
New-VHD -Path $Destination -SizeBytes $SizeBytes -Dynamic -BlockSizeBytes $BlockSizeBytes | Out-Null
$disk = Mount-VHD -Path $Destination -Passthru | Get-Disk
try {
    $n = $disk.Number
    Initialize-Disk -Number $n -PartitionStyle GPT

    # EFI system partition
    $efi = New-Partition -DiskNumber $n -Size 260MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
    Format-Volume -Partition $efi -FileSystem FAT32 -NewFileSystemLabel 'System' -Confirm:$false | Out-Null
    $efiLetter = Get-FreeLetter
    Add-PartitionAccessPath -DiskNumber $n -PartitionNumber $efi.PartitionNumber -AccessPath "$($efiLetter):\"

    # MSR
    New-Partition -DiskNumber $n -Size 16MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' | Out-Null

    # Windows
    $os = New-Partition -DiskNumber $n -UseMaximumSize
    Format-Volume -Partition $os -FileSystem NTFS -NewFileSystemLabel 'Windows' -Confirm:$false | Out-Null
    $osLetter = Get-FreeLetter
    Add-PartitionAccessPath -DiskNumber $n -PartitionNumber $os.PartitionNumber -AccessPath "$($osLetter):\"

    # --- 3. Apply image + boot files ---
    # /Compact keeps CompactOS compression - without it every file is written uncompressed
    Write-Host "Applying image to $($osLetter):\ ..." -ForegroundColor Cyan
    dism /Apply-Image /ImageFile:"$WimPath" /Index:1 /ApplyDir:"$($osLetter):\" /CheckIntegrity /Compact
    if ($LASTEXITCODE -ne 0) { throw "DISM apply failed ($LASTEXITCODE)" }

    Write-Host "Writing UEFI boot files..." -ForegroundColor Cyan
    bcdboot "$($osLetter):\Windows" /s "$($efiLetter):" /f UEFI
    if ($LASTEXITCODE -ne 0) { throw "bcdboot failed ($LASTEXITCODE)" }

    Remove-PartitionAccessPath -DiskNumber $n -PartitionNumber $efi.PartitionNumber -AccessPath "$($efiLetter):\"
}
finally {
    Dismount-VHD -Path $Destination
}

# --- 4. Result ---
"{0,-12} {1,8:N1} GB" -f 'Source',      ((Get-Item $Source).Length / 1GB)
"{0,-12} {1,8:N1} GB" -f 'New VHDX',    ((Get-Item $Destination).Length / 1GB)
"{0,-12} {1,8:N1} GB" -f 'WIM backup',  ((Get-Item $WimPath).Length / 1GB)
Write-Host "Done. Test by attaching $Destination to a NEW Gen 2 VM (not the template VM)." -ForegroundColor Green
