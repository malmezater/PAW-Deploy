# Installation

Complete [REQUIREMENTS.md](REQUIREMENTS.md) and [PREPARATION.md](PREPARATION.md) first.

## Run manually (testing)

From an elevated PowerShell prompt:

```powershell
PowerShell.exe -ExecutionPolicy Bypass -NoProfile -File "Install-PAWDeploy.ps1"
```

If Stage 1 enables Hyper-V for the first time, the script exits with code **1641** (reboot required). Reboot and re-run; the orchestrator skips already-completed stages.

## Deploy via Intune (Win32 app)

1. Edit `Settings.psm1` with your company name and VHDX URL (see [CONFIGURATION.md](CONFIGURATION.md)).
2. Wrap the `Install PAWDeploy` folder with the Microsoft Win32 Content Prep Tool (`IntuneWinAppUtil.exe`) — or reuse the pre-built package in [Default Intune Files/](../../Default%20Intune%20Files/) if you kept the default `CompanyName` (`DeployIT`).
3. In Intune, configure the app with:

   - **Install command:**
     ```
     PowerShell.exe -ExecutionPolicy ByPass -NoProfile -WindowStyle Hidden -File Install-PAWDeploy.ps1
     ```
   - **Uninstall command:** your preferred uninstall script (manually delete `C:\ProgramData\VMDeploy` and any Start menu shortcuts; see [Uninstall / Re-run](#uninstall--re-run)).
   - **Detection rule:** registry value `HKLM:\SOFTWARE\<CompanyName>\VMDeploy` → `VMDeployVersion` equals the installed version (see [Detection rules](#detection-rules) below).
   - **Behavior:** install as **system**; allow **device restart** (exit code 1641).

### Install behavior

| Context | Supported |
| --- | --- |
| System | ✅ Preferred |
| Administrator (interactive) | ⚠️ Works, but not recommended |
| User (non-admin) | ❌ Does not work |

### Detection rules

The installer writes multiple registry values under `HKLM:\SOFTWARE\<CompanyName>\VMDeploy` (`DeployIT` by default). Full example export: [VMDeploy-Detections.txt](VMDeploy-Detections.txt).

| Setting | Value |
| --- | --- |
| Use a custom detection script | No |
| Run script as 32-bit process on 64-bit clients | No |
| Enforce script signature check and run script silently | No |

## Deploy via SCCM / ConfigMgr

1. Add the `Install PAWDeploy` folder to the Application Library.
2. Create an application (e.g. **Install VMDeploy**) using the install command above.

## Running VM Deploy and VM Remove (post-install)

Create two separate applications/shortcuts to let users deploy and remove VMs after installation:

| Application | Command |
| --- | --- |
| Deploy Windows | `PowerShell -ExecutionPolicy ByPass -NoProfile -File "C:\ProgramData\VMDeploy\VMDeploywUI.ps1"` |
| Destroy VM | `PowerShell -ExecutionPolicy ByPass -NoProfile -File "C:\ProgramData\VMDeploy\VMRemovewUI.ps1"` |

When `LocalInstall = $true`, two **Run as Administrator** shortcuts for these are created in the Start Menu automatically during installation; they are **not** created when `LocalInstall = $false` (Intune/ConfigMgr). See [Default Intune Files/README.md](../../Default%20Intune%20Files/README.md) for the pre-packaged Intune apps that wrap these same commands.

---

## Installation stages

| Stage | Script | What it does | Registry stamp |
| --- | --- | --- | --- |
| 1 | [Install-Features_for_PAW.ps1](../../Install%20PAWDeploy/1_Install-Features_for_PAW/Install-Features_for_PAW.ps1) | Enables all required Hyper-V Optional Features (with a 3-attempt verification loop). | One value per feature (e.g. `Microsoft-Hyper-V-All = Enabled`). |
| 2a | [Configure-PAWNetwork.ps1](../../Install%20PAWDeploy/2_Install_VMDeploy-configuration/Configure-PAWNetwork.ps1) | Creates an external VMSwitch named **"Ethernet Cable"** on the first active physical NIC. | `PawNetwork = True` |
| 2b | [Set-FirewallRules.ps1](../../Install%20PAWDeploy/2_Install_VMDeploy-configuration/Set-FirewallRules.ps1) | Disables Hyper-V remoting firewall rules that interfere with PAW usage. | One value per rule name. |
| 2c | [Add-HyperVAdmin.ps1](../../Install%20PAWDeploy/2_Install_VMDeploy-configuration/Add-HyperVAdmin.ps1) | Adds the signed-in user to the **Hyper-V Administrators** local group and creates the `Hypervuser` service account. | `HyperV-Admins = True` |
| 3 | [Install-VMDeploy.ps1](../../Install%20PAWDeploy/3_Install_VMDeploy/Install-VMDeploy.ps1) | Robocopies the `Source/VMDeploy` tree to `C:\ProgramData\VMDeploy`. Creates Start Menu shortcuts only when `$LocalInstall = $true`. | `VMDeployVersion = 2.2.1` |
| 4 | [download-vhdx.ps1](../../Install%20PAWDeploy/4_Download_Windows_VHDX/download-vhdx.ps1) | Downloads the Windows 11 VHDX template. Auto-selects the transfer method: Azure Blob/Files → AzCopy, `\\server\share` → Copy-Item, HTTP/HTTPS → BITS with `Invoke-WebRequest` fallback. | `WindowsVHDX = Win11-25H2` |

The orchestrator ([Install-PAWDeploy.ps1](../../Install%20PAWDeploy/Install-PAWDeploy.ps1)) skips any stage whose stamp matches the expected value, making the installer safe to re-run.

## Registry layout

Default key: `HKLM:\SOFTWARE\<CompanyName>\VMDeploy`

| Value | Meaning |
| --- | --- |
| `(Default)` | `True` once installation finishes successfully. |
| `VMDeployVersion` | Installed VMDeploy version (matches `$ScriptVersion`). |
| `WindowsVHDX` | Currently downloaded VHDX tag (matches `$VHDXVersion`). |
| `PawNetwork` | `True` after VMSwitch creation. |
| `HyperV-Admins` | `True` after group/user setup. |
| Hyper-V feature names | `Enabled` for each successfully installed feature. |
| Firewall rule names | Status of each disabled rule. |

Full example export: [VMDeploy-Detections.txt](VMDeploy-Detections.txt).

## Logging

All scripts write transcripts to:

```
C:\ProgramData\<CompanyName>\Logs\
```

File names include the script name and date stamp (`yyMMdd`), for example `Install-VMDeploy-260528.log`.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Stage / installation completed successfully. |
| `1` | A stage failed; check the matching log file in the Logs folder. |
| `1641` | Reboot required after Hyper-V feature install (Intune treats this as success and reboots). |

## Uninstall / Re-run

- To force a stage to re-run, delete its registry stamp under `HKLM:\SOFTWARE\<CompanyName>\VMDeploy` and re-run the orchestrator.
- To remove VMDeploy itself, manually delete `C:\ProgramData\VMDeploy` and the Start menu shortcuts.
