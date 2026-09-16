<#
 # VMDeploywUI.ps1 - Privileged Access Workstation deployment tool (GUI)
 #
 # Pick a template, adjust the VM settings and choose what to install:
 #   Packages            bundles of apps, modules and downloads   (Packages\<Name>.xml)
 #   Applications        winget packages                          (Apps.xml, template <AppProfile>)
 #   PowerShell modules  PowerShell Gallery modules               (Modules.xml, template <ModuleProfile>)
 #
 # Packages are referenced with <Package Name="..." Default="True|False" /> in the app and/or module
 # profile of the template. They are listed once in the Packages box, whichever profile references them.
 # Build hands the selection to VMDeploy.ps1.
#>

$DLL = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
Add-Type -MemberDefinition $DLL -name NativeMethods -namespace Win32
$Process = (Get-Process PowerShell | Where-Object MainWindowTitle -like '*VM Deploy*').MainWindowHandle
# Minimize window
#[Win32.NativeMethods]::ShowWindowAsync($Process, 2)

#Get Env:
$RootFolder = $MyInvocation.MyCommand.Path | Split-Path -Parent

#Get Data
$XMLDatafile = "$RootFolder\Config.XML"
[XML]$XMLData = Get-Content -Path "$XMLDatafile"

#Get Templates
$Templates = $XMLData.Settings.Templates.Template | Where-Object Active -EQ $True
$TemplatesSelection = $Templates.name

#Get App Profiles
$AppsXMLFile = "$RootFolder\Apps.XML"
if(Test-Path -Path $AppsXMLFile){
    [XML]$AppsXMLData = Get-Content -Path $AppsXMLFile
}
else{
    $AppsXMLData = $null
}

#Get Module Profiles
$ModulesXMLFile = "$RootFolder\Modules.XML"
if(Test-Path -Path $ModulesXMLFile){
    [XML]$ModulesXMLData = Get-Content -Path $ModulesXMLFile
}
else{
    $ModulesXMLData = $null
}

#region Selection helpers {

$PackagesFolder = "$RootFolder\Packages"
$PackageCache = @{}

Function New-CheckListItem
{
    # An app or module entry for a CheckedListBox.
    param(
        [string]$Key,
        [string]$DisplayName,
        [ValidateSet('App','Module')][string]$Kind,
        [string]$Description,
        [bool]$SkipPublisherCheck = $false
    )
    if(-not $DisplayName){ $DisplayName = $Key }
    $Item = New-Object PSObject -Property @{
        Id                 = $Key
        Name               = $Key
        Kind               = $Kind
        DisplayName        = $DisplayName
        Description        = $Description
        SkipPublisherCheck = $SkipPublisherCheck
    }
    # Override ToString so the CheckedListBox shows the friendly name
    $Item | Add-Member -MemberType ScriptMethod -Name ToString -Value { $this.DisplayName } -Force
    return $Item
}

