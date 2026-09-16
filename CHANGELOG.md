# Changelog

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
