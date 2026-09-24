# Changelog

## 2.3.2

Adds a proper uninstaller, a much smaller and fully rebuildable template VHDX (`Win11-2609`),
reliable winget installs in deployed VMs, Enhanced Session that works on the first connect, and
closes an attack-surface gap in Intune/ConfigMgr deployments.

> **Repackaging required.** `Install-PAWDeploy.ps1` and VM Deploy changed and
> `Uninstall-PAWDeploy.ps1` is new, so the `.intunewin` package must be rebuilt. Add an uninstall
> command in Intune - see [Uninstall](docs/setup/INSTALLATION.md#uninstall).
>
> **New template VHDX.** The default VHDX tag is now `Win11-2609`. Build it with the updated
> [Create Templade VHDX](Create%20Templade%20VHDX/README.md) guide and upload it to `$DownloadUrl`.

### Added

- **Uninstall-PAWDeploy.ps1.** Removes everything the installer puts on the machine - the
  `C:\ProgramData\VMDeploy` program folder, Start Menu shortcuts, `DeployIT` check/tool files, and
  the registry key Intune uses for detection. Safe to run more than once and safe to run when
  nothing is installed. VMs stored under `VMDeploy\VMs`, the Hyper-V VM switch, the `Hypervuser`
  account and the Hyper-V Windows features are all shared with the rest of the machine or destroy
  data, so they're left alone by default - opt in per piece (`-RemoveVMs`, `-RemoveVMSwitch`,
  `-RemoveHyperVUser`, `-DisableHyperVFeatures`) or all at once (`-Full`). The firewall rules Stage
  2b disabled/scoped are restored by default. Lives next to `Install-PAWDeploy.ps1` in the same
  package, sharing its `Settings.psm1` - just a new uninstall command, no separate package.
