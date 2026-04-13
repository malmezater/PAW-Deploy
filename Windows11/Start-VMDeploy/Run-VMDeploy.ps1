
$item = "$PSScriptRoot\$SourceFiles"
$SourceFiles = "Run-VMDeploy"
$RejlersIT = "C:\ProgramData\RejlersIT"
$RejlersITLogs = "$RejlersIT\logs"
$PowershellLogPath = "$RejlersITLogs\$SourceFiles.log"
$vhdxtemp = Get-childitem -Path $env:ProgramData\RejlersIT\VMDeploy\Images\Windows11.vhdx
$CheckItem = New-Item -Path "$RejlersIT\Check\Run-VMDeploy.txt" -Force

Start-Transcript -Path $PowershellLogPath -Force -Append

##*===============================================
##* RejlersIT LOG AND DOWNLOAD DIRECTORY
##*===============================================

    if(!(Test-Path $RejlersITLogs)){
        write-host "Logpath: $RejlersITLogs doesn't exist. Creating directory."
        New-Item -ItemType Directory $RejlersITLogs -Force
    }
    else{
        write-host "Logpath: $RejlersITLogs already exist. No need to create directory."
    }


##*===============================================
##* Check if the hash ID matches
##*===============================================    

    if ($vhdxtemp) {

        Write-Host "Windows 11 template is downloaded, proceeding with the script."
        Powershell.exe -ExecutionPolicy Bypass -File $env:ProgramData\RejlersIT\VMDeploy\VMDeploywUI.ps1

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
