<#

.VERSION
    1.3

.LAST UPDATED
    260413

.PURPOSE
    Template for powershell skript
    Made for Intune installation
 
.INFORMATION
    Loggname will be the name of the script
 
.EXAMPLE
    Execute with the following parameters:
    PowerShell -ExecutionPolicy ByPass -NoProfile -WindowStyle hidden -File NAMEOFSCRIPT.ps1

.UPDATE INFORMATION

#>

#----------------------------------------------------------------------------#

#region Parameter
##*===============================================
##* PARAMETER
##*===============================================

#endregion

#region Variables
##*===============================================
##* Configuration Variables
##*===============================================

$SoftwareName = "VMDeploy" <# Enter the name of the software you want to install #>

##*===============================================
##* Static VARIABLES
##*===============================================
$SourceFiles = "WindowsVHDX"
$VHDXVersion = "Win11-25H2"
$DownloadUrl = "https://malmesaterarchive.blob.core.windows.net/vmdeply-temp/VM-Temp/Win-Template.vhdx"
$DownloadPath = "$env:ProgramData\$SoftwareName\Images\Windows11.vhdx"
$DeployIT = "$env:ProgramData\DeployIT"
$DeployITLogs = "$DeployIT\logs"
$DeployITDownload = "$DeployIT\Download"
$RegistryPath = "HKLM:\SOFTWARE\DeployIT"
$RegistrySoftwareName = "$RegistryPath\$SoftwareName" -replace (" ","")
$ApplicationKeyPath = "$RegistrySoftwareName"
$Date = Get-Date -Format yyMMdd
$Global:InstallerCount = 0

#endregion

#region Start Transcript and load functions
##*==========================================================
##* START TRANSCRIPT AND LOAD FUNCTIONS
##*==========================================================

$LogPath = "$DeployITLogs\$($MyInvocation.MyCommand.Name)-$Date.log"
Start-Transcript -Path $LogPath -Force -Append

if(!(Test-Path $DeployITLogs)){
    write-host "Logpath: $DeployITLogs doesn't exist. Creating directory."
    New-Item -ItemType Directory $DeployITLogs -Force
    }
    else{
    write-host "Logpath: $DeployITLogs already exist. No need to create directory."
    }

if(!(Test-Path $DeployITDownload)){
    write-host "DownloadPath: $DeployITDownload doesn't exist. Creating directory."
    New-Item -ItemType Directory $DeployITDownload -Force
    }
    else{
    write-host "DownloadPath: $DeployITDownload already exist. No need to create directory."
    }

# if (-not (Test-Path $RegistryApplicationName)) {
#     Write-Host "Registry key $RegistryApplicationName does not exist. Creating it..."
#     New-Item -Path $RegistryApplicationName -Force
#     } 
#     else {
#     Write-Host "Registry key $RegistryApplicationName already exists."
#     }

if (-not (Test-Path $RegistrySoftwareName)) 
{
    Write-Host "Registry key $RegistrySoftwareName does not exist. Creating it..."
    New-Item -Path $RegistrySoftwareName -Force
} else {
    Write-Host "Registry key $RegistrySoftwareName already exists."
}

#endregion

#region Information
##*===============================================
##* INFORMATION
##*===============================================
Write-Host "========================================================"
Write-Host "                     INFORMATION"
Write-Host "========================================================"
Write-Host " "

Write-Host "Running File: $($MyInvocation.MyCommand.Source)"
Write-Host " "

#endregion

#region Custom Variables
    ##*===============================================
    ##* CUSTOM VARIABLES
    ##*===============================================



#endregion

#region Custom Functions
    ##*===============================================
    ##* CUSTOM FUNCTIONS
    ##*===============================================

<# 
Download file with AzCopy if available, otherwise fallback to Invoke-WebRequest
#>
function Download-WithAzCopy {
    param (
        [Parameter(Mandatory=$true)]
        [string]$SourceUrl,

        [Parameter(Mandatory=$true)]
        [string]$DestinationPath
    )

    $azcopy = Get-AzCopyIfNeeded

    Write-Host "Starting download with AzCopy..."

    & $azcopy copy $SourceUrl $DestinationPath --overwrite=true

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Download completed successfully"
    } else {
        Write-Error "AzCopy failed with exit code $LASTEXITCODE"
    }
}
<#
Install AzCopy if not already installed and return the path to the executable
#>
function Get-AzCopyIfNeeded {
    param (
        [string]$InstallPath = "$env:LOCALAPPDATA\AzCopy"
    )

    $azcopyExe = Join-Path $InstallPath "azcopy.exe"

    if (Test-Path $azcopyExe) {
        return $azcopyExe
    }

    Write-Host "AzCopy not found. Downloading..."

    $zipUrl = "https://aka.ms/downloadazcopy-v10-windows"
    $zipPath = Join-Path $env:TEMP "azcopy.zip"
    $extractPath = Join-Path $env:TEMP "azcopy_extract"

    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    # Find azcopy.exe in extracted folder
    $exe = Get-ChildItem -Path $extractPath -Recurse -Filter "azcopy.exe" | Select-Object -First 1

    if (-not $exe) {
        throw "Failed to locate azcopy.exe after extraction"
    }

    # Create install dir
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null

    Copy-Item $exe.FullName -Destination $azcopyExe -Force

    Write-Host "AzCopy installed at $azcopyExe"

    return $azcopyExe
}

