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
$ScriptVersion = "2.0.1"
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

#region Step 1
		##*===============================================
		##* INSTALLATION of HyperV Feature
		##*===============================================
        Write-Host "========================================================"
        Write-Host "                 Install HyperV Feature"
        Write-Host "========================================================"
        Write-Host " "

        IF (Get-ItemProperty -Path $RegistrySoftwareName -Name "Microsoft-Hyper-V-All" -ErrorAction SilentlyContinue) {
            Write-Host -Message "HyperV Feature is already installed." -Level SUCCEEDED
            $HyperVInstalled = $true
        }
        else {
            Powershell.exe -executionpolicy bypass -File "$PSScriptRoot\1_Install-Features_for_PAW\Install-Features_for_PAW.ps1"
        }

        Write-Host " "
#endregion

#region Step 2
		##*===============================================
		##* Install VMDeploy Configuration
		##*===============================================
        Write-Host "========================================================"
        Write-Host "             Configure VM Deploy Network"
        Write-Host "========================================================"
        Write-Host " "

        IF ($HyperVInstalled -eq $true) {
            Write-Host -Message "HyperV Feature is already installed. Setting network configuration." -Level SUCCEEDED
            Powershell.exe -executionpolicy bypass -File "$PSScriptRoot\2_Install_VMDeploy-configuration\Configure-PAWNetwork.ps1"
            $PAWNetworkConfigured = $true
        }
        else {
            Write-Host -Message "HyperV Feature is not installed. Cannot set network configuration." -Level WARNING
            Exit
        }

        Write-Host " "

        Write-Host "========================================================"
        Write-Host "            Set Firewall Rules for VM Deploy"
        Write-Host "========================================================"
        Write-Host " "

        IF ($PAWNetworkConfigured -eq $true) {
            Write-Host -Message "PAW Network is configured. Setting firewall rules." -Level SUCCEEDED
            Powershell.exe -executionpolicy bypass -File "$PSScriptRoot\2_Install_VMDeploy-configuration\Set-FirewallRules.ps1"
            $FirewallRulesSet = $true
        }
        else {
            Write-Host -Message "PAW Network is not configured. Cannot set firewall rules." -Level WARNING
            Exit
        }

        Write-Host " "

        Write-Host "========================================================"
        Write-Host "                  Add HyperV User"
        Write-Host "========================================================"
        Write-Host " "

        IF ($FirewallRulesSet -eq $true) {
            Write-Host -Message "Firewall rules are set. Adding HyperV user." -Level SUCCEEDED
            Powershell.exe -executionpolicy bypass -File "$PSScriptRoot\2_Install_VMDeploy-configuration\Add-HyperVAdmin.ps1"
        }
        else {
            Write-Host -Message "Firewall rules are not set. Cannot add HyperV user." -Level WARNING
            Exit
        }

        Write-Host " "

#endregion

#region Step 3
		##*===============================================
		##* INSTALLATION
		##*===============================================
        Write-Host "========================================================"
        Write-Host "                Install VM Deploy"
        Write-Host "========================================================"
        Write-Host " "

        IF (Get-LocalUser "Hypervuser" -ErrorAction SilentlyContinue) {
            Write-Host -Message "HyperV user already exists. Proceeding with VM Deploy installation." -Level SUCCEEDED
            New-ItemProperty -Path $ApplicationKeyPath -Name "VMDeployVersion" -Value "Uninstalled" -PropertyType String -Force | Out-Null
            IF (!(Get-ItemPropertyValue -Path $ApplicationKeyPath -Name "VMDeployVersion" -ErrorAction SilentlyContinue) -eq $ScriptVersion){
                Powershell.exe -executionpolicy bypass -File "$PSScriptRoot\3_Install_VMDeploy\Install-VMDeploy.ps1"
            }
        }
        else {
            Write-Host -Message "HyperV user does not exist. Cannot proceed with VM Deploy installation." -Level WARNING
            Exit
        }

        Write-Host " "
#endregion

#region Step 4
		##*===============================================
		##* Download
		##*===============================================
        Write-Host "========================================================"
        Write-Host "                Download VHDX"
        Write-Host "========================================================"
        Write-Host " "

        IF (Get-Item -Path $Env:Programdata\VMDeploy\Images -ErrorAction SilentlyContinue) {
            Write-Host -Message "Downloading Windows 11 VHDX Template to VMDeploy Image folder." -Level SUCCEEDED
            Powershell.exe -executionpolicy bypass -File "$PSScriptRoot\4_Download_Windows_VHDX\download-vhdx.ps1"
        }
        else {
            Write-Host -Message "Image folder is missing, creating Image folder and ask user to download VHDX" -Level WARNING
            New-Item -Path "$Env:Programdata\VMDeploy" -Name "Images" -ItemType Directory -ErrorAction SilentlyContinue -Confirm:$true
            Powershell.exe -executionpolicy bypass -File "$PSScriptRoot\4_Download_Windows_VHDX\download-vhdx.ps1"
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
        
        IF (Get-Item -Path "$env:ProgramData\VMDeploy\") {
            Write-Host -Message "VM Deploy installation directory exists. Post-installation checks passed." -Level SUCCEEDED
            $CheckInstallItem = "$env:ProgramData\VMDeploy"
        }
        else {
            Write-Host -Message "VM Deploy installation directory does not exist. Post-installation checks failed." -Level WARNING
            Exit
        }

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

        if (Get-Item -path $CheckInstallItem) {
            Write-Host -Message "Installation finished successfully" -Level SUCCEEDED
            Write-Host "========================================================"

            try {
                Set-ItemProperty -Path $ApplicationKeyPath -Name "(Default)" -Value "True" -Force | Out-Null
                Write-Host "Registry value for $SoftwareName created/updated successfully."
            } catch {
                Write-Error "Failed to create/update registry value for $SoftwareName."
            }
            
        Write-Host "========================================================"
        Stop-Transcript
        Exit 0
    }
    else {
        Write-Host -Message "Installation finished unsuccessfully" -Level WARNING
        Write-Host "========================================================"
        Stop-Transcript
        Exit 1
    }

#endregion