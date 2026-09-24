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
   - **Uninstall command:**
     ```
     PowerShell.exe -ExecutionPolicy ByPass -NoProfile -WindowStyle Hidden -File Uninstall-PAWDeploy.ps1
     ```
     (same package as the install command; see [Uninstall](#uninstall)).
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
| 1 | [Install-Features_for_PAW.ps1](../../Install%20PAWDeploy/Stages/1_Install-Features_for_PAW/Install-Features_for_PAW.ps1) | Enables the required Hyper-V Optional Features. Exits `1641` only when Windows reports that a restart is needed, otherwise `0`. | One value per feature (e.g. `Microsoft-Hyper-V-All = Enabled`). |
| 2a | [Configure-PAWNetwork.ps1](../../Install%20PAWDeploy/Stages/2_Install_VMDeploy-configuration/Configure-PAWNetwork.ps1) | Creates the external VMSwitch `$VMSwitchName` on `$VMSwitchAdapterName`, or on the first active physical NIC when that is empty. | `PawNetwork = True` |
| 2b | [Set-FirewallRules.ps1](../../Install%20PAWDeploy/Stages/2_Install_VMDeploy-configuration/Set-FirewallRules.ps1) | Disables Hyper-V remoting firewall rules that interfere with PAW usage. | One value per rule: `Disabled`, or `NotFound` if the rule doesn't exist on this Windows build. |
| 2c | [Add-HyperVAdmin.ps1](../../Install%20PAWDeploy/Stages/2_Install_VMDeploy-configuration/Add-HyperVAdmin.ps1) | Adds the signed-in user to **Hyper-V Administrators**. Creates the `Hypervuser` account when `$CreateHyperVUser = $true` and the install is interactive (the password is prompted for); as SYSTEM it is skipped with a warning. | `HyperV-Admins = True` |
| 3 | [Install-VMDeploy.ps1](../../Install%20PAWDeploy/Stages/3_Install_VMDeploy/Install-VMDeploy.ps1) | Robocopies the `Source/VMDeploy` tree to `C:\ProgramData\VMDeploy` (fails on Robocopy exit code 8+). Creates Start Menu shortcuts only when `$LocalInstall = $true`. | `VMDeployVersion = <ScriptVersion>` |
| 4 | [download-vhdx.ps1](../../Install%20PAWDeploy/Stages/4_Download_Windows_VHDX/download-vhdx.ps1) | Downloads the Windows 11 VHDX to a temporary file, verifies `$VHDXSha256` when set, then replaces the image. Azure Blob/Files → AzCopy, `\\server\share` → Copy-Item, HTTP/HTTPS → BITS with `Invoke-WebRequest` fallback. | `WindowsVHDX = <VHDXVersion>` |

The orchestrator ([Install-PAWDeploy.ps1](../../Install%20PAWDeploy/Install-PAWDeploy.ps1)) holds the stage list together with the stamp check for each stage, skips stages that are already done, and finishes by re-checking every stage before it writes `(Default) = True`. Changing `$ScriptVersion` or `$VHDXVersion` makes stage 3 or 4 run again on the next install, which is how updates are rolled out.

All stage scripts share the same start/end and stamp helpers from `Settings.psm1`, so each script only contains its own logic. Every stage can still be run on its own for troubleshooting.

## Permissions (Intune / ConfigMgr only)

When `$LocalInstall = $false`, nobody signs in and runs VMDeploy interactively - the Intune Management Extension (or ConfigMgr) drives everything as SYSTEM, including the "Run VMDeploy" / "Remove VM" helper apps. Neither local Administrators nor ordinary Users (which inherit read access from `C:\ProgramData`'s own default ACL) has a legitimate need to read or write VM configs, virtual disks or the downloaded VHDX in that case, so once every stage has finished, the orchestrator runs:

```
icacls "C:\ProgramData\VMDeploy" /inheritance:d /T /C /Q
icacls "C:\ProgramData\VMDeploy" /remove:g "*S-1-5-32-544" "*S-1-5-32-545" "*S-1-5-11" /T /C /Q
```

(the well-known SIDs for `BUILTIN\Administrators`, `BUILTIN\Users` and `NT AUTHORITY\Authenticated Users`, used instead of names so this works on non-English Windows too), leaving `SYSTEM` as the only real accessor on the whole tree - this reduces the attack surface against deployed VMs. It is applied last, after all stages, so a stage running as a non-SYSTEM elevated admin (an unusual combination with `LocalInstall = $false`) doesn't lock itself out mid-install. Ownership is deliberately left unchanged - `icacls /setowner` needs `SeTakeOwnershipPrivilege` to be explicitly enabled, which is unreliable even from an elevated admin token, and a partial failure there risks leaving the folder inaccessible to everyone. [Uninstall-PAWDeploy.ps1](../../Install%20PAWDeploy/Uninstall-PAWDeploy.ps1) runs `takeown.exe` before deleting the folder (which reliably reclaims access in that same situation), so uninstalling as an elevated admin still works.

This is defense in depth, not a hard boundary: a local Administrator can always run `takeown.exe` on their own machine to reclaim access, so it stops casual or automated access rather than a deliberate, fully-privileged local admin. When `$LocalInstall = $true`, permissions are left at their normal `ProgramData` default.

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

### Event Log (readable without local admin)

On an Intune/ConfigMgr install, `C:\ProgramData\VMDeploy` (and its `logs` subfolder) is [restricted to SYSTEM](#permissions-intune--configmgr-only), so the transcripts above aren't readable by an operator who isn't a full local admin. Every stage, the orchestrator, `Uninstall-PAWDeploy.ps1`, and VM Deploy/Remove also write one-line entries to a Windows Event Log instead:

**Event Viewer → Applications and Services Logs → VMDeploy → Operational**, or:

```powershell
Get-WinEvent -LogName "VMDeploy/Operational"
```

This log is created on first use with its default permissions (any interactively logged-on account can read and write it - not just local admins), so it stays readable even where the files aren't. Sources: `VMDeploy-Setup` (install/uninstall stages), `VMDeploy-Create` (VM Deploy), `VMDeploy-Remove` (VM Remove). It only carries short status lines (stage start/finish, exit codes, VM deployed/removed, fatal errors) - the transcripts remain the detailed record for troubleshooting.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Stage / installation completed successfully. |
| `1` | A stage failed; check the matching log file in the Logs folder. |
| `1641` | Reboot required after Hyper-V feature install (Intune treats this as success and reboots). |

## Uninstall

[Uninstall-PAWDeploy.ps1](../../Install%20PAWDeploy/Uninstall-PAWDeploy.ps1) sits next to the installer and shares its `Settings.psm1`, so it belongs in the same package (no separate `.intunewin` to build). Run it directly, or as the Intune uninstall command shown above.

```powershell
PowerShell.exe -ExecutionPolicy Bypass -NoProfile -File "Uninstall-PAWDeploy.ps1"
```

It is safe to run more than once and safe to run when nothing is installed (it detects that and exits `0`).

By default it removes only what is exclusively PAWDeploy's own and cheap to put back:

- The `C:\ProgramData\VMDeploy` program folder (Start Menu shortcuts, branding, downloaded VHDX) - unless VMs are found stored under `VMDeploy\VMs`, in which case those (and only those) are left behind with a warning.
- Start Menu shortcuts.
- `Check`/`Tools` files under `C:\ProgramData\<CompanyName>` (`Logs` is kept).
- The `HKLM:\SOFTWARE\<CompanyName>\VMDeploy` registry key (this is also the Intune detection key, so removing it is what makes Intune see the app as uninstalled) - and the parent `<CompanyName>` key too, if nothing else is using it.
- The Hyper-V firewall rules disabled/scoped by Stage 2b are restored (`Enabled`, unscoped).

Left alone unless you opt in, because they are shared with the rest of the machine or hard to reverse:

| Switch | Also removes |
| --- | --- |
| `-RemoveVMs` | Any Hyper-V VM stored under `VMDeploy\VMs`, **including its virtual disks**. |
| `-RemoveVMSwitch` | The `$VMSwitchName` external switch - skipped with a warning if any VM on the host still uses it. |
| `-RemoveHyperVUser` | The local `Hypervuser` account (its profile folder, if any, is left in place). The signed-in user added to **Hyper-V Administrators** during install is never removed automatically. |
| `-DisableHyperVFeatures` | The Hyper-V Windows Optional Features from Stage 1. Affects **every** VM on the computer, not only PAWDeploy's, and normally needs a reboot (exit `1641`). |
| `-SkipFirewallRestore` | Opts *out* of the default firewall-rule restore above. |
| `-RemoveLogs` | `C:\ProgramData\<CompanyName>\Logs`. |
| `-Full` | Shorthand for `-RemoveVMs -RemoveVMSwitch -RemoveHyperVUser -DisableHyperVFeatures` - a complete teardown. |

To force an install stage to re-run instead of uninstalling, delete its registry stamp under `HKLM:\SOFTWARE\<CompanyName>\VMDeploy` and re-run the orchestrator.
