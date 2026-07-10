$SourceFiles = "Remove-PAWDeploy"
$DeployIT = "C:\ProgramData\DeployIT"
$DeployITLogs = "$DeployIT\logs"
$PowershellLogPath = "$DeployITLogs\$SourceFiles.log"
$CheckItem = New-Item -Path "$DeployIT\Check\Remove-PAWDeploy.txt" -Force

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

write-host " "
write-host " Starting the script to remove VM's."

Powershell.exe -ExecutionPolicy Bypass -File $env:ProgramData\VMDeploy\VMRemovewUI.ps1

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
