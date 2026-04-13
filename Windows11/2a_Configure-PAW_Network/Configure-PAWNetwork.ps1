
$ApplicationName = "VMDeploy"
$SourceFiles = "PawNetwork"
$RegistryPath = "HKLM:\SOFTWARE\RejlersIT"
$RegistryApplicationName = "$RegistryPath\$ApplicationName"
$ApplicationKeyPath = "$RegistryApplicationName"
$Application = $ApplicationName # Replace with the actual application name
$item = "$PSScriptRoot\$SourceFiles"
$RejlersIT = "C:\ProgramData\RejlersIT"
$RejlersITLogs = "$RejlersIT\logs"
$RejlersITDownload = "$RejlersIT\Download"
$Date = Get-Date -Format yyMMdd-HHmm
$PowershellLogPath = "$RejlersITLogs\$SourceFiles-PS.log"

Start-Transcript -Path $PowershellLogPath -Force -Append

##*===============================================
##* FUNCTIONS
##*===============================================


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
    } else {
        Write-Host "Registry key $RegistryApplicationName already exists."
    }



# Check if Hyper-v is installed
if((Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-v).State -ne "Enabled")
{
    Write-Warning "Hyper-V is not enabled, will exit"

}

##*===============================================
##* INSTALLATION
##*===============================================

# Create VMSwitch for External access

# Verify the switch
if((Get-VMSwitch | Where-Object Name -EQ UplinkSwitch))
{
    Write-Host "VMSwitch UplinkSwitch already exists, will not create it again"
    write-host "#==================================================================#"
    Write-Host "Check for registry key for $SourceFiles"
    try {
        New-ItemProperty -Path $ApplicationKeyPath -Name $SourceFiles -Value "True" -PropertyType String -Force | Out-Null
        Write-Host "Registry value for $SourceFiles created/updated successfully."
    } catch {
        Write-Error "registry value for $SourceFiles. Allready exists."
    }
    
}

else {

    $NetAdapter = Get-NetAdapter -Physical | Where-Object Status -EQ Up
    New-VMSwitch -Name "UplinkSwitch" -NetAdapterName $NetAdapter.Name -AllowManagementOS $true
    Write-Host "The VMSwitch UplinkSwitch was created"
    try {
        New-ItemProperty -Path $ApplicationKeyPath -Name $SourceFiles -Value "True" -PropertyType String -Force | Out-Null
        Write-Host "Registry value for $SourceFiles created/updated successfully."
    } catch {
        Write-Error "Failed to create/update registry value for $SourceFiles."
    }
}

#Get-NetAdapter -Name "*default switch*" | Disable-NetAdapter -Confirm:$false

Stop-Transcript