#endregion

#region Pre-Installation
    ##*===============================================
    ##* PRE-INSTALLATION
    ##*===============================================
    Write-Host "========================================================"
    Write-Host "                    PRE-INSTALLATION"
    Write-Host "========================================================"
    Write-Host " "

    Get-AzCopyIfNeeded

    Write-Host " "
#endregion

#region Download VHDX
    ##*===============================================
    ##* DOWNLOAD VHDX
    ##*===============================================
    Write-Host "========================================================"           -ForegroundColor Yellow
    Write-Host "            This Download may take a while"                         -ForegroundColor Yellow
    Write-Host "========================================================"           -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Yellow
    Write-Host "           Download size is approximately 20GB"            -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Yellow

    try
    {
        if(!(test-path "$env:ProgramData\$SoftwareName\Images"))
        {
            New-Item "$env:ProgramData\$SoftwareName\Images" -ItemType Directory -Force
        }

        IF (!(Get-ItemPropertyValue -Path $ApplicationKeyPath -Name $SourceFiles -ErrorAction SilentlyContinue) -eq $VHDXVersion) {
            Write-Host "========================================================" -ForegroundColor Yellow
            Write-Host "           Downloading Windows 11 VHDX Template."            -ForegroundColor Yellow
            Write-Host "========================================================" -ForegroundColor Yellow

            Download-WithAzCopy `
                -SourceUrl $DownloadUrl `
                -DestinationPath $DownloadPath
            New-ItemProperty -Path $ApplicationKeyPath -Name $SourceFiles -Value $VHDXVersion -PropertyType String -Force | Out-Null

            Write-Host "========================================================" -ForegroundColor Green
            Write-Host "           Download completed successfully."               -ForegroundColor Green
            Write-Host "========================================================" -ForegroundColor Green
        }
        elseif ((Get-ItemPropertyValue -Path $ApplicationKeyPath -Name $SourceFiles -ErrorAction SilentlyContinue) -ne $VHDXVersion) {
            Write-Host "========================================================" -ForegroundColor Yellow
            Write-Host "           Updating Windows 11 VHDX Template."           -ForegroundColor Yellow
            Write-Host "========================================================" -ForegroundColor Yellow

            Download-WithAzCopy `
                -SourceUrl $DownloadUrl `
                -DestinationPath $DownloadPath
            Set-ItemProperty -Path $ApplicationKeyPath -Name $SourceFiles -Value $VHDXVersion -Force | Out-Null

            Write-Host "========================================================" -ForegroundColor Green
            Write-Host "           Download completed successfully."               -ForegroundColor Green
            Write-Host "========================================================" -ForegroundColor Green
        }
        ELSE {
            Write-Host "========================================================" -ForegroundColor Green
            Write-Host "           VHDX Template already downloaded."              -ForegroundColor Green
            Write-Host "========================================================" -ForegroundColor Green

        }
    }
    catch
    {
        Exit 1
    }        

    Write-Host " "
#endregion

#region Post-Installation
		##*===============================================
		##* POST-INSTALLATION
		##*===============================================
        Write-Host "========================================================"
        Write-Host "                   POST-INSTALLATION"
        Write-Host "========================================================"
        Write-Host " "
        


        Write-Host " "
#endregion

#region Check Installation
		##*===============================================
		##* CHECK INSTALLATION
		##*===============================================        
        Write-Host "========================================================"
        Write-Host "                   CHECK INSTALLATION"
        Write-Host "========================================================"
        Write-Host " "

        IF ((Get-ItemPropertyValue -Path $ApplicationKeyPath -Name $SourceFiles -ErrorAction SilentlyContinue) -eq $VHDXVersion) {
            Write-Host -Message "Installation finished successfully" -Level SUCCEEDED
            Write-Host "========================================================"
            Stop-Transcript
            Exit 0
        }
        else {
            Write-Host -Message "Download finished unsuccessfully" -Level WARNING
            Write-Host "========================================================"
            Stop-Transcript
            Exit 1
        }
#endregion