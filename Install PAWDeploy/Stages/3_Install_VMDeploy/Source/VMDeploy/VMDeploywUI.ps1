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

#Get Branding
# Branding.xml is written by the installer (Stage 3) from ProductName/BrandingLogo in Settings.psm1.
# These defaults are what the tool looks like when it is not present.
$BrandProductName = "Privileged Access Workstation"
$BrandLogo        = "PAWDeploy.png"
$BrandingFile     = "$RootFolder\Branding.xml"
if(Test-Path -Path $BrandingFile){
    try{
        [XML]$BrandingXML = Get-Content -Path $BrandingFile -Raw
        if($BrandingXML.Branding.ProductName){ $BrandProductName = $BrandingXML.Branding.ProductName }
        if($BrandingXML.Branding.Logo){ $BrandLogo = $BrandingXML.Branding.Logo }
    }
    catch{
        Write-Warning "Could not read $BrandingFile ($($_.Exception.Message)) - using the default branding."
    }
}

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
        [bool]$SkipPublisherCheck = $false,
        [string]$Version = ''
    )
    if(-not $DisplayName){ $DisplayName = $Key }
    $Item = New-Object PSObject -Property @{
        Id                 = $Key
        Name               = $Key
        Kind               = $Kind
        DisplayName        = $DisplayName
        Description        = $Description
        SkipPublisherCheck = $SkipPublisherCheck
        Version            = $Version
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
        -SkipPublisherCheck ($Node.GetAttribute('SkipPublisherCheck') -eq 'True') `
        -Version $Node.GetAttribute('Version')
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
$Form.Text            = "$BrandProductName deployment tool"
$Form.Font            = $Font
$Form.StartPosition   = 'CenterScreen'
$Form.FormBorderStyle = 'FixedDialog'
$Form.MaximizeBox     = $false
$Form.TopMost         = $false

# ── Header ──────────────────────────────────────────────────
$PictureBox1               = New-Control -Type PictureBox -X 16 -Y 10 -Width 64 -Height 64 -Parent $Form
$PictureBox1.ImageLocation = "$RootFolder\Images\$BrandLogo"
$PictureBox1.SizeMode      = [System.Windows.Forms.PictureBoxSizeMode]::Zoom

$TitleLabel      = New-Control -Type Label -X 92 -Y 14 -Width 880 -Height 30 -Text "$BrandProductName deployment" -Parent $Form
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
        $VersionText = if($Item.Version){ "version $($Item.Version)" } else { "latest version" }
        [void]$Lines.Add("Installed for all users, $VersionText" + $(if($Item.SkipPublisherCheck){ " (publisher check skipped)" }))
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

# Input validation for everything that gets passed to VMDeploy.ps1 - besides catching typos,
# this is what stands between a text box and a process argument, so it also closes the command
# injection path a bare interpolated Start-Process command line used to have (see
# docs/security/SECURITY-REVIEW.md finding 1).
Function Test-VMDeployVMName
{
    param([string]$Value)
    return ($Value -match '^[A-Za-z0-9-]{1,62}$')
}

Function Test-VMDeployHostOrIP
{
    # 'DHCP' or a dotted-quad IPv4 address.
    param([string]$Value)
    return ($Value -eq 'DHCP' -or $Value -match '^\d{1,3}(\.\d{1,3}){3}$')
}

Function Test-VMDeploySubnetPrefix
{
    # 'DHCP' or a CIDR prefix length (0-32).
    param([string]$Value)
    return ($Value -eq 'DHCP' -or $Value -match '^(3[0-2]|[12]?\d)$')
}

Function Test-VMDeployVlanId
{
    # Empty (untagged) or a numeric VLAN id.
    param([string]$Value)
    return ([string]::IsNullOrWhiteSpace($Value) -or $Value -match '^\d{1,4}$')
}

Function Test-VMDeployDomainAccount
{
    # DOMAIN\user, user@domain, or a bare username - no shell metacharacters.
    param([string]$Value)
    return ($Value -match '^[A-Za-z0-9 ._-]+([\\@][A-Za-z0-9 ._-]+)?$')
}

Function OkButtonSelected
{
    $Template = $($TemplateListbox.SelectedItem)
    if(-not $Template){ Show-BuildError -Message "Select a template first." -Control $TemplateListbox; return }
    if(-not $VMnameTextBox.Text.Trim()){ Show-BuildError -Message "Enter a VM name." -Control $VMnameTextBox; return }
    if(-not (Test-VMDeployVMName $VMnameTextBox.Text.Trim())){ Show-BuildError -Message "VM name may only contain letters, digits and hyphens." -Control $VMnameTextBox; return }
    if(-not $LPasswordTextBox.Text){ Show-BuildError -Message "Enter the local administrator password for the VM." -Control $LPasswordTextBox; return }
    if($DJANameTextBox.Enabled){
        if(-not $DJANameTextBox.Text.Trim()){ Show-BuildError -Message "Enter the domain account used to join the domain." -Control $DJANameTextBox; return }
        if(-not (Test-VMDeployDomainAccount $DJANameTextBox.Text.Trim())){ Show-BuildError -Message "Domain account contains characters that are not allowed." -Control $DJANameTextBox; return }
        if(-not $DJAPasswordTextBox.Text){ Show-BuildError -Message "Enter the password for the domain account." -Control $DJAPasswordTextBox; return }
    }
    if(-not (Test-VMDeployHostOrIP $IPAddressTextBox.Text.Trim())){ Show-BuildError -Message "IP address must be 'DHCP' or a valid IPv4 address." -Control $IPAddressTextBox; return }
    if(-not (Test-VMDeployHostOrIP $GatewayTextBox.Text.Trim())){ Show-BuildError -Message "Gateway must be 'DHCP' or a valid IPv4 address." -Control $GatewayTextBox; return }
    if(-not (Test-VMDeployHostOrIP $DNS1TextBox.Text.Trim())){ Show-BuildError -Message "DNS 1 must be 'DHCP' or a valid IPv4 address." -Control $DNS1TextBox; return }
    if(-not (Test-VMDeployHostOrIP $DNS2TextBox.Text.Trim())){ Show-BuildError -Message "DNS 2 must be 'DHCP' or a valid IPv4 address." -Control $DNS2TextBox; return }
    if(-not (Test-VMDeploySubnetPrefix $SubnetTextBox.Text.Trim())){ Show-BuildError -Message "Subnet prefix must be 'DHCP' or 0-32." -Control $SubnetTextBox; return }
    if(-not (Test-VMDeployVlanId $VlanTextBox.Text.Trim())){ Show-BuildError -Message "VLAN ID must be numeric." -Control $VlanTextBox; return }

    $result.ForeColor = $MutedColor
    $result.Text = "Starting the build..."

    $VMname = $VMnameTextBox.Text.Trim()
    $OSDAdapter0IPAddressList = $($IPAddressTextBox.Text.Trim())
    $OSDAdapter0Gateways = $($GatewayTextBox.Text.Trim())
    $OSDAdapter0DNS1 = $($DNS1TextBox.Text.Trim())
    $OSDAdapter0DNS2 = $($DNS2TextBox.Text.Trim())
    $OSDAdapter0SubnetMaskPrefix = $($SubnetTextBox.Text.Trim())
    $AdminPassword = $($LPasswordTextBox.text)
    $DomainAdmin = $($DJANameTextBox.Text.Trim())
    $DomainAdminPassword = $($DJAPasswordTextBox.text)
    $vlanid = $($VlanTextBox.Text.Trim())

    # Selected apps, modules and downloads (packages expanded, duplicates removed)
    $Selection = Get-Selection
    $WingetApps = (@($Selection.Apps | ForEach-Object { $_.Id }) -join ',')
    $PSModules = (@($Selection.Modules | ForEach-Object { if($_.Version){ "$($_.Name)@$($_.Version)" } else { $_.Name } }) -join ',')
    $PSModulesSkipPublisherCheck = (@($Selection.Modules | Where-Object { $_.SkipPublisherCheck } | ForEach-Object { $_.Name }) -join ',')
    $Downloads = @($Selection.Downloads)

    # Everything from here on can fail (disk full, DPAPI unavailable, Export-Clixml denied,
    # Start-Process denied, ...). A PowerShell Windows Forms click handler routinely swallows an
    # unhandled exception instead of showing it, which is exactly what made a launch failure look
    # like "Build just closes, no error, no log" - catch it ALL explicitly (everything below is
    # inside the try, including building $DataToExport - an earlier version of this fix left that
    # construction outside the try, so its own errors were never actually caught) and show it
    # instead of letting the form vanish silently.
    try {
        # AdminPassword/DomainAdminPassword are DPAPI-encrypted (bound to this user+machine) before
        # being written to disk, instead of as literal readable text - see
        # docs/security/SECURITY-REVIEW.md finding 6. Uses System.Security.Cryptography.ProtectedData
        # directly (plain .NET assembly loading via Add-Type) rather than the SecureString type or
        # the ConvertTo-SecureString cmdlet: both of those - along with Export-Clixml's special
        # SecureString serialization - ultimately depend on the Microsoft.PowerShell.Security
        # PowerShell module, which can fail to autoload on a locked-down host (confusingly, a
        # different thing from the System.Security .NET assembly used here). This path never
        # touches that module at all.
        Add-Type -AssemblyName System.Security -ErrorAction Stop
        Function Protect-VMDeployString
        {
            param([string]$PlainText)
            if([string]::IsNullOrEmpty($PlainText)){ return "" }
            $Bytes = [System.Text.Encoding]::Unicode.GetBytes($PlainText)
            $Protected = [System.Security.Cryptography.ProtectedData]::Protect($Bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
            return [Convert]::ToBase64String($Protected)
        }
        # EVERYTHING the operator chose or typed travels in this file - nothing of theirs goes on
        # the command line. That is the recommended fix for docs/security/SECURITY-REVIEW.md
        # finding 1 (no user input crosses a command-line boundary, so there is nothing to inject
        # into), and it also sidesteps a Windows PowerShell 5.1 defect: Start-Process
        # -ArgumentList joins array elements with spaces WITHOUT quoting them, so any value
        # containing a space - such as the template name "Windows 11 - WORKGROUP" - arrives at
        # VMDeploy.ps1 split across several arguments and parameter binding fails before that
        # script can run a single line (no window, no transcript, no error anyone can see).
        $DataToExport = @{
            Template=$Template
            VMName=$VMname
            OSDAdapter0IPAddressList=$OSDAdapter0IPAddressList
            OSDAdapter0Gateways=$OSDAdapter0Gateways
            OSDAdapter0DNS1=$OSDAdapter0DNS1
            OSDAdapter0DNS2=$OSDAdapter0DNS2
            OSDAdapter0SubnetMaskPrefix=$OSDAdapter0SubnetMaskPrefix
            VlanID=$(if($vlanid -ne ""){ $vlanid } else { '0' })
            DomainAdmin=$DomainAdmin
            AdminPassword=(Protect-VMDeployString $AdminPassword)
            DomainAdminPassword=(Protect-VMDeployString $DomainAdminPassword)
            WingetApps=$WingetApps
            PSModules=$PSModules
            PSModulesSkipPublisherCheck=$PSModulesSkipPublisherCheck
            Downloads=$Downloads
        }
        $DataToExport | Export-Clixml -Path "$env:TEMP\vmdeploy.xml" -ErrorAction Stop

        $ScriptToRun = "$RootFolder\VMDeploy.ps1"

        # $PSHOME can resolve to a PowerShell 7 App Execution Alias stub under WindowsApps instead of
        # the real Windows PowerShell 5.1 install on some Windows 11 configurations - that stub is not
        # a launchable file, so Start-Process fails immediately with "cannot find the file specified"
        # before VMDeploy.ps1 ever starts (no error surfaced here previously; reproduced directly).
        # Always prefer the real, non-aliasable path; fall back to $PSHOME only if that's ever missing.
        $KnownPowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $PowerShellExe = if(Test-Path $KnownPowerShellExe){ $KnownPowerShellExe } else { Join-Path $PSHOME 'powershell.exe' }
        if(-not (Test-Path $PowerShellExe)){
            throw "Could not find powershell.exe (checked '$KnownPowerShellExe' and '$PSHOME')."
        }

        # A single, explicitly quoted command-line STRING - not an array. Windows PowerShell 5.1's
        # Start-Process joins an -ArgumentList array with spaces and does NOT quote the elements,
        # which corrupts any value containing a space. The only thing interpolated here is the
        # script's own path (derived from this script's location, never operator input), and it is
        # quoted; every operator-supplied value travels in the hand-off file instead.
        $Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -RootFolder NA -DataFromFile' -f $ScriptToRun

        # Record exactly what is being launched, before launching it. If the deployment window ever
        # disappears without explaining itself, this file shows whether the launch was even reached
        # and with what.
        $LaunchLog = "$env:ProgramData\VMDeploy\logs\VMDeploy-launch.log"
        try {
            New-Item -Path (Split-Path $LaunchLog -Parent) -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Add-Content -Path $LaunchLog -Value ("{0}  Launching: {1} {2}" -f (Get-Date -Format o), $PowerShellExe, $Arguments) -ErrorAction Stop
        } catch { }

        Start-Process -FilePath $PowerShellExe -ArgumentList $Arguments -ErrorAction Stop
    }
    catch {
        [void][System.Windows.Forms.MessageBox]::Show(
            "Could not start the build:`r`n`r`n$($_.Exception.Message)",
            "VM Deploy", "OK", "Error")
        Show-BuildError -Message "Build failed to start: $($_.Exception.Message)"
        return
    }
    $Form.close()
}

$DetailsTextBox.Text = "Select a template, then a package, application or module to see what it installs."
$result.Text = "Select a template to start."
[void]$Form.ShowDialog()