- **"Windows 11 - Domain Joined" template.** VM Deploy already fully supports domain join (the
  domain admin account/password fields and unattend logic were already there, just unused) - this
  adds a template that turns it on, using the external `Ethernet Cable` switch (instead of the
  internal `Default Switch` the other templates use) so the VM can reach a domain controller on the
  physical network. Edit its `DNSDomain`/`MachineObjectOU` placeholders in `Config.xml` before use -
  see [Domain-joined VMs](docs/setup/PREPARATION.md#domain-joined-vms).
- **Event Log logging, readable without local admin.** Now that `C:\ProgramData\VMDeploy` is
  SYSTEM-only on Intune/ConfigMgr installs, its transcript logs aren't readable by an operator who
  isn't a full local admin. Every install/uninstall stage, VM Deploy and VM Remove now also write a
  short status line to **Event Viewer → Applications and Services Logs → VMDeploy → Operational**
  (`Get-WinEvent -LogName "VMDeploy/Operational"`), which any interactively logged-on account can
  read by default - see [Event Log](docs/setup/INSTALLATION.md#event-log-readable-without-local-admin).
- **Optional Windows Client Security Baseline for VMs.** VM Deploy can now run Mikael Nystrom's
  vendored `Remediate-WindowsClientSecurityBaseline.ps1` toolkit against a deployed VM
  (Defender/firewall/LSA/SMB1/NTLM hardening - never removes the operator from local
  Administrators). Applies every `-HardenRecommended` switch except `-SetInboundDefaultBlock`.
  Pre-checked only for the **Workgroup** template via a new `<ApplySecurityBaseline>` flag in
  `Config.xml`, since Domain Joined/Intune OOBE already get hardening from AD/Intune - the checkbox
  stays disabled there. Failed actions are logged individually (name + reason), not just a count.
  See [Security baseline](docs/setup/PREPARATION.md#security-baseline). The vendored
  `Set-RegistryDwordValue`/`Set-RegistryStringValue` helpers also carry a local bugfix: they crashed
  under the script's own `Set-StrictMode -Version Latest` whenever a registry value didn't already
  exist (the normal case on a fresh, never-managed machine), which failed 8 of the 13 applied actions
  on first test (2026-09-22). Patched to read the current value with `Get-ItemPropertyValue` in a
  `try/catch` instead; see
  [SecurityBaseline/VENDORED-FROM.md](Install%20PAWDeploy/Stages/3_Install_VMDeploy/Source/VMDeploy/SecurityBaseline/VENDORED-FROM.md).

- **VM Deploy primes the VM's first interactive logon.** Even with Remote Desktop and Enhanced
  Session both correctly enabled, the very first VMConnect to a newly deployed VM used to briefly
  fall back to a Basic session before upgrading itself to Enhanced - because nobody had completed an
  interactive logon yet, and Windows runs a first-logon "checking for updates" pass (part of
  finishing OOBE/specialize) that has to complete, restart included if it triggers one, before
  Enhanced Session's own driver negotiation succeeds. VM Deploy now does that logon unattended for
  every non-OOBE VM, using the local Administrator credentials already collected for the unattend
  file, then clears autologon again (LSA secret included) once done - so the VM is Enhanced
  Session-ready before it's handed over. This is what makes it safe to keep VMs shielded (no Basic
  session to fall back into). Confirmed live (SecPack006, 2026-09-22): Enhanced Session connects
  directly on the first attempt with no hang and no Basic fallback. The very first logon signs itself
  out once before settling - that's Windows finishing first-time profile setup, not a bug. See
  [Remote Desktop / Enhanced Session
  access](docs/setup/PREPARATION.md#remote-desktop--enhanced-session-access).

- **"Intune Packaging" package.** `Packages\IntunePackaging.xml` downloads the Microsoft Win32 Content
  Prep Tool (`IntuneWinAppUtil.exe`) from Microsoft's GitHub repository into
  `C:\PackTools\IntuneWinAppUtil` - always the latest version, and no longer a manual step when
  building the template VHDX. Added to the `PAW-Workgroup` profile in `Apps.xml`.
- **Rebuilt template VHDX workflow (`Win11-2609`).** The template is now built from a Windows 11
  Enterprise ISO (Media Creation Tool, `/MediaEdition Enterprise`) with a step-by-step guide and new
  scripts:
  - `Optimize-Template.ps1` - removes Features on Demand and optional features a VM doesn't need
    (payload included), disables Reserved Storage and hibernation, runs
    `DISM /StartComponentCleanup /ResetBase`, clears caches/logs and compacts the OS.
  - `Rebuild-TemplateVHDX.ps1` (optional tip) - captures the sysprepped volume to a WIM and applies
    it to a fresh VHDX with 1 MB blocks. `Optimize-VHD` can only release whole 32 MB blocks, so this
    is what really shrinks the file (20.3 GB -> 15.9 GB measured) and leaves a ~4-5 GB WIM backup.
  - `Uninstall-WinApps.ps1` rewritten - wildcard keep-list (winget and its dependencies, language
    pack, Entra sign-in), skips system/framework packages, removes provisioned packages first,
    uninstalls OneDrive from the Default profile and reports anything that would block sysprep.
  - `Remove-TempFiles.ps1` takes `-Drive`, removes `pagefile.sys`/`swapfile.sys`/`hiberfil.sys`
    offline and no longer touches the host's Windows Update service.
  - `Invoke-SysprepPrep.ps1` also removes the leftover `defaultuser0` account.
  - All template scripts are ASCII/English and check that they run in Windows PowerShell 5.1.

### Fixed

- **Remote Desktop / Enhanced Session never actually worked.** Two separate, stacked bugs, both
  pre-existing and unrelated to the security baseline feature above (reproduced on a plain workgroup
  VM with no baseline applied at all):
  - VM Deploy has always added the operator to Remote Desktop Users and created an `.rdp` shortcut,
    but never turned Remote Desktop *on* - a fresh Windows install ships with it off
    (`fDenyTSConnections=1`, "Remote Desktop" firewall rules disabled). Fixed for every non-OOBE VM,
    unconditionally.
  - No interactive logon had ever completed on the VM, and Enhanced Session only comes up once one
    has. Every VM is shielded (`Set-VMSecurityPolicy -Shielded $true`), which blocks the Basic
    (console) session deliberately - so with the guest not yet Enhanced Session-ready there was
    nothing to fall back into and VMConnect hung. Fixed by priming that logon during deployment (see
    above); shielding stays on, since it's what makes Enhanced Session the only way into a delivered
    VM.
- **winget installs rewritten around what actually works.** On a freshly built template every app
  failed: winget was never registered for the PS Direct Administrator profile (no interactive logon),
  so its App Execution Alias didn't exist, and Administrator can't start the package's `winget.exe`
  directly ("Access is denied" - no package identity). Now:
  - The host pushes only the latest DesktopAppInstaller msixbundle and provisions it (falls back to the
    template's winget if that fails). The VCLibs/UI.Xaml provisioning (always "Element not found"),
    the Administrator alias registration and the `Microsoft.Winget.Source` seeding are removed.
  - Every app is installed by a one-shot **SYSTEM scheduled task** running
    `winget install --scope machine`, with the VCLibs / UI.Xaml / Windows App Runtime package folders
    on `PATH` (otherwise winget exits with `0xC0000135`, DLL not found). winget's output and exit code
    still go to the deployment log.
  - "Already installed" (`0x8A150061`) and "no applicable upgrade" (`0x8A15002B`) count as success
    and are logged as *already installed* - e.g. Windows Terminal, which ships in the template.
- **Priming wait shortened.** The priming step always sat through a fixed 3-minute window watching
  for a first-logon restart before checking the logon. It now polls for the logon (max 5 min),
  handles a self-restart whenever it happens, and only watches 45 s extra once the logon is
  confirmed. The final shutdown is now logged ("Deployment complete - shutting down") - handing the VM
  over powered off is intentional.
- **Leftover `defaultuser0` account.** Entering Audit Mode with CTRL+Shift+F3 in OOBE leaves the
  temporary OOBE account in the template, where it shows up on the logon screen of every deployed VM
  and gets in the way of the primed Administrator autologon. VM Deploy now removes it before priming,
  and `Invoke-SysprepPrep.ps1` removes it from new templates. When the primed logon is not observed,
  the log now also shows the Winlogon autologon values and recent failed logons (4625) for diagnosis.
- **Primed logon is now verified.** The priming step assumed the autologon happened; it now waits for
  `explorer.exe` running as Administrator and warns in the log if it never appears. It also sets
  `DevicePasswordLessBuildVersion=0`, since Windows 11's "Only allow Windows Hello sign-in" silently
  blocks password autologon.
- **Security baseline no longer tries to enable the Defender EDR (Sense) service.** It only starts on
  devices onboarded to Defender for Endpoint, which these VMs never are, so it always failed with a
  warning in the deployment log.

### Security

- **VMDeploy folder restricted to SYSTEM when `LocalInstall = $false` (reduced attack surface).** In
  Intune/ConfigMgr deployments nobody signs in and uses VMDeploy interactively - only SYSTEM ever
  needs to. Once every stage finishes, the installer now strips local Administrators and Users (both
  inherit access from `C:\ProgramData`'s own default ACL) from `C:\ProgramData\VMDeploy`, leaving
  SYSTEM as the sole accessor. This is defense in depth, not a hard boundary - a local Administrator
  can still `takeown.exe` their way back in on their own machine - but it removes casual/automated
  access, and a deliberate attempt becomes a more visible, detectable action.
  `Uninstall-PAWDeploy.ps1` reclaims access with `takeown.exe` before deleting the folder, so
  uninstalling as an elevated admin still works. Unchanged when `LocalInstall = $true`.

### Documentation

- [Create Templade VHDX/README.md](Create%20Templade%20VHDX/README.md) rewritten as an 11-step guide
  (ISO download, VM creation, Audit Mode, manual prerequisites, each script, sysprep troubleshooting,
  offline compaction) with the rebuild as an optional tip. `Optimize-VHD -Mode Full` is now run on a
  **read-only** mount - on a detached disk it barely shrinks the file.
- Default VHDX tag updated to `Win11-2609` in the README and setup docs (`Win11-YYMM` convention).
- Clarified that the signed-in user is always added to **Hyper-V Administrators** regardless of
  settings - it's required to use VMs at all. `$CreateHyperVUser` only controls the separate,
  optional `Hypervuser` account (e.g. for RDP-based host admin sign-in).

## 2.3.1

A security and reliability release. It closes the findings from the [source-code security
review](docs/security/SECURITY-REVIEW.md), fixes several bugs that could stop a deployment with no
visible error, and adds simple branding.

> **Repackaging required.** The installer folders moved (see [Layout](#layout)), so the
> `.intunewin` packages must be rebuilt. The install command itself is unchanged.

### Security

Eight of the thirteen review findings are now fixed. See
[SECURITY-REVIEW.md](docs/security/SECURITY-REVIEW.md) for the full status of each.

- **Command injection in VM Deploy (critical).** The window used to build a command line by pasting
  the values you typed into a string, so text entered in any field could run as PowerShell with
  administrator rights. Nothing you enter now goes on the command line at all — the template, VM
  name, network settings and credentials all travel in a hand-off file, so there is nothing to
  inject into.
- **Credentials left inside every deployed VM (critical/high).** The unattend answer file kept the
  local administrator password — and, for domain templates, the domain-join password — readable on
  the guest disk long after setup, and the AutoLogon password stayed in the guest registry. Both are
  now scrubbed by `SetupComplete.cmd` on first boot. *If you deploy domain-joined VMs, treat any
  domain-join account used with an earlier version as exposed and rotate it.*
- **AzCopy was downloaded and run unverified (high).** Its Authenticode signature is now checked,
  and must be valid and Microsoft-signed, before it is used.
- **Deployment config could be fetched over plain HTTP (medium).** `Config.xml` decides the
  domain-join target, the OU and the VHD source, so anyone on the network path could have rewritten
  it. `Source = http` now requires an `https://` URL. `Source = unc` is read as a file path (it was
  incorrectly routed through a web client before).
- **Credential hand-off file was plain text (medium).** It is now DPAPI-encrypted, tied to the
  account and machine that wrote it, and always deleted — including when a build fails partway.
- **Firewall rules can be scoped instead of disabled (medium, opt-in).** Stage 2b disabled three
  Hyper-V remoting rules outright, opening them to the whole network. Set `$FirewallScopeSubnet` in
  `Settings.psm1` to a management subnet and the rules stay enabled, scoped to it. Left empty,
  behaviour is unchanged and the log now says the rule is open to the whole network.
- **PowerShell modules can be pinned (low, opt-in).** `<Module>` entries accept `Version="1.2.3"`,
  which installs exactly that version instead of whatever is newest on PSGallery.

Deliberately **not** changed: BitLocker recovery keys are still not escrowed anywhere. Writing a
guest's recovery key to the host would let anyone who obtains the host — or just the VHDX file —
decrypt the guest without its TPM, which defeats the reason the disk is encrypted. This is an
accepted trade-off, not an oversight.

### Deployment fixes

- **Build did nothing.** Clicking **Build** could close the window with no error, no log and no VM.
  Windows PowerShell 5.1 does not quote arguments passed to `Start-Process` as a list, so a template
  name containing a space — which every shipped template has — arrived at `VMDeploy.ps1` split
  across several arguments and failed before the script ran a single line. All values now travel in
  the hand-off file instead.
- **Deployment hung forever.** After the VM booted, the installer waited indefinitely for the guest
  to report that setup had finished. That signal is now written first, before the cleanup steps, so
  a slow or blocked cleanup can no longer stall the deployment.
- **Failures are no longer silent.** `VMDeploy.ps1` now checks it is running elevated and says so
  plainly if not; any unhandled error is written to `%TEMP%\VMDeploy-fatal-error.log` and left on
  screen instead of closing the window; the transcript falls back to `%TEMP%` if
  `C:\ProgramData\VMDeploy\logs` cannot be written; and each launch is recorded in
  `VMDeploy-launch.log`.
- **Red errors during installation.** Installing printed a series of alarming errors about missing
  registry values. They were harmless — the installer was checking whether each stage had already
  run — but they looked like failures. The check no longer reports anything when a value is absent.

### winget

- **Applications failed to install** with `0x8A15000F — Data required by the source is missing`.
  The package index never installed inside a freshly deployed VM, so winget had nothing to search.
  The index is now downloaded on the host, like the winget client already was, and installed in the
  guest — no connectivity needed from the VM for this step.
- **winget failures now explain themselves.** Only an exit code was logged before (`exit
  -1978335217`); winget's own message is now recorded alongside it.

### Downloads

- **Package downloads retry before giving up.** A single timeout no longer falls straight back to a
  cached copy: transient failures are retried three times with a growing delay, while a genuine
  `404` still fails immediately. Note that GitHub `.zip` archive links redirect to
  `codeload.github.com` — if your proxy allows `github.com` but not that host, downloads fail with
  `504 Gateway Timeout`. It is now listed in [REQUIREMENTS.md](docs/setup/REQUIREMENTS.md#network-access).

### Branding

Rebrand the tool with two settings and one image — no code changes:

```powershell
$Script:ProductName  = "Contoso Secure Workstation"
$Script:BrandingLogo = "contoso-logo.png"     # file in Install PAWDeploy\Branding\
```

The name appears in the VM Deploy title bar and banner, and the logo in both VM Deploy windows.
Branding is cosmetic only — it does not affect install paths, the registry or Intune detection, which
still follow `CompanyName`. Defaults are unchanged, and an installation without branding information
falls back to the current appearance. See [CONFIGURATION.md](docs/setup/CONFIGURATION.md#branding).

Not branded: the Start Menu folder name and the shortcut icons.

### Layout

The installer folder was reorganised — this is why the `.intunewin` packages need rebuilding:

```
Install PAWDeploy/
  Install-PAWDeploy.ps1     (unchanged location)
  Settings.psm1             (unchanged location)
  Branding/                 <- put your logo here
  Stages/                   <- the four install stages moved in here
    1_Install-Features_for_PAW/
    2_Install_VMDeploy-configuration/
    3_Install_VMDeploy/
    4_Download_Windows_VHDX/
```

### Documentation

- `SECURITY-REVIEW.md` now records the status of every finding — fixed, open, or deliberately
  rejected — with what changed for each.
- `CONFIGURATION.md` documents branding, `FirewallScopeSubnet` and module version pinning.
- `REQUIREMENTS.md` lists which hosts the **host** needs to reach versus the **guest**, including
  `codeload.github.com`.

### Upgrading from 2.3.0

1. **Rebuild the `.intunewin` packages** — the folder layout changed. The install command
   (`Install-PAWDeploy.ps1`) is unchanged.
2. **Carry your settings over** into the new `Settings.psm1`: `CompanyName`, `DownloadUrl`,
   `VHDXVersion` and anything else you customised. New optional settings: `ProductName`,
   `BrandingLogo`, `FirewallScopeSubnet`.
3. **Deploy.** Intune sees `VMDeployVersion` = `2.3.1` and reinstalls VMDeploy. Existing VMs are
   untouched; the fixes apply to VMs built from now on.
4. **If you deploy domain-joined VMs**, rotate the domain-join account used with earlier versions —
   its password is recoverable from every VM built with them.

## 2.3.0

### VM Deploy – packages

- **Packages** bundle winget apps, PowerShell modules and downloads for one use case in one file under `Source\VMDeploy\Packages\`. You reference them from a profile in `Apps.xml` and/or `Modules.xml` with `<Package Name="..." Default="False" />`.
- **Two packages included:**
  - **Security Audit** – PowerShell 7, Azure CLI, Python 3.12, the modules used by [Simple Azure Audit](https://github.com/malmezater/Simple-Azure-Audit) (Az, Microsoft Graph Authentication, Pester, Maester, PSRule, PSRule for Azure, WARA, ImportExcel, Azure Resource Inventory, AzAPICall), and Simple Azure Audit downloaded into `C:\PackTools\Simple-Azure-Audit`.
  - **Azure DevOps** – PowerShell 7, Windows Terminal, Azure CLI, Bicep CLI, Terraform, Git, Visual Studio Code, GitHub Desktop, Az, Microsoft Graph, Microsoft Graph Beta, PSScriptAnalyzer and Pester.
- **Downloads** – a `<Download Name Url Destination />` entry downloads a file on the host and copies it into the VM over PowerShell Direct, so the VM doesn't need internet for this step.
  - A `.zip` is extracted into the destination; the top-level folder of GitHub archives is flattened.
  - Files are unblocked after copying.
  - If the download fails, the cached copy in `%ProgramData%\VMDeploy\Downloads` is used.
- **`SkipPublisherCheck="True"`** on a module adds `-SkipPublisherCheck`, needed for Pester 5 next to Windows' built-in Pester 3.4.
- **`Description`** on apps and modules is shown in VM Deploy.
- **Duplicates** – apps and modules that appear both in a checked package and in the lists are installed once.
- **Package template** – [docs/templates/Package-Template.xml](docs/templates/Package-Template.xml).

### VM Deploy – window

- **Redesigned layout** – the virtual machine settings are on the left. The right side has separate **Packages**, **Applications (winget)** and **PowerShell modules** boxes.
- **Details box** – shows what a selected package installs. For a selected app or module it shows the description and where it is installed from (winget ID or PowerShell Gallery link).
- **Status line** – shows how many packages, applications, modules and downloads the build will install.
- **Domain fields** – the domain account and password are disabled for workgroup templates.
- **Build validation** – Build checks that a template, VM name and local administrator password are set (plus domain account and password for domain templates) before starting.

### VM Deploy – provisioning

- **Early password check** – `VMDeploy.ps1` stops before creating anything when no local administrator password was provided, instead of leaving a half-built VM.
- **Module installs** – modules flagged with `SkipPublisherCheck` are installed with that switch.
- **Downloads step** – runs after module installation and is skipped for Intune OOBE templates.

### Installer

- **`Install-PAWDeploy.ps1` rewritten**
  - Stages are defined in one table, each with a completion check. Finished stages are skipped on re-run.
  - When started from a 32-bit process (Intune Management Extension), it relaunches in 64-bit PowerShell.
  - Before changing anything, it checks that it runs elevated and that `DownloadUrl` is configured. Placeholder values such as `Download URL` are rejected.
  - Exit codes are handled consistently: `0` success, `1` failure, `1641` reboot required. All stages are verified at the end.
- **`Settings.psm1`**
  - New settings: `VHDXSha256`, `VMSwitchName`, `VMSwitchAdapterName`, `CreateHyperVUser`.
  - Shared helpers for logging, registry stamps and exit codes: `Start-DeployStage`, `Stop-DeployStage`, `Get-/Set-/Test-DeployStamp`, `Test-InteractiveSession`.
- **Stage 1 (features)** – exits `1641` only when Windows actually requires a restart.
- **Stage 2a (network)** – binds the switch to `VMSwitchAdapterName`, or the first physical adapter that is up.
- **Stage 2b (firewall)** – rules that don't exist on the Windows build are stamped `NotFound` instead of failing.
- **Stage 2c (Hyper-V admins)** – fixed a runtime error and the password dialog. The `Hypervuser` account is skipped with a warning when running as SYSTEM.
- **Stage 3 (VMDeploy)** – fails on real Robocopy errors (exit code 8 or higher).
- **Stage 4 (VHDX)**
  - Downloads to a temporary `.partial` file and optionally verifies SHA256 before use.
  - AzCopy is kept under `<DeployPath>\Tools`.

### Intune files

- **`Run-VMDeploy.ps1`** starts `VMDeploywUI.ps1`, and **`Remove-VMDeploy.ps1`** starts `VMRemovewUI.ps1`.
- **Rebuild required** – rebuild the `.intunewin` packages with IntuneWinAppUtil after changing these scripts.

### Documentation

- **`docs/setup/CONFIGURATION.md`** – documents packages, downloads, descriptions and the new window.
- **`docs/README.md` and `docs/setup/README.md`** – link to the package template and this changelog.
- **Detection reference** – `VMDeploy-Detections.txt` updated to `VMDeployVersion` 2.3.0.

### Upgrading from 2.2.x

1. **Update `Settings.psm1`** – copy your values for `CompanyName`, `DownloadUrl`, `VHDXVersion` and `LocalInstall`. Review the new settings above.
2. **Keep your profiles and templates** – `Apps.xml`, `Modules.xml` and `Config.xml` keep working. Add `<Package ... />` references to use the new packages.
3. **Rebuild the installer package** – Intune detects the new version through `VMDeployVersion` = `2.3.0` and reinstalls VMDeploy.
