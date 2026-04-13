$item = "$PSScriptRoot\$SourceFiles"
$SourceFiles = "Remove-VMDeploy"
$RejlersIT = "C:\ProgramData\RejlersIT"
$RejlersITLogs = "$RejlersIT\logs"
$PowershellLogPath = "$RejlersITLogs\$SourceFiles.log"
$CheckItem = New-Item -Path "$RejlersIT\Check\Remove-VMDeploy.txt" -Force

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

write-host " "
write-host " Starting the script to remove VM's."

Powershell.exe -ExecutionPolicy Bypass -File $env:ProgramData\RejlersIT\VMDeploy\VMRemovewUI.ps1

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
