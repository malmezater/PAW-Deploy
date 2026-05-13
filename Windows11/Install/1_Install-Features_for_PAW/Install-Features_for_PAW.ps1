$SoftwareName = "VMDeploy"
$RegistryPath = "HKLM:\SOFTWARE\DeployIT"
$RegistrySoftwareName = "$RegistryPath\$SoftwareName"
$ApplicationKeyPath = "$RegistrySoftwareName"
$DeployIT = "C:\ProgramData\DeployIT"
$DeployITLogs = "$DeployIT\logs"
$DeployITDownload = "$DeployIT\Download"

$SourceFiles = "HyperV"
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

if (-not (Test-Path $RegistrySoftwareName)) {
    Write-Host "Registry key $RegistrySoftwareName does not exist. Creating it..."
    New-Item -Path $RegistrySoftwareName -Force
    } 
    else {
    Write-Host "Registry key $RegistrySoftwareName already exists."
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
            Enable-WindowsOptionalFeature -FeatureName $Feature -LimitAccess -NoRestart -Online
        }
    }
}

##*===============================================
##* Check if all features are enabled
##*===============================================

$MaxCheckAttempts = 3
$RemainingAttempts = $MaxCheckAttempts

Write-Host "Checking HyperV feature status up to $MaxCheckAttempts times."

do {
    $AllFeaturesEnabled = $true

    Foreach ($Feature in $HyperVFeatures) {
        $featureState = (Get-WindowsOptionalFeature -FeatureName $Feature -Online).State

        if ($featureState -eq "Enabled") {
            Write-Host "HyperV Feature $Feature is Enabled"
            try {
                New-ItemProperty -Path $ApplicationKeyPath -Name $Feature -Value "Enabled" -PropertyType String -Force | Out-Null
                Write-Host "Registry value for $Feature created/updated successfully."
            } catch {
                Write-Error "Failed to create/update registry value for $Feature."
            }
        } else {
            Write-Host "HyperV Feature $Feature is Disabled"
            $AllFeaturesEnabled = $false
        }
    }

    if ($AllFeaturesEnabled) {
        break
    }

    $RemainingAttempts--
    if ($RemainingAttempts -gt 0) {
        Write-Host "Not all features are enabled yet. Retrying in 10 seconds. Remaining attempts: $RemainingAttempts"
        Start-Sleep -Seconds 10
    } else {
        Write-Host "Retry counter reached 0."
    }
} while ($RemainingAttempts -gt 0)

if ($AllFeaturesEnabled -or $RemainingAttempts -eq 0) {
    Write-Host "Reboot required. Exiting with code 1641."
    Stop-Transcript
    exit 1641
} else {
    Write-Host "Not all features enabled and retries remain. No reboot required."
    Stop-Transcript
    exit 0
}