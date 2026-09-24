# PAW-Deploy

**PAW-Deploy** is a PowerShell-based deployment solution for setting up a **Privileged Access Workstation (PAW)** on Windows 11. It automates the installation and configuration of Hyper-V, network switches, firewall rules, and the **VMDeploy** tool used to provision Windows and Linux virtual machines from pre-built VHDX templates.

The solution is designed to be deployed via **Microsoft Intune** (as a Win32 app) or run manually by an administrator, and it tracks installation state through the Windows registry to make every stage idempotent and re-runnable.

<p align="center">
  <a href="https://github.com/malmezater/PAW-Deploy/releases/latest" rel="nofollow"><img src="https://badgen.net/github/release/malmezater/PAW-Deploy/latest?cache=3600" alt="Latest release" style="max-width: 100%;"></a>
  <br>
  <a href="https://github.com/malmezater/PAW-Deploy/commits/main" rel="nofollow"><img src="https://badgen.net/github/last-commit/malmezater/PAW-Deploy/main?cache=3600" alt="Last commit" style="max-width: 100%;"></a>
  <img src="https://badgen.net/badge/PowerShell/%E2%89%A5%205.1/blue" alt="PowerShell 5.1+" style="max-width: 100%;">
  <br>
  <img src="https://badgen.net/badge/installer/2.3.2/green" alt="Installer version 2.3.2" style="max-width: 100%;">
  <img src="https://badgen.net/badge/VHDX%20tag/Win11-2609/cyan" alt="Default VHDX tag Win11-2609" style="max-width: 100%;">
  <img src="https://badgen.net/badge/Windows%2011/Enterprise/blue" alt="Windows 11 Enterprise" style="max-width: 100%;">
</p>

- Installer version: **2.3.2**
- Default VHDX tag: **Win11-2609**

---

## What it does

A PAW (Privileged Access Workstation) is a hardened endpoint used by administrators to perform sensitive tasks in isolation from a user's day-to-day workstation. This project turns a standard Windows 11 device into a PAW host by:

1. Enabling Hyper-V and related Windows Optional Features.
2. Creating a Hyper-V external switch bound to the configured (or first active) physical NIC.
3. Configuring the firewall rules required by Hyper-V remoting.
4. Adding the signed-in user to the **Hyper-V Administrators** group and, in interactive installs, creating a local `Hypervuser` service account.
5. Deploying the **VMDeploy** application (PowerShell + UI shortcuts) to `C:\ProgramData\VMDeploy`.
6. Downloading a pre-built Windows 11 VHDX template.

Once installed, the administrator launches **VM Deploy** from the Start menu to spin up Windows (or Linux/Kali) guest VMs on demand. VM Deploy installs the selected winget applications, PowerShell modules and **packages** into the new VM, for example:

| Package | Installs |
| --- | --- |
| **Security Audit** | PowerShell 7, Azure CLI, Python, the Azure audit modules (Maester, PSRule, WARA, ARI and more), and [Simple Azure Audit](https://github.com/malmezater/Simple-Azure-Audit) in `C:\PackTools`. |
| **Azure DevOps** | PowerShell 7, Windows Terminal, Azure CLI, Bicep, Terraform, Git, VS Code, GitHub Desktop, Az, Microsoft Graph, PSScriptAnalyzer and Pester. |
| **Intune Packaging** | The Microsoft Win32 Content Prep Tool (`IntuneWinAppUtil.exe`) in `C:\PackTools\IntuneWinAppUtil`, for building `.intunewin` packages. |

Create your own from [docs/templates/Package-Template.xml](docs/templates/Package-Template.xml).

## Repository structure

| Path | Purpose |
| --- | --- |
| [Install PAWDeploy/](Install%20PAWDeploy/) | The installer and uninstaller (run by Intune, SCCM, or manually) and the VMDeploy application it deploys. `Install-PAWDeploy.ps1`, `Uninstall-PAWDeploy.ps1` and `Settings.psm1` sit at the top; the four install stages live in [Stages/](Install%20PAWDeploy/Stages/), and the logo in [Branding/](Install%20PAWDeploy/Branding/). |
| [Create Templade VHDX/](Create%20Templade%20VHDX/) | Step-by-step guide and scripts for building (and optionally shrinking) the Windows 11 Enterprise template VHDX that VMDeploy provisions guests from. |
| [Default Intune Files/](Default%20Intune%20Files/) | Pre-packaged `.intunewin` apps for running/removing VMs, for use with the default configuration. |
| [docs/](docs/) | Full documentation — see below. |

## Documentation

| | |
| --- | --- |
| [docs/setup/](docs/setup/) | **Setup guide** — requirements, preparation, configuration reference, and installation (manual, Intune, SCCM). |
| [docs/templates/](docs/templates/) | Template for new VM Deploy packages. |
| [CHANGELOG.md](CHANGELOG.md) | Release notes per version. |
| [docs/security/PAW-CONCEPT.md](docs/security/PAW-CONCEPT.md) | The PAW security model this project implements, and why it matters. |
| [docs/security/SECURITY-REVIEW.md](docs/security/SECURITY-REVIEW.md) | Source-code security review of the installer and VMDeploy tooling. |

Start with [docs/setup/README.md](docs/setup/README.md) for a step-by-step walkthrough.

---

## Thank you to
[Mikael Nyström (DeploymentBunny)](https://github.com/DeploymentBunny).
