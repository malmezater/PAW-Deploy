$ApplicationName = "VMDeploy"
$SourceFiles = "HyperV"
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

if (-not (Test-Path $RegistryApplicationName)) {
    Write-Host "Registry key $RegistryApplicationName does not exist. Creating it..."
    New-Item -Path $RegistryApplicationName -Force
    } 
    else {
    Write-Host "Registry key $RegistryApplicationName already exists."
    }

##*===============================================
##* INSTALLATION
##*===============================================

$HyperVFeatures = @(
    "Microsoft-Hyper-V-All"
    "Microsoft-Hyper-V"
    "Microsoft-Hyper-V-Tools-All"
    "Microsoft-Hyper-V-Management-PowerShell"
    "Microsoft-Hyper-V-Hypervisor"
    "Microsoft-Hyper-V-Services"
    "Microsoft-Hyper-V-Management-Clients"
    "HostGuardian"
)

Foreach($Feature in $HyperVFeatures) {
    Get-WindowsOptionalFeature -FeatureName $Feature -Online | ForEach-Object {
        if ($_.State -eq "Enabled") {
            Write-Host "$Feature is already enabled."
        } else {
            $AllFeaturesEnabled = $false
            Enable-WindowsOptionalFeature -FeatureName $Feature -LimitAccess -NoRestart -Online
        }
    }
}

##*===============================================
##* Check if all features are enabled
##*===============================================


Foreach ($Feature in $HyperVFeatures) {

    if ((Get-WindowsOptionalFeature -FeatureName $Feature -Online).State -eq "Enabled") {
        Write-Host "HyperV Features $Feature is Enabled"
        try {
            New-ItemProperty -Path $ApplicationKeyPath -Name $Feature -Value "Enabled" -PropertyType String -Force | Out-Null
            Write-Host "Registry value for $Feature created/updated successfully."
        } catch {
            Write-Error "Failed to create/update registry value for $Feature."
        }

    } else {
        Write-Host "HyperV Feature $Feature is Disabled"
    }

}

Stop-Transcript