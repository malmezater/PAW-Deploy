# Configuration Reference

All deployment-wide settings live in [Install PAWDeploy/Settings.psm1](../../Install%20PAWDeploy/Settings.psm1). Edit the user-configurable block **before packaging** the installer.

## Settings.psm1 — user-configurable

```powershell
$Script:CompanyName         = "DeployIT"        # Used in registry path and ProgramData folder
$Script:DownloadUrl         = "Download URL"    # Full SAS / HTTPS URL or UNC path to the VHDX
$Script:VHDXVersion         = "Win11-25H2"      # Stored as a registry stamp
$Script:VHDXSha256          = ""                # Optional SHA256 - verifies the downloaded VHDX
$Script:LocalInstall        = $true             # $true = local install (shortcuts created); $false = Intune/ConfigMgr
$Script:VMSwitchName        = "Ethernet Cable"  # Hyper-V external switch (must match <VMSwitch> in Config.xml)
$Script:VMSwitchAdapterName = ""                # Physical adapter for the switch. Empty = first adapter that is Up
$Script:CreateHyperVUser    = $true             # Create the local Hypervuser account (interactive installs only)
```

| Setting | Description |
| --- | --- |
| `CompanyName` | Name used for the registry path and ProgramData folder. Default: `DeployIT`. |
| `DownloadUrl` | Source of the Windows 11 VHDX. Azure Blob/Files, SMB/UNC, or HTTP/HTTPS — see [REQUIREMENTS.md](REQUIREMENTS.md#network-access). |
| `VHDXVersion` | Version tag for the VHDX — change if you use a different image (e.g. `Win11-24H2`). Default: `Win11-25H2`. |
| `LocalInstall` | `$true` = local/manual install (Start Menu shortcuts created). `$false` = Intune / ConfigMgr (no shortcuts). |
| `VHDXSha256` | Optional. When set, Stage 4 verifies the downloaded file with `Get-FileHash` and refuses to use it on mismatch. Get the value with `(Get-FileHash .\Windows11.vhdx).Hash`. |
| `VMSwitchName` | Name of the external Hyper-V switch Stage 2a creates. Must match `<VMSwitch>` in `Config.xml`. Default: `Ethernet Cable`. |
| `VMSwitchAdapterName` | Physical adapter to bind the switch to (e.g. `Ethernet`). Empty = first physical adapter that is Up; a warning is logged when several are Up. |
| `CreateHyperVUser` | `$true` = create the local `Hypervuser` account in Stage 2c. It needs a password prompt, so it is skipped with a warning when the installer runs as SYSTEM. |

## Settings.psm1 — derived values

Normally left as-is:

| Variable | Value |
| --- | --- |
| `$ScriptVersion` | `2.3.0` |
| `$SoftwareName` | `VMDeploy` |
| `$DeployPath` | `C:\ProgramData\<CompanyName>` |
| `$DeployITLogs` | `C:\ProgramData\<CompanyName>\Logs` |
| `$VMDeployPath` | `C:\ProgramData\VMDeploy` |
| `$VHDXDownloadPath` | `C:\ProgramData\VMDeploy\Images\Windows11.vhdx` |
| `$RegistrySoftwareName` | `HKLM:\SOFTWARE\<CompanyName>\VMDeploy` |

The module also defines the list of Hyper-V features to enable (`$HyperVFeatures`), the firewall rules to disable (`$FirewallRules`), the shared exit codes, and the helper functions every stage uses (`Start-DeployStage`, `Stop-DeployStage`, `Get-/Set-/Test-DeployStamp`) — see the [installation stages](INSTALLATION.md#installation-stages).

## Apps.xml / Modules.xml

When you launch **VM Deploy** and pick a template, the right side of the window shows three optional boxes:

- **Packages** — bundles of apps, modules and downloads for one use case.
- **Applications (winget)** — `winget` package IDs to install inside the guest VM.
- **PowerShell modules** — modules installed from PSGallery into the **AllUsers** scope at their **latest** version.

Selecting a row in any of the lists shows it in the **Details** box:
- **Package** — the apps, modules and downloads it installs.
- **Application or module** — its description and where it is installed from (winget ID or PowerShell Gallery link).

The line at the bottom of the window shows how many packages, applications, modules and downloads the build will install.

Both are populated per template via two XML catalogs shipped next to `Config.xml`:

| File | Purpose |
| --- | --- |
| [Apps.xml](../../Install%20PAWDeploy/3_Install_VMDeploy/Source/VMDeploy/Apps.xml) | Named profiles of winget application IDs. |
| [Modules.xml](../../Install%20PAWDeploy/3_Install_VMDeploy/Source/VMDeploy/Modules.xml) | Named profiles of PowerShell module names. |
| [Packages\\*.xml](../../Install%20PAWDeploy/3_Install_VMDeploy/Source/VMDeploy/Packages) | Reusable bundles of apps, modules and downloads, referenced from profiles (see [Packages](#packages)). Template: [Package-Template.xml](../templates/Package-Template.xml). |

A template references a profile by name in [Config.xml](../../Install%20PAWDeploy/3_Install_VMDeploy/Source/VMDeploy/Config.xml):

```xml
<Template Name="Windows 11 - WORKGROUP">
  ...
  <AppProfile>PAW-Workgroup</AppProfile>
  <ModuleProfile>PAW-Workgroup</ModuleProfile>
</Template>
```

If a template has no `AppProfile` / `ModuleProfile`, the corresponding checklist is disabled. **Intune OOBE** templates intentionally skip both (the VM is sysprepped, so app/module configuration is delivered via Intune instead).

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

- `Id` — the exact winget package ID (`winget search <name>` to look it up).
- `DisplayName` — friendly text shown in the UI.
- `Description` — optional one-line description shown in the Details box.
- `Default="True"` — pre-checks the item in the UI.

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

- `Name` — the exact PSGallery module name as used by `Install-Module`.
- Modules are installed with `Install-Module -Scope AllUsers -Force -AllowClobber` (always the latest version available on PSGallery).
- `SkipPublisherCheck="True"` (optional) — adds `-SkipPublisherCheck`. Only use it for modules that clash with an inbox signed module, such as **Pester 5** next to Windows' built-in Pester 3.4.

### Packages

> **New package?** Start from the commented template [docs/templates/Package-Template.xml](../templates/Package-Template.xml). It describes every element and attribute.

A package is a separate XML file in `Packages\` that bundles the apps, modules **and** downloads for one use case, e.g. [Packages\SecurityAudit.xml](../../Install%20PAWDeploy/3_Install_VMDeploy/Source/VMDeploy/Packages/SecurityAudit.xml) for the Simple-Azure-Audit toolset, or [Packages\AzureDevOps.xml](../../Install%20PAWDeploy/3_Install_VMDeploy/Source/VMDeploy/Packages/AzureDevOps.xml) for Azure, Bicep/Terraform and Git work:

```xml
<Package Name="SecurityAudit" DisplayName="Security Audit">
  <App    Id="Python.Python.3.12" DisplayName="Python 3.12 (Prowler)" />
  <Module Name="Pester"           DisplayName="Pester (Maester)"      SkipPublisherCheck="True" />
  <Module Name="Maester"          DisplayName="Maester" />
  <!-- ... -->
  <Download Name="Simple Azure Audit"
            Url="https://github.com/malmezater/Simple-Azure-Audit/archive/refs/heads/main.zip"
            Destination="C:\PackTools\Simple-Azure-Audit" />
</Package>
```

Reference the package by file name from a profile in `Apps.xml` and/or `Modules.xml`:

```xml
<Profile Name="PAW-Workgroup">
  <Module Name="Az" DisplayName="Azure Az" Default="True" />
  <Package Name="SecurityAudit" Default="False" />
</Profile>
```

- Packages are listed in the **Packages** box, once per package, e.g. `Security Audit  (3 apps, 10 modules, 1 download)`, whether the template's app profile, module profile or both reference it.
- `Default="True"` on a `<Package>` element pre-checks it. If the package is referenced from both profiles, one `Default="True"` is enough.
- When the build starts, checked packages are expanded into their apps, modules and downloads. Duplicates (e.g. `Az` both checked in the modules list and included in a package) are installed once. Individually checked items come first, then package contents.
- A missing package file is skipped with a warning.
- `<Download>` entries run when the package is checked in either list:
  - **Where it downloads:** the file is downloaded **on the host** into `%ProgramData%\VMDeploy\Downloads` and copied into the VM over PowerShell Direct, so the guest doesn't need internet for this step.
  - **Latest version:** a new download is attempted on every deployment. If it fails, the cached copy from an earlier deployment is used.
  - **Zip files:** a `.zip` is extracted to `Destination`. A single top-level folder in the archive, as in GitHub archives (`repo-main\`), is flattened. Any other file type is copied into `Destination` as is.
  - **Unblocked:** extracted files are unblocked, so scripts run without execution-policy prompts.

> **Network requirement:** the guest VM must reach `cdn.winget.microsoft.com` and `www.powershellgallery.com`. In isolated PAW networks you may need an internal mirror or an outbound allow-list.
>
> **PowerShell 7 note:** Modules are installed into Windows PowerShell 5.1's `C:\Program Files\WindowsPowerShell\Modules`. To also get PowerShell 7, add `Microsoft.PowerShell` to the app list — PS7 picks up the 5.1 modules automatically via its compatibility module path.

## How guest provisioning applies this

After the VM has booted and BitLocker has finished encrypting, [VMDeploy.ps1](../../Install%20PAWDeploy/3_Install_VMDeploy/Source/VMDeploy/VMDeploy.ps1) connects to the guest via **PowerShell Direct** (`Invoke-Command -VMName`) as `\Administrator` and:

1. **Registers winget** — `Add-AppxPackage -Register -DisableDevelopmentMode`, since the App Execution Alias is only created on first interactive logon, which a freshly deployed VM has never had.
2. **Installs winget applications** — each in its own `Invoke-Command` call, using `winget.exe --scope machine --exact --silent`. If an installer restarts the Windows Installer service mid-install and kills the Hyper-V socket, the script reconnects via `Wait-VIAVMHavePSDirect` and retries automatically. Packages that only support user scope are retried without `--scope machine`.
3. **Installs PowerShell modules** — a single `Invoke-Command` installs everything selected with `Install-Module -Scope AllUsers -Force -AllowClobber -Repository PSGallery`, after ensuring TLS 1.2, the NuGet provider, and a trusted PSGallery.
4. **Copies downloads** — `<Download>` entries from checked packages are downloaded on the host, copied into the VM and extracted to their `Destination` (e.g. Simple Azure Audit to `C:\PackTools\Simple-Azure-Audit`).

All of these steps are skipped entirely for **Intune OOBE** templates. Every package/module result is logged in the deploy transcript with its exit code / installed version.
