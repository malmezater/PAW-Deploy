# PAW-Deploy

**PAW-Deploy** is a PowerShell-based deployment solution for setting up a **Privileged Access Workstation (PAW)** on Windows 11. It automates the installation and configuration of Hyper-V, network switches, firewall rules, and the **VMDeploy** tool used to provision Windows and Linux virtual machines from pre-built VHDX templates.

The solution is designed to be deployed via **Microsoft Intune** (as a Win32 app) or run manually by an administrator, and it tracks installation state through the Windows registry to make every stage idempotent and re-runnable.

---

## Version

- Installer version: **2.2.1**
- Default VHDX tag: **Win11-25H2**

<p align="center">
  <a href="https://github.com/malmezater/PAW-Deploy/releases/latest" rel="nofollow"><img src="https://badgen.net/github/release/malmezater/PAW-Deploy" alt="Latest release" style="max-width: 100%;"></a>
  <br>
  <a href="https://github.com/malmezater/PAW-Deploy/commits/main" rel="nofollow"><img src="https://badgen.net/github/last-commit/malmezater/PAW-Deploy" alt="Last commit" style="max-width: 100%;"></a>
  <img src="https://badgen.net/badge/PowerShell/%E2%89%A5%205.1/blue" alt="PowerShell 5.1+" style="max-width: 100%;">
