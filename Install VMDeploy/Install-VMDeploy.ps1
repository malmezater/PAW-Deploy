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

$SoftwareName = "PAWDeploy" <# Enter the name of the software you want to install #>

##*===============================================
##* Static VARIABLES
##*===============================================

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
Start-Transcript -Path $LogPath
    
$DeployPSM1File = Get-ChildItem $PSScriptRoot -Filter "DeployPowershellModule.psm1" | select -ExpandProperty FullName
if (!($DeployPSM1File))
{
    try
    {
        Invoke-Expression (New-Object Net.WebClient).DownloadString($URLModule)
    }
    catch
    {
        Write-Warning "Could not load Deploy module!"
        Write-Warning "Script will now end!"
        Stop-Transcript
    }
}
else
{
    try
    {
        Import-Module $DeployPSM1File -Force -ErrorAction Stop
    }
    catch
    {
        $_
        Write-Warning "Could not load Deploy module!"
        Write-Warning "Script will now end!"
        Stop-Transcript
    }
}

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
Write-Log "========================================================"
Write-Log "                     INFORMATION"
Write-Log "========================================================"
Write-Log " "

Write-Log "Running File: $($MyInvocation.MyCommand.Source)"
Write-Log " "

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
        Write-Log "========================================================"
        Write-Log "                    PRE-INSTALLATION"
        Write-Log "========================================================"
        Write-Log " "

        if ((Get-IsUserElevated) -eq $true)
        {
            Add-DeployITLogs
            Add-DeployITDownload
        }





        Write-Log " "
#endregion

#region Step 1
		##*===============================================
		##* INSTALLATION of HyperV Feature
		##*===============================================
        Write-Log "========================================================"
        Write-Log "                 Install HyperV Feature"
        Write-Log "========================================================"
        Write-Log " "

        IF (Get-ItemProperty -Path $RegistrySoftwareName -Name "Microsoft-Hyper-V-All" -ErrorAction SilentlyContinue) {
            Write-Log -Message "HyperV Feature is already installed." -Level SUCCEEDED
            $HyperVInstalled = $true
        }
        else {
            Powershell.exe -executionpolicy bypass -File "$PSScriptRoot\1_Install-Features_for_PAW\Install-Features_for_PAW.ps1"
        }

        Write-Log " "
#endregion

#region Step 2
		##*===============================================
		##* Install VMDeploy Configuration
		##*===============================================
        Write-Log "========================================================"
        Write-Log "             Configure VM Deploy Network"
        Write-Log "========================================================"
        Write-Log " "

        IF ($HyperVInstalled -eq $true) {
            Write-Log -Message "HyperV Feature is already installed. Setting network configuration." -Level SUCCEEDED
            Powershell.exe -executionpolicy bypass -File "$PSScriptRoot\2_Install_VMDeploy-configuration\Configure-PAWNetwork.ps1"
            $PAWNetworkConfigured = $true
        }
        else {
            Write-Log -Message "HyperV Feature is not installed. Cannot set network configuration." -Level WARNING
            Exit
        }

        Write-Log " "

        Write-Log "========================================================"
        Write-Log "            Set Firewall Rules for VM Deploy"
        Write-Log "========================================================"
        Write-Log " "

        IF ($PAWNetworkConfigured -eq $true) {
            Write-Log -Message "PAW Network is configured. Setting firewall rules." -Level SUCCEEDED
            Powershell.exe -executionpolicy bypass -File "$PSScriptRoot\2_Install_VMDeploy-configuration\Set-FirewallRules.ps1"
            $FirewallRulesSet = $true
        }
        else {
            Write-Log -Message "PAW Network is not configured. Cannot set firewall rules." -Level WARNING
            Exit
        }

        Write-Log " "

        Write-Log "========================================================"
        Write-Log "                  Add HyperV User"
        Write-Log "========================================================"
        Write-Log " "

        IF ($FirewallRulesSet -eq $true) {
            Write-Log -Message "Firewall rules are set. Adding HyperV user." -Level SUCCEEDED
            Powershell.exe -executionpolicy bypass -File "$PSScriptRoot\2_Install_VMDeploy-configuration\Add-HyperVAdmin.ps1"
        }
        else {
            Write-Log -Message "Firewall rules are not set. Cannot add HyperV user." -Level WARNING
            Exit
        }

        Write-Log " "

#endregion

#region Step 3
		##*===============================================
		##* INSTALLATION
		##*===============================================
        Write-Log "========================================================"
        Write-Log "                Install VM Deploy"
        Write-Log "========================================================"
        Write-Log " "

        IF (Get-LocalUser "HyperVUser" -eq $true) {
            Write-Log -Message "HyperV user already exists. Proceeding with VM Deploy installation." -Level SUCCEEDED
            Powershell.exe -executionpolicy bypass -File "$PSScriptRoot\3_Install_VMDeploy\Install-VMDeploy.ps1"
        }
        else {
            Write-Log -Message "HyperV user does not exist. Cannot proceed with VM Deploy installation." -Level WARNING
            Exit
        }

        Write-Log " "
#endregion

#region Post-Installation
		##*===============================================
		##* POST-INSTALLATION
		##*===============================================
        Write-Log "========================================================"
        Write-Log "                   POST-INSTALLATION"
        Write-Log "========================================================"
        Write-Log " "
        


        Write-Log " "
#endregion

#region Check Installation
		##*===============================================
		##* CHECK INSTALLATION
		##*===============================================        
        Write-Log "========================================================"
        Write-Log "                   CHECK INSTALLATION"
        Write-Log "========================================================"
        Write-Log " "

        if (Get-Item -path $CheckInstallItem) {
            Write-Log -Message "Installation finished successfully" -Level SUCCEEDED
            Write-Log "========================================================"

            try {
                Set-ItemProperty -Path $ApplicationKeyPath -Name "(Default)" -Value "True" -Force | Out-Null
                Write-Host "Registry value for $SoftwareName created/updated successfully."
            } catch {
                Write-Error "Failed to create/update registry value for $SoftwareName."
            }
            
        Write-Log "========================================================"
        Stop-Transcript
    }
    else {
        Write-Log -Message "Installation finished unsuccessfully" -Level WARNING
        Write-Log "========================================================"
        Stop-Transcript
    }

#endregion