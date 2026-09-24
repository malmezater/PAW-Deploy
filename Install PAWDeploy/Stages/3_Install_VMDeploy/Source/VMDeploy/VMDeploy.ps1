[cmdletbinding(SupportsShouldProcess=$true)]
Param
(
    # Not mandatory: when -DataFromFile is used (how VMDeploywUI.ps1 launches this script), these
    # arrive from the encrypted hand-off file instead of the command line, so nothing the operator
    # typed ever has to survive command-line quoting. Marking them mandatory would make PowerShell
    # prompt for them in that case, which looks like a hung window. They are checked explicitly
    # after the hand-off file is read.
    [parameter(Position=1,mandatory=$False)]
    [String]
    $VMname = "",

    [parameter(Position=2,mandatory=$False)]
    [String]
    $Template = "",

    [parameter(Position=3,mandatory=$False)]
    [ValidateNotNullOrEmpty()]
    [String]
    $RootFolder="NA",

    [parameter(Position=4,mandatory=$False)]
    [ValidateNotNullOrEmpty()]
    [String]
    $VMLocation="C:\Programdata\VMDeploy\VMs",

    [parameter(Position=5,mandatory=$False)]
    [String]
    $OSDAdapter0IPAddressList = "DHCP",

    [parameter(Position=6,mandatory=$False)]
    [String]
    $OSDAdapter0Gateways,

    [parameter(Position=7,mandatory=$False)]
    [String]
    $OSDAdapter0DNS1,

    [parameter(Position=8,mandatory=$False)]
    [String]
    $OSDAdapter0DNS2,

    [parameter(Position=9,mandatory=$False)]
    [String]
    $OSDAdapter0SubnetMaskPrefix,

    [parameter(Position=10,mandatory=$False)]
    [String]
    $AdminPassword,

    [parameter(Position=11,mandatory=$False)]
    [String]
    $DomainAdmin,

    [parameter(Position=12,mandatory=$False)]
    [String]
    $DomainAdminPassword,

    [parameter(Position=13,mandatory=$False)]
    [String]
    $VlanID = '0',

    [parameter(Position=13,mandatory=$False)]
    [Switch]
    $DataFromFile,

    [parameter(Position=14,mandatory=$False)]
    [String]
    $RemoteDesktopUser,

    [parameter(Position=15,mandatory=$False)]
    [String]
    $WingetApps = "",

    [parameter(Position=16,mandatory=$False)]
    [String]
    $PSModules = "",

    [parameter(Position=17,mandatory=$False)]
    [String]
    $PSModulesSkipPublisherCheck = "",

    # Files to download into the VM: @{ Name; Url; Destination } (from <Download> in package files)
    [parameter(mandatory=$False)]
    [Object[]]
    $Downloads = @(),

    # Applies Mikael Nystrom's Windows Client Security Baseline (vendored in .\SecurityBaseline)
    # with the -HardenRecommended preset. Comes from the "Apply Security Baseline" checkbox in
    # VMDeploywUI.ps1, which defaults to the template's <ApplySecurityBaseline> value.
    [parameter(mandatory=$False)]
    [bool]
    $ApplySecurityBaseline = $false
)

# Safety net: this script is normally launched by VMDeploywUI.ps1 via Start-Process, in its own
# console window with no -NoExit - if ANYTHING throws an unhandled terminating error anywhere
# below (a bad module, a missing dependency, whatever), the window closes the instant the script
# ends, often too fast to read, and (if it happens before Start-Transcript) with no log at all.
# This trap guarantees that can't happen silently again: log the real error to a file that is
# always writable, print it, and hold the window open long enough to actually read it.
trap {
    $ErrorLog = Join-Path $env:TEMP "VMDeploy-fatal-error.log"
    $Message = "$(Get-Date -Format o)  VMDeploy.ps1 failed:`r`n$($_ | Out-String)`r`n$($_.ScriptStackTrace)"
    try { Add-Content -Path $ErrorLog -Value $Message -ErrorAction Stop } catch { }
    try { Write-VIAEvent -Source "VMDeploy-Create" -Message "Deployment of '$VMname' failed: $($_.Exception.Message)" -EntryType Error -EventId 2099 } catch { }
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Red
    Write-Host "  VMDeploy.ps1 failed - see below (also logged to $ErrorLog)" -ForegroundColor Red
    Write-Host "========================================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    try { Stop-Transcript | Out-Null } catch { }
    Write-Host ""
    Write-Host "Closing in 60 seconds - press Ctrl+C to close now, or read this first." -ForegroundColor Yellow
    Start-Sleep -Seconds 60
    Exit 1
}

if($RootFolder -eq "NA"){
    $RootFolder = $MyInvocation.MyCommand.Path | Split-Path -Parent
}

# Event Log entries are readable without local admin rights, unlike the transcript below (which
# lives under the SYSTEM-only C:\ProgramData\VMDeploy on Intune/ConfigMgr installs) - see
# Functions\VIAEventLogModule.psm1. Loaded this early so the trap above can use it too.
try { Import-Module -Global "$RootFolder\Functions\VIAEventLogModule.psm1" -ErrorAction Stop -Force } catch { }

# Hyper-V management (VM creation, VHD mount, etc.) requires local Administrator rights, but
# nothing enforced that before this check existed - launched non-elevated (e.g. from a plain
# console instead of the "Deploy Windows" shortcut, which has its Run-as-administrator flag set),
# this script would fail near-instantly on its first privileged call, often before Start-Transcript
# even runs, so the spawned console window closes with no visible error and no log. Fail loudly
# and immediately instead.
$IsElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $IsElevated){
    Write-Warning "VMDeploy.ps1 must run elevated (Hyper-V management requires local Administrator rights). Launch 'Deploy Windows' from the Start Menu (it runs as administrator), or start PowerShell as Administrator first."
    Start-Sleep -Seconds 15
    Exit 1
}

Function New-TSxShortCut{
    Param    (
        $SoruceFile,
        $DestinationFile,
        $Arguments,
        $IconDLL = "NA",
        [switch]$RunAsAdmin
    )

    $WshShell = New-Object -ComObject WScript.Shell
    $ShortCut = $WshShell.CreateShortcut($DestinationFile)
    $ShortCut.TargetPath = $SoruceFile
    $ShortCut.Arguments = $Arguments
    

    if($IconDLL -ne "NA"){
            $ShortCut.IconLocation = $IconDLL
    }
    $ShortCut.Save()

    if($RunAsAdmin){
        $bytes = [System.IO.File]::ReadAllBytes("$($ShortCut.FullName)")
        $bytes[0x15] = $bytes[0x15] -bor 0x20 #set byte 21 (0x15) bit 6 (0x20) ON
        [System.IO.File]::WriteAllBytes("$($ShortCut.FullName)", $bytes)
    }
}

