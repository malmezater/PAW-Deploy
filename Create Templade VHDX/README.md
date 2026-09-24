# Create Template VHDX

Builds the generalized (sysprepped) Windows 11 Enterprise VHDX that VMDeploy uses as the base image for every VM.

PowerShell modules and winget apps do **not** need to be installed here. VMDeploy installs them on each VM at deployment time.

| Result | Typical size |
|---|---|
| Template after steps 1–11 | ~20 GB VHDX |
| Template after the [rebuild tip](#tip--rebuild-the-vhdx-for-a-much-smaller-file) | ~13–16 GB VHDX (+ ~4–5 GB WIM backup) |

---

## Files in this folder

| File | Runs | Purpose |
|---|---|---|
| `LayoutModification.xml` | In VM | Default Start menu / taskbar pins (Edge, Explorer, Notepad) |
| `Uninstall-WinApps.ps1` | In VM | Removes inbox apps and OneDrive, keeps winget and its dependencies |
| `Install-Module.ps1` | In VM | Installs the AutoPilot module/script and initialises winget |
| `Optimize-Template.ps1` | In VM | Removes unneeded features, cleans WinSxS, caches and logs, compacts the OS |
| `Invoke-SysprepPrep.ps1` | In VM | Removes the per-user winget source, disables the network, runs sysprep |
| `Remove-TempFiles.ps1` | On host | Offline cleanup of the mounted VHDX after sysprep |
| `Rebuild-TemplateVHDX.ps1` | On host | Optional: rebuilds the VHDX via a WIM for a much smaller file |

> Run every script in **Windows PowerShell 5.1** (`powershell.exe`) as Administrator — **not** PowerShell 7. Check with `$PSVersionTable.PSVersion` (should be 5.1.x). In Windows Terminal, pick **Windows PowerShell** from the ▾ menu.

---

## Prerequisites

- Hyper-V host with ~60 GB free disk
- Internet access for the template VM (Windows Update, PowerShell Gallery, winget)
- A Windows 11 Enterprise ISO (step 1)

---

## Step 1 – Download a Windows 11 Enterprise ISO (host)

The consumer ISO from microsoft.com only contains Home/Pro/Education. Use the **Media Creation Tool** in business mode to get an ISO that includes Enterprise:

1. Download `MediaCreationTool.exe` from Microsoft's Windows 11 download page.
2. Run from an **elevated** command prompt:

   ```cmd
   MediaCreationTool.exe /Eula Accept /Retail /MediaArch x64 /MediaLangCode en-US /MediaEdition Enterprise
   ```

   Change `/MediaLangCode` if you want another language (e.g. `sv-SE`).
3. When asked for a product key, enter the public Enterprise KMS client key (GVLK): `NPPR9-FWDCX-D2C8J-H872K-2YT43`. It only selects the edition — it does not activate anything.
4. Choose **ISO file** and save it.

> **Error `0x80070006 - 0x90018`:** leftovers from an earlier attempt. Delete `C:\$Windows.~WS`, `C:\$Windows.~BT` and `C:\ESD`, reboot and try again — or run it on another machine.
>
> **Error `0x80072F8F` / `0x80072EE7`:** the tool can't reach Microsoft (clock, TLS 1.2, proxy or SSL inspection).

---

## Step 2 – Create the template VM (host)

```powershell
$vm   = "Win11-Template"
$vhdx = "C:\VMs\$vm\$vm.vhdx"
$iso  = "C:\ISO\Win11_Enterprise.iso"

New-VM -Name $vm -Generation 2 -MemoryStartupBytes 4GB -NewVHDPath $vhdx -NewVHDSizeBytes 64GB -SwitchName "Default Switch"
Set-VMProcessor      -VMName $vm -Count 2
Set-VM               -VMName $vm -CheckpointType Disabled -AutomaticCheckpointsEnabled $false
Set-VMFirmware       -VMName $vm -SecureBootTemplate MicrosoftWindows
Set-VMKeyProtector   -VMName $vm -NewLocalKeyProtector
Enable-VMTPM         -VMName $vm
Add-VMDvdDrive       -VMName $vm -Path $iso
Set-VMFirmware       -VMName $vm -FirstBootDevice (Get-VMDvdDrive -VMName $vm)
Start-VM $vm
```

> Keep checkpoints **off** for the whole build. A checkpoint moves data into an `.avhdx` and breaks the size optimisation later.

---

## Step 3 – Install Windows and enter Audit Mode (VM)

1. Install Windows and pick **Windows 11 Enterprise**.
2. On the **first OOBE screen** (region selection), press **`CTRL + Shift + F3`**.
   The VM reboots into **Audit Mode** and logs on as the built-in Administrator. Close the Sysprep dialog that opens — the VM stays in Audit Mode across reboots until sysprep runs in step 9.

---

## Step 4 – Prepare the OS (VM, manual)

Run in Windows PowerShell 5.1 as Administrator.

**1. Stop automatic device encryption.** A VM with a vTPM encrypts its disk automatically, and an encrypted disk can't be compacted:

```powershell
reg add HKLM\SYSTEM\CurrentControlSet\Control\BitLocker /v PreventDeviceEncryption /t REG_DWORD /d 1 /f
manage-bde -status C:          # must show "Fully Decrypted", 0.0 %
manage-bde -off C:             # only if it isn't - wait until decryption is finished
```

**2. Windows Update.** Settings → Windows Update → install everything, reboot, and repeat until nothing more is offered.

**3. Install the manual tools:**

| Tool | Note |
|---|---|
| `C:\PackTools` | Create the folder - VMDeploy packages download their tools here |
| .NET Framework 3.5 | **Only if something on the VMs needs it** (adds several hundred MB) — Windows Features |

> The Microsoft Win32 Content Prep Tool (`IntuneWinAppUtil.exe`) no longer needs to be baked into the template — check the **Intune Packaging** package in VM Deploy and it is downloaded to `C:\PackTools\IntuneWinAppUtil` on every deployment (always the latest version).

**4. Copy this folder into the VM**, e.g. from the host with PowerShell Direct:

```powershell
$s = New-PSSession -VMName $vm -Credential (Get-Credential Administrator)
Copy-Item "C:\Temp\Github\PAW-Deploy-Preview\Create Templade VHDX" -Destination C:\Temp\Template -ToSession $s -Recurse
```

(or copy/paste the files through an Enhanced Session). The rest of the steps run from `C:\Temp\Template` inside the VM.

---

## Step 5 – Start menu layout (VM)

```powershell
Copy-Item C:\Temp\Template\LayoutModification.xml `
  "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml" -Force
```

The layout pins **Microsoft Edge**, **File Explorer** and **Notepad**.

---

## Step 6 – Debloat (VM)

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
C:\Temp\Template\Uninstall-WinApps.ps1
```

The script:

- Removes provisioned packages first, then installed packages for all users (keeps sysprep happy)
- Skips system apps, frameworks and non-removable packages automatically (shell, Start, search, OOBE)
- Uninstalls OneDrive and removes `OneDriveSetup` from the Default user profile
- Removes the Microsoft Store (`$removeStore = $true`; winget works without it)
- Disables consumer features (re-install of suggested apps)
- Lists any package that is installed per user but not provisioned — those would block sysprep

**Kept packages:**

| Package | Why |
|---|---|
| `Microsoft.DesktopAppInstaller` | winget |
| `Microsoft.WindowsAppRuntime*`, `Microsoft.UI.Xaml*`, `Microsoft.VCLibs*`, `Microsoft.NET.Native*` | winget dependencies |
| `Microsoft.SecHealthUI` | Windows Security |
| `Microsoft.LanguageExperiencePack*` | Display language |
| `Microsoft.AAD.BrokerPlugin`, `Microsoft.AccountsControl` | Entra ID sign-in |
| `Microsoft.WindowsNotepad`, `Microsoft.WindowsTerminal`, `Microsoft.Windows.Photos` | Apps we want |

Calculator, Snipping Tool and Quick Assist are commented out in `$keep` — uncomment to keep them. Edge, Explorer and PowerShell are not Appx packages and are never touched.

---

## Step 7 – AutoPilot module and winget (VM)

```powershell
C:\Temp\Template\Install-Module.ps1
```

Installs the `WindowsAutoPilotIntune` module and `Get-WindowsAutoPilotInfo` script, then runs `winget --info` and `winget source update`.

Confirm winget is **provisioned for all users** — a winget that is only installed for Administrator blocks sysprep:

```powershell
Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq Microsoft.DesktopAppInstaller
```

If nothing is returned: `Install-Module Microsoft.WinGet.Client -Force; Repair-WinGetPackageManager -AllUsers -Latest`.

> VMDeploy pushes the latest winget into every VM at deployment time, so the version in the template does not matter — it only has to be present and provisioned.

---

## Step 8 – Optimize and clean up (VM)

```powershell
C:\Temp\Template\Optimize-Template.ps1
```

Takes 15–40 minutes. It:

- Removes Features on Demand a VM doesn't need (handwriting, OCR, speech, IE mode, Media Player, WordPad, PowerShell ISE, Wi-Fi drivers …)
- Disables optional features **and removes their payload** from WinSxS
- Disables Reserved Storage (up to ~7 GB) and hibernation
- Runs `DISM /StartComponentCleanup /ResetBase`
- Clears Windows Update / Delivery Optimization caches, temp, logs and event logs
- Runs `Compact.exe /CompactOS:always` and `Optimize-Volume -ReTrim`
- Prints used space before/after

**Then reboot the VM** (it comes back in Audit Mode). Removing features leaves pending operations, and sysprep refuses to run until the machine has restarted.

---

## Step 9 – Sysprep (VM)

Run as the **very last action** — do **not** run winget between this and sysprep.

```powershell
C:\Temp\Template\Invoke-SysprepPrep.ps1
```

It removes the per-user `Microsoft.Winget.Source` package, removes the leftover `defaultuser0` account that entering Audit Mode from OOBE leaves behind, disables the network adapters and runs `sysprep /generalize /oobe /shutdown /quiet`. The VM shuts down when done.

> **Never start the template VM again** after this — it would run OOBE and the template is spent.

**If sysprep fails** ("Sysprep was not able to validate your Windows installation"):

```powershell
Select-String C:\Windows\System32\Sysprep\Panther\setupact.log -Pattern "Error" | Select-Object -Last 10
```

| Log says | Fix |
|---|---|
| `Package Microsoft.Winget.Source_… was installed for a user, but not provisioned` | `Get-AppxPackage -AllUsers Microsoft.Winget.Source* \| Remove-AppxPackage -AllUsers` and don't run winget again |
| `Package <other> was installed for a user, but not provisioned` | `Get-AppxPackage -AllUsers *<name>* \| Remove-AppxPackage -AllUsers` |
| `One or more Windows updates that require a reboot` (`0x8007139f`) | Reboot the VM and run step 9 again |
| Anything about BitLocker | `manage-bde -off C:` and wait for full decryption |

> In PowerShell, run sysprep manually as `.\sysprep.exe` or with the full path — plain `sysprep` is not found.

---

## Step 10 – Offline cleanup and compaction (host)

With the VM shut down after sysprep:

```powershell
$vhdx = "C:\VMs\Win11-Template\Win11-Template.vhdx"

# 1. Offline cleanup (pagefile/swapfile, caches, logs, WinSxS)
Mount-VHD $vhdx
# Give the Windows volume a drive letter in Disk Management if it has none, e.g. E:
.\Remove-TempFiles.ps1 -Drive E:

defrag E: /h /x
defrag E: /h /k /l
defrag E: /h /x
defrag E: /h /k
Dismount-VHD $vhdx

# 2. Compact - Optimize-VHD -Mode Full only reclaims unused blocks when mounted READ-ONLY
Mount-VHD $vhdx -ReadOnly
Optimize-VHD $vhdx -Mode Full
Dismount-VHD $vhdx

"{0:N1} GB" -f ((Get-Item $vhdx).Length / 1GB)
```

> If your device policy has FDV Deny Write Access enabled, disable it first:
> `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FVE` → `FDVDenyWriteAccess = 0`

---

## Step 11 – Test and upload (host)

1. Keep a copy of the finished VHDX before testing anything.
2. Test with a **copy** — run a VMDeploy deployment against it, or attach it to a **new** Gen 2 VM (never the template VM).
3. Upload the VHDX to the storage location referenced by `$DownloadUrl` in `Settings.psm1` (Azure Blob, SMB share or web server).

---

## TIP – Rebuild the VHDX for a much smaller file

After step 10 the VHDX is usually still several GB larger than the space Windows actually uses (e.g. a 20 GB file with 12 GB used). A dynamic VHDX allocates space in **32 MB blocks**, and `Optimize-VHD` can only release a block that is completely empty — free space scattered across partly used blocks is never returned.

`Rebuild-TemplateVHDX.ps1` fixes this by rebuilding the disk (run it between step 10 and step 11):

1. Mounts the sysprepped VHDX read-only and captures the Windows volume to a compressed WIM
2. Creates a new dynamic VHDX with **1 MB blocks** (GPT: EFI + MSR + Windows)
3. Applies the WIM with CompactOS compression kept (`/Compact`) and writes the UEFI boot files with `bcdboot`

The result is still sysprepped and contains only the files, laid out contiguously.

```powershell
mkdir C:\Temp\Template -Force        # the destination folder must exist
.\Rebuild-TemplateVHDX.ps1 -Source $vhdx -Destination C:\Temp\Template\Windows11.vhdx
```

- The source VHDX must be **dismounted** and the VM **off** — the script mounts and dismounts by itself.
- The capture takes 10–20 minutes (`/Compress:max`).
- The WIM is kept next to the new VHDX (`Windows11.wim`) as a compact backup. Use `-WimPath` to put it elsewhere and `-SizeBytes` to change the max disk size (default 64 GB).
- The destination file must not exist — the script refuses to overwrite.

Measured on a real build: **20.3 GB → 15.9 GB**, before `/Compact` was added to the apply step, so expect a few GB less now. Upload the rebuilt `Windows11.vhdx` in step 11 instead of the original.