Function New-ItemFromNode
{
    # <App Id DisplayName Description /> or <Module Name DisplayName Description SkipPublisherCheck />
    param($Node, [ValidateSet('App','Module')][string]$Kind)
    $KeyAttribute = if($Kind -eq 'App'){ 'Id' } else { 'Name' }
    New-CheckListItem -Key $Node.GetAttribute($KeyAttribute) -Kind $Kind `
        -DisplayName $Node.GetAttribute('DisplayName') `
        -Description $Node.GetAttribute('Description') `
        -SkipPublisherCheck ($Node.GetAttribute('SkipPublisherCheck') -eq 'True')
}

Function Get-VMDeployPackage
{
    # Reads Packages\<Name>.xml into an item with its apps, modules and downloads. $null if missing.
    param([string]$Name)
    if($PackageCache.ContainsKey($Name)){ return $PackageCache[$Name] }

    $Result = $null
    $PackageFile = Join-Path $PackagesFolder "$Name.xml"
    if(Test-Path -Path $PackageFile){
        [XML]$PackageXML = Get-Content -Path $PackageFile
        $Node = $PackageXML.Package
        $Apps = @(); $Modules = @(); $Downloads = @()
        foreach($Member in $Node.ChildNodes){
            if($Member.NodeType -ne [System.Xml.XmlNodeType]::Element){ continue }
            switch($Member.LocalName){
                'App'      { $Apps    += New-ItemFromNode -Node $Member -Kind App }
                'Module'   { $Modules += New-ItemFromNode -Node $Member -Kind Module }
                'Download' { $Downloads += @{
                                 Name        = $Member.GetAttribute('Name')
                                 Url         = $Member.GetAttribute('Url')
                                 Destination = $Member.GetAttribute('Destination')
                             } }
            }
        }

        $DisplayName = $Node.GetAttribute('DisplayName')
        if(-not $DisplayName){ $DisplayName = $Name }
        $Counts = @()
        if($Apps.Count)     { $Counts += "{0} app{1}"      -f $Apps.Count,      $(if($Apps.Count -ne 1){ 's' }) }
        if($Modules.Count)  { $Counts += "{0} module{1}"   -f $Modules.Count,   $(if($Modules.Count -ne 1){ 's' }) }
        if($Downloads.Count){ $Counts += "{0} download{1}" -f $Downloads.Count, $(if($Downloads.Count -ne 1){ 's' }) }

        $Result = New-Object PSObject -Property @{
            Name        = $Name
            DisplayName = $DisplayName
            Summary     = ($Counts -join ', ')
            Description = $Node.GetAttribute('Description')
            Apps        = $Apps
            Modules     = $Modules
            Downloads   = $Downloads
        }
        $Result | Add-Member -MemberType ScriptMethod -Name ToString -Value {
            if($this.Summary){ "{0}  ({1})" -f $this.DisplayName, $this.Summary } else { $this.DisplayName }
        } -Force
    }
    $PackageCache[$Name] = $Result
    return $Result
}

Function Get-ProfileItems
{
    # Returns @{ Item; Default } for every <App> or <Module> in a profile (packages are handled separately).
    param(
        $ProfileNode,
        [ValidateSet('App','Module')][string]$ItemType
    )
    if(-not $ProfileNode){ return }
    foreach($Node in $ProfileNode.ChildNodes){
        if($Node.NodeType -ne [System.Xml.XmlNodeType]::Element -or $Node.LocalName -ne $ItemType){ continue }
        $Item = New-ItemFromNode -Node $Node -Kind $ItemType
        [pscustomobject]@{ Item = $Item; Default = ($Node.GetAttribute('Default') -eq 'True') }
    }
}

Function Get-ProfilePackages
{
    # Returns @{ Item; Default } for every <Package> referenced in the given profiles, once per package.
    # A package is pre-checked when any profile references it with Default="True".
    param([object[]]$ProfileNodes)
    $Order = New-Object System.Collections.ArrayList
    $Defaults = @{}
    foreach($ProfileNode in @($ProfileNodes | Where-Object { $_ })){
        foreach($Node in $ProfileNode.ChildNodes){
            if($Node.NodeType -ne [System.Xml.XmlNodeType]::Element -or $Node.LocalName -ne 'Package'){ continue }
            $Name = $Node.GetAttribute('Name')
            if(-not $Name){ continue }
            if(-not $Defaults.ContainsKey($Name)){ [void]$Order.Add($Name); $Defaults[$Name] = $false }
            if($Node.GetAttribute('Default') -eq 'True'){ $Defaults[$Name] = $true }
        }
    }
    foreach($Name in $Order){
        $Package = Get-VMDeployPackage -Name $Name
        if(-not $Package){
            Write-Warning "Package '$Name' not found in $PackagesFolder"
            continue
        }
        [pscustomobject]@{ Item = $Package; Default = $Defaults[$Name] }
    }
}

Function Select-UniqueItems
{
    # Removes duplicates by Name, first occurrence wins.
    param([object[]]$Items)
    $Seen = @{}
    foreach($Item in $Items){
        if(-not $Item -or -not $Item.Name -or $Seen.ContainsKey($Item.Name)){ continue }
        $Seen[$Item.Name] = $true
        $Item
    }
}

Function Select-UniqueDownloads
{
    # One download per destination folder.
    param([object[]]$Downloads)
    $Seen = @{}
    foreach($Download in $Downloads){
        if(-not $Download -or -not $Download.Url -or -not $Download.Destination){ continue }
        $Key = $Download.Destination.TrimEnd('\').ToLowerInvariant()
        if($Seen.ContainsKey($Key)){ continue }
        $Seen[$Key] = $true
        $Download
    }
}

#endregion Selection helpers }

#Generate Randomname
$chars = [char[]]"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
$RandomName = [string](($chars[0..25]|Get-Random)+(($chars|Get-Random -Count 3) -join ""))

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

#region begin GUI{

$Font      = New-Object System.Drawing.Font('Segoe UI', 9)
$FontBold  = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$FontTitle = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
$MutedColor = [System.Drawing.Color]::FromArgb(96, 96, 96)

Function New-Control
{
    param([string]$Type, [int]$X, [int]$Y, [int]$Width, [int]$Height, [string]$Text = '', $Parent)
    $Control = New-Object "System.Windows.Forms.$Type"
    $Control.Location = New-Object System.Drawing.Point($X, $Y)
    $Control.Size     = New-Object System.Drawing.Size($Width, $Height)
    $Control.Font     = $Font
    if($Text){ $Control.Text = $Text }
    if($Parent){ [void]$Parent.Controls.Add($Control) }
    return $Control
}

Function New-Field
{
    # Label + text box on one row inside a group box. Returns the text box.
    param($Parent, [string]$Label, [int]$Y, [string]$Value = '', [switch]$Password)
    [void](New-Control -Type Label -X 12 -Y ($Y + 3) -Width 110 -Height 20 -Text $Label -Parent $Parent)
    $TextBox = New-Control -Type TextBox -X 124 -Y $Y -Width 236 -Height 23 -Parent $Parent
    $TextBox.Text = $Value
    if($Password){ $TextBox.UseSystemPasswordChar = $true }
    return $TextBox
}

$Form                 = New-Object System.Windows.Forms.Form
$Form.ClientSize      = New-Object System.Drawing.Size(1000, 660)
$Form.Text            = "Privileged Access Workstation deployment tool"
$Form.Font            = $Font
$Form.StartPosition   = 'CenterScreen'
$Form.FormBorderStyle = 'FixedDialog'
$Form.MaximizeBox     = $false
$Form.TopMost         = $false

# ── Header ──────────────────────────────────────────────────
$PictureBox1               = New-Control -Type PictureBox -X 16 -Y 10 -Width 64 -Height 64 -Parent $Form
$PictureBox1.ImageLocation = "$RootFolder\Images\PAWDeploy.png"
$PictureBox1.SizeMode      = [System.Windows.Forms.PictureBoxSizeMode]::Zoom

$TitleLabel      = New-Control -Type Label -X 92 -Y 14 -Width 880 -Height 30 -Text "Privileged Access Workstation deployment" -Parent $Form
$TitleLabel.Font = $FontTitle
$SubtitleLabel   = New-Control -Type Label -X 94 -Y 46 -Width 880 -Height 20 -Parent $Form `
                     -Text "Select a template, adjust the virtual machine settings and choose what to install."
$SubtitleLabel.ForeColor = $MutedColor

# ── Left: virtual machine ───────────────────────────────────
$VMGroup = New-Control -Type GroupBox -X 16 -Y 84 -Width 372 -Height 520 -Text "Virtual machine" -Parent $Form

[void](New-Control -Type Label -X 12 -Y 24 -Width 340 -Height 20 -Text "Template" -Parent $VMGroup)
$TemplateListbox = New-Control -Type ListBox -X 12 -Y 44 -Width 348 -Height 84 -Parent $VMGroup
$TemplateListbox.IntegralHeight = $false

$VMnameTextBox      = New-Field -Parent $VMGroup -Label "VM name"        -Y 140
$LPasswordTextBox   = New-Field -Parent $VMGroup -Label "Local password" -Y 170 -Password
$DJANameTextBox     = New-Field -Parent $VMGroup -Label "Domain account" -Y 200
$DJAPasswordTextBox = New-Field -Parent $VMGroup -Label "Domain password" -Y 230 -Password

$NetworkLabel      = New-Control -Type Label -X 12 -Y 272 -Width 340 -Height 20 -Text "Network  (DHCP or static values)" -Parent $VMGroup
$NetworkLabel.Font = $FontBold

$IPAddressTextBox = New-Field -Parent $VMGroup -Label "IP address" -Y 296 -Value 'DHCP'
$SubnetTextBox    = New-Field -Parent $VMGroup -Label "Subnet prefix" -Y 326 -Value 'DHCP'
$GatewayTextBox   = New-Field -Parent $VMGroup -Label "Gateway"    -Y 356 -Value 'DHCP'
$DNS1TextBox      = New-Field -Parent $VMGroup -Label "DNS 1"      -Y 386 -Value 'DHCP'
$DNS2TextBox      = New-Field -Parent $VMGroup -Label "DNS 2"      -Y 416 -Value 'DHCP'
$VlanTextBox      = New-Field -Parent $VMGroup -Label "VLAN ID"    -Y 446

$TemplateInfoLabel           = New-Control -Type Label -X 12 -Y 482 -Width 348 -Height 30 -Parent $VMGroup
$TemplateInfoLabel.ForeColor = $MutedColor

# ── Right: packages ─────────────────────────────────────────
$PackagesGroup = New-Control -Type GroupBox -X 404 -Y 84 -Width 284 -Height 172 -Text "Packages" -Parent $Form

$PackagesCheckedListBox                = New-Control -Type CheckedListBox -X 12 -Y 24 -Width 260 -Height 136 -Parent $PackagesGroup
$PackagesCheckedListBox.CheckOnClick   = $true
$PackagesCheckedListBox.IntegralHeight = $false

# ── Right: details for the selected package, application or module ──
$DetailsGroup = New-Control -Type GroupBox -X 700 -Y 84 -Width 284 -Height 172 -Text "Details" -Parent $Form

$DetailsTextBox             = New-Control -Type TextBox -X 12 -Y 24 -Width 260 -Height 136 -Parent $DetailsGroup
$DetailsTextBox.Multiline   = $true
$DetailsTextBox.ReadOnly    = $true
$DetailsTextBox.ScrollBars  = 'Vertical'
$DetailsTextBox.BorderStyle = 'None'
$DetailsTextBox.BackColor   = $Form.BackColor

# ── Right: applications ─────────────────────────────────────
$AppsGroup = New-Control -Type GroupBox -X 404 -Y 264 -Width 284 -Height 340 -Text "Applications (winget)" -Parent $Form
$AppsCheckedListBox                = New-Control -Type CheckedListBox -X 12 -Y 24 -Width 260 -Height 304 -Parent $AppsGroup
$AppsCheckedListBox.CheckOnClick   = $true
$AppsCheckedListBox.IntegralHeight = $false

# ── Right: PowerShell modules ───────────────────────────────
$ModulesGroup = New-Control -Type GroupBox -X 700 -Y 264 -Width 284 -Height 340 -Text "PowerShell modules (AllUsers, latest)" -Parent $Form
$ModulesCheckedListBox                = New-Control -Type CheckedListBox -X 12 -Y 24 -Width 260 -Height 304 -Parent $ModulesGroup
$ModulesCheckedListBox.CheckOnClick   = $true
$ModulesCheckedListBox.IntegralHeight = $false

# ── Footer ──────────────────────────────────────────────────
$result           = New-Control -Type Label -X 16 -Y 620 -Width 772 -Height 30 -Parent $Form
$result.TextAlign = 'MiddleLeft'
$result.ForeColor = $MutedColor

$OkButton     = New-Control -Type Button -X 800 -Y 618 -Width 88 -Height 32 -Text "Build" -Parent $Form
$CancelButton = New-Control -Type Button -X 896 -Y 618 -Width 88 -Height 32 -Text "Close" -Parent $Form
$Form.AcceptButton = $OkButton
$Form.CancelButton = $CancelButton

foreach($item in $TemplatesSelection){
    [void] $TemplateListbox.Items.Add($item)
}

#region gui events {
$OkButton.Add_Click({ OkButtonSelected })
$CancelButton.Add_Click({ CancelButtonSelected })
$TemplateListbox.Add_SelectedValueChanged({ TemplateListboxChanged })
$PackagesCheckedListBox.Add_SelectedIndexChanged({ Show-Details -Item $PackagesCheckedListBox.SelectedItem })
$AppsCheckedListBox.Add_SelectedIndexChanged({ Show-Details -Item $AppsCheckedListBox.SelectedItem })
$ModulesCheckedListBox.Add_SelectedIndexChanged({ Show-Details -Item $ModulesCheckedListBox.SelectedItem })
# ItemCheck fires before the check state changes - update the summary once it has been applied
$PackagesCheckedListBox.Add_ItemCheck({ $Form.BeginInvoke([Action]{ Update-SelectionSummary }) | Out-Null })
$AppsCheckedListBox.Add_ItemCheck({ $Form.BeginInvoke([Action]{ Update-SelectionSummary }) | Out-Null })
$ModulesCheckedListBox.Add_ItemCheck({ $Form.BeginInvoke([Action]{ Update-SelectionSummary }) | Out-Null })
#endregion events }

#endregion GUI }

Function Show-Details
{
    # Short description of the selected package, application or module.
    param($Item)
    if(-not $Item){
        $DetailsTextBox.Text = "Select a package, application or module to see what it installs."
        return
    }
    $Lines = New-Object System.Collections.ArrayList
    if($Item.PSObject.Properties['Apps']){
        # Package: just what gets installed
        [void]$Lines.Add($Item.DisplayName)
        if($Item.Apps.Count)     { [void]$Lines.Add("Apps: " + ((@($Item.Apps) | ForEach-Object { $_.DisplayName }) -join ', ')) }
        if($Item.Modules.Count)  { [void]$Lines.Add("Modules: " + ((@($Item.Modules) | ForEach-Object { $_.Name }) -join ', ')) }
        foreach($Download in @($Item.Downloads)){ [void]$Lines.Add("Download: $($Download.Name) -> $($Download.Destination)") }
    }
    elseif($Item.Kind -eq 'App'){
        [void]$Lines.Add($Item.DisplayName)
        if($Item.Description){ [void]$Lines.Add($Item.Description) }
        [void]$Lines.Add('')
        [void]$Lines.Add("Source: winget community repository")
        [void]$Lines.Add("Id: $($Item.Id)")
        [void]$Lines.Add("Installed machine-wide (falls back to user scope)")
    }
    else{
        [void]$Lines.Add($Item.DisplayName)
        if($Item.Description){ [void]$Lines.Add($Item.Description) }
        [void]$Lines.Add('')
        [void]$Lines.Add("Source: PowerShell Gallery")
        [void]$Lines.Add("https://www.powershellgallery.com/packages/$($Item.Name)")
        [void]$Lines.Add("Installed for all users, latest version" + $(if($Item.SkipPublisherCheck){ " (publisher check skipped)" }))
    }
    $DetailsTextBox.Text = ($Lines -join "`r`n")
}

Function Get-Selection
{
    # Everything that will be installed: checked packages expanded, duplicates removed.
    $Packages = @($PackagesCheckedListBox.CheckedItems)
    $Apps     = @(Select-UniqueItems -Items (@($AppsCheckedListBox.CheckedItems) + @($Packages | ForEach-Object { $_.Apps })))
    $Modules  = @(Select-UniqueItems -Items (@($ModulesCheckedListBox.CheckedItems) + @($Packages | ForEach-Object { $_.Modules })))
    $Downloads = @(Select-UniqueDownloads -Downloads @($Packages | ForEach-Object { $_.Downloads }))
    [pscustomobject]@{ Packages = $Packages; Apps = $Apps; Modules = $Modules; Downloads = $Downloads }
}

Function Update-SelectionSummary
{
    $Selection = Get-Selection
    $result.Text = "Will install: {0} package(s), {1} application(s), {2} module(s), {3} download(s)" -f `
        $Selection.Packages.Count, $Selection.Apps.Count, $Selection.Modules.Count, $Selection.Downloads.Count
}

Function TemplateListboxChanged
{
    $SelectedTemplate = $($TemplateListbox.SelectedItem)
    $TemplateData = $XMLData.Settings.Templates.Template | Where-Object Name -EQ $SelectedTemplate

    $VMnameTextBox.Text = $env:COMPUTERNAME + "-" + $TemplateData.NameSuffix + $RandomName
    $VlanTextBox.Text = $TemplateData.vlanid
    $TemplateInfoLabel.Text = "{0} · {1} vCPU · {2} MB memory" -f $TemplateData.DomainOrWorkGroup, $TemplateData.NoCPU, $TemplateData.Memory

    # Domain account and password are only used when the template joins a domain
    $IsDomain = ($TemplateData.DomainOrWorkGroup -eq 'Domain')
    $DJANameTextBox.Enabled = $IsDomain
    $DJAPasswordTextBox.Enabled = $IsDomain
    if(-not $IsDomain){ $DJANameTextBox.Text = ''; $DJAPasswordTextBox.Text = '' }

    $AppProfile = $null
    if($TemplateData.AppProfile -and $AppsXMLData){
        $AppProfile = $AppsXMLData.AppProfiles.Profile | Where-Object Name -EQ $TemplateData.AppProfile
    }
    $ModProfile = $null
    if($TemplateData.ModuleProfile -and $ModulesXMLData){
        $ModProfile = $ModulesXMLData.ModuleProfiles.Profile | Where-Object Name -EQ $TemplateData.ModuleProfile
    }

    # Packages (from both profiles)
    $PackagesCheckedListBox.Items.Clear()
    foreach($Entry in (Get-ProfilePackages -ProfileNodes @($AppProfile, $ModProfile))){
        [void]$PackagesCheckedListBox.Items.Add($Entry.Item, $Entry.Default)
    }
    $PackagesCheckedListBox.Enabled = ($PackagesCheckedListBox.Items.Count -gt 0)
    $PackagesGroup.Text = if($PackagesCheckedListBox.Items.Count -gt 0){ "Packages" } else { "Packages (none for this template)" }
    Show-Details -Item $null

    # Applications
    $AppsCheckedListBox.Items.Clear()
    foreach($Entry in (Get-ProfileItems -ProfileNode $AppProfile -ItemType App)){
        [void]$AppsCheckedListBox.Items.Add($Entry.Item, $Entry.Default)
    }
    $AppsCheckedListBox.Enabled = [bool]$AppProfile
    $AppsGroup.Text = if(-not $TemplateData.AppProfile){ "Applications (none for this template)" }
                      elseif(-not $AppProfile){ "Applications (profile '$($TemplateData.AppProfile)' not found)" }
                      else{ "Applications - $($TemplateData.AppProfile)" }

    # PowerShell modules
    $ModulesCheckedListBox.Items.Clear()
    foreach($Entry in (Get-ProfileItems -ProfileNode $ModProfile -ItemType Module)){
        [void]$ModulesCheckedListBox.Items.Add($Entry.Item, $Entry.Default)
    }
    $ModulesCheckedListBox.Enabled = [bool]$ModProfile
    $ModulesGroup.Text = if(-not $TemplateData.ModuleProfile){ "PowerShell modules (none for this template)" }
                         elseif(-not $ModProfile){ "PowerShell modules (profile '$($TemplateData.ModuleProfile)' not found)" }
                         else{ "PowerShell modules - $($TemplateData.ModuleProfile)" }

    Update-SelectionSummary
}

function CancelButtonSelected()
{
    $Form.close()
}

Function Show-BuildError
{
    param([string]$Message, $Control)
    $result.ForeColor = [System.Drawing.Color]::Firebrick
    $result.Text = $Message
    if($Control){ [void]$Control.Focus() }
}

Function OkButtonSelected
{
    $Template = $($TemplateListbox.SelectedItem)
    if(-not $Template){ Show-BuildError -Message "Select a template first." -Control $TemplateListbox; return }
    if(-not $VMnameTextBox.Text.Trim()){ Show-BuildError -Message "Enter a VM name." -Control $VMnameTextBox; return }
    if(-not $LPasswordTextBox.Text){ Show-BuildError -Message "Enter the local administrator password for the VM." -Control $LPasswordTextBox; return }
    if($DJANameTextBox.Enabled){
        if(-not $DJANameTextBox.Text.Trim()){ Show-BuildError -Message "Enter the domain account used to join the domain." -Control $DJANameTextBox; return }
        if(-not $DJAPasswordTextBox.Text){ Show-BuildError -Message "Enter the password for the domain account." -Control $DJAPasswordTextBox; return }
    }
    $result.ForeColor = $MutedColor
    $result.Text = "Starting the build..."

    $VMname = $VMnameTextBox.Text
    $OSDAdapter0IPAddressList = $($IPAddressTextBox.Text)
    $OSDAdapter0Gateways = $($GatewayTextBox.Text)
    $OSDAdapter0DNS1 = $($DNS1TextBox.Text)
    $OSDAdapter0DNS2 = $($DNS2TextBox.Text)
    $OSDAdapter0SubnetMaskPrefix = $($SubnetTextBox.Text)
    $AdminPassword = $($LPasswordTextBox.text)
    $DomainAdmin = $($DJANameTextBox.Text)
    $DomainAdminPassword = $($DJAPasswordTextBox.text)
    $vlanid = $($VlanTextBox.Text)

    # Selected apps, modules and downloads (packages expanded, duplicates removed)
    $Selection = Get-Selection
    $WingetApps = (@($Selection.Apps | ForEach-Object { $_.Id }) -join ',')
    $PSModules = (@($Selection.Modules | ForEach-Object { $_.Name }) -join ',')
    $PSModulesSkipPublisherCheck = (@($Selection.Modules | Where-Object { $_.SkipPublisherCheck } | ForEach-Object { $_.Name }) -join ',')
    $Downloads = @($Selection.Downloads)

    $DataToExport = @{
        AdminPassword=$AdminPassword
        DomainAdminPassword=$DomainAdminPassword
        WingetApps=$WingetApps
        PSModules=$PSModules
        PSModulesSkipPublisherCheck=$PSModulesSkipPublisherCheck
        Downloads=$Downloads
    }
    $DataToExport | Export-Clixml -Path "$env:TEMP\vmdeploy.xml"

    if($DomainAdmin -eq ""){
        $ScriptArguments = "-Template `'$Template`' -RootFolder NA -VMName $VMName -OSDAdapter0IPAddressList $OSDAdapter0IPAddressList -OSDAdapter0Gateways $OSDAdapter0Gateways -OSDAdapter0DNS1 $OSDAdapter0DNS1 -OSDAdapter0DNS2 $OSDAdapter0DNS2 -OSDAdapter0SubnetMaskPrefix $OSDAdapter0SubnetMaskPrefix -vlanid $vlanid -DataFromFile"
    }
    else{
        $ScriptArguments = "-Template `'$Template`' -RootFolder NA -VMName $VMName -OSDAdapter0IPAddressList $OSDAdapter0IPAddressList -OSDAdapter0Gateways $OSDAdapter0Gateways -OSDAdapter0DNS1 $OSDAdapter0DNS1 -OSDAdapter0DNS2 $OSDAdapter0DNS2 -OSDAdapter0SubnetMaskPrefix $OSDAdapter0SubnetMaskPrefix -vlanid $vlanid -DomainAdmin $DomainAdmin -DataFromFile"
    }

    $ScriptToRun = "$RootFolder\VMDeploy.ps1"
    $Argument = "$ScriptToRun $ScriptArguments"

    Start-Process PowerShell -ArgumentList "$Argument" -Verbose
    $Form.close()
}

$DetailsTextBox.Text = "Select a template, then a package, application or module to see what it installs."
$result.Text = "Select a template to start."
[void]$Form.ShowDialog()
