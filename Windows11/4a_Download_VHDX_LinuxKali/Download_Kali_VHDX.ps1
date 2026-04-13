$SourceFiles = "Kali-Template"
$ApplicationName = "VMDeploy"
$RegistryPath = "HKLM:\SOFTWARE\DeployIT"
$RegistryApplicationName = "$RegistryPath\$ApplicationName"
$ApplicationKeyPath = "$RegistryApplicationName"
$DeployIT = "C:\ProgramData\DeployIT"
$DeployITLogs = "$DeployIT\logs"
$DeployITDownload = "$DeployIT\Download"
$PowershellLogPath = "$DeployITLogs\$SourceFiles-PS.log"

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

if(!(Test-Path $DeployITDownload)){
    write-host "DownloadPath: $DeployITDownload doesn't exist. Creating directory."
    New-Item -ItemType Directory $DeployITDownload -Force
    }
    else{
    write-host "DownloadPath: $DeployITDownload already exist. No need to create directory."
    }

    # Check if the DeployIT key exists, if not, create it
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
    if(!(test-path C:\ProgramData\DeployIT\VMDeploy\Images))
    {
	    New-Item C:\ProgramData\DeployIT\VMDeploy\Images -ItemType Directory -Force
    }

    else
    {
        Write-Host "Directory C:\ProgramData\DeployIT\VMDeploy\Images already exists."
        $HashID = (get-filehash -Path C:\ProgramData\DeployIT\VMDeploy\Images\Kali.vhdx -Algorithm SHA256).Hash
    }

    if ($HashID -eq "995ADFDD19C64E5BEE1871B24DB5768A0947097FDE3C500BD749843A70EBC41B") {

        Write-Host "The hash ID matches the expected value. Proceeding with the script."

    } 
        
    else {
        
        Write-Host "VHDX file not found. Downloading the VHDX file."
        Start-BitsTransfer -Source https://it.Deploy.se/powershell/VMDeploy/Images/Kali.vhdx -Destination C:\ProgramData\DeployIT\VMDeploy\Images\Kali.vhdx

    }

}
catch
{
 Write-Host "An error occurred: $_"
}

#*===============================================
#* Check if installation file exist
#*===============================================

if  (Get-ChildItem -Path "C:\ProgramData\DeployIT\VMDeploy\Images\Kali.vhdx" -ErrorAction SilentlyContinue) {
    
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