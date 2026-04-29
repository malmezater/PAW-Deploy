$SourceFiles = "HyperV-Admins"
$ApplicationName = "PAWDeploy"
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

try{
$LocalAdminGRoup = (Get-WmiObject -Query "Select * From Win32_Group Where LocalAccount = TRUE And SID = 'S-1-5-32-578'").name
$LoggedinUser = (Get-CimInstance -Class Win32_ComputerSystem).Username

if (Get-LocalGroupMember -Name $LocalAdminGRoup | Where-Object { $_.Name -eq $LoggedinUser }) {
    Write-host "$LoggedinUser is already a member of the $LocalAdminGRoup group."
} else {
    Write-host "$LoggedinUser is not a member of the $LocalAdminGRoup group."
    Write-host "Adding $LoggedinUser to the $LocalAdminGRoup group."
    # Add the logged-in user to the local administrators group
    Add-LocalGroupMember -Group $LocalAdminGRoup -Member $LoggedinUser
}

}catch{}

$username = "Hypervuser"

if (Get-Localuser -Name $username) {
    Write-host "Hypervuser already exists."
} else {
    do {
        $password = [string](Read-Host -Prompt 'Please enter a 15 char password' )
        if ($password.Length -ge 14) {
            Write-Host $password.Length
            $userpassword = $password | ConvertTo-SecureString -AsPlainText -Force
            break
        }
    
    } while ($true)
    
    Write-host "Creating Hyper-v user: $username"
    New-LocalUser -Name $username -Password $userpassword -FullName $username -PasswordNeverExpires:$true
    Add-LocalGroupMember -SID S-1-5-32-578 -Member $username
}

#*===============================================
#* Check if installation file exist
#*===============================================

if  (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {

    try {
        New-ItemProperty -Path $ApplicationKeyPath -Name $SourceFiles -Value "True" -PropertyType String -Force | Out-Null
        Write-Host "Registry value for $SourceFiles created/updated successfully."
    } catch {
        Write-Error "Failed to create/update registry value for $SourceFiles."
    }
}
else {
    Write-Warning "The HyperVUser was not found, exit"
}

Stop-Transcript