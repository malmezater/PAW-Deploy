#Requires -Version 5.1
<#
.SYNOPSIS
    Stage 2c - Add the signed-in user to Hyper-V Administrators and (optionally)
              create the local "Hypervuser" account.
.NOTES
    Hypervuser needs a password from the operator. When the installer runs as SYSTEM
    (Intune / ConfigMgr) no dialog can be shown, so the account is skipped with a warning
    instead of hanging the installation. Run this script interactively later to create it.
#>

Import-Module "$PSScriptRoot\..\Settings.psm1" -Force
Start-DeployStage -Name "HyperV-Admins" -Title "Stage 2c - Hyper-V Administrators"

$HyperVAdminsSid = "S-1-5-32-578"
$HyperVUsername  = "Hypervuser"
$MinPasswordLen  = 15

function Add-HyperVAdminMember {
    param([Parameter(Mandatory)][string]$Member)
    try {
        Add-LocalGroupMember -SID $HyperVAdminsSid -Member $Member -ErrorAction Stop
        Write-Host "Added '$Member' to Hyper-V Administrators."
    }
    catch [Microsoft.PowerShell.Commands.MemberExistsException] {
        Write-Host "'$Member' is already a member of Hyper-V Administrators."
    }
}

function Read-HyperVUserPassword {
    # Returns a SecureString, or $null when the operator cancels.
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing

    $form = New-Object System.Windows.Forms.Form -Property @{
        Text = "Create Hyper-V User"; Size = New-Object System.Drawing.Size(400, 220)
        StartPosition = "CenterScreen"; FormBorderStyle = "FixedDialog"
        MaximizeBox = $false; MinimizeBox = $false; TopMost = $true
    }
    $newLabel = {
        param($Text, $X, $Y, $W = 80)
        New-Object System.Windows.Forms.Label -Property @{
            Text = $Text; Location = New-Object System.Drawing.Point($X, $Y); Size = New-Object System.Drawing.Size($W, 20)
        }
    }

    $form.Controls.Add((& $newLabel "Username:" 20 20))
    $form.Controls.Add((New-Object System.Windows.Forms.TextBox -Property @{
        Text = $HyperVUsername; ReadOnly = $true; BackColor = [System.Drawing.Color]::LightGray
        Location = New-Object System.Drawing.Point(110, 20); Size = New-Object System.Drawing.Size(250, 20)
    }))
    $form.Controls.Add((& $newLabel "Password:" 20 60))

    $txtPwd = New-Object System.Windows.Forms.TextBox -Property @{
        UseSystemPasswordChar = $true
        Location = New-Object System.Drawing.Point(110, 60); Size = New-Object System.Drawing.Size(250, 20)
    }
    $form.Controls.Add($txtPwd)

    $lblCount = & $newLabel "Characters: 0/$MinPasswordLen (minimum)" 110 90 250
    $lblCount.ForeColor = [System.Drawing.Color]::Red
    $form.Controls.Add($lblCount)
    $txtPwd.Add_TextChanged({
        $lblCount.Text = "Characters: $($txtPwd.Text.Length)/$MinPasswordLen (minimum)"
        $lblCount.ForeColor = if ($txtPwd.Text.Length -ge $MinPasswordLen) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::Red }
    })

    $btnOK = New-Object System.Windows.Forms.Button -Property @{
        Text = "OK"; Location = New-Object System.Drawing.Point(170, 140); Size = New-Object System.Drawing.Size(100, 30)
    }
    $btnOK.Add_Click({
        if ($txtPwd.Text.Length -lt $MinPasswordLen) {
            [void][System.Windows.Forms.MessageBox]::Show("Password must be at least $MinPasswordLen characters!", "Invalid Password", "OK", "Warning")
        } else {
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        }
    })
    $form.Controls.Add($btnOK)
    $form.Controls.Add((New-Object System.Windows.Forms.Button -Property @{
        Text = "Cancel"; DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        Location = New-Object System.Drawing.Point(280, 140); Size = New-Object System.Drawing.Size(100, 30)
    }))

    if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    $secure = ConvertTo-SecureString -String $txtPwd.Text -AsPlainText -Force
    $txtPwd.Clear()
    return $secure
}

# -------  Signed-in user  -------

$signedInUser = (Get-CimInstance -ClassName Win32_ComputerSystem).UserName
if ($signedInUser) {
    try { Add-HyperVAdminMember -Member $signedInUser }
    catch { Write-Warning "Could not add '$signedInUser' to Hyper-V Administrators: $($_.Exception.Message)" }
} else {
    Write-Warning "No signed-in user found - only the Hypervuser account is configured."
}

# -------  Hypervuser account  -------

if (-not $CreateHyperVUser) {
    Write-Host "CreateHyperVUser = `$false - skipping '$HyperVUsername'."
}
elseif (Get-LocalUser -Name $HyperVUsername -ErrorAction SilentlyContinue) {
    Write-Host "'$HyperVUsername' already exists."
    try { Add-HyperVAdminMember -Member $HyperVUsername } catch { Write-Warning $_.Exception.Message }
}
elseif (-not (Test-InteractiveSession)) {
    Write-Warning "Running non-interactively (e.g. as SYSTEM) - '$HyperVUsername' cannot be created because no password prompt can be shown. Run Add-HyperVAdmin.ps1 interactively to create it."
}
else {
    $password = Read-HyperVUserPassword
    if (-not $password) {
        Write-Warning "Cancelled - '$HyperVUsername' was not created."
        exit (Stop-DeployStage $ExitFailure)
    }
    try {
        New-LocalUser -Name $HyperVUsername -Password $password -FullName $HyperVUsername -PasswordNeverExpires:$true -ErrorAction Stop | Out-Null
        Add-HyperVAdminMember -Member $HyperVUsername
        Write-Host "'$HyperVUsername' created."
    }
    catch {
        Write-Warning "Could not create '$HyperVUsername': $($_.Exception.Message)"
        exit (Stop-DeployStage $ExitFailure)
    }
}

Set-DeployStamp -Name "HyperV-Admins" -Value "True"
exit (Stop-DeployStage $ExitSuccess)
