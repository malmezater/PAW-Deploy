$SoftwareName = "VMDeploy"
$RegistryPath = "HKLM:\SOFTWARE\DeployIT"
$RegistrySoftwareName = "$RegistryPath\$SoftwareName"
$ApplicationKeyPath = "$RegistrySoftwareName"
$DeployIT = "C:\ProgramData\DeployIT"
$DeployITLogs = "$DeployIT\logs"
$DeployITDownload = "$DeployIT\Download"

$SourceFiles = "HyperV-Admins"
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
if (-not (Test-Path $RegistrySoftwareName)) 
    {
        Write-Host "Registry key $RegistrySoftwareName does not exist. Creating it..."
        New-Item -Path $RegistrySoftwareName -Force
    } 
    else {
        Write-Host "Registry key $RegistrySoftwareName already exists."
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

if (Get-Localuser -Name $username -ErrorAction SilentlyContinue) {
    Write-host "Hypervuser already exists."
} else {
    ##*===============================================
    ##* GUI PASSWORD INPUT DIALOG
    ##*===============================================
    
    function Show-PasswordDialog {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "Create Hyper-V User"
        $form.Size = New-Object System.Drawing.Size(400, 220)
        $form.StartPosition = "CenterScreen"
        $form.FormBorderStyle = "FixedDialog"
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.TopMost = $true
        
        # Username Label
        $usernameLabel = New-Object System.Windows.Forms.Label
        $usernameLabel.Text = "Username:"
        $usernameLabel.Location = New-Object System.Drawing.Point(20, 20)
        $usernameLabel.Size = New-Object System.Drawing.Size(80, 20)
        $form.Controls.Add($usernameLabel)
        
        # Username TextBox (Read-only)
        $usernameTextBox = New-Object System.Windows.Forms.TextBox
        $usernameTextBox.Text = "Hypervuser"
        $usernameTextBox.Location = New-Object System.Drawing.Point(110, 20)
        $usernameTextBox.Size = New-Object System.Drawing.Size(250, 20)
        $usernameTextBox.ReadOnly = $true
        $usernameTextBox.BackColor = [System.Drawing.Color]::LightGray
        $form.Controls.Add($usernameTextBox)
        
        # Password Label
        $passwordLabel = New-Object System.Windows.Forms.Label
        $passwordLabel.Text = "Password:"
        $passwordLabel.Location = New-Object System.Drawing.Point(20, 60)
        $passwordLabel.Size = New-Object System.Drawing.Size(80, 20)
        $form.Controls.Add($passwordLabel)
        
        # Password TextBox
        $passwordTextBox = New-Object System.Windows.Forms.TextBox
        $passwordTextBox.UseSystemPasswordChar = $true
        $passwordTextBox.Location = New-Object System.Drawing.Point(110, 60)
        $passwordTextBox.Size = New-Object System.Drawing.Size(250, 20)
        $form.Controls.Add($passwordTextBox)
        
        # Info Label
        $infoLabel = New-Object System.Windows.Forms.Label
        $infoLabel.Text = "(Minimum 15 characters required)"
        $infoLabel.Location = New-Object System.Drawing.Point(110, 85)
        $infoLabel.Size = New-Object System.Drawing.Size(250, 20)
        $infoLabel.ForeColor = [System.Drawing.Color]::DarkBlue
        $infoLabel.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Italic)
        $form.Controls.Add($infoLabel)
        
        # Character Count Label
        $charCountLabel = New-Object System.Windows.Forms.Label
        $charCountLabel.Text = "Characters: 0/15"
        $charCountLabel.Location = New-Object System.Drawing.Point(110, 105)
        $charCountLabel.Size = New-Object System.Drawing.Size(250, 20)
        $charCountLabel.ForeColor = [System.Drawing.Color]::Red
        $charCountLabel.Font = New-Object System.Drawing.Font("Arial", 9)
        $form.Controls.Add($charCountLabel)
        
        # Update character count on text change
        $passwordTextBox.Add_TextChanged({
            $charCountLabel.Text = "Characters: $($passwordTextBox.Text.Length)/15"
            if ($passwordTextBox.Text.Length -ge 15) {
                $charCountLabel.ForeColor = [System.Drawing.Color]::Green
            } else {
                $charCountLabel.ForeColor = [System.Drawing.Color]::Red
            }
        })
        
        # OK Button
        $okButton = New-Object System.Windows.Forms.Button
        $okButton.Text = "OK"
        $okButton.Location = New-Object System.Drawing.Point(170, 140)
        $okButton.Size = New-Object System.Drawing.Size(100, 30)
        $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $okButton.Add_Click({
            if ($passwordTextBox.Text.Length -lt 15) {
                [System.Windows.Forms.MessageBox]::Show("Password must be at least 15 characters!", "Invalid Password", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            } else {
                $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
                $form.Close()
            }
        })
        $form.Controls.Add($okButton)
        
        # Cancel Button
        $cancelButton = New-Object System.Windows.Forms.Button
        $cancelButton.Text = "Cancel"
        $cancelButton.Location = New-Object System.Drawing.Point(280, 140)
        $cancelButton.Size = New-Object System.Drawing.Size(100, 30)
        $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Controls.Add($cancelButton)
        
        $result = $form.ShowDialog()
        
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            return $passwordTextBox.Text
        } else {
            return $null
        }
    }
    
    $password = Show-PasswordDialog
    
    if ($password -eq $null) {
        Write-Warning "User cancelled the operation."
    } else {
        $userpassword = $password | ConvertTo-SecureString -AsPlainText -Force
        
        Write-host "Creating Hyper-v user: $username"
        New-LocalUser -Name $username -Password $userpassword -FullName $username -PasswordNeverExpires:$true
        Add-LocalGroupMember -SID S-1-5-32-578 -Member $username
    }
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