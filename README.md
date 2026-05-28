# PAW-Deploy

**PAW-Deploy** is a PowerShell-based deployment solution for setting up a **Privileged Access Workstation (PAW)** on Windows 11. It automates the installation and configuration of Hyper-V, network switches, firewall rules, and the **VMDeploy** tool used to provision Windows and Linux virtual machines from pre-built VHDX templates.

The solution is designed to be deployed via **Microsoft Intune** (as a Win32 app) or run manually by an administrator, and it tracks installation state through the Windows registry to make every stage idempotent and re-runnable.

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
- [Legacy Content](#legacy-content)

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
Install-VMDeploy.ps1   (Intune entry point / orchestrator)
        │
        ├── Stage 1 : Install-Features_for_PAW.ps1   → enables Hyper-V features
        ├── Stage 2a: Configure-PAWNetwork.ps1       → creates "Ethernet Cable" VMSwitch
        ├── Stage 2b: Set-FirewallRules.ps1          → disables blocking firewall rules
        ├── Stage 2c: Add-HyperVAdmin.ps1            → group membership + service account
        ├── Stage 3 : Install-VMDeploy.ps1           → Robocopy app + Start menu shortcuts
        └── Stage 4 : download-vhdx.ps1              → AzCopy Windows 11 template
```

Each stage:

- Imports the shared [Settings.psm1](Install/Settings.psm1) module.
- Calls `Initialize-DeployEnvironment` to create log/download folders and the registry key.
- Writes a "stamp" value to the registry on success so the orchestrator can skip it next time.

---

## Repository Structure

| Path | Purpose |
| --- | --- |
| [Install/](Install/) | Current production installer (run by Intune). |
| [Install/Install-VMDeploy.ps1](Install/Install-VMDeploy.ps1) | Top-level orchestrator that runs all four stages. |
| [Install/Settings.psm1](Install/Settings.psm1) | Shared module with paths, registry keys, and config. |
| [Install/1_Install-Features_for_PAW/](Install/1_Install-Features_for_PAW/) | Stage 1 — Hyper-V feature enablement. |
| [Install/2_Install_VMDeploy-configuration/](Install/2_Install_VMDeploy-configuration/) | Stage 2 — Network switch, firewall rules, Hyper-V admins. |
| [Install/3_Install_VMDeploy/](Install/3_Install_VMDeploy/) | Stage 3 — Deploys the VMDeploy application files. |
| [Install/4_Download_Windows_VHDX/](Install/4_Download_Windows_VHDX/) | Stage 4 — AzCopy download of the Windows 11 VHDX template. |

---

## Prerequisites

- Windows 11 (Pro/Enterprise) with virtualization enabled in firmware.
- Local administrator rights (Intune runs as SYSTEM).
- PowerShell 5.1 or later (`#Requires -Version 5.1` in every script).
- An active physical network adapter (used to bind the Hyper-V external switch).
- Internet access to:
  - `https://aka.ms/downloadazcopy-v10-windows` (AzCopy installer)
  - The VHDX download URL configured in `Settings.psm1`.

---

## Configuration

All deployment-wide settings live in [Install/Settings.psm1](Install/Settings.psm1). Edit the user-configurable block **before packaging** the installer:

```powershell
$Script:CompanyName  = "COMPANY NAME"   # Used in registry path and ProgramData folder
$Script:DownloadUrl  = "Download URL"   # Full SAS / HTTPS URL to the VHDX
$Script:VHDXVersion  = "Win11-25H2"     # Stored as a registry stamp
```

Derived values that you normally should not need to change:

| Variable | Value |
| --- | --- |
| `$ScriptVersion` | `2.0.4` |
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
PowerShell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install\Install-VMDeploy.ps1
```

If Stage 1 enables Hyper-V for the first time, the script exits with code **1641** (reboot required). Reboot and re-run; the orchestrator will skip already-completed stages.

### Deploy via Intune (Win32 app)

1. Edit `Settings.psm1` with your company name and VHDX URL.
2. Wrap the `Install` folder with the Microsoft Win32 Content Prep Tool (`IntuneWinAppUtil.exe`).
3. In Intune, configure the app with:
   - **Install command:**
     ```
     PowerShell.exe -ExecutionPolicy ByPass -NoProfile -WindowStyle Hidden -File Install-VMDeploy.ps1
     ```
   - **Uninstall command:** your preferred uninstall script (see [Windows11/Start-VMDeploy/Remove VMDeploy/](Windows11/Start-VMDeploy/Remove%20VMDeploy/)).
   - **Detection rule:** registry value
     `HKLM:\SOFTWARE\<CompanyName>\VMDeploy` → `VMDeployVersion` equals `2.0.4`.
   - **Behavior:** install as **system**; allow **device restart** (exit code 1641).

---

## Installation Stages

| Stage | Script | What it does | Registry stamp |
| --- | --- | --- | --- |
| 1 | [Install-Features_for_PAW.ps1](Install/1_Install-Features_for_PAW/Install-Features_for_PAW.ps1) | Enables all required Hyper-V Optional Features (with a 3-attempt verification loop). | One value per feature (e.g. `Microsoft-Hyper-V-All = Enabled`). |
| 2a | [Configure-PAWNetwork.ps1](Install/2_Install_VMDeploy-configuration/Configure-PAWNetwork.ps1) | Creates an external VMSwitch named **"Ethernet Cable"** on the first active physical NIC. | `PawNetwork = True` |
| 2b | [Set-FirewallRules.ps1](Install/2_Install_VMDeploy-configuration/Set-FirewallRules.ps1) | Disables Hyper-V remoting firewall rules that interfere with PAW usage. | One value per rule name. |
| 2c | [Add-HyperVAdmin.ps1](Install/2_Install_VMDeploy-configuration/Add-HyperVAdmin.ps1) | Adds the signed-in user to the **Hyper-V Administrators** local group and creates the `Hypervuser` service account. | `HyperV-Admins = True` |
| 3 | [Install-VMDeploy.ps1](Install/3_Install_VMDeploy/Install-VMDeploy.ps1) | Robocopies the `Source/VMDeploy` tree to `C:\ProgramData\VMDeploy` and creates Start menu shortcuts (with the "Run as administrator" flag). | `VMDeployVersion = 2.0.4` |
| 4 | [download-vhdx.ps1](Install/4_Download_Windows_VHDX/download-vhdx.ps1) | Installs AzCopy on demand and downloads the Windows 11 VHDX template to `C:\ProgramData\VMDeploy\Images\Windows11.vhdx`. | `WindowsVHDX = Win11-25H2` |

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
- To remove VMDeploy itself, use the Intune package in [Windows11/Start-VMDeploy/Remove VMDeploy/](Windows11/Start-VMDeploy/Remove%20VMDeploy/) or manually delete `C:\ProgramData\VMDeploy` and the Start menu shortcuts.

---

## Creating a Template VHDX

The [Create Templade VHDX/](Create%20Templade%20VHDX/) folder contains helpers used when building the reference Windows 11 image that ships as `Windows11.vhdx`:

- [Install-Module.ps1](Create%20Templade%20VHDX/Install-Module.ps1) — installs Graph / Intune / AutoPilot PowerShell modules used during image preparation.
- [Uninstall-WinApps.ps1](Create%20Templade%20VHDX/Uninstall-WinApps.ps1) — removes pre-installed Microsoft Store apps.
- [Remove-TempFiles.ps1](Create%20Templade%20VHDX/Remove-TempFiles.ps1) — cleans temp folders prior to sysprep.
- [LayoutModification.xml](Create%20Templade%20VHDX/LayoutModification.xml) — Start menu layout applied to the template.

After running these and a `sysprep /generalize /oobe /shutdown`, the resulting VHDX is uploaded to the storage account referenced by `$DownloadUrl` in `Settings.psm1`.

---

## Legacy Content

The [Windows11/Old/](Windows11/Old/) directory contains the earlier, single-stage versions of these scripts (pre-orchestrator). They are kept for reference but are **not** used by the current installer. Use the scripts in [Install/](Install/) for all new deployments.

---

## Version

- Installer version: **2.0.4**
- Default VHDX tag: **Win11-25H2**

Refrence and thank you to Mikael Nyström. 
[https://github.com/DeploymentBunny/PAWDeplo](https://github.com/DeploymentBunny/PAWDeploy)
Thank you [Mikael Nyström (DeploymentBunny)](https://github.com/DeploymentBunny).
