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



#endregion

#region Pre-Installation
    ##*===============================================
    ##* PRE-INSTALLATION
    ##*===============================================
    Write-Host "========================================================"
    Write-Host "                    PRE-INSTALLATION"
    Write-Host "========================================================"
    Write-Host " "





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

        IF ((Get-ItemPropertyValue -Path $ApplicationKeyPath -Name $SourceFiles -ErrorAction SilentlyContinue) -eq $VHDXVersion) {
            Write-Host "========================================================" -ForegroundColor Green
            Write-Host "           VHDX Template already downloaded."              -ForegroundColor Green
            Write-Host "========================================================" -ForegroundColor Green
        }
        elseif (Get-ItemProperty -Path $ApplicationKeyPath -Name $SourceFiles -ErrorAction SilentlyContinue) {
            Write-Host "========================================================" -ForegroundColor Yellow
            Write-Host "           Updating Windows 11 VHDX Template."           -ForegroundColor Yellow
            Write-Host "========================================================" -ForegroundColor Yellow

            $DownloadUrl  = 'https://download.nvxo.se/vmdeploy/vhdx/Windows11.vhdx'
            $DownloadPath = "$env:ProgramData\$SoftwareName\Images\Windows11.vhdx"
            $WebClient    = New-Object Net.WebClient
            $WebClient.DownloadFile($DownloadUrl, $DownloadPath)
            Set-ItemProperty -Path $ApplicationKeyPath -Name $SourceFiles -Value $VHDXVersion -Force | Out-Null

            Write-Host "========================================================" -ForegroundColor Green
            Write-Host "           Download completed successfully."               -ForegroundColor Green
            Write-Host "========================================================" -ForegroundColor Green
        }
        ELSE {
            Write-Host "========================================================" -ForegroundColor Yellow
            Write-Host "           Downloading Windows 11 VHDX Template."            -ForegroundColor Yellow
            Write-Host "========================================================" -ForegroundColor Yellow

            $DownloadUrl  = 'https://download.nvxo.se/vmdeploy/vhdx/Windows11.vhdx'
            $DownloadPath = "$env:ProgramData\$SoftwareName\Images\Windows11.vhdx"
            $WebClient    = New-Object Net.WebClient
            $WebClient.DownloadFile($DownloadUrl, $DownloadPath)
            New-ItemProperty -Path $ApplicationKeyPath -Name $SourceFiles -Value $VHDXVersion -PropertyType String -Force | Out-Null

            Write-Host "========================================================" -ForegroundColor Green
            Write-Host "           Download completed successfully."               -ForegroundColor Green
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