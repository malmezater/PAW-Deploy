# Installation

Complete [REQUIREMENTS.md](REQUIREMENTS.md) and [PREPARATION.md](PREPARATION.md) first.

## Run manually (testing)

From an elevated PowerShell prompt:

```powershell
PowerShell.exe -ExecutionPolicy Bypass -NoProfile -File "Install-PAWDeploy.ps1"
```

If Stage 1 enables Hyper-V for the first time, the script exits with code **1641** (reboot required). Reboot and re-run; the orchestrator skips already-completed stages.

The orchestrator checks before it changes anything that it runs elevated and that `DownloadUrl` in `Settings.psm1` has been configured. When started from a 32-bit process (as the Intune Management Extension does), it relaunches itself in 64-bit PowerShell, which DISM and the Hyper-V cmdlets require.

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
| 1 | [Install-Features_for_PAW.ps1](../../Install%20PAWDeploy/1_Install-Features_for_PAW/Install-Features_for_PAW.ps1) | Enables the required Hyper-V Optional Features. Exits `1641` only when Windows reports that a restart is needed, otherwise `0`. | One value per feature (e.g. `Microsoft-Hyper-V-All = Enabled`). |
| 2a | [Configure-PAWNetwork.ps1](../../Install%20PAWDeploy/2_Install_VMDeploy-configuration/Configure-PAWNetwork.ps1) | Creates the external VMSwitch `$VMSwitchName` on `$VMSwitchAdapterName`, or on the first active physical NIC when that is empty. | `PawNetwork = True` |
| 2b | [Set-FirewallRules.ps1](../../Install%20PAWDeploy/2_Install_VMDeploy-configuration/Set-FirewallRules.ps1) | Disables Hyper-V remoting firewall rules that interfere with PAW usage. | One value per rule: `Disabled`, or `NotFound` if the rule doesn't exist on this Windows build. |
| 2c | [Add-HyperVAdmin.ps1](../../Install%20PAWDeploy/2_Install_VMDeploy-configuration/Add-HyperVAdmin.ps1) | Adds the signed-in user to **Hyper-V Administrators**. Creates the `Hypervuser` account when `$CreateHyperVUser = $true` and the install is interactive (the password is prompted for); as SYSTEM it is skipped with a warning. | `HyperV-Admins = True` |
| 3 | [Install-VMDeploy.ps1](../../Install%20PAWDeploy/3_Install_VMDeploy/Install-VMDeploy.ps1) | Robocopies the `Source/VMDeploy` tree to `C:\ProgramData\VMDeploy` (fails on Robocopy exit code 8+). Creates Start Menu shortcuts only when `$LocalInstall = $true`. | `VMDeployVersion = <ScriptVersion>` |
| 4 | [download-vhdx.ps1](../../Install%20PAWDeploy/4_Download_Windows_VHDX/download-vhdx.ps1) | Downloads the Windows 11 VHDX to a temporary file, verifies `$VHDXSha256` when set, then replaces the image. Azure Blob/Files → AzCopy, `\\server\share` → Copy-Item, HTTP/HTTPS → BITS with `Invoke-WebRequest` fallback. | `WindowsVHDX = <VHDXVersion>` |

The orchestrator ([Install-PAWDeploy.ps1](../../Install%20PAWDeploy/Install-PAWDeploy.ps1)) holds the stage list together with the stamp check for each stage, skips stages that are already done, and finishes by re-checking every stage before it writes `(Default) = True`. Changing `$ScriptVersion` or `$VHDXVersion` makes stage 3 or 4 run again on the next install, which is how updates are rolled out.

All stage scripts share the same start/end and stamp helpers from `Settings.psm1`, so each script only contains its own logic. Every stage can still be run on its own for troubleshooting.

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

Each stage writes `<Stage>-<yyMMdd>.log`, for example `Install-PAWDeploy-260916.log`, `HyperV-260916.log`, `PawNetwork-260916.log`, `FirewallRules-260916.log`, `HyperV-Admins-260916.log`, `Install-VMDeploy-260916.log` and `download-vhdx-260916.log`.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Stage / installation completed successfully. |
| `1` | A stage failed; check the matching log file in the Logs folder. |
| `1641` | Reboot required after Hyper-V feature install (Intune treats this as success and reboots). |

## Uninstall / Re-run

- To force a stage to re-run, delete its registry stamp under `HKLM:\SOFTWARE\<CompanyName>\VMDeploy` and re-run the orchestrator.
- To remove VMDeploy itself, manually delete `C:\ProgramData\VMDeploy` and the Start menu shortcuts.
