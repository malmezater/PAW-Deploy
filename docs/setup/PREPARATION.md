# Preparation

What to do before you run (or package) the PAW-Deploy installer. Confirm [REQUIREMENTS.md](REQUIREMENTS.md) is met first.

## 1. Build a template VHDX

VMDeploy provisions every guest VM from a single generalized (sysprepped) Windows 11 Enterprise VHDX. This is built once, ahead of time, and uploaded to wherever `$DownloadUrl` will point.

Full walkthrough and scripts: [Create Templade VHDX/README.md](../../Create%20Templade%20VHDX/README.md). Summary of the process:

| Step | Runs | What it does |
| --- | --- | --- |
| 1 | In VM (Audit Mode) | Install Windows 11 Enterprise, enter Audit Mode. |
| 2 | In VM | Apply the custom Start menu layout (`LayoutModification.xml`). |
| 3 | In VM | Remove bloatware / unwanted Store apps (`Uninstall-WinApps.ps1`). |
| 4 | In VM | Install the AutoPilot module and **initialize winget** (`Install-Module.ps1`) — required, or every winget install on deployed VMs fails. |
| 5 | In VM | Compact OS, run Disk Cleanup, turn off BitLocker. |
| 6 | In VM | `Invoke-SysprepPrep.ps1` — removes winget's per-user source cache, disables networking, runs `sysprep /generalize /oobe /shutdown`. |
| 7 | On host | Mount the VHDX offline, run `Remove-TempFiles.ps1`, then defrag/`Optimize-VHD`. |
| 8 | On host | Upload the finished VHDX to the location referenced by `$DownloadUrl`. |

## 2. Configure the installer

Edit the user-configurable block in [Settings.psm1](../../Install%20PAWDeploy/Settings.psm1) **before** packaging or running the installer:

```powershell
$Script:CompanyName  = "COMPANY NAME"   # Registry path + ProgramData folder name (default: DeployIT)
$Script:DownloadUrl  = "Download URL"   # Full URL to the template VHDX built in step 1
$Script:VHDXVersion  = "Win11-25H2"     # Version tag stamped to the registry
$Script:LocalInstall = $true            # $true = local install (shortcuts created); $false = Intune/ConfigMgr
```

Full field reference: [CONFIGURATION.md](CONFIGURATION.md).

## 3. Choose which apps and modules guest VMs get

If you want the VM Deploy UI to offer optional winget applications / PowerShell modules per template, define profiles in [Apps.xml](../../Install%20PAWDeploy/Stages/3_Install_VMDeploy/Source/VMDeploy/Apps.xml) and [Modules.xml](../../Install%20PAWDeploy/Stages/3_Install_VMDeploy/Source/VMDeploy/Modules.xml), then reference the profile names from the relevant template in [Config.xml](../../Install%20PAWDeploy/Stages/3_Install_VMDeploy/Source/VMDeploy/Config.xml). Format details: [CONFIGURATION.md](CONFIGURATION.md#appsxml--modulesxml).

This step is optional — templates without an `AppProfile`/`ModuleProfile` simply skip that checklist (Intune OOBE templates intentionally skip both, since app/module delivery happens via Intune post-enrollment).

## 4. Package for deployment

- **Intune:** wrap the `Install PAWDeploy` folder with the Microsoft Win32 Content Prep Tool (`IntuneWinAppUtil.exe`). If you kept the default `CompanyName` (`DeployIT`), you can reuse the pre-built `.intunewin` files in [Default Intune Files/](../../Default%20Intune%20Files/) instead of repackaging.
- **SCCM:** add the `Install PAWDeploy` folder to the Application Library directly (no wrapping needed).
- **Manual/local:** no packaging needed — run `Install-PAWDeploy.ps1` directly from an elevated prompt.

Once packaged, proceed to [INSTALLATION.md](INSTALLATION.md).
