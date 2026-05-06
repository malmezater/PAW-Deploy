#Requires -RunAsAdministrator
#Requires -Modules Hyper-V

Add-Type -AssemblyName System.Windows.Forms

# Create a form to enter the VM name
$form = New-Object System.Windows.Forms.Form
$form.Text = "Create Virtual Machine"
$form.Size = New-Object System.Drawing.Size(400, 200)
$form.StartPosition = "CenterScreen"

# Create a label
$label = New-Object System.Windows.Forms.Label
$label.Text = "Enter the name for the Virtual Machine:"
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(10, 20)
$form.Controls.Add($label)

# Create a text box
$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Size = New-Object System.Drawing.Size(360, 20)
$textBox.Location = New-Object System.Drawing.Point(10, 50)
$form.Controls.Add($textBox)

# Create an OK button
$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = "OK"
$okButton.Location = New-Object System.Drawing.Point(220, 100)
$okButton.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($textBox.Text)) {
        $form.Tag = $textBox.Text
        $form.Close()
    } else {
        [System.Windows.Forms.MessageBox]::Show("Please enter a valid name for the Virtual Machine.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})
$form.Controls.Add($okButton)

# Create a Cancel button
$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = "Cancel"
$cancelButton.Location = New-Object System.Drawing.Point(300, 100)
$cancelButton.Add_Click({
    $form.Tag = $null
    $form.Close()
})
$form.Controls.Add($cancelButton)

# Show the form
$form.ShowDialog()

# Get the VM name from the form
$Name = $form.Tag

if (-not $Name) {
    Write-Host "Operation canceled by the user."
    exit
}

##*===============================================
##* Ubuntu Server VM Settings
##*===============================================
$SourceFiles = "UbuntuServerMinimalx64"
$VMDeploy = "$Env:ProgramData\VMDeploy"
$VMDeployLogs = "$VMDeploy\logs"
$PowershellLogPath = "$VMDeployLogs\$SourceFiles.log"
$CheckItem = New-Item -Path "$VMDeploy\Check\$SourceFiles.txt" -Force
$vhdxtemp = "$VMDeploy\Images\UbuntuServerMinimalx64.vhdx"
$vhdx = "$VMDeploy\VMs\$Name\$Name.vhdx"

$Description = "Ubuntu Server Minimal x64 2025-05-06

- - - - - - - - - - - - - - - - - -

Username: ubuntu
Password: ubuntu
(SE keyboard layout)

- - - - - - - - - - - - - - - - - -"

Start-Transcript -Path $PowershellLogPath -Force -Append

##*===============================================
##* VMDeploy LOG AND DOWNLOAD DIRECTORY
##*===============================================

if (!(Test-Path $VMDeployLogs)) {
    Write-Host "Logpath: $VMDeployLogs doesn't exist. Creating directory."
    New-Item -ItemType Directory $VMDeployLogs -Force
} else {
    Write-Host "Logpath: $VMDeployLogs already exists. No need to create directory."
}

##*===============================================
##* Check if the hash ID matches
##*===============================================    


    Powershell.exe -ExecutionPolicy Bypass -File "$env:ProgramData\VMDeploy\VMDeploy\Create-Ubuntu-Server.ps1"

#region Installation
##*===============================================
##* Installation
##*===============================================

# Ensure the destination directory exists
if (!(Test-Path -Path (Split-Path -Path $vhdx -Parent))) {
    New-Item -ItemType Directory -Path (Split-Path -Path $vhdx -Parent) -Force
}

# Copy the VHDX file
Get-Item -Path $vhdxtemp | Copy-Item -Destination $vhdx -Force

# Create the VM
New-VM `
  -Generation 2 `
  -Name "$Name" `
  -MemoryStartupBytes 4096MB `
  -SwitchName "Default Switch" `
  -VHDPath $vhdx

Set-VM -Name "$Name" -Notes "$Description"
Set-VM -Name "$Name" -EnhancedSessionTransportType HVSocket
Set-VMFirmware -VMName "$Name" -EnableSecureBoot Off
Set-VMProcessor -VMName "$Name" -Count 2
Enable-VMIntegrationService -VMName "$Name" -Name "Guest Service Interface"

Write-Host ""
Write-Host "Your Ubuntu-Server virtual machine is ready."
Write-Host "In order to use it, please start: Hyper-V Manager"
Write-Host "For more information please see:"
Write-Host "https://ubuntu.com/download/server"
Write-Host ""
#endregion

#region Check
##*===============================================
##* Remove Check file
##*===============================================

if (Test-Path $CheckItem) {
    Remove-Item -Path $CheckItem -Force
    Write-Host "Check file removed successfully."
} else {
    Write-Host "Check file does not exist."
}
#endregion

Stop-Transcript