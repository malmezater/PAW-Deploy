# Create Template VHDX

## Overview

Creates a generalized Windows 11 Enterprise VHDX used as the base image for VMDeploy.
PowerShell modules do **not** need to be installed manually here — they are installed automatically by VMDeploy at a later stage.

---

## Process Overview

1. Prepare the OS in Audit Mode
2. Customize the Start Menu
3. Debloat Windows
4. Install AutoPilot module & initialise winget
5. Compact and clean up
6. Remove temp files (offline)
7. Run `Invoke-SysprepPrep.ps1` — removes winget source cache, disables network, runs sysprep

---

## Step 1 – Preparation

- OS: **Windows 11 Enterprise**
- Enter Audit Mode: `CTRL + Shift + F3`

Install the following tools manually while in Audit Mode:

| Tool | Note |
|---|---|
| `C:\PackTools` | Place tools here |
| IntuneWinPrepTool | For packaging Intune apps |
| Winget | Enabled via DesktopAppInstaller |
| .NET Framework 3.5 | Enable via Windows Features |

---

## Step 2 – Customize Start Menu

Copy `LayoutModification.xml` to:

```
C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml
```

The layout pins **Microsoft Edge**, **File Explorer**, and **Notepad** to the Start Menu by default.

> `Start.bin` (if applicable) goes in:
> `C:\Users\Default\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState`

---

## Step 3 – Debloat Windows

Run `Uninstall-WinApps.ps1` to remove bloatware and unwanted inbox apps.

The script:
- Removes Appx packages and provisioned packages for all users, except whitelisted apps
- Disables OneDrive autostart (does not uninstall)
- Removes the new Outlook app
- Optionally removes the Microsoft Store
- Disables Windows consumer features via Group Policy registry keys

**Whitelisted apps** (kept during debloat):

| Package Name | Description |
|---|---|
| `Microsoft.WindowsStore` | Microsoft Store |
| `Microsoft.DesktopAppInstaller` | Required for winget |
| `Microsoft.SecHealthUI` | Windows Security UI |
| `Microsoft.UI.Xaml` | UI framework dependency |
| `Microsoft.VCLibs` | Runtime dependency |
| `Microsoft.NET.Native` | Runtime dependency |
| `Microsoft.Windows.ShellExperienceHost` | Shell component |
| `Microsoft.Windows.StartMenuExperienceHost` | Start Menu |
| `Microsoft.WindowsNotepad` | Notepad |
| `Microsoft.WindowsTerminal` | Windows Terminal |
| `Microsoft.Windows.Photos` | Microsoft Photos |

---

## Step 4 – Install AutoPilot Module & Initialise Winget

Run `Install-Module.ps1` to install the AutoPilot PowerShell module and initialise the Desktop App Installer (winget) COM server.

The script:
1. Installs the **`WindowsAutoPilotIntune`** module and **`Get-WindowsAutoPilotInfo`** script
2. Runs `winget --info` to activate the COM server and App Execution Alias infrastructure
3. Runs `winget source update` to download the initial source index

> **This step is required.** If winget has never been run on the template machine, all winget package installations on deployed VMs will fail with exit code `0x8A150002`.

> Note: All other PowerShell modules are installed automatically by VMDeploy at deployment time.

---

## Step 5 – Compact and Clean Up

Run the following commands inside the VM before the final cleanup step:

```powershell
# Run a full Disk Cleanup including system files (recommended)
cleanmgr.exe /sageset:65535
cleanmgr.exe /sagerun:65535

# Compact the OS (reduces VHDX size)
Compact.exe /CompactOS:always

# Turn off BitLocker if enabled (Enabled by default)
Manage-bde -off C:
```

> **Tip:** `cleanmgr /sageset:65535` opens the Disk Cleanup UI where you can select all categories (including system files). Running `/sagerun:65535` afterwards executes the cleanup silently with those settings.

---

## Step 6 – Remove Temp Files (offline)

Shut down the VM, mount the VHDX on the host, and run `Remove-TempFiles.ps1` to clean up the offline image.

> Update the `$drive` variable in `Remove-TempFiles.ps1` to match the assigned drive letter before running.

Unmount the VHDX and start the VM again.

---

## Step 7 – Sysprep

Run `Invoke-SysprepPrep.ps1` as the **very last action** before the VM shuts down. Do NOT run winget between this script and sysprep.

The script:
1. Removes all `Microsoft.Winget.Source` per-user packages — these are per-user source index caches created when winget updates its sources. They are not provisioned for all users and **will cause sysprep to fail** if not removed.
2. Disables all network adapters to prevent background tasks from re-triggering a source update before sysprep.
3. Runs `sysprep /generalize /oobe /shutdown`.

The script removes:
- Windows Update download cache
- Temp files (system and user profiles)
- Prefetch and log files
- Recycle Bin contents
- Runs `DISM /Cleanup-Image /StartComponentCleanup /ResetBase` on the offline image

```powershell
Mount-VHD "D:\VMNAME\Virtual Hard Disks\DISKNAME.vhdx"
# Assign a drive letter in Disk Management, e.g. D:

# Run cleanup script against the mounted drive
# (update $drive in Remove-TempFiles.ps1 to correct drive letter if needed.)
.\Remove-TempFiles.ps1

defrag D: /h /x
defrag D: /h /k /l
defrag D: /h /x
defrag D: /h /k

Dismount-VHD "D:\VMNAME\Virtual Hard Disks\DISKNAME.vhdx"
Optimize-VHD "D:\VMNAME\Virtual Hard Disks\DISKNAME.vhdx" -Mode Full
```

> **Tip:** If your device policys have FDV Deny Write Access enabled, you need to disable this to perform this stage. 
> Reg Value: HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FVE.
> FDVDenyWriteAccess = 0

The VHDX is now ready to be used by VMDeploy.