</p>

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Installation](#installation)
- [Installation Stages](#installation-stages)
- [Registry Layout](#registry-layout)
- [Logging](#logging)
- [Exit Codes](#exit-codes)
- [Uninstall / Re-run](#uninstall--re-run)
- [Creating a Template VHDX](#creating-a-template-vhdx)
- [In-Guest Application & Module Selection](#in-guest-application--module-selection)

---

## Overview

A PAW (Privileged Access Workstation) is a hardened endpoint used by administrators to perform sensitive tasks in isolation from a user's day-to-day workstation. This project turns a standard Windows 11 device into a PAW host by:

1. Enabling Hyper-V and related Windows Optional Features.
2. Creating a Hyper-V external switch bound to the active physical NIC.
3. Configuring the firewall rules required by Hyper-V remoting.
4. Adding the signed-in user to the **Hyper-V Administrators** group and creating a local `Hypervuser` service account.
5. Deploying the **VMDeploy** application (PowerShell + UI shortcuts) to `C:\ProgramData\VMDeploy`.
6. Downloading a pre-built Windows 11 VHDX template via AzCopy.

Once installed, the administrator can launch **VM Deploy** from the Start menu to spin up Windows (or Linux/Kali) guest VMs on demand.

---

## Architecture

```
Install-PAWDeploy.ps1   (Intune entry point / orchestrator)
        │
        ├── Stage 1 : Install-Features_for_PAW.ps1   → enables Hyper-V features
        ├── Stage 2a: Configure-PAWNetwork.ps1       → creates "Ethernet Cable" VMSwitch
        ├── Stage 2b: Set-FirewallRules.ps1          → disables blocking firewall rules
        ├── Stage 2c: Add-HyperVAdmin.ps1            → group membership + service account
        ├── Stage 3 : Install-VMDeploy.ps1           → Robocopy app + Start menu shortcuts
        └── Stage 4 : download-vhdx.ps1              → downloads Windows 11 VHDX (Azure / SMB / HTTP)
```

Each stage:

- Imports the shared [Settings.psm1](Install%20PAWDeploy/Settings.psm1) module.
- Calls `Initialize-DeployEnvironment` to create log/download folders and the registry key.
- Writes a "stamp" value to the registry on success so the orchestrator can skip it next time.

---

## Repository Structure

| Path | Purpose |
| --- | --- |
| [Install PAWDeploy/](Install%20PAWDeploy/) | Current production installer (run by Intune). |
| [Install PAWDeploy/Install-PAWDeploy.ps1](Install%20PAWDeploy/Install-PAWDeploy.ps1) | Top-level orchestrator that runs all four stages. |
| [Install PAWDeploy/Settings.psm1](Install%20PAWDeploy/Settings.psm1) | Shared module with paths, registry keys, and config. |
| [Install PAWDeploy/1_Install-Features_for_PAW/](Install%20PAWDeploy/1_Install-Features_for_PAW/) | Stage 1 - Hyper-V feature enablement. |
| [Install PAWDeploy/2_Install_VMDeploy-configuration/](Install%20PAWDeploy/2_Install_VMDeploy-configuration/) | Stage 2 - Network switch, firewall rules, Hyper-V admins. |
| [Install PAWDeploy/3_Install_VMDeploy/](Install%20PAWDeploy/3_Install_VMDeploy/) | Stage 3 - Deploys the VMDeploy application files. |
| [Install PAWDeploy/4_Download_Windows_VHDX/](Install%20PAWDeploy/4_Download_Windows_VHDX/) | Stage 4 - Downloads the Windows 11 VHDX template (Azure Blob, SMB share, or HTTP/HTTPS). |

---

## Prerequisites

- Windows 11 (Pro/Enterprise) with virtualization enabled in firmware.
- Local administrator rights (Intune runs as SYSTEM).
- PowerShell 5.1 or later (`#Requires -Version 5.1` in every script).
- An active physical network adapter (used to bind the Hyper-V external switch).
- Access to the VHDX source configured in `$DownloadUrl` in `Settings.psm1`:
  - **Azure Blob/Files URL** — also requires internet access to `https://aka.ms/downloadazcopy-v10-windows` (AzCopy is auto-installed on demand).
  - **SMB/UNC share** — requires network path access to the file server.
  - **HTTP/HTTPS web server** — requires access to the internal or external web server.

---

## Configuration

All deployment-wide settings live in [Install PAWDeploy/Settings.psm1](Install%20PAWDeploy/Settings.psm1). Edit the user-configurable block **before packaging** the installer:

```powershell
$Script:CompanyName  = "COMPANY NAME"   # Used in registry path and ProgramData folder
$Script:DownloadUrl  = "Download URL"   # Full SAS / HTTPS URL to the VHDX
$Script:VHDXVersion  = "Win11-25H2"     # Stored as a registry stamp
$Script:LocalInstall = $true            # $true = local install (shortcuts created); $false = Intune/ConfigMgr (no shortcuts)
```

Derived values that you normally should not need to change:

| Variable | Value |
| --- | --- |
| `$ScriptVersion` | `2.2.1` |
| `$SoftwareName` | `VMDeploy` |
| `$DeployPath` | `C:\ProgramData\<CompanyName>` |
| `$DeployITLogs` | `C:\ProgramData\<CompanyName>\Logs` |
| `$VHDXDownloadPath` | `C:\ProgramData\VMDeploy\Images\Windows11.vhdx` |
| `$RegistrySoftwareName` | `HKLM:\SOFTWARE\<CompanyName>\VMDeploy` |

The module also defines the list of Hyper-V features to enable (`$HyperVFeatures`) and the firewall rules to disable (`$FirewallRules`).

---

## Installation

### Run manually (testing)

From an elevated PowerShell prompt:

```powershell
PowerShell.exe -ExecutionPolicy Bypass -NoProfile -File "Install-PAWDeploy.ps1"
```

If Stage 1 enables Hyper-V for the first time, the script exits with code **1641** (reboot required). Reboot and re-run; the orchestrator will skip already-completed stages.

### Deploy via Intune (Win32 app)

1. Edit `Settings.psm1` with your company name and VHDX URL.
2. Wrap the `Install` folder with the Microsoft Win32 Content Prep Tool (`IntuneWinAppUtil.exe`).
3. In Intune, configure the app with:
   - **Install command:**
     ```
     PowerShell.exe -ExecutionPolicy ByPass -NoProfile -WindowStyle Hidden -File Install-PAWDeploy.ps1
     ```
   - **Uninstall command:** your preferred uninstall script (manually delete `C:\ProgramData\VMDeploy` and any Start menu shortcuts; see the [Uninstall / Re-run](#uninstall--re-run) section).
   - **Detection rule:** registry value
     `HKLM:\SOFTWARE\<CompanyName>\VMDeploy` → `VMDeployVersion` equals `2.2.1`.
   - **Behavior:** install as **system**; allow **device restart** (exit code 1641).

---

## Installation Stages

| Stage | Script | What it does | Registry stamp |
| --- | --- | --- | --- |
| 1 | [Install-Features_for_PAW.ps1](Install%20PAWDeploy/1_Install-Features_for_PAW/Install-Features_for_PAW.ps1) | Enables all required Hyper-V Optional Features (with a 3-attempt verification loop). | One value per feature (e.g. `Microsoft-Hyper-V-All = Enabled`). |
| 2a | [Configure-PAWNetwork.ps1](Install%20PAWDeploy/2_Install_VMDeploy-configuration/Configure-PAWNetwork.ps1) | Creates an external VMSwitch named **"Ethernet Cable"** on the first active physical NIC. | `PawNetwork = True` |
| 2b | [Set-FirewallRules.ps1](Install%20PAWDeploy/2_Install_VMDeploy-configuration/Set-FirewallRules.ps1) | Disables Hyper-V remoting firewall rules that interfere with PAW usage. | One value per rule name. |
| 2c | [Add-HyperVAdmin.ps1](Install%20PAWDeploy/2_Install_VMDeploy-configuration/Add-HyperVAdmin.ps1) | Adds the signed-in user to the **Hyper-V Administrators** local group and creates the `Hypervuser` service account. | `HyperV-Admins = True` |
| 3 | [Install-VMDeploy.ps1](Install%20PAWDeploy/3_Install_VMDeploy/Install-VMDeploy.ps1) | Robocopies the `Source/VMDeploy` tree to `C:\ProgramData\VMDeploy`. Creates Start Menu shortcuts (Run as administrator) only when `$LocalInstall = $true` in `Settings.psm1`. Set to `$false` for Intune/ConfigMgr deployments. | `VMDeployVersion = 2.2.1` |
| 4 | [download-vhdx.ps1](Install%20PAWDeploy/4_Download_Windows_VHDX/download-vhdx.ps1) | Downloads the Windows 11 VHDX template to `C:\ProgramData\VMDeploy\Images\Windows11.vhdx`. Automatically selects the transfer method based on `$DownloadUrl`: Azure Blob/Files → AzCopy (auto-installed), `\\server\share` → Copy-Item, HTTP/HTTPS → BITS with Invoke-WebRequest fallback. | `WindowsVHDX = Win11-25H2` |

The orchestrator skips any stage whose stamp matches the expected value, making the installer safe to re-run.

---

## Registry Layout

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

---

## Logging

All scripts write transcripts to:

```
C:\ProgramData\<CompanyName>\Logs\
```

File names include the script name and date stamp (`yyMMdd`), for example `Install-VMDeploy-260528.log`.

---

## Exit Codes

| Code | Meaning |
| --- | --- |
| `0` | Stage / installation completed successfully. |
| `1` | A stage failed; check the matching log file in the Logs folder. |
| `1641` | Reboot required after Hyper-V feature install (Intune treats this as success and reboots). |

---

## Uninstall / Re-run

- To force a stage to re-run, delete its registry stamp under `HKLM:\SOFTWARE\<CompanyName>\VMDeploy` and re-run the orchestrator.
- To remove VMDeploy itself, manually delete `C:\ProgramData\VMDeploy` and the Start menu shortcuts.

---

## In-Guest Application & Module Selection

When you launch **VM Deploy** and pick a template, the UI now shows two checklists
on the right side:

- **Applications** - `winget` package IDs to install inside the guest VM.
- **PowerShell Modules** - modules installed from PSGallery into the
  **AllUsers** scope at their **latest** version.

Both checklists are populated per template via two new XML catalogs that ship
next to `Config.xml`:

| File | Purpose |
| --- | --- |
| [Apps.xml](Install%20PAWDeploy/3_Install_VMDeploy/Source/VMDeploy/Apps.xml) | Defines named profiles of winget application IDs. |
| [Modules.xml](Install%20PAWDeploy/3_Install_VMDeploy/Source/VMDeploy/Modules.xml) | Defines named profiles of PowerShell module names. |

A template references a profile by name in [Config.xml](Install%20PAWDeploy/3_Install_VMDeploy/Source/VMDeploy/Config.xml):

```xml
<Template Name="Windows 11 - WORKGROUP">
  ...
  <AppProfile>PAW-Workgroup</AppProfile>
  <ModuleProfile>PAW-Workgroup</ModuleProfile>
</Template>
```

If a template has no `AppProfile` / `ModuleProfile`, the corresponding checklist
is disabled. **Intune OOBE** templates intentionally skip both steps (the VM is
sysprepped, so app/module configuration should be delivered via Intune).

### Apps.xml format

```xml
<AppProfiles>
  <Profile Name="PAW-Workgroup">
    <App Id="Microsoft.VisualStudioCode" DisplayName="Visual Studio Code" Default="True"  />
    <App Id="Git.Git"                    DisplayName="Git"                Default="False" />
    <!-- ... -->
  </Profile>
</AppProfiles>
```

- `Id` - the exact winget package ID (`winget search <name>` to look it up).
- `DisplayName` - friendly text shown in the UI.
- `Default="True"` - pre-checks the item in the UI.

### Modules.xml format

```xml
<ModuleProfiles>
  <Profile Name="PAW-Workgroup">
    <Module Name="Microsoft.Graph"          DisplayName="Microsoft Graph"            Default="True"  />
    <Module Name="Az"                       DisplayName="Azure Az"                   Default="True"  />
    <Module Name="ExchangeOnlineManagement" DisplayName="Exchange Online Management" Default="True"  />
    <!-- ... -->
  </Profile>
</ModuleProfiles>
```

- `Name` - the exact PSGallery module name as used by `Install-Module`.
- Modules are installed with `Install-Module -Scope AllUsers -Force -AllowClobber`
  (always the latest version available on PSGallery).

### How it runs

After the VM has booted and BitLocker has finished encrypting, [VMDeploy.ps1](Install%20PAWDeploy/3_Install_VMDeploy/Source/VMDeploy/VMDeploy.ps1) connects to the guest via **PowerShell Direct** (`Invoke-Command -VMName`) as `\Administrator` and runs the following steps in order:

**1. Register winget**

The Desktop App Installer (winget) is provisioned system-wide on Windows 11, but its App Execution Alias is only created per-user on the first interactive logon. On a freshly deployed VM the `Administrator` account has never logged in interactively, so `VMDeploy.ps1` registers it explicitly with `Add-AppxPackage -Register -DisableDevelopmentMode` before attempting any installations.

**2. Winget applications**

Each selected app is installed in its own isolated `Invoke-Command` call:
- Uses `winget.exe --scope machine --exact --silent` so packages install to `Program Files` and are visible to all users after reboot.
- If an installer (e.g. Azure CLI) restarts the Windows Installer service mid-install and kills the Hyper-V socket, the script reconnects via `Wait-VIAVMHavePSDirect` and **retries the package automatically**.
- Packages that only support user scope are retried without `--scope machine`.

**3. PowerShell modules**

A single `Invoke-Command` installs all selected modules with `Install-Module -Scope AllUsers -Force -AllowClobber -Repository PSGallery` after ensuring TLS 1.2, the NuGet provider, and a trusted PSGallery.

Both steps are skipped entirely for **Intune OOBE** templates (the VM is sysprepped — app and module delivery happens via Intune after enrollment).

Every package and module result is logged in the deploy transcript with its exit code / installed version so failures are visible without stopping the rest of the deployment.

> **Network requirement:** the guest VM must reach `cdn.winget.microsoft.com` and `www.powershellgallery.com`. In isolated PAW networks you may need an internal mirror or an outbound allow-list.

> **PowerShell 7 note:** Modules are installed into Windows PowerShell 5.1's `C:\Program Files\WindowsPowerShell\Modules`. To also get PowerShell 7, add `Microsoft.PowerShell` to the app list — PS7 picks up the 5.1 modules automatically via its compatibility module path.

---

## Creating a Template VHDX

Building the reference Windows 11 image that ships as `Windows11.vhdx` typically involves the following preparation steps before sysprep:

- **Install PowerShell modules** — install Graph / Intune / AutoPilot modules used during image preparation.
- **Uninstall built-in Store apps** — remove unwanted pre-installed Microsoft Store apps.
- **Clean temp files** — clean temp folders prior to sysprep.
- **Apply Start layout** — a `LayoutModification.xml` can be applied to customise the Start menu.

After running these and a `sysprep /generalize /oobe /shutdown`, the resulting VHDX is placed in the location referenced by `$DownloadUrl` in `Settings.psm1` (Azure Blob storage, an SMB share, or a web server).

---

## Thank you to
[Mikael Nyström (DeploymentBunny)](https://github.com/DeploymentBunny).
