##*===============================================
##* Custom variables
##*===============================================

$SoftwareName = "VMDeploy"

##*===============================================
##* Static variables
##*===============================================

$RegistryPath = "HKLM:\SOFTWARE\DeployIT"
$RegistrySoftwareName = "$RegistryPath\$SoftwareName"
$ApplicationKeyPath = "$RegistrySoftwareName"
$DeployIT = "C:\ProgramData\DeployIT"
$DeployITLogs = "$DeployIT\logs"
$DeployITDownload = "$DeployIT\Download"

$SourceFiles = "FirewallRules"
$PowershellLogPath = "$DeployITLogs\$SourceFiles-PS.log"

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
if (-not (Test-Path $RegistrySoftwareName)) 
    {
        Write-Host "Registry key $RegistrySoftwareName does not exist. Creating it..."
        New-Item -Path $RegistrySoftwareName -Force
    } 
    else {
        Write-Host "Registry key $RegistrySoftwareName already exists."
    }


##*===============================================
##* Custom variables for Firewall Rules
##*===============================================
    
##*===============================================


##*===============================================
##* INSTALLATION Firewall Rules
##*===============================================

Start-Transcript -Path $PowershellLogPath -Force -Append
Write-Host "Checking if Firewall settings are disabled..."

$Rules = @("VIRT-WMI-RPCSS-In-TCP-NoScope","VIRTCL-WMI-RPCSS-In-TCP-NoScope","VIRT-REMOTEDESKTOP-In-TCP-NoScope")


$Rules | ForEach-Object {
    $Application = $_

    if ((Get-NetFirewallRule -Name $_).Enabled -eq "False") {
        Write-Host "Firewall rule $_ is disabled"

        # Create or update the registry value
        try {
            New-ItemProperty -Path $ApplicationKeyPath -Name $Application -Value "Disabled" -PropertyType String -Force | Out-Null
            Write-Host "Registry value for $Application created/updated successfully."
        } catch {
            Write-Error "Failed to create/update registry value for $Application."
        }
    } else {
        Write-Host "Disabling firewall rule $_"
        Set-NetFirewallRule -Name $_ -Enabled False

        # Create or update the registry value
        try {
            New-ItemProperty -Path $ApplicationKeyPath -Name $Application -Value "Disabled" -PropertyType String -Force | Out-Null
            Write-Host "Registry value for $Application created/updated successfully."
        } catch {
            Write-Error "Failed to create/update registry value for $Application."
        }
    }
}

Stop-Transcript