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

#region Installation
		##*===============================================
		##* INSTALLATION
		##*===============================================
        Write-Host "========================================================"
        Write-Host "                     INSTALLATION"
        Write-Host "========================================================"
        Write-Host " "

        Start-BitsTransfer -Source "https://download.nvxo.se/vmdeploy/vhdx/windows11.vhdx" -Destination "$env:ProgramData\$SoftwareName\Windows11.vhdx"

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

        if (Get-Item -path "$env:ProgramData\$SoftwareName\Windows11.vhdx") {
            Write-Host -Message "Installation finished successfully" -Level SUCCEEDED
            Write-Host "========================================================"

        try {
            New-ItemProperty -Path $ApplicationKeyPath -Name $SourceFiles -Value "Win1122H2" -PropertyType String -Force | Out-Null
            Write-Host "Registry value for $SourceFiles created/updated successfully."
        } catch {
            Write-Error "Failed to create/update registry value for $SourceFiles."
        }
            
        Write-Host "========================================================"
        Stop-Transcript
    }
    else {
        Write-Host -Message "Installation finished unsuccessfully" -Level WARNING
        Write-Host "========================================================"
        Stop-Transcript
    }

#endregion