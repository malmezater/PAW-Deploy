
$item = "$PSScriptRoot\$SourceFiles"
$SourceFiles = "Run-VMDeploy"
$DeployIT = "C:\ProgramData\DeployIT"
$DeployITLogs = "$DeployIT\logs"
$PowershellLogPath = "$DeployITLogs\$SourceFiles.log"
$vhdxtemp = Get-childitem -Path $env:ProgramData\DeployIT\VMDeploy\Images\Windows11.vhdx
$CheckItem = New-Item -Path "$DeployIT\Check\Run-VMDeploy.txt" -Force

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

    if ($vhdxtemp) {

        Write-Host "Windows 11 template is downloaded, proceeding with the script."
        Powershell.exe -ExecutionPolicy Bypass -File $env:ProgramData\DeployIT\VMDeploy\VMDeploywUI.ps1

    } 
        
    else {
        
        Write-Host "Windows 11 template is not downloaded, please download the image file."

    }

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
Stop-Transcript
