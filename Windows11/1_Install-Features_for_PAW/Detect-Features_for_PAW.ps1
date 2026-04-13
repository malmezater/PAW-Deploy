$Features = @(
    "Microsoft-Hyper-V-All"
    "Microsoft-Hyper-V"
    "Microsoft-Hyper-V-Tools-All"
    "Microsoft-Hyper-V-Management-PowerShell"
    "Microsoft-Hyper-V-Hypervisor"
    "Microsoft-Hyper-V-Services"
    "Microsoft-Hyper-V-Management-Clients"
    "HostGuardian"
)

$AllFeaturesEnabled = $true

Foreach($Feature in $Features) {
    Get-WindowsOptionalFeature -FeatureName $Feature -Online | ForEach-Object {
        if ($_.State -eq "Enabled") {
            Write-Host "$Feature is already enabled."
        } else {
            $AllFeaturesEnabled = $false
            New-Item -ItemType File -Path "C:\ProgramData\RejlersIT\Check\$Feature-ConfHyperv.log" -Force
        }
    }
}

if ($AllFeaturesEnabled) {
    Write-Host "All features are enabled. Reboot required."
    Write-Host 1641  # Exit code 1641 indicates a reboot is required.
} else {
    Write-Host "Not all features are enabled. No reboot required."
    Write-Host 0  # Exit code 0 indicates success without reboot.
}