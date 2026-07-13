#Requires -RunAsAdministrator
#Requires -Modules Hyper-V

$item = "$PSScriptRoot\$SourceFiles"
$SourceFiles = "Run-VMDeploy"
$DeployIT = "C:\ProgramData\DeployIT"
$DeployITLogs = "$DeployIT\logs"
$PowershellLogPath = "$DeployITLogs\$SourceFiles.log"
$HashID = (get-filehash -Path $env:ProgramData\DeployIT\VMDeploy\Images\Windows11.vhdx -Algorithm SHA256).Hash
$CheckItem = New-Item -Path "$DeployIT\Check\Run-VMDeploy.txt" -Force
$vhdxtemp = "C:\ProgramData\DeployIT\VMDeploy\Images\Kali.vhdx"


Start-Transcript -Path $PowershellLogPath -Force -Append

##*===============================================
##* DeployIT LOG AND DOWNLOAD DIRECTORY
##*===============================================

    if(!(Test-Path $DeployITLogs)){
        write-host "Logpath: $DeployITLogs doesn't exist. Creating directory."
        New-Item -ItemType Directory $DeployITLogs -Force
    }
    else{
        write-host "Logpath: $DeployITLogs already exist. No need to create directory."
    }


##*===============================================
##* Check if the hash ID matches
##*===============================================    

    if ($HashID -eq "F20B5343ED8BA5CEA49F91CFAD8D1BA27EEAB9ADB06FC248AB068BB600AAD8AA") {

        Write-Host "The hash ID matches the expected value. Proceeding with the script."
        Powershell.exe -ExecutionPolicy Bypass -File $env:ProgramData\DeployIT\VMDeploy\VMDeploywUI.ps1

    } 
        
    else {
        
        Write-Host "The hash ID does not match the expected value. Please check the image file."

    }

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
    ##* Installation
    ##*===============================================
    $vhdx = "C:\ProgramData\DeployIT\VMDeploy\VMs\$VM\$VM.vhdx"
    $Description = "Kali Rolling (2025.1a) x64 2025-03-07

    - - - - - - - - - - - - - - - - - -

    Username: kali
    Password: kali
    (SE keyboard layout)

    - - - - - - - - - - - - - - - - - -"


    Get-Item -Path $vhdxtemp | Copy-Item -Destination $vhdx -Force

    New-VM `
      -Generation 2 `
      -Name "$Name" `
      -MemoryStartupBytes 2048MB `
      -SwitchName "Default Switch" `
      -VHDPath $vhdx

    Set-VM -Name "$Name" -Notes "$Description"
    Set-VM -Name "$Name" -EnhancedSessionTransportType HVSocket
    Set-VMFirmware -VMName "$Name" -EnableSecureBoot Off
    Set-VMProcessor -VMName "$Name" -Count 2
    Enable-VMIntegrationService -VMName "$Name" -Name "Guest Service Interface"

    Write-Host ""
    Write-Host "Your Kali Linux virtual machine is ready."
    Write-Host "In order to use it, please start: Hyper-V Manager"
    Write-Host "For more information please see:"
    Write-Host "  https://www.kali.org/docs/virtualization/import-premade-hyper-v/"
    Write-Host ""
#endregion

#region Check
  ##*===============================================
  ##* Remove Check file
  ##*===============================================

      if (Test-Path $CheckItem) {
          Remove-Item -Path $CheckItem -Force
          Write-Host "Check file removed successfully."
      } else {
          Write-Host "Check file does not exist."
      }
  ##*===============================================   
#endregion
Stop-Transcript

