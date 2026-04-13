$ApplicationName = "VMDeploy"
$SourceFiles = "FirewallRules"
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