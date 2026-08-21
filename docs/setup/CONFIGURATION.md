# Configuration Reference

All deployment-wide settings live in [Install PAWDeploy/Settings.psm1](../../Install%20PAWDeploy/Settings.psm1). Edit the user-configurable block **before packaging** the installer.

## Settings.psm1 — user-configurable

```powershell
$Script:CompanyName  = "COMPANY NAME"   # Used in registry path and ProgramData folder / Default will be DeployIT
$Script:DownloadUrl  = "Download URL"   # Full SAS / HTTPS URL to the VHDX
$Script:VHDXVersion  = "Win11-25H2"     # Stored as a registry stamp
$Script:LocalInstall = $true            # $true = local install (shortcuts created); $false = Intune/ConfigMgr (no shortcuts)
```

| Setting | Description |
| --- | --- |
| `CompanyName` | Name used for the registry path and ProgramData folder. Default: `DeployIT`. |
| `DownloadUrl` | Source of the Windows 11 VHDX. Azure Blob/Files, SMB/UNC, or HTTP/HTTPS — see [REQUIREMENTS.md](REQUIREMENTS.md#network-access). |
| `VHDXVersion` | Version tag for the VHDX — change if you use a different image (e.g. `Win11-24H2`). Default: `Win11-25H2`. |
| `LocalInstall` | `$true` = local/manual install (Start Menu shortcuts created). `$false` = Intune / ConfigMgr (no shortcuts). |

## Settings.psm1 — derived values

Normally left as-is:

| Variable | Value |
| --- | --- |
| `$ScriptVersion` | `2.2.3` |
| `$SoftwareName` | `VMDeploy` |
| `$DeployPath` | `C:\ProgramData\<CompanyName>` |
| `$DeployITLogs` | `C:\ProgramData\<CompanyName>\Logs` |
| `$VHDXDownloadPath` | `C:\ProgramData\VMDeploy\Images\Windows11.vhdx` |
| `$RegistrySoftwareName` | `HKLM:\SOFTWARE\<CompanyName>\VMDeploy` |

The module also defines the list of Hyper-V features to enable (`$HyperVFeatures`) and the firewall rules to disable (`$FirewallRules`) — see the [installation stages](INSTALLATION.md#installation-stages) for what consumes each.

## Apps.xml / Modules.xml

When you launch **VM Deploy** and pick a template, the UI can show two optional checklists:

- **Applications** — `winget` package IDs to install inside the guest VM.
- **PowerShell Modules** — modules installed from PSGallery into the **AllUsers** scope at their **latest** version.

Both are populated per template via two XML catalogs shipped next to `Config.xml`:

| File | Purpose |
| --- | --- |
| [Apps.xml](../../Install%20PAWDeploy/3_Install_VMDeploy/Source/VMDeploy/Apps.xml) | Named profiles of winget application IDs. |
| [Modules.xml](../../Install%20PAWDeploy/3_Install_VMDeploy/Source/VMDeploy/Modules.xml) | Named profiles of PowerShell module names. |

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

> **Network requirement:** the guest VM must reach `cdn.winget.microsoft.com` and `www.powershellgallery.com`. In isolated PAW networks you may need an internal mirror or an outbound allow-list.
>
> **PowerShell 7 note:** Modules are installed into Windows PowerShell 5.1's `C:\Program Files\WindowsPowerShell\Modules`. To also get PowerShell 7, add `Microsoft.PowerShell` to the app list — PS7 picks up the 5.1 modules automatically via its compatibility module path.

## How guest provisioning applies this

After the VM has booted and BitLocker has finished encrypting, [VMDeploy.ps1](../../Install%20PAWDeploy/3_Install_VMDeploy/Source/VMDeploy/VMDeploy.ps1) connects to the guest via **PowerShell Direct** (`Invoke-Command -VMName`) as `\Administrator` and:

1. **Registers winget** — `Add-AppxPackage -Register -DisableDevelopmentMode`, since the App Execution Alias is only created on first interactive logon, which a freshly deployed VM has never had.
2. **Installs winget applications** — each in its own `Invoke-Command` call, using `winget.exe --scope machine --exact --silent`. If an installer restarts the Windows Installer service mid-install and kills the Hyper-V socket, the script reconnects via `Wait-VIAVMHavePSDirect` and retries automatically. Packages that only support user scope are retried without `--scope machine`.
3. **Installs PowerShell modules** — a single `Invoke-Command` installs everything selected with `Install-Module -Scope AllUsers -Force -AllowClobber -Repository PSGallery`, after ensuring TLS 1.2, the NuGet provider, and a trusted PSGallery.

Both steps are skipped entirely for **Intune OOBE** templates. Every package/module result is logged in the deploy transcript with its exit code / installed version.
