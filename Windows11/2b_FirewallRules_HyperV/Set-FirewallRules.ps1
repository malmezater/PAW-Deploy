$ApplicationName = "VMDeploy"
$SourceFiles = "FirewallRules"
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
##* INSTALLATION
##*===============================================

Write-Host "Checking if Firewall settings are disabled..."

$Rules = @("VIRT-WMI-RPCSS-In-TCP-NoScope","VIRTCL-WMI-RPCSS-In-TCP-NoScope","VIRT-REMOTEDESKTOP-In-TCP-NoScope")


$Rules | ForEach-Object {
    $Application = $_
    $RegistryValuePath = "$ApplicationKeyPath\$Application"

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