#region Custom Attributes
##*===============================================
##* CUSTOM ATTRIBUTES
##*===============================================
Write-Host "========================================================"
Write-Host "                     Custom Attributes"
Write-Host "========================================================"
Write-Host " "

$CompanyName = "COMPANY NAME" <# Enter the name who is deploying the software #>

$ScriptVersion = "2.0.4"

$DownloadUrl = "Download URL" <# Enter the URL to download the VHDX file #>
$VHDXVersion = "Win11-25H2"

Write-Host " "

#endregion

#region Static Attributes
##*===============================================
##* STATIC ATTRIBUTES
##*===============================================
Write-Host "========================================================"
Write-Host "                     Static Attributes"
Write-Host "========================================================"
Write-Host " "

##*===============================================
##* Software name and installation paths
##*===============================================
    $SoftwareName = "VMDeploy"
    $DeployPath = "$env:ProgramData\$CompanyName"
    $DeployITLogs = "$DeployPath\logs"
    $DeployITDownload = "$DeployPath\Download"

##*===============================================
#Software registry path
##*===============================================
    $RegistryPath = "HKLM:\SOFTWARE\DeployIT"
    $RegistrySoftwareName = "$RegistryPath\$SoftwareName" -replace (" ","")
    $ApplicationKeyPath = "$RegistrySoftwareName"

##*===============================================
#Registry values and settings
##*===============================================
    #Stage 1 - HyperV
    ##*===========================================
        $HyperVFeatures = @(
            "Microsoft-Hyper-V-All"
            "Microsoft-Hyper-V"
            "Microsoft-Hyper-V-Tools-All"
            "Microsoft-Hyper-V-Management-PowerShell"
            "Microsoft-Hyper-V-Hypervisor"
            "Microsoft-Hyper-V-Services"
            "Microsoft-Hyper-V-Management-Clients"
            "HostGuardian"
        )
    #Stage 2 - Configure VMDeploy
    ##*===========================================
        $Rules = @(
            "VIRT-WMI-RPCSS-In-TCP-NoScope",
            "VIRTCL-WMI-RPCSS-In-TCP-NoScope",
            "VIRT-REMOTEDESKTOP-In-TCP-NoScope"
            )
    #Stage 3 - Install VMDeploy
    ##*===========================================

    #Stage 4 - Download VHDX
    ##*===========================================
        $SourceFiles = "WindowsVHDX"

Write-Host " "
#endregion