# Read the hand-off file from VMDeploywUI.ps1 BEFORE anything uses its values (the transcript path
# below already needs $VMName). Everything the operator typed travels in this file rather than on
# the command line - that keeps user input away from a command-line boundary entirely (the
# recommended fix for docs/security/SECURITY-REVIEW.md finding 1) and avoids Windows PowerShell
# 5.1's Start-Process -ArgumentList, which joins array elements with spaces WITHOUT quoting them
# and so silently mangles any value containing a space (e.g. a template named "Windows 11 - WORKGROUP").
if($DataFromFile){
    try {
        # AdminPassword/DomainAdminPassword were DPAPI-encrypted (bound to this user+machine) by
        # VMDeploywUI.ps1 before being written to disk - decrypt back to plain text here since every
        # downstream consumer (unattend XML, the PSCredential) expects a plain string. See
        # docs/security/SECURITY-REVIEW.md finding 6. Uses System.Security.Cryptography.ProtectedData
        # directly (a plain .NET assembly, loaded via Add-Type) rather than
        # SecureString/ConvertTo-SecureString, which - like Export-Clixml's special SecureString
        # handling - depend on the Microsoft.PowerShell.Security PowerShell module and can fail to
        # autoload on a locked-down host.
        Add-Type -AssemblyName System.Security -ErrorAction Stop
        Function Unprotect-VMDeployString
        {
            param([string]$ProtectedBase64)
            if([string]::IsNullOrEmpty($ProtectedBase64)){ return "" }
            $ProtectedBytes = [Convert]::FromBase64String($ProtectedBase64)
            $Bytes = [System.Security.Cryptography.ProtectedData]::Unprotect($ProtectedBytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
            return [System.Text.Encoding]::Unicode.GetString($Bytes)
        }
        $ProtectedFields = @('AdminPassword', 'DomainAdminPassword')

        $clixmldata = Import-Clixml -Path "$env:TEMP\vmdeploy.xml"
        foreach($item in $clixmldata.GetEnumerator()){
            $ItemValue = $item.Value
            if($ProtectedFields -contains $item.Name){
                $ItemValue = Unprotect-VMDeployString $ItemValue
            }
            New-Variable -Name $item.Name -Value $ItemValue -Force
        }
    }
    finally {
        # Always remove the temp file, even if Import-Clixml or the loop above throws.
        Remove-Item -Path "$env:TEMP\vmdeploy.xml" -Force -ErrorAction SilentlyContinue
    }
}

# $VMname/$Template are not mandatory parameters (see the Param block) because -DataFromFile
# supplies them; fail clearly here rather than letting PowerShell prompt for them in a window
# nobody is watching.
if([string]::IsNullOrWhiteSpace($VMname) -or [string]::IsNullOrWhiteSpace($Template)){
    Write-Warning "VMName and Template are required. Pass -VMName/-Template, or -DataFromFile with a hand-off file that contains them."
    Start-Sleep -Seconds 15
    Exit 1
}

try { Write-VIAEvent -Source "VMDeploy-Create" -Message "Starting VM deployment: $VMname (template: $Template)" -EventId 2000 } catch { }

$VIALogFolder = "C:\ProgramData\VMDeploy\logs"
try {
    New-Item -Path $VIALogFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Start-Transcript -Path "$VIALogFolder\$VMName-VMDeploy.log" -Append -ErrorAction Stop
}
catch {
    # If this fails (e.g. no write access to C:\ProgramData\VMDeploy), fall back to %TEMP% so the
    # failure is never silent - and keep going with a transcript rather than exiting, since the
    # rest of the deployment may well still work (only logging is affected).
    $FallbackLog = Join-Path $env:TEMP "$VMName-VMDeploy.log"
    Write-Warning "Could not start the deployment log at $VIALogFolder\$VMName-VMDeploy.log ($($_.Exception.Message)). Logging to $FallbackLog instead."
    Start-Transcript -Path $FallbackLog -Append
}

#Get LData
$XMLLDatafile = "$RootFolder\lConfig.XML"
[XML]$XMLLData = Get-Content -Path $XMLLDatafile

switch ($XMLLData.Settings.Source)
{
    'local' {
        #Get Data
        $XMLDatafile = $XMLLData.Settings.XMLFile
        [XML]$XMLData = Get-Content -Path "$RootFolder\$XMLDatafile"
    }
    'http' {
        #Get Data
        $XMLDatafile = $XMLLData.Settings.XMLFile
        # Config.xml controls the domain-join target, MachineObjectOU and VHD source - plain HTTP
        # would let anyone on the network path rewrite it. See docs/security/SECURITY-REVIEW.md
        # finding 5.
        if($XMLDatafile -notmatch '^https://'){
            throw "LConfig.xml Source is 'http' but XMLFile '$XMLDatafile' is not an https:// URL. Use https:// (or switch Source to 'local'/'unc')."
        }
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
        $ConfigResponse = Invoke-WebRequest -Uri $XMLDatafile -UseBasicParsing
        [XML]$XMLData = $ConfigResponse.Content
    }
    'unc' {
        #Get Data
        $XMLDatafile = $XMLLData.Settings.XMLFile
        # A UNC path is a filesystem path, not an HTTP endpoint - read it directly instead of
        # routing it through WebClient. Trust boundary is the SMB share ACLs, same as 'local'.
        [XML]$XMLData = Get-Content -Path $XMLDatafile -Raw
    }
    Default {}
}

$MountFolder = "$RootFolder\Mount"

$CustomerData = $XMLData.Settings.CustomerData
$TemplateData = $XMLData.Settings.Templates.Template | Where-Object Name -EQ $Template

$OrgName = $CustomerData.OrgName
$Fullname = $CustomerData.FullName

$Generation = $TemplateData.VMGen
$DomainOrWorkGroup = $TemplateData.DomainOrWorkGroup
$VMMemoryInMB = $TemplateData.Memory
$VMMemoryLowInMB = $TemplateData.MemoryLow
$VMMemoryHighInMB = $TemplateData.MemoryHigh
$VHDFile = $TemplateData.VHDFile
$NoCPU = $TemplateData.NoCPU
$TimeZoneName = $TemplateData.TimeZoneName
$DNSDomain = $TemplateData.DNSDomain
$DiskMode = $TemplateData.DiskMode
$MachineObjectOU = $TemplateData.MachineObjectOU
$OSClass = $TemplateData.OSClass
$OS = $TemplateData.OS
$VMSwitchName = $TemplateData.VMSwitch
$DomainAdminDomain = $TemplateData.DNSDomain

if($OSDAdapter0IPAddressList -eq 'DHCP'){
    $OSDAdapter0Gateways = 'DHCP'
    $OSDAdapter0DNS1 = 'DHCP'
    $OSDAdapter0DNS2 = 'DHCP'
    $OSDAdapter0SubnetMaskPrefix = 'DHCP'
}

#Default setting for verbose
$Global:VerbosePreference = "SilentlyContinue"

#Import-Modules
Import-Module -Global $rootFolder\Functions\VIAHypervModule.psm1 -ErrorAction Stop -Force
Import-Module -Global $rootFolder\Functions\VIAUtilityModule.psm1 -ErrorAction Stop -Force
Import-Module -Global $rootFolder\Functions\VIADeployModule.psm1 -ErrorAction Stop -Force

#Enable verbose for testing
$Global:VerbosePreference = "Continue"

# SetupComplete.cmd runs once inside the guest, right after first logon. The host's
# Wait-VIAVMDeployment polls the KVP registry for OSDeployment=Done in an UNTIMED loop (it will
# wait forever), so that write must happen first and must not be able to get stuck behind
# anything else. The cleanup below it - scrubbing the unattend answer file and the AutoLogon
# password that Windows Setup would otherwise leave in plaintext on/under the guest disk
# (Panther\Unattend.xml and HKLM\...\Winlogon\DefaultPassword, see
# docs/security/SECURITY-REVIEW.md findings 2 and 3) - runs after, so a slow/locked file or
# registry key during Setup's own finalization phase can never block the host's wait again (this
# is exactly what caused the deployment to hang indefinitely the first time this ran).
$VIASetupCompletecmdCommand = @'
PowerShell.exe -Command "New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest' -Name OSDeployment -Value Done -PropertyType String -Force"
del /f /q "%WINDIR%\Panther\Unattend.xml" >nul 2>&1
del /f /q "%WINDIR%\Panther\unattend.xml" >nul 2>&1
del /f /q "%WINDIR%\System32\Sysprep\Panther\unattend.xml" >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 0 /f >nul 2>&1
'@

# -------------------------------------------------------------------------
# Get-WingetBootstrapPackages
# Downloads (with local cache) the .msixbundle / .appx files needed to
# provision the latest Microsoft.DesktopAppInstaller (winget) inside a VM.
# The host has internet, the guest may not - and the guest's own winget
# client is often too old to reliably self-repair. Doing the download on
# the host and copying the packages into the VM is deterministic and
# survives an old VHDX template forever.
# -------------------------------------------------------------------------
Function Get-WingetBootstrapPackages {
    [CmdletBinding()]
    Param(
        [string]$CacheFolder = "$env:ProgramData\VMDeploy\WingetBootstrap",
        [int]$MaxAgeDays = 14
    )

    New-Item -Path $CacheFolder -ItemType Directory -Force | Out-Null
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

    # Only the winget msixbundle is pushed to the guest. VCLibs / UI.Xaml / Windows App Runtime
    # come with the template, and the winget source index is fetched by winget itself (as SYSTEM).
    $result = [ordered]@{
        Winget = $null
    }

    # --- Microsoft.DesktopAppInstaller (winget) ---------------------------
    $wingetFile = Join-Path $CacheFolder 'Microsoft.DesktopAppInstaller.msixbundle'
    $needsWinget = -not (Test-Path $wingetFile) -or
                   ((Get-Item $wingetFile).LastWriteTime -lt (Get-Date).AddDays(-$MaxAgeDays))
    if ($needsWinget) {
        try {
            Write-Verbose "Fetching latest winget-cli release metadata from GitHub ..."
            $headers = @{ 'User-Agent' = 'PAW-Deploy'; 'Accept' = 'application/vnd.github+json' }
            $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -Headers $headers -UseBasicParsing
            $asset = $release.assets | Where-Object { $_.name -like 'Microsoft.DesktopAppInstaller_*.msixbundle' } | Select-Object -First 1
            if ($asset) {
                Write-Verbose "Downloading $($asset.name) ($([math]::Round($asset.size/1MB,1)) MB) ..."
                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $wingetFile -UseBasicParsing
            } else {
                Write-Warning "Could not find winget msixbundle in latest GitHub release."
            }
        } catch {
            Write-Warning "Could not refresh winget bootstrap from GitHub: $($_.Exception.Message)"
        }
    }
    if (Test-Path $wingetFile) { $result.Winget = (Get-Item $wingetFile).FullName }

    return [pscustomobject]$result
}

# -------------------------------------------------------------------------
# Get-VMDeployDownload
# Downloads a file on the host (the guest may not have internet) into a local
# cache. A fresh download is attempted every deployment so the VM gets the
# latest version; the cached copy is used if the download fails.
# -------------------------------------------------------------------------
Function Get-VMDeployDownload {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Url,
        [string]$CacheFolder = "$env:ProgramData\VMDeploy\Downloads"
    )

    New-Item -Path $CacheFolder -ItemType Directory -Force | Out-Null
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

    $safeName  = ($Name -replace '[^A-Za-z0-9._-]', '_')
    $extension = [System.IO.Path]::GetExtension(([Uri]$Url).AbsolutePath)
    if (-not $extension) { $extension = '.bin' }
    $target  = Join-Path $CacheFolder "$safeName$extension"
    $partial = "$target.partial"

    # Retry transient failures before falling back to the cache. A single 5xx or timeout is common
    # here: a GitHub archive URL redirects to codeload.github.com, a different host that proxies
    # often handle worse than github.com itself, and a proxy that cannot reach it answers 504.
    # Giving up on the first attempt means a cached (possibly stale) copy - or nothing at all on a
    # host that has never downloaded it.
    $MaxAttempts = 3
    $LastError   = $null

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url -OutFile $partial -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop
            Move-Item -Path $partial -Destination $target -Force
            Write-Verbose "Downloaded $Name ($([math]::Round((Get-Item $target).Length / 1KB)) KB)"
            return (Get-Item $target).FullName
        }
        catch {
            Remove-Item -Path $partial -Force -ErrorAction SilentlyContinue
            $LastError = $_.Exception.Message
            $Status = $null
            try { $Status = [int]$_.Exception.Response.StatusCode } catch { }

            # 5xx, a timeout (408), rate limiting (429) or no response at all can fix themselves.
            # A 404 or 403 will not, so do not spend three attempts on it.
            $Retryable = (-not $Status) -or ($Status -ge 500) -or ($Status -eq 408) -or ($Status -eq 429)
            if (-not $Retryable -or $attempt -eq $MaxAttempts) { break }

            $Wait = 5 * $attempt
            Write-Verbose "  $Name -> attempt $attempt of $MaxAttempts failed ($LastError) - retrying in $Wait seconds ..."
            Start-Sleep -Seconds $Wait
        }
    }

    if (Test-Path $target) {
        Write-Warning "Could not download $Name after $MaxAttempts attempts ($LastError) - using cached copy from $((Get-Item $target).LastWriteTime)."
        return (Get-Item $target).FullName
    }
    Write-Warning "Could not download $Name from $Url after $MaxAttempts attempts : $LastError"
    return $null
}

### End Init ###

# The local Administrator password is needed for the unattend file and for PowerShell Direct.
# Stop before anything is created instead of failing halfway with a half-built VM.
if([string]::IsNullOrEmpty($AdminPassword) -and $VHDFile -ne 'NA'){
    Write-Warning "No local administrator password was provided. Enter the password in VM Deploy and build again."
    Start-Sleep -Seconds 10
    Exit 1
}

Write-Verbose "DomainOrWorkgroup: $DomainOrWorkGroup"


# Check if the VM exists
Write-Verbose "Check if VM already exist"
If ((Test-VIAVMExists -VMname $VMName) -eq $true){
    Write-Warning "$VMName already exist"
    Start-Sleep -Seconds 5
    Exit 1
}
else{
    Write-Verbose "$VMname does not exist, continue"
}

# Check if the Switch exists
Write-Verbose "Check if switch $VMSwitchName exist"
If (!((Get-VMSwitch | Where-Object Name -EQ $VMSwitchName).count -eq 1)){
    Write-Warning "Switch $VMSwitchName does not exist"
    Start-Sleep -Seconds 5
    Exit 1
}
else{
    Write-Verbose "Switch $VMSwitchName exist"
}


#Download the VHDx
Write-Verbose "Creating folders"
$result = New-Item -Path "$VMlocation\$VMName" -ItemType Directory -Force
$result = New-Item -Path "$VMlocation\$VMName\Virtual Hard Disks" -ItemType Directory  -Force

if($VHDFile -ne 'NA'){
    Write-Verbose "Loading the webclient"
    $wc = New-Object System.Net.WebClient
    Write-Verbose "Download from from $VHDFile"
    Write-Verbose "Download to $VMlocation\$VMName\Virtual Hard Disks\$($VHDFile | Split-Path -Leaf)"
    Write-Verbose "This will take time...Take a break..."
    $wc.DownloadFile($VHDFile, "$VMlocation\$VMName\Virtual Hard Disks\$($VHDFile | Split-Path -Leaf)")
}

if($VHDFile -ne 'NA'){
    if((Test-Path -Path "$VMlocation\$VMName\Virtual Hard Disks\$($VHDFile | Split-Path -Leaf)") -ne $true){
        Write-Warning "Could not find the file $VMlocation\$VMName\Virtual Hard Disks\$($VHDFile | Split-Path -Leaf), sorry, but the file transfer was not sucessful"
        Start-Sleep -Seconds 5
        EXIT
    }
}

if($VHDFile -ne 'NA'){
    Write-Verbose "Creating $VMName"
    $VM = New-VIAVM -VMName $VMName -VMMem ([int]$VMMemoryInMB * 1024 * 1024) -VMvCPU $NoCPU -VMLocation $VMlocation -VHDFile "$VMlocation\$VMName\Virtual Hard Disks\$($VHDFile | Split-Path -Leaf)" -DiskMode $DiskMode -VMSwitchName $VMSwitchName -VMGeneration $Generation -Verbose -DynaMem
}
else{
    Write-Verbose "Creating $VMName"
    $VM = New-VIAVM -VMName $VMName -VMMem ([int]$VMMemoryInMB * 1024 * 1024) -VMvCPU $NoCPU -VMLocation $VMlocation -DiskMode $DiskMode -VMSwitchName $VMSwitchName -VMGeneration $Generation -Verbose -DynaMem -EmptyDiskSize 120GB
}

Write-Verbose "Check if exist"
If ((Test-VIAVMExists -VMname $VMName) -eq $False){
    Write-Warning "$VMName does not exist"
    Start-Sleep -Seconds 5
    Exit 1
}


if($VHDFile -ne 'NA'){
    #Create unattend xml
    switch ($OSClass){
        'Client'{
            if($OS -eq 'W7'){
                $VIAUnattendXML = New-VIAUnattendXMLClientForW7 -Computername $VMName -OSDAdapter0IPAddressList $OSDAdapter0IPAddressList -DomainOrWorkGroup $DomainOrWorkGroup -ProtectYourPC 3 -Verbose -OSDAdapter0Gateways $OSDAdapter0Gateways -OSDAdapter0DNS1 $OSDAdapter0DNS1 -OSDAdapter0DNS2 $OSDAdapter0DNS2 -OSDAdapter0SubnetMaskPrefix $OSDAdapter0SubnetMaskPrefix -OrgName $OrgName -Fullname $Fullname -TimeZoneName $TimeZoneName -DNSDomain $DNSDomain -DomainAdmin $DomainAdmin -DomainAdminPassword $DomainAdminPassword -DomainAdminDomain $DomainAdminDomain -MachineObjectOU $MachineObjectOU -AdminPassword $AdminPassword
            }
            else{
                $VIAUnattendXML = New-VIAUnattendXMLClientfor1709 -Computername $VMName -OSDAdapter0IPAddressList $OSDAdapter0IPAddressList -DomainOrWorkGroup $DomainOrWorkGroup -ProtectYourPC 3 -Verbose -OSDAdapter0Gateways $OSDAdapter0Gateways -OSDAdapter0DNS1 $OSDAdapter0DNS1 -OSDAdapter0DNS2 $OSDAdapter0DNS2 -OSDAdapter0SubnetMaskPrefix $OSDAdapter0SubnetMaskPrefix -OrgName $OrgName -Fullname $Fullname -TimeZoneName $TimeZoneName -DNSDomain $DNSDomain -DomainAdmin $DomainAdmin -DomainAdminPassword $DomainAdminPassword -DomainAdminDomain $DomainAdminDomain -MachineObjectOU $MachineObjectOU -AdminPassword $AdminPassword
            }
        }
        'Server'{
            $VIAUnattendXML = New-VIAUnattendXML -Computername $VMName -OSDAdapter0IPAddressList $OSDAdapter0IPAddressList -DomainOrWorkGroup $DomainOrWorkGroup -ProtectYourPC 3 -Verbose -OSDAdapter0Gateways $OSDAdapter0Gateways -OSDAdapter0DNS1 $OSDAdapter0DNS1  -OSDAdapter0DNS2 $OSDAdapter0DNS2 -OSDAdapter0SubnetMaskPrefix $OSDAdapter0SubnetMaskPrefix -OrgName $OrgName -Fullname $Fullname -TimeZoneName $TimeZoneName -DNSDomain $DNSDomain -DomainAdmin $DomainAdmin -DomainAdminPassword $DomainAdminPassword -DomainAdminDomain $DomainAdminDomain -MachineObjectOU $MachineObjectOU -AdminPassword $AdminPassword
        }
        Default{
            $VIAUnattendXML = New-VIAUnattendXMLClientfor1709 -Computername $VMName -OSDAdapter0IPAddressList $OSDAdapter0IPAddressList -DomainOrWorkGroup $DomainOrWorkGroup -ProtectYourPC 3 -Verbose -OSDAdapter0Gateways $OSDAdapter0Gateways -OSDAdapter0DNS1 $OSDAdapter0DNS1 -OSDAdapter0DNS2 $OSDAdapter0DNS2 -OSDAdapter0SubnetMaskPrefix $OSDAdapter0SubnetMaskPrefix -OrgName $OrgName -Fullname $Fullname -TimeZoneName $TimeZoneName -DNSDomain $DNSDomain -DomainAdmin $DomainAdmin -DomainAdminPassword $DomainAdminPassword -DomainAdminDomain $DomainAdminDomain -MachineObjectOU $MachineObjectOU -AdminPassword $AdminPassword
        }
    }

    $VIASetupCompletecmd = New-VIASetupCompleteCMD -Command $VIASetupCompletecmdCommand
    $VMVHDFile = (Get-VMHardDiskDrive -VMName $VMName)
    If((Test-Path -Path $MountFolder) -eq $true){Remove-Item -Path $MountFolder -Force -Recurse}
    Mount-VIAVHDInFolder -VHDfile $VMVHDFile.Path -MountFolder $MountFolder
    New-Item -Path "$MountFolder\Windows\Panther" -ItemType Directory -Force | Out-Null
    New-Item -Path "$MountFolder\Windows\Setup" -ItemType Directory -Force | Out-Null
    New-Item -Path "$MountFolder\Windows\Setup\Scripts" -ItemType Directory -Force | Out-Null
    Copy-Item -Path $VIAUnattendXML.FullName -Destination "$MountFolder\Windows\Panther\$($VIAUnattendXML.Name)" -Force
    Copy-Item -Path $VIASetupCompletecmd.FullName -Destination "$MountFolder\Windows\Setup\Scripts\$($VIASetupCompletecmd.Name)" -Force

    Dismount-VIAVHDInFolder -VHDfile $VMVHDFile.Path -MountFolder $MountFolder
    Remove-Item -Path $VIAUnattendXML.FullName
    Remove-Item -Path $VIASetupCompletecmd.FullName
}

#Set VLANid for NIC01
if($VLanID -ne '0'){
    Write-Verbose "Setting VLAN $VLanID"
    Set-VMNetworkAdapterVlan -VMName $VMName -VlanId $VLanID -Access
}

#Adjust memory
#Set-VMMemory -VMName $VMname -StartupBytes ([int]$VMMemoryInMB * 1024 * 1024) -MinimumBytes ([int]$VMMemoryLowInMB * 1024 * 1024) -MaximumBytes ([int]$VMMemoryHighInMB * 1024 * 1024)
Set-VMMemory -VMName $VMname -DynamicMemoryEnabled $false -StartupBytes ([int]$VMMemoryInMB * 1024 * 1024)


# Configure VM
$Action = "Configure VM"
Write-Verbose "$Action"

# Disable AutomaticCheckpointsEnabled
Write-Verbose "Disable AutomaticCheckpointsEnabled"
Get-VM -Name $VMname | Set-VM -AutomaticCheckpointsEnabled 0 -ErrorAction SilentlyContinue -Verbose

# Set BatteryPassthroughEnabled
Write-Verbose "Set BatteryPassthroughEnabled"
Get-VM -Name $VMname | Set-VM -BatteryPassthroughEnabled $true -Verbose

# Create VM Protector for the VM and enable TPM
Write-Verbose "Create VM Protector for the VM and enable TPM"
Set-VMKeyProtector -VMName $VMname -NewLocalKeyProtector -Verbose
Get-VM -Name $VMname | Enable-VMTPM -Verbose

