# PAW-Deploy 2.3.2

A new, smaller Windows 11 Enterprise template (`Win11-2609`), winget installs that work reliably in every deployed VM, Enhanced Session that works on the very first connect, a proper uninstaller, and a smaller attack surface on Intune/ConfigMgr installs.

> [!IMPORTANT]
> **Repackaging required.** `Install-PAWDeploy.ps1` and VM Deploy changed and `Uninstall-PAWDeploy.ps1` is new — rebuild the `.intunewin` package and add an uninstall command in Intune ([Uninstall](https://github.com/malmezater/PAW-Deploy/blob/main/docs/setup/INSTALLATION.md#uninstall)).
>
> **New template VHDX.** The default VHDX tag is now **`Win11-2609`**. Build it with the updated [Create Templade VHDX](https://github.com/malmezater/PAW-Deploy/blob/main/Create%20Templade%20VHDX/README.md) guide and upload it to `$DownloadUrl`.

## Highlights

### Smaller, rebuildable template VHDX
- New 11-step guide: Windows 11 **Enterprise** ISO from the Media Creation Tool → Audit Mode → debloat → optimize → sysprep → offline compaction.
- **`Optimize-Template.ps1`** removes unneeded features (payload included), Reserved Storage and hibernation, cleans WinSxS, caches and logs, and compacts the OS.
- **`Rebuild-TemplateVHDX.ps1`** *(optional)* rebuilds the sysprepped disk via a WIM into a new VHDX with 1 MB blocks — **20.3 GB → 15.9 GB** measured, plus a ~4–5 GB WIM backup.
- `Uninstall-WinApps.ps1` rewritten with a wildcard keep-list that keeps winget and its dependencies; `Invoke-SysprepPrep.ps1` also removes the leftover `defaultuser0` account.

### winget in deployed VMs — rewritten around what works
- The host pushes the latest winget and provisions it; every app is installed by a one-shot **SYSTEM scheduled task** (`winget install --scope machine`).
- "Already installed" / "no newer version" now count as success.
- Removed the approaches that never worked on a fresh VM (Administrator alias registration, direct `winget.exe` calls, separate VCLibs/UI.Xaml provisioning, source seeding).

### Enhanced Session works on the first connect
- Remote Desktop is now actually turned on in the guest.
- VM Deploy primes the first interactive logon unattended, **verifies** it (explorer.exe as Administrator), then clears autologon again (LSA secret included). VMs stay shielded.
- Fixed the autologon being blocked by a leftover `defaultuser0` account and by Windows 11's *"Only allow Windows Hello sign-in"*.
- Shorter wait: the logon is polled directly instead of a fixed 3-minute window.

### New
- **`Uninstall-PAWDeploy.ps1`** — removes everything the installer adds; VMs, switch, `Hypervuser` and Hyper-V features only on opt-in (`-Full` for everything).
- **"Windows 11 - Domain Joined"** template on the external switch.
- **"Intune Packaging"** package — downloads the Microsoft Win32 Content Prep Tool (`IntuneWinAppUtil.exe`) to `C:\PackTools\IntuneWinAppUtil`.
- **Optional Windows Client Security Baseline** for Workgroup VMs (Defender, firewall, LSA, SMB1, NTLM hardening). The Defender EDR (Sense) step is skipped, since it only works on onboarded devices.
- **Event Log** (`VMDeploy/Operational`) readable without local admin.

### Security
- `C:\ProgramData\VMDeploy` is restricted to **SYSTEM** on Intune/ConfigMgr installs (`LocalInstall = $false`).

## Known issue
- On first boot the VM may spend a moment in OOBE's *"Checking for updates"* before the deployment continues. It completes on its own; a follow-up is planned.

Full details: [CHANGELOG.md](https://github.com/malmezater/PAW-Deploy/blob/main/CHANGELOG.md#232)
