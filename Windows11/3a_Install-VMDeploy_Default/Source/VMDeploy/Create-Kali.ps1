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
##* Kali VM Settings
##*===============================================
$SourceFiles = "Create-Kali"
$RejlersIT = "C:\ProgramData\RejlersIT"
$RejlersITLogs = "$RejlersIT\logs"
$PowershellLogPath = "$RejlersITLogs\$SourceFiles.log"
$HashID = (get-filehash -Path $env:ProgramData\RejlersIT\VMDeploy\Images\Kali.vhdx -Algorithm SHA256).Hash
$CheckItem = New-Item -Path "$RejlersIT\Check\$SourceFiles.txt" -Force
$vhdxtemp = "C:\ProgramData\RejlersIT\VMDeploy\Images\Kali.vhdx"
$vhdx = "C:\ProgramData\RejlersIT\VMDeploy\VMs\$Name\$Name.vhdx"

$Description = "Kali Rolling (2025.1a) x64 2025-03-07

- - - - - - - - - - - - - - - - - -

Username: kali
Password: kali
(SE keyboard layout)

- - - - - - - - - - - - - - - - - -"

Start-Transcript -Path $PowershellLogPath -Force -Append

##*===============================================
##* RejlersIT LOG AND DOWNLOAD DIRECTORY
##*===============================================

if (!(Test-Path $RejlersITLogs)) {
    Write-Host "Logpath: $RejlersITLogs doesn't exist. Creating directory."
    New-Item -ItemType Directory $RejlersITLogs -Force
} else {
    Write-Host "Logpath: $RejlersITLogs already exists. No need to create directory."
}

##*===============================================
##* Check if the hash ID matches
##*===============================================    

if ($HashID -eq "995ADFDD19C64E5BEE1871B24DB5768A0947097FDE3C500BD749843A70EBC41B") {
    Write-Host "The hash ID matches the expected value. Proceeding with the script."
    Powershell.exe -ExecutionPolicy Bypass -File "$env:ProgramData\RejlersIT\VMDeploy\Create-Kali.ps1"
} else {
    Write-Host "The hash ID does not match the expected value. Please check the image file."
    exit
}

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
  -MemoryStartupBytes 2048MB `
  -SwitchName "Default Switch" `
  -VHDPath $vhdx

Set-VM -Name "$Name" -Notes "$Description"
Set-VM -Name "$Name" -EnhancedSessionTransportType HVSocket
Set-VMFirmware -VMName "$Name" -EnableSecureBoot Off
Set-VMProcessor -VMName "$Name" -Count 2
Enable-VMIntegrationService -VMName "$Name" -Name "Guest Service Interface"

Write-Host ""
Write-Host "Your Kali Linux virtual machine is ready."
Write-Host "In order to use it, please start: Hyper-V Manager"
Write-Host "For more information please see:"
Write-Host "  https://www.kali.org/docs/virtualization/import-premade-hyper-v/"
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