# Setup Guide

This is the index for setting up PAW-Deploy, from a blank Windows 11 host to a working PAW with VM provisioning. Work through these in order:

1. **[REQUIREMENTS.md](REQUIREMENTS.md)** — confirm the host, network, and account prerequisites are in place.
2. **[PREPARATION.md](PREPARATION.md)** — build the template VHDX, edit the configuration, and package the installer.
3. **[CONFIGURATION.md](CONFIGURATION.md)** — reference for every setting in `Settings.psm1`, `Apps.xml`, `Modules.xml`, and `Config.xml`.
4. **[INSTALLATION.md](INSTALLATION.md)** — run the installer manually, or deploy it via Intune / SCCM; installation stages, registry layout, logging, and uninstall.

## Architecture at a glance

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

Each stage imports the shared [Settings.psm1](../../Install%20PAWDeploy/Settings.psm1) module and writes a "stamp" to the registry on success, so the orchestrator can skip already-completed stages on re-run.

Once installed, launch **VM Deploy** from the Start menu to provision Windows (or Linux/Kali) guest VMs on demand from the template VHDX.

See the [root README](../../README.md) for the project summary, and [docs/security/](../security/) for the security model and review this design should be held to.
