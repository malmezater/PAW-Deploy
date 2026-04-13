$SourceFiles = "VHDX-Template"
$ApplicationName = "VMDeploy"
$RegistryPath = "HKLM:\SOFTWARE\RejlersIT"
$RegistryApplicationName = "$RegistryPath\$ApplicationName"
$ApplicationKeyPath = "$RegistryApplicationName"
$RejlersIT = "C:\ProgramData\RejlersIT"
$RejlersITLogs = "$RejlersIT\logs"
$RejlersITDownload = "$RejlersIT\Download"
$PowershellLogPath = "$RejlersITLogs\$SourceFiles-PS.log"

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

if(!(Test-Path $RejlersITDownload)){
    write-host "DownloadPath: $RejlersITDownload doesn't exist. Creating directory."
    New-Item -ItemType Directory $RejlersITDownload -Force
    }
    else{
    write-host "DownloadPath: $RejlersITDownload already exist. No need to create directory."
    }

    # Check if the RejlersIT key exists, if not, create it
if (-not (Test-Path $RegistryApplicationName)) 
    {
        Write-Host "Registry key $RegistryApplicationName does not exist. Creating it..."
        New-Item -Path $RegistryApplicationName -Force
    } 
    else {
        Write-Host "Registry key $RegistryApplicationName already exists."
    }

##*===============================================
##* Installation
##*===============================================    

try
{
    if(!(test-path C:\ProgramData\RejlersIT\VMDeploy\Images))
    {
	    New-Item C:\ProgramData\RejlersIT\VMDeploy\Images -ItemType Directory -Force
    }

    else
    {
        Write-Host "Directory C:\ProgramData\RejlersIT\VMDeploy\Images already exists."
        $HashID = (get-filehash -Path C:\ProgramData\RejlersIT\VMDeploy\Images\Windows11.vhdx -Algorithm SHA256).Hash
    }

    if ($HashID -eq "F20B5343ED8BA5CEA49F91CFAD8D1BA27EEAB9ADB06FC248AB068BB600AAD8AA") {

        Write-Host "The hash ID matches the expected value. Proceeding with the script."

    } 
        
    else {
        
        Write-Host "VHDX file not found. Downloading the VHDX file."
        Start-BitsTransfer -Source https://it.rejlers.se/powershell/VMDeploy/Images/Windows11.vhdx -Destination C:\ProgramData\RejlersIT\VMDeploy\Images\Windows11.vhdx

    }

}
catch
{
 Write-Host "An error occurred: $_"
}

#*===============================================
#* Check if installation file exist
#*===============================================

if  (Get-ChildItem -Path "C:\ProgramData\RejlersIT\VMDeploy\Images\Windows11.vhdx" -ErrorAction SilentlyContinue) {
    
    try {
        New-ItemProperty -Path $ApplicationKeyPath -Name $SourceFiles -Value "True" -PropertyType String -Force | Out-Null
        Write-Host "Registry value for $SourceFiles created/updated successfully."
    } catch {
        Write-Error "Failed to create/update registry value for $SourceFiles."
    }
}
else {
    Write-Warning "The VHDX was not found, exit"
}

Stop-Transcript