
#Requires -Version 5.1
<#
.SYNOPSIS
    Stage 2c - Add the logged-in user to the Hyper-V Administrators group
              and create the local "Hypervuser" service account.
#>

# -------  Bootstrap: load shared settings  -------
Import-Module "$PSScriptRoot\..\..\Settings.psm1" -Force

$SourceFiles = "HyperV-Admins"
$LogPath     = "$DeployITLogs\$SourceFiles-PS.log"
Start-Transcript -Path $LogPath -Force -Append

Initialize-DeployEnvironment

# -------  Add logged-in user to Hyper-V Administrators (SID S-1-5-32-578)  -------

Write-Host "========================================================"
Write-Host "                  Add Hyper-V Administrators"
Write-Host "========================================================"

try {
    $HyperVAdminGroup = (Get-WmiObject -Query "Select * From Win32_Group Where LocalAccount = TRUE And SID = 'S-1-5-32-578'").Name
    $LoggedInUser     = (Get-CimInstance -Class Win32_ComputerSystem).Username

    if (Get-LocalGroupMember -Name $HyperVAdminGroup -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $LoggedInUser }) {
        Write-Host "$LoggedInUser is already a member of '$HyperVAdminGroup'."
    } else {
        Write-Host "Adding '$LoggedInUser' to '$HyperVAdminGroup' ..."
        Add-LocalGroupMember -Group $HyperVAdminGroup -Member $LoggedInUser
    }
} catch {
    Write-Warning "Could not add current user to Hyper-V Administrators: $_"
}

# -------  Create Hypervuser service account  -------

Write-Host "========================================================"
Write-Host "               Create Hypervuser Account"
Write-Host "========================================================"

$HyperVUsername = "Hypervuser"

if (Get-LocalUser -Name $HyperVUsername -ErrorAction SilentlyContinue) {
    Write-Host "'$HyperVUsername' already exists - skipping creation."
} else {
    # GUI password input dialog
    function Show-PasswordDialog {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $form                  = New-Object System.Windows.Forms.Form
        $form.Text             = "Create Hyper-V User"
        $form.Size             = New-Object System.Drawing.Size(400, 220)
        $form.StartPosition    = "CenterScreen"
        $form.FormBorderStyle  = "FixedDialog"
        $form.MaximizeBox      = $false
        $form.MinimizeBox      = $false
        $form.TopMost          = $true

        $lblUser          = New-Object System.Windows.Forms.Label
        $lblUser.Text     = "Username:"
        $lblUser.Location = New-Object System.Drawing.Point(20, 20)
        $lblUser.Size     = New-Object System.Drawing.Size(80, 20)
        $form.Controls.Add($lblUser)

        $txtUser          = New-Object System.Windows.Forms.TextBox
        $txtUser.Text     = $HyperVUsername
        $txtUser.Location = New-Object System.Drawing.Point(110, 20)
        $txtUser.Size     = New-Object System.Drawing.Size(250, 20)
        $txtUser.ReadOnly = $true
        $txtUser.BackColor = [System.Drawing.Color]::LightGray
        $form.Controls.Add($txtUser)

        $lblPwd          = New-Object System.Windows.Forms.Label
        $lblPwd.Text     = "Password:"
        $lblPwd.Location = New-Object System.Drawing.Point(20, 60)
        $lblPwd.Size     = New-Object System.Drawing.Size(80, 20)
        $form.Controls.Add($lblPwd)

        $txtPwd                      = New-Object System.Windows.Forms.TextBox
        $txtPwd.UseSystemPasswordChar = $true
        $txtPwd.Location             = New-Object System.Drawing.Point(110, 60)
        $txtPwd.Size                 = New-Object System.Drawing.Size(250, 20)
        $form.Controls.Add($txtPwd)

        $lblInfo          = New-Object System.Windows.Forms.Label
        $lblInfo.Text     = "(Minimum 15 characters required)"
        $lblInfo.Location = New-Object System.Drawing.Point(110, 85)
        $lblInfo.Size     = New-Object System.Drawing.Size(250, 20)
        $lblInfo.ForeColor = [System.Drawing.Color]::DarkBlue
        $lblInfo.Font     = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Italic)
        $form.Controls.Add($lblInfo)

        $lblCount          = New-Object System.Windows.Forms.Label
        $lblCount.Text     = "Characters: 0/15"
        $lblCount.Location = New-Object System.Drawing.Point(110, 105)
        $lblCount.Size     = New-Object System.Drawing.Size(250, 20)
        $lblCount.ForeColor = [System.Drawing.Color]::Red
        $lblCount.Font     = New-Object System.Drawing.Font("Arial", 9)
        $form.Controls.Add($lblCount)

        $txtPwd.Add_TextChanged({
            $lblCount.Text = "Characters: $($txtPwd.Text.Length)/15"
            $lblCount.ForeColor = if ($txtPwd.Text.Length -ge 15) {
                [System.Drawing.Color]::Green
            } else {
                [System.Drawing.Color]::Red
            }
        })

        $btnOK          = New-Object System.Windows.Forms.Button
        $btnOK.Text     = "OK"
        $btnOK.Location = New-Object System.Drawing.Point(170, 140)
        $btnOK.Size     = New-Object System.Drawing.Size(100, 30)
        $btnOK.Add_Click({
            if ($txtPwd.Text.Length -lt 15) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Password must be at least 15 characters!",
                    "Invalid Password",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
            } else {
                $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
                $form.Close()
            }
        })
        $form.Controls.Add($btnOK)

        $btnCancel          = New-Object System.Windows.Forms.Button
        $btnCancel.Text     = "Cancel"
        $btnCancel.Location = New-Object System.Drawing.Point(280, 140)
        $btnCancel.Size     = New-Object System.Drawing.Size(100, 30)
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Controls.Add($btnCancel)

        $result = $form.ShowDialog()
        return if ($result -eq [System.Windows.Forms.DialogResult]::OK) { $txtPwd.Text } else { $null }
    }

    $password = Show-PasswordDialog

    if ($null -eq $password) {
        Write-Warning "User cancelled - '$HyperVUsername' was not created."
        Stop-Transcript
        exit 1
    }

    $securePassword = $password | ConvertTo-SecureString -AsPlainText -Force
    Write-Host "Creating local user '$HyperVUsername' ..."
    New-LocalUser -Name $HyperVUsername -Password $securePassword -FullName $HyperVUsername -PasswordNeverExpires:$true
    Add-LocalGroupMember -SID "S-1-5-32-578" -Member $HyperVUsername
    Write-Host "'$HyperVUsername' created and added to Hyper-V Administrators."
}

# -------  Write registry  -------

if (Get-LocalUser -Name $HyperVUsername -ErrorAction SilentlyContinue) {
    try {
        New-ItemProperty -Path $ApplicationKeyPath -Name $SourceFiles -Value "True" -PropertyType String -Force | Out-Null
        Write-Host "Registry value '$SourceFiles' written successfully."
    } catch {
        Write-Warning "Failed to write registry value for '$SourceFiles'."
    }
} else {
    Write-Warning "'$HyperVUsername' not found - registry not updated."
}

Stop-Transcript
exit 0
