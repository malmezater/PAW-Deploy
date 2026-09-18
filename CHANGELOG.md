# Changelog

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