#Deploy VM
$Action = "Deploy VM"
Start-VM -VMname $VMname
Wait-VIAVMIsRunning -VMname $VMname
if($VHDFile -ne 'NA'){
    # Generate credentials for the VM
    Write-Verbose "Generate credentials for the VM"
    $SecurePassword = ConvertTo-SecureString -String $AdminPassword -AsPlainText -Force
    $Cred = New-Object System.Management.Automation.PSCredential -ArgumentList ".\Administrator",$SecurePassword

    # Wait for the VM to start
    Write-Verbose "Wait for the VM to start"
    Wait-VIAVMHaveICLoaded -VMname $VMname
    Wait-VIAVMHaveIP -VMname $VMname
    Wait-VIAVMDeployment -VMname $VMName
    Wait-VIAVMHavePSDirect -VMname $VMName -Credentials $Cred

    # Connect and enable bitlocker
    Write-Verbose "Get TPM status and enable bitlocker"
    $ScriptBlock = {
        try {
            # Wait until TPM is ready
            $tpm = Get-Tpm
            if (-not $tpm.TpmPresent) {
                throw "TPM not present"
            }
            while ($tpm.TpmReady -eq $false) {
                Start-Sleep -Seconds 5
                $tpm = Get-Tpm
            }
            # Initialize TPM if needed
            if ($tpm.TpmReady -eq $false) {
                Initialize-Tpm -AllowClear
            }
            # Enable BitLocker with TPM protector
            Enable-BitLocker -MountPoint "C:" -EncryptionMethod Aes256 -UsedSpaceOnly -TpmProtector
        }
        catch {
            # Fallback if TPM fails
            Enable-BitLocker -MountPoint "C:" -EncryptionMethod Aes256 -UsedSpaceOnly -RecoveryPasswordProtector
        }
    }
    Invoke-Command -VMName $VMname -ScriptBlock $ScriptBlock -Credential $Cred

    # Restart the VM
    Write-Verbose "Restarting VM"
    Stop-VM -Name $VMname
    Start-VM -Name $VMname
    Wait-VIAVMHaveICLoaded -VMname $VMname
    Wait-VIAVMHaveIP -VMname $VMname
    Wait-VIAVMHavePSDirect -VMname $VMName -Credentials $Cred

    # Connect and enable bitlocker
    Write-Verbose "Connect and enable bitlocker"
    $ScriptBlock = {
        do{
            Get-BitLockerVolume -MountPoint "C:" | Select-Object EncryptionPercentage
            Start-Sleep -Seconds 15
        }
        until ((Get-BitLockerVolume -MountPoint c:).volumestatus -eq "FullyEncrypted")
    }
    Invoke-Command -VMName $VMname -ScriptBlock $ScriptBlock -Credential $Cred

    # RDP File
    Write-Verbose "Creating Folder for RDP Link"
    New-Item -Path "$env:ALLUSERSPROFILE\Desktop\VMLinks" -Type Directory -Force
    Write-Verbose "Creating VM RDP Link"
    $Item = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    Write-Verbose "VM Name: $($item.VMName)"
    Write-Verbose "VM GUID: $($item.VMId)"
    New-Item -Path "$env:ALLUSERSPROFILE\Desktop\VMLinks" -Type Directory -Force 

$RDPFileTemplate = @"

pcb:s:{0};EnhancedMode=1
full address:s:localhost
server port:i:2179
allow font smoothing:i:0
allow desktop composition:i:0
audiocapturemode:i:1
audiomode:i:0
authentication level:i:0
autoreconnection enabled:i:1
bandwidthautodetect:i:1
compression:i:1
connection type:i:7
connect to console:i:1
devicestoredirect:s:*
drivestoredirect:s:DynamicDrives
disable wallpaper:i:0
disable full window drag:i:1
disable menu anims:i:1
disable themes:i:0
disable cursor setting:i:0
displayconnectionbar:i:1
enableworkspacereconnect:i:0
gatewayusagemethod:i:4
gatewaycredentialssource:i:4
gatewayprofileusagemethod:i:0
gatewaybrokeringtype:i:0
keyboardhook:i:1
networkautodetect:i:1
prompt for credentials:i:0
negotiate security layer:i:0
remoteapplicationmode:i:0
promptcredentialonce:i:1
redirectprinters:i:1
redirectcomports:i:1
redirectsmartcards:i:1
redirectclipboard:i:1
redirectposdevices:i:0
screen mode id:i:1
session bpp:i:32
span monitors:i:0
use multimon:i:0
videoplaybackmode:i:1
use redirection server name:i:0
bitmapcachepersistenable:i:1
usbdevicestoredirect:s:*
winposstr:s:0,3,0,0,800,600
redirectlocation:i:0
redirectwebauthn:i:1
alternate shell:s:
shell working directory:s:
gatewayhostname:s:
rdgiskdcproxy:i:0
kdcproxyname:s:
enablerdsaadauth:i:0
desktopwidth:i:1920
desktopheight:i:1200
"@

    Write-Verbose "Creating VM RDP Link"
    $Item = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    Write-Verbose "VM Name: $($item.VMName)"
    Write-Verbose "VM GUID: $($item.VMId)"
    If (Test-Path -Path "$Env:PUBLIC\Desktop\VMLinks") {
        Write-Verbose "Folder for RDP Link already exist"
    }else{
        Write-Verbose "Creating Folder for RDP Link"
        New-Item -Path "$Env:PUBLIC\Desktop\VMLinks" -Type Directory -Force
    }

    $($RDPFileTemplate -f $item.VMId) | Out-File "$Env:PUBLIC\Desktop\VMLinks\$($item.VMName).rdp" -Force


    # Install winget applications inside the VM (skip for Intune OOBE templates - those are sysprepped)
    if($WingetApps -and ($Template -notlike "*OOBE*")){
        Write-Verbose "Installing winget applications: $WingetApps"
        $AppIds = @($WingetApps -split ',' | Where-Object { $_ -and $_.Trim() -ne '' })

        # -----------------------------------------------------------------
        # Preflight: make sure the guest is not stuck in a pending reboot /
        # active shutdown state before we try to install anything. Newer
        # Windows 11 VHDX templates often finish first-boot with Windows
        # Update or CBS servicing pending, which puts the OS into
        # "A system shutdown is in progress" mode. In that state ANY
        # Appx / DISM / MSI call fails with "Access is denied" without
        # any way to recover except restarting the VM.
        # -----------------------------------------------------------------
        Write-Verbose "Preflight: checking guest for pending reboot / active shutdown ..."
        $pending = $null
        try {
            $pending = Invoke-Command -VMName $VMname -Credential $Cred -ErrorAction Stop -ScriptBlock {
                $reasons = @()

                # Attempt to abort an active shutdown; if this succeeds, one was scheduled.
                $abortOutput = & shutdown.exe /a 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $reasons += 'Active shutdown aborted'
                }

                if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
                    $reasons += 'CBS RebootPending'
                }
                if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
                    $reasons += 'WU RebootRequired'
                }
                $pfro = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
                    -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
                if ($pfro -and $pfro.PendingFileRenameOperations) {
                    $reasons += 'PendingFileRenameOperations'
                }

                # Detect the "shutdown in progress" state itself - a harmless read
                # (Get-Item on HKLM) will throw when the session manager is locked.
                try { $null = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -AllUsers -ErrorAction Stop } catch {
                    if ($_.Exception.Message -match 'shutdown is in progress') {
                        $reasons += 'Session manager shutdown lock'
                    }
                }

                [pscustomobject]@{ Reasons = $reasons }
            }
        }
        catch {
            Write-Verbose "Preflight probe failed: $($_.Exception.Message) - forcing restart to recover."
            $pending = [pscustomobject]@{ Reasons = @('Preflight probe threw') }
        }

        if ($pending -and $pending.Reasons -and $pending.Reasons.Count -gt 0) {
            Write-Verbose ("VM has pending reboot/shutdown state: {0}. Restarting to recover..." -f ($pending.Reasons -join ', '))
            try { Stop-VM -Name $VMname -Force -TurnOff -ErrorAction SilentlyContinue } catch { }
            do { Start-Sleep -Seconds 3 } until ((Get-VM -Name $VMname).State -eq 'Off')
            Start-VM -Name $VMname
            Wait-VIAVMHaveICLoaded -VMname $VMname
            Wait-VIAVMHaveIP -VMname $VMname
            Wait-VIAVMHavePSDirect -VMname $VMName -Credentials $Cred

            # Give first-logon servicing a moment to settle before we start installing.
            Start-Sleep -Seconds 15
        }
        else {
            Write-Verbose "Guest is clean - no pending reboot detected."
        }

        # -----------------------------------------------------------------
        # Winget in the guest - the approach that has proven to work:
        #  1. Push the latest DesktopAppInstaller (winget) msixbundle from the
        #     host and provision it. The template's dependencies (VCLibs,
        #     UI.Xaml, Windows App Runtime) are already in the image.
        #  2. Install every app as SYSTEM through a one-shot scheduled task.
        #
        # Dropped (never worked on a fresh VM): registering winget / its App
        # Execution Alias for Administrator over PS Direct, running winget.exe
        # directly as Administrator ("Access is denied" - no package identity),
        # provisioning VCLibs/UI.Xaml separately ("Element not found") and
        # seeding Microsoft.Winget.Source for Administrator (SYSTEM keeps its
        # own source cache and downloads it itself).
        # -----------------------------------------------------------------
        Write-Verbose "Preparing winget bootstrap package on host ..."
        $bootstrap = Get-WingetBootstrapPackages -Verbose:$false

        if (-not $bootstrap.Winget) {
            Write-Warning "No winget msixbundle available on host cache - using the winget already in the template."
        }
        else {
            $session = $null
            try {
                Write-Verbose "Opening PSSession to $VMname for bootstrap copy ..."
                $session = New-PSSession -VMName $VMname -Credential $Cred -ErrorAction Stop
                Invoke-Command -Session $session -ScriptBlock {
                    $folder = 'C:\Windows\Temp\WingetBootstrap'
                    if (Test-Path $folder) { Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue }
                    New-Item -Path $folder -ItemType Directory -Force | Out-Null
                } | Out-Null

                $leaf = Split-Path $bootstrap.Winget -Leaf
                Write-Verbose "Copying $leaf into VM ..."
                Copy-Item -Path $bootstrap.Winget -Destination "C:\Windows\Temp\WingetBootstrap\$leaf" -ToSession $session -Force

                $versions = Invoke-Command -Session $session -ScriptBlock {
                    param($Leaf)
                    $file = "C:\Windows\Temp\WingetBootstrap\$Leaf"
                    $get = { (Get-AppxPackage -Name Microsoft.DesktopAppInstaller -AllUsers -ErrorAction SilentlyContinue |
                              Sort-Object Version -Descending | Select-Object -First 1).Version }
                    $before = & $get
                    $err = $null
                    try { Add-AppxProvisionedPackage -Online -PackagePath $file -SkipLicense -ErrorAction Stop | Out-Null }
                    catch { $err = $_.Exception.Message }
                    Remove-Item 'C:\Windows\Temp\WingetBootstrap' -Recurse -Force -ErrorAction SilentlyContinue
                    [pscustomobject]@{ Before = "$before"; After = "$(& $get)"; Error = $err }
                } -ArgumentList $leaf

                if ($versions.Error) {
                    Write-Warning "Could not provision the latest winget ($($versions.Error)) - using the template's winget $($versions.Before)."
                } else {
                    Write-Verbose "winget provisioned: $($versions.Before) -> $($versions.After)"
                }
            }
            catch {
                Write-Warning "winget bootstrap step failed: $($_.Exception.Message) - using the template's winget."
            }
            finally {
                if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
            }
        }

        # winget exit codes that mean "nothing to do" - treat as success
        #   -1978335135 = 0x8A150061 APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED
        #   -1978335189 = 0x8A15002B APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE (already installed, no newer version)
        $WingetOkCodes = @(0, -1978335135, -1978335189)

        # One Invoke-Command per package, each running winget as SYSTEM via a one-shot scheduled
        # task. The task keeps running inside the guest even if an installer restarts msiserver and
        # drops the PS Direct socket; the retry below then just finds the package already installed.
        $InstallOneApp = {
            param($AppId)

            $pkg = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -AllUsers -ErrorAction SilentlyContinue |
                    Sort-Object Version -Descending | Select-Object -First 1
            $exe = if ($pkg) { Join-Path $pkg.InstallLocation 'winget.exe' } else { $null }
            if (-not $exe -or -not (Test-Path $exe -ErrorAction SilentlyContinue)) {
                return @{ Id = $AppId; ExitCode = -99; Scope = 'none'; Error = 'winget.exe not found (DesktopAppInstaller is not installed in the VM)' }
            }

            # Outside its package winget.exe does not get its dependency graph, so it dies with
            # 0xC0000135 (STATUS_DLL_NOT_FOUND) unless the dependency package folders (VCLibs,
            # UI.Xaml, Windows App Runtime) are on PATH. Newest x64 of each.
            $depDirs = @(
                foreach ($name in 'Microsoft.VCLibs.140.00.UWPDesktop', 'Microsoft.VCLibs.140.00', 'Microsoft.UI.Xaml*', 'Microsoft.WindowsAppRuntime*') {
                    Get-AppxPackage -Name $name -AllUsers -ErrorAction SilentlyContinue |
                        Where-Object { $_.Architecture -eq 'X64' -and $_.InstallLocation } |
                        Group-Object Name | ForEach-Object {
                            ($_.Group | Sort-Object Version -Descending | Select-Object -First 1).InstallLocation
                        }
                }
            ) | Select-Object -Unique
            $wingetDir = Split-Path $exe -Parent

            $log      = Join-Path $env:SystemRoot ("Temp\winget-{0}.log" -f ($AppId -replace '[^A-Za-z0-9._-]','_'))
            $cmdFile  = Join-Path $env:SystemRoot 'Temp\VMDeploy-winget.cmd'
            $taskName = 'VMDeploy-winget'
            Remove-Item $log -Force -ErrorAction SilentlyContinue
            @(
                '@echo off'
                ('set "PATH={0};{1};%PATH%"' -f $wingetDir, ($depDirs -join ';'))
                ('cd /d "{0}"' -f $wingetDir)
                ('"{0}" install --id "{1}" --exact --silent --scope machine --accept-package-agreements --accept-source-agreements --disable-interactivity > "{2}" 2>&1' -f $exe, $AppId, $log)
                'exit /b %ERRORLEVEL%'
            ) | Set-Content -Path $cmdFile -Encoding ASCII
            $action    = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\cmd.exe" -Argument ('/c "{0}"' -f $cmdFile)
            $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
            $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
            Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
            Start-ScheduledTask -TaskName $taskName

            # Wait for the task to start and then finish (max 30 min)
            $deadline = (Get-Date).AddMinutes(30)
            Start-Sleep -Seconds 3
            while ((Get-ScheduledTask -TaskName $taskName).State -in 'Running', 'Queued' -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }
            $exit = (Get-ScheduledTaskInfo -TaskName $taskName).LastTaskResult
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
            Remove-Item $cmdFile -Force -ErrorAction SilentlyContinue

            $out = if (Test-Path $log) { ((Get-Content $log -Raw -ErrorAction SilentlyContinue) -replace '\s+$', '') } else { '' }
            Remove-Item $log -Force -ErrorAction SilentlyContinue
            # LastTaskResult is the raw process exit code as UInt32 - convert to winget's signed HRESULT
            $exitSigned = [int32]([BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$exit), 0))
            return @{ Id = $AppId; ExitCode = $exitSigned; Scope = 'machine (SYSTEM)'; Error = $null; Output = $out }
        }

        foreach ($appId in $AppIds) {
            $appId = $appId.Trim()
            if (-not $appId) { continue }
            Write-Verbose "Installing winget app: $appId"
            try {
                $r = Invoke-Command -VMName $VMname -Credential $Cred `
                    -ScriptBlock $InstallOneApp -ArgumentList $appId -ErrorAction Stop
                if ($WingetOkCodes -contains $r.ExitCode) {
                    Write-Verbose ("  $appId -> {0} (scope: $($r.Scope), exit $($r.ExitCode))" -f $(if ($r.ExitCode -eq 0) { "installed" } else { "already installed" }))
                } elseif ($r.Error) {
                    Write-Warning "  $appId -> $($r.Error)"
                } else {
                    Write-Warning "  $appId -> exit $($r.ExitCode) (scope: $($r.Scope))"
                    if ($r.Output) { Write-Warning "  $appId -> winget said: $($r.Output)" }
                }
            }
            catch {
                # The installer restarted msiserver, which kills both the Hyper-V socket
                # AND rolls back any in-flight MSI installation. Reconnect and retry once -
                # after msiserver has stabilised the retry typically succeeds.
                Write-Verbose "  $appId -> socket dropped during install (msiserver may have restarted - retrying after reconnect)"
                Wait-VIAVMHavePSDirect -VMname $VMName -Credentials $Cred
                Write-Verbose "  $appId -> retrying ..."
                try {
                    $r2 = Invoke-Command -VMName $VMname -Credential $Cred `
                        -ScriptBlock $InstallOneApp -ArgumentList $appId -ErrorAction Stop
                    if ($WingetOkCodes -contains $r2.ExitCode) {
                        Write-Verbose ("  $appId -> {0} on retry (scope: $($r2.Scope), exit $($r2.ExitCode))" -f $(if ($r2.ExitCode -eq 0) { "installed" } else { "already installed" }))
                    } elseif ($r2.Error) {
                        Write-Warning "  $appId -> retry: $($r2.Error)"
                    } else {
                        Write-Warning "  $appId -> exit $($r2.ExitCode) on retry (scope: $($r2.Scope))"
                        if ($r2.Output) { Write-Warning "  $appId -> winget said: $($r2.Output)" }
                    }
                }
                catch {
                    Write-Warning "  $appId -> retry also failed: $($_.Exception.Message)"
                }
            }
        }
    }


    # Wait for VM to be ready before the PSModules session.
    # The winget scheduled task may still be finishing up (or restarted services),
    # so we re-verify connectivity before opening a new PS Direct session.
    Wait-VIAVMHavePSDirect -VMname $VMName -Credentials $Cred

    # Install PowerShell modules (AllUsers scope, latest version) inside the VM
    if($PSModules -and ($Template -notlike "*OOBE*")){
        Write-Verbose "Installing PowerShell modules: $PSModules"
        $ModuleNames = @($PSModules -split ',' | Where-Object { $_ -and $_.Trim() -ne '' })
        # Modules flagged SkipPublisherCheck="True" (e.g. Pester 5, which conflicts with the inbox signed Pester 3.4)
        $SkipPublisherCheckNames = @($PSModulesSkipPublisherCheck -split ',' | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })

        $ModuleScript = {
            param($Names, $SkipPublisherCheckNames)
            $results = @()

            # Ensure TLS 1.2 for PowerShell Gallery
            try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

            # Make sure NuGet provider and PSGallery are ready
            try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -ErrorAction Stop | Out-Null } catch { }
            try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop } catch { }

            foreach($entry in $Names){
                $entry = $entry.Trim()
                if(-not $entry){ continue }
                # Modules may be listed as "Name" (latest) or "Name@Version" (pinned) - see the
                # optional Version attribute on <Module> in Package-Template.xml.
                $name, $requiredVersion = $entry -split '@', 2
                $name = $name.Trim()
                if($requiredVersion){ $requiredVersion = $requiredVersion.Trim() }
                Write-Host ("Installing module {0} (AllUsers, {1}) ..." -f $name, $(if($requiredVersion){ "version $requiredVersion" } else { "latest" }))
                try{
                    $InstallParams = @{
                        Name         = $name
                        Scope        = 'AllUsers'
                        Force        = $true
                        AllowClobber = $true
                        Repository   = 'PSGallery'
                        ErrorAction  = 'Stop'
                    }
                    if($requiredVersion){ $InstallParams.RequiredVersion = $requiredVersion }
                    if(@($SkipPublisherCheckNames) -contains $name){ $InstallParams.SkipPublisherCheck = $true }
                    Install-Module @InstallParams
                    $installed = Get-Module -ListAvailable -Name $name | Sort-Object Version -Descending | Select-Object -First 1
                    $results += [pscustomobject]@{
                        Name    = $name
                        Version = if($installed){ $installed.Version.ToString() } else { 'unknown' }
                        Status  = 'Installed'
                    }
                }
                catch{
                    $results += [pscustomobject]@{
                        Name    = $name
                        Version = ''
                        Status  = 'Failed'
                        Error   = $_.Exception.Message
                    }
                }
            }
            return $results
        }

        try{
            $modResult = Invoke-Command -VMName $VMname -Credential $Cred `
                -ScriptBlock $ModuleScript -ArgumentList $ModuleNames, $SkipPublisherCheckNames -ErrorAction Stop
            foreach($r in $modResult){
                if($r.Status -eq 'Installed'){
                    Write-Verbose ("  {0} {1} -> {2}" -f $r.Name, $r.Version, $r.Status)
                }
                else{
                    Write-Warning ("  {0} -> {1}: {2}" -f $r.Name, $r.Status, $r.Error)
                }
            }
        }
        catch{
            Write-Warning "PowerShell module installation block failed: $($_.Exception.Message)"
        }
    }


    # Download files from selected packages (<Download> entries) and copy them into the VM
    if(@($Downloads).Count -gt 0 -and ($Template -notlike "*OOBE*")){
        Wait-VIAVMHavePSDirect -VMname $VMName -Credentials $Cred
        foreach($Download in @($Downloads)){
            if(-not $Download -or -not $Download.Url -or -not $Download.Destination){ continue }
            $DownloadName = if($Download.Name){ $Download.Name } else { Split-Path $Download.Destination -Leaf }
            Write-Verbose "Downloading $DownloadName -> $($Download.Destination)"

            $LocalFile = Get-VMDeployDownload -Name $DownloadName -Url $Download.Url
            if(-not $LocalFile){ continue }

            $session = $null
            try{
                $session = New-PSSession -VMName $VMname -Credential $Cred -ErrorAction Stop
                $GuestStaging = 'C:\Windows\Temp\VMDeployDownloads'
                Invoke-Command -Session $session -ScriptBlock {
                    param($Folder)
                    New-Item -Path $Folder -ItemType Directory -Force | Out-Null
                } -ArgumentList $GuestStaging
                $GuestFile = "$GuestStaging\$(Split-Path $LocalFile -Leaf)"
                Copy-Item -Path $LocalFile -Destination $GuestFile -ToSession $session -Force

                $Result = Invoke-Command -Session $session -ScriptBlock {
                    param($File, $Destination)
                    $ErrorActionPreference = 'Stop'
                    New-Item -Path $Destination -ItemType Directory -Force | Out-Null
                    if($File -like '*.zip'){
                        $Extract = Join-Path (Split-Path $File) ([IO.Path]::GetFileNameWithoutExtension($File) + '_extract')
                        if(Test-Path $Extract){ Remove-Item $Extract -Recurse -Force }
                        Expand-Archive -Path $File -DestinationPath $Extract -Force
                        # GitHub archives contain one top-level folder (repo-branch) - copy its content
                        $Top = @(Get-ChildItem -Path $Extract -Force)
                        $Source = if($Top.Count -eq 1 -and $Top[0].PSIsContainer){ $Top[0].FullName } else { $Extract }
                        Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
                        Remove-Item $Extract -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    else{
                        Copy-Item -Path $File -Destination $Destination -Force
                    }
                    Remove-Item $File -Force -ErrorAction SilentlyContinue
                    # Scripts must not be treated as downloaded from the internet
                    Get-ChildItem -Path $Destination -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
                    @{ Files = @(Get-ChildItem -Path $Destination -Recurse -File).Count }
                } -ArgumentList $GuestFile, $Download.Destination -ErrorAction Stop

                Write-Verbose "  $DownloadName -> $($Download.Destination) ($($Result.Files) files)"
            }
            catch{
                Write-Warning "  $DownloadName -> could not copy into VM: $($_.Exception.Message)"
            }
            finally{
                if($session){ Remove-PSSession $session -ErrorAction SilentlyContinue }
            }
        }
    }


    # Restart the VM
    Write-Verbose "Restarting VM"
    Stop-VM -Name $VMname
    do { Start-Sleep -Seconds 3 } until ((Get-VM -Name $VMname).State -eq 'Off')
    
    if(!($Template -like "*OOBE*")){

        # Enhanced Session Mode has to be allowed on the host, or shielding below locks the operator
        # out completely rather than just downgrading them to Basic - there is no Basic to downgrade
        # to. It's on by default on Windows client, but it's a documented hardening step to turn off,
        # so a PAW host is exactly the kind of machine where it may have been disabled by policy.
        try {
            Set-VMHost -EnableEnhancedSessionMode $true -ErrorAction Stop
        }
        catch {
            Write-Warning "Could not enable Enhanced Session Mode on this host: $($_.Exception.Message)"
            Write-Warning "VMs are shielded and have no Basic session - without Enhanced Session Mode there is no way to connect to them."
        }

        # Keep this $true. Shielding blocks the Basic (console) session, which leaves Enhanced
        # Session - RDP over VMBus, authenticated by the guest itself - as the only way in. That is
        # deliberate and load-bearing here: the VM is handed to a user who will not go and pick
        # Enhanced Session out of a menu, so it has to be the only option they can land in.
        #
        # This was briefly changed to $false on 2026-09-22 after VMConnect hung forever on "waiting
        # for an enhanced session", which looked like shielding blocking Enhanced Session. It wasn't.
        # Shielding removes the Basic *fallback*, so a guest that can't do Enhanced Session yet has
        # nothing to fall back to and just hangs. Two things had to be true before Enhanced Session
        # could actually come up, and neither was: Remote Desktop had to be turned on in the guest
        # (it never was - see the fDenyTSConnections/firewall fix further down), and one interactive
        # logon had to have completed (see the priming step further down). Both are handled by the
        # deployment now, so shielding can stay on without hanging anything.
        Get-VM -Name $VMname | Set-VMSecurityPolicy -Shielded $true -Verbose

    }
    Start-VM -Name $VMname
    Wait-VIAVMHaveICLoaded -VMname $VMname
    Wait-VIAVMHaveIP -VMname $VMname
    Wait-VIAVMHavePSDirect -VMname $VMName -Credentials $Cred

    If($Template -notlike "*Intune OOBE*"){

    
    if($RemoteDesktopUser -ne "Null"){

            switch ($DomainOrWorkGroup)
            {
                'Domain' {
                    
                    
                    $ScriptBlock = {
                        
                        Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $("{0}\{1}" -f $args[0],$args[1])
                        Add-LocalGroupMember -SID 'S-1-5-32-555' -Member $("{0}\{1}" -f $args[0],$args[1])

                    }

                    Write-Verbose "Adding $("{0}\{1}" -f $DNSDomain,$RemoteDesktopUser) to the Remote Desktop Users-Group"
                    Invoke-Command -VMName $VMName -Credential $Cred -ScriptBlock $ScriptBlock -ArgumentList $DNSDomain,$RemoteDesktopUser

                }
				
				'Workgroup' {
                    
                    
                    $ScriptBlock = {
                        
                         Add-LocalGroupMember -SID 'S-1-5-32-555' -Member S-1-5-4

                    }

                    Write-Verbose "Adding NT AUTHORITY\INTERACTIVE to the Remote Desktop Users-Group"
                    Invoke-Command -VMName $VMName -Credential $Cred -ScriptBlock $ScriptBlock -ArgumentList $DNSDomain,$RemoteDesktopUser

                }
				

                Default {

                }
            }

            # Remote Desktop is off by default on a fresh Windows install (fDenyTSConnections=1 and
            # the built-in "Remote Desktop" firewall rules disabled) - this tool has always added the
            # operator to Remote Desktop Users above and created an .rdp shortcut, but never actually
            # turned Remote Desktop itself on, so neither RDP nor VMConnect's Enhanced Session (which
            # uses the RDP protocol, just over VMBus instead of the network) ever worked. Confirmed
            # 2026-09-22 on a plain workgroup VM with no security baseline applied at all - not
            # something the security baseline feature caused or can fix by itself.
            Write-Verbose "Enabling Remote Desktop"
            Invoke-Command -VMName $VMName -Credential $Cred -ScriptBlock {
                Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -Force
                Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
            }
        }

        # Windows Client Security Baseline (Mikael Nystrom, deploymentbunny.com) - vendored under
        # .\SecurityBaseline. Only offered (checked/enabled) in VMDeploywUI.ps1 for templates that
        # have nobody else managing policy (Workgroup) - Intune-managed and domain-joined VMs get
        # hardening from Intune/AD instead, so applying this too would just be duplicate, unmanaged
        # local policy.
        #
        # Deliberately NOT -HardenRecommended as a whole: that preset includes
        # -SetInboundDefaultBlock (Set-NetFirewallProfile -DefaultInboundAction Block on every
        # profile), which is an unnecessary default-deny posture for a lab/PAW VM this tool's own
        # operator needs to reach - every other -HardenRecommended switch is applied explicitly below
        # instead. It never removes the operator from local Administrators either way - see
        # SecurityBaseline\README.md for the full list of what each switch changes.
        #
        # Note: VMConnect's Enhanced Session hanging on "waiting for an enhanced session" during
        # testing (2026-09-22) turned out to be unrelated to this feature - confirmed by reproducing
        # it on a plain workgroup VM with no baseline applied at all. The causes were that Remote
        # Desktop was never turned on in the guest (fixed above) and that no interactive logon had
        # ever completed (fixed by the priming step below); on a shielded VM there is no Basic
        # session to fall back into while either is missing, so VMConnect just hangs.
        if($ApplySecurityBaseline){
            Write-Verbose ""
            Write-Verbose "Applying Windows Client Security Baseline ..."
            $BaselineSource = Join-Path $RootFolder "SecurityBaseline"
            if(-not (Test-Path "$BaselineSource\Remediate-WindowsClientSecurityBaseline.ps1")){
                Write-Warning "Security baseline scripts not found at $BaselineSource - skipping."
            }
            else{
                $session = $null
                try{
                    Wait-VIAVMHavePSDirect -VMname $VMName -Credentials $Cred
                    $session = New-PSSession -VMName $VMname -Credential $Cred -ErrorAction Stop
                    $GuestBaselineFolder = 'C:\Windows\Temp\VMDeploySecurityBaseline'
                    Invoke-Command -Session $session -ScriptBlock {
                        param($Folder)
                        if(Test-Path $Folder){ Remove-Item -Path $Folder -Recurse -Force }
                        New-Item -Path $Folder -ItemType Directory -Force | Out-Null
                    } -ArgumentList $GuestBaselineFolder
                    Copy-Item -Path "$BaselineSource\*" -Destination $GuestBaselineFolder -ToSession $session -Recurse -Force

                    $BaselineResult = Invoke-Command -Session $session -ScriptBlock {
                        param($Folder)
                        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
                        & "$Folder\Remediate-WindowsClientSecurityBaseline.ps1" `
                            -EnableDefenderRealtimeProtection -EnableDefenderAntivirus `
                            -EnableFirewallProfiles `
                            -EnableLsaProtection -EnableLsassProtectedProcess `
                            -DisableWDigestCredentialCaching -SetCachedLogonsCount1 `
                            -DisableSMB1 -HardenNTLM `
                            -EnableUAC -EnableSmartScreen `
                            -DisableMulticastNameResolution
                    } -ArgumentList $GuestBaselineFolder

                    Write-Verbose ("Security baseline applied: {0} changed, {1} failed, restart required: {2} (guest log: {3})" -f $BaselineResult.ChangedCount, $BaselineResult.FailedCount, $BaselineResult.RestartRequired, $BaselineResult.LogFile)
                    $FailedActions = @($BaselineResult.Result | Where-Object { $_.Status -eq 'Failed' })
                    foreach($FailedAction in $FailedActions){
                        Write-Warning ("Security baseline action failed: {0} - {1}" -f $FailedAction.Action, $FailedAction.Details)
                    }
                    try {
                        $EntryType = if($BaselineResult.FailedCount -gt 0){ 'Warning' } else { 'Information' }
                        $FailureSummary = if($FailedActions.Count -gt 0){ " Failed: " + (($FailedActions | ForEach-Object { $_.Action }) -join '; ') } else { "" }
                        Write-VIAEvent -Source "VMDeploy-Create" -Message ("Security baseline applied to '{0}': {1} changed, {2} failed, restart required: {3}.{4} Guest log: {5}" -f $VMname, $BaselineResult.ChangedCount, $BaselineResult.FailedCount, $BaselineResult.RestartRequired, $FailureSummary, $BaselineResult.LogFile) -EntryType $EntryType -EventId 2010
                    } catch { }

                    if($BaselineResult.RestartRequired){
                        Write-Verbose "Restarting VM to finish applying the security baseline ..."
                        Stop-VM -Name $VMname
                        do { Start-Sleep -Seconds 3 } until ((Get-VM -Name $VMname).State -eq 'Off')
                        Start-VM -Name $VMname
                        Wait-VIAVMHaveICLoaded -VMname $VMname
                        Wait-VIAVMHaveIP -VMname $VMname
                        Wait-VIAVMHavePSDirect -VMname $VMName -Credentials $Cred
                    }
                }
                catch{
                    Write-Warning "Could not apply the security baseline: $($_.Exception.Message)"
                    try { Write-VIAEvent -Source "VMDeploy-Create" -Message "Could not apply the security baseline to '$VMname': $($_.Exception.Message)" -EntryType Warning -EventId 2011 } catch { }
                }
                finally{
                    if($session){ Remove-PSSession $session -ErrorAction SilentlyContinue }
                }
            }
        }

        # Prime the VM's first interactive logon so VMConnect's Enhanced Session works on the very
        # first real connection. This is required, not a convenience: the VM is shielded (see
        # Set-VMSecurityPolicy above), so there is no Basic session to fall back into - a guest that
        # isn't Enhanced Session-ready yet leaves VMConnect hanging on "waiting for an enhanced
        # session" with no way in at all. Confirmed live (2026-09-22): Enhanced Session only starts
        # working once a user has
        # completed one full interactive logon on the VM - Windows runs a first-logon "checking for
        # updates" pass there (part of finishing OOBE/specialize, unrelated to Enhanced Session
        # itself and to the security baseline above), and if that pass triggers its own restart,
        # Enhanced Session only works once that restart has also completed. This does that logon
        # unattended, using the local Administrator credentials already collected for the unattend
        # file ($Cred/$AdminPassword) - the operator chose them, so nothing new is introduced. The
        # password is written as an LSA secret (the same mechanism Sysinternals Autologon.exe uses),
        # never as the plaintext Winlogon\DefaultPassword registry value, and autologon is cleared
        # again - secret included - as soon as priming finishes. The VM is stopped at the end of this
        # script either way (see below / the OOBE branch), so there is no left-over logged-on session
        # for the operator to find.
        Write-Verbose ""
        Write-Verbose "Priming first interactive logon (for Enhanced Session) ..."
        try{
            # $Enable=$true writes DefaultUserName/DefaultDomainName + the DefaultPassword LSA
            # secret and arms AutoAdminLogon for exactly one logon (AutoLogonCount=1). $Enable=$false
            # clears all of it again, including the secret - Windows decrements AutoLogonCount to 0
            # and turns AutoAdminLogon back off by itself after the one logon, but it does NOT clear
            # the stored password, so this script must.
            $SetAutoLogonScript = {
                param($UserName, $Password, $Enable)

                $Signature = @'
using System;
using System.Runtime.InteropServices;

public static class VMDeployLsaSecret {
    [StructLayout(LayoutKind.Sequential)]
    private struct LSA_UNICODE_STRING {
        public UInt16 Length;
        public UInt16 MaximumLength;
        public IntPtr Buffer;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LSA_OBJECT_ATTRIBUTES {
        public int Length;
        public IntPtr RootDirectory;
        public IntPtr ObjectName;
        public int Attributes;
        public IntPtr SecurityDescriptor;
        public IntPtr SecurityQualityOfService;
    }

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern uint LsaOpenPolicy(ref LSA_UNICODE_STRING SystemName, ref LSA_OBJECT_ATTRIBUTES ObjectAttributes, int AccessMask, out IntPtr PolicyHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern uint LsaStorePrivateData(IntPtr PolicyHandle, ref LSA_UNICODE_STRING KeyName, ref LSA_UNICODE_STRING PrivateData);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern uint LsaClose(IntPtr PolicyHandle);

    private static LSA_UNICODE_STRING ToLsaString(string value) {
        var lus = new LSA_UNICODE_STRING();
        if (value == null) { return lus; }
        lus.Buffer = Marshal.StringToHGlobalUni(value);
        lus.Length = (UInt16)(value.Length * 2);
        lus.MaximumLength = (UInt16)((value.Length + 1) * 2);
        return lus;
    }

    // Winlogon reads the "DefaultPassword" LSA secret in preference to the plaintext
    // Winlogon\DefaultPassword registry value - the same mechanism Sysinternals Autologon.exe
    // uses. A null value clears the secret.
    public static void SetSecret(string key, string value) {
        LSA_UNICODE_STRING system = new LSA_UNICODE_STRING();
        LSA_OBJECT_ATTRIBUTES oa = new LSA_OBJECT_ATTRIBUTES();
        IntPtr handle = IntPtr.Zero;
        const int POLICY_CREATE_SECRET = 0x0020;
        const int POLICY_GET_PRIVATE_INFORMATION = 0x0004;
        uint status = LsaOpenPolicy(ref system, ref oa, POLICY_CREATE_SECRET | POLICY_GET_PRIVATE_INFORMATION, out handle);
        if (status != 0) { throw new InvalidOperationException(string.Format("LsaOpenPolicy failed: 0x{0:X8}", status)); }
        try {
            LSA_UNICODE_STRING keyStr = ToLsaString(key);
            LSA_UNICODE_STRING valueStr = ToLsaString(value);
            status = LsaStorePrivateData(handle, ref keyStr, ref valueStr);
            if (status != 0) { throw new InvalidOperationException(string.Format("LsaStorePrivateData failed: 0x{0:X8}", status)); }
        }
        finally {
            LsaClose(handle);
        }
    }
}
'@
                if (-not ([System.Management.Automation.PSTypeName]'VMDeployLsaSecret').Type) {
                    Add-Type -TypeDefinition $Signature -ErrorAction Stop
                }

                $WinlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
                if ($Enable) {
                    # Windows 11 "Only allow Windows Hello sign-in" (DevicePasswordLessBuildVersion=2)
                    # silently blocks password autologon - turn it off for this local-account VM.
                    $PwdLessPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device'
                    if (-not (Test-Path $PwdLessPath)) { New-Item -Path $PwdLessPath -Force | Out-Null }
                    Set-ItemProperty -Path $PwdLessPath -Name 'DevicePasswordLessBuildVersion' -Value 0 -Type DWord -Force
                    Set-ItemProperty -Path $WinlogonPath -Name 'DefaultUserName' -Value $UserName -Force
                    Set-ItemProperty -Path $WinlogonPath -Name 'DefaultDomainName' -Value $env:COMPUTERNAME -Force
                    Remove-ItemProperty -Path $WinlogonPath -Name 'DefaultPassword' -Force -ErrorAction SilentlyContinue
                    [VMDeployLsaSecret]::SetSecret('DefaultPassword', $Password)
                    Set-ItemProperty -Path $WinlogonPath -Name 'AutoAdminLogon' -Value '1' -Force
                    Set-ItemProperty -Path $WinlogonPath -Name 'AutoLogonCount' -Value 1 -Force -Type DWord
                }
                else {
                    Set-ItemProperty -Path $WinlogonPath -Name 'AutoAdminLogon' -Value '0' -Force -ErrorAction SilentlyContinue
                    Remove-ItemProperty -Path $WinlogonPath -Name 'AutoLogonCount' -Force -ErrorAction SilentlyContinue
                    Remove-ItemProperty -Path $WinlogonPath -Name 'DefaultPassword' -Force -ErrorAction SilentlyContinue
                    [VMDeployLsaSecret]::SetSecret('DefaultPassword', $null)
                }
            }

            # A template built by pressing CTRL+Shift+F3 in OOBE can carry a leftover 'defaultuser0'
            # (the temporary OOBE account). It is then offered on the logon screen and gets in the
            # way of the Administrator autologon - remove it and its profile.
            Invoke-Command -VMName $VMName -Credential $Cred -ScriptBlock {
                if (Get-LocalUser -Name 'defaultuser0' -ErrorAction SilentlyContinue) {
                    Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
                        Where-Object { $_.LocalPath -like '*\defaultuser0*' } |
                        Remove-CimInstance -ErrorAction SilentlyContinue
                    Remove-LocalUser -Name 'defaultuser0' -ErrorAction SilentlyContinue
                    Write-Host "Removed leftover account 'defaultuser0'."
                }
            }

            Invoke-Command -VMName $VMName -Credential $Cred -ScriptBlock $SetAutoLogonScript -ArgumentList 'Administrator', $AdminPassword, $true

            Write-Verbose "Restarting $VMname to trigger the primed logon ..."
            Stop-VM -Name $VMname
            do { Start-Sleep -Seconds 3 } until ((Get-VM -Name $VMname).State -eq 'Off')
            Start-VM -Name $VMname
            Wait-VIAVMHaveICLoaded -VMname $VMname
            Wait-VIAVMHaveIP -VMname $VMname
            Wait-VIAVMHavePSDirect -VMname $VMName -Credentials $Cred

            # Wait for the primed logon (explorer.exe running as Administrator). The first logon can
            # also trigger a first-logon update check that restarts the VM by itself - if that
            # happens, wait for it to come back and keep watching. Once the logon is confirmed,
            # watch a short extra window for such a restart instead of always waiting 3 minutes.
            Write-Verbose "Waiting for the primed logon (max 5 min) ..."
            $SelfRestartDetected = $false
            $LogonConfirmed = $false
            $LogonDeadline = (Get-Date).AddMinutes(5)
            while (-not $LogonConfirmed -and (Get-Date) -lt $LogonDeadline) {
                if ((Get-VM -Name $VMname).State -ne 'Running') {
                    $SelfRestartDetected = $true
                    Write-Verbose "$VMname restarted itself (first-logon update check) - waiting for it to come back ..."
                    do { Start-Sleep -Seconds 3 } until ((Get-VM -Name $VMname).State -eq 'Running')
                    Wait-VIAVMHaveICLoaded -VMname $VMname
                    Wait-VIAVMHavePSDirect -VMname $VMName -Credentials $Cred
                    continue
                }
                try {
                    $LogonConfirmed = [bool](Invoke-Command -VMName $VMName -Credential $Cred -ErrorAction Stop -ScriptBlock {
                        Get-Process -Name explorer -IncludeUserName -ErrorAction SilentlyContinue |
                            Where-Object { $_.UserName -like '*\Administrator' }
                    })
                } catch { }
                if (-not $LogonConfirmed) { Start-Sleep -Seconds 10 }
            }
            if ($LogonConfirmed -and -not $SelfRestartDetected) {
                # Short settle window for a first-logon restart
                $SettleUntil = (Get-Date).AddSeconds(45)
                while ((Get-Date) -lt $SettleUntil) {
                    if ((Get-VM -Name $VMname).State -ne 'Running') {
                        $SelfRestartDetected = $true
                        Write-Verbose "$VMname restarted itself after logon - waiting for it to come back ..."
                        do { Start-Sleep -Seconds 3 } until ((Get-VM -Name $VMname).State -eq 'Running')
                        Wait-VIAVMHaveICLoaded -VMname $VMname
                        Wait-VIAVMHavePSDirect -VMname $VMName -Credentials $Cred
                        break
                    }
                    Start-Sleep -Seconds 5
                }
            }
            if ($LogonConfirmed) {
                Write-Verbose "Interactive logon confirmed (explorer.exe running as Administrator)."
            } else {
                Write-Warning "Primed logon was NOT observed within 5 minutes - Enhanced Session may not work until someone logs on once."
                try {
                    $diag = Invoke-Command -VMName $VMName -Credential $Cred -ErrorAction Stop -ScriptBlock {
                        $wl = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
                        $failed = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625; StartTime = (Get-Date).AddMinutes(-10) } -ErrorAction SilentlyContinue)
                        "AutoAdminLogon={0}; AutoLogonCount={1}; DefaultUserName={2}; DefaultDomainName={3}; failed logons (4625, last 10 min)={4}" -f `
                            $wl.AutoAdminLogon, $wl.AutoLogonCount, $wl.DefaultUserName, $wl.DefaultDomainName, $failed.Count
                    }
                    Write-Warning "Autologon diagnostics: $diag"
                } catch { }
            }

            Write-Verbose "Clearing autologon ..."
            Invoke-Command -VMName $VMName -Credential $Cred -ScriptBlock $SetAutoLogonScript -ArgumentList $null, $null, $false

            try { Write-VIAEvent -Source "VMDeploy-Create" -Message "Primed first interactive logon on '$VMname' for Enhanced Session (logon confirmed: $LogonConfirmed, self-restart observed: $SelfRestartDetected)." -EventId 2020 } catch { }
        }
        catch{
            Write-Warning "Could not prime the first interactive logon: $($_.Exception.Message)"
            try { Write-VIAEvent -Source "VMDeploy-Create" -Message "Could not prime the first interactive logon on '$VMname': $($_.Exception.Message)" -EntryType Warning -EventId 2021 } catch { }
        }
    }


    ##################

  
    if($Template -like "*OOBE*"){

        Write-Verbose ""
        Write-Verbose "Exporting AutoPilotHWID and starting OOBE"
        $ScriptBlock = {

            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
            New-Item -Type Directory -Path "C:\HWID" -Force
            Set-Location -Path "C:\HWID"
            $env:Path += ";C:\Program Files\WindowsPowerShell\Scripts"
            Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
            Install-Script -Name Get-WindowsAutoPilotInfo -Force -Confirm:$false
            Get-WindowsAutoPilotInfo -OutputFile AutoPilotHWID.csv
        
        }

        Invoke-Command -VMName $VMName -Credential $Cred -ScriptBlock $ScriptBlock

        if(!(Test-Path C:\IntuneHardwareHash\)){
    
            New-Item C:\IntuneHardwareHash\ -ItemType Directory -Force 
        }

        Invoke-Command -VMName $VMName -Credential $Cred -ScriptBlock $ScriptBlock

        $ScriptBlock = {
                        
            Add-LocalGroupMember -SID 'S-1-5-32-555' -Member S-1-5-4

        }

        Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {Get-Content C:\HWID\AutoPilotHWID.csv} | Out-file C:\IntuneHardwareHash\$VMName.csv -Force

        Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {Remove-Item C:\HWID\ -Recurse -Force}
        start-sleep -Seconds 120
        Invoke-Command -VMName $VMName -Credential $Cred -ScriptBlock {Start-Process -FilePath 'C:\Windows\System32\Sysprep\Sysprep.exe' -ArgumentList "/oobe /shutdown /quiet"}

        Write-Verbose "HardwareHash exported and OOBE is done."

    }else{

        # Deliberate: the VM is handed over powered off (see the priming notes above).
        Write-Verbose "Deployment complete - shutting down $VMname ..."
        Stop-VM -Name $VMname
        Write-Verbose "VM Done"

    }
}

try { Write-VIAEvent -Source "VMDeploy-Create" -Message "Deployment of '$VMname' (template: $Template) completed successfully." -EventId 2001 } catch { }

Stop-Transcript
Exit 0