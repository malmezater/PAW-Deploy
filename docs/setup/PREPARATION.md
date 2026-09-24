# Preparation

What to do before you run (or package) the PAW-Deploy installer. Confirm [REQUIREMENTS.md](REQUIREMENTS.md) is met first.

## 1. Build a template VHDX

VMDeploy provisions every guest VM from a single generalized (sysprepped) Windows 11 Enterprise VHDX. This is built once, ahead of time, and uploaded to wherever `$DownloadUrl` will point.

Full walkthrough and scripts: [Create Templade VHDX/README.md](../../Create%20Templade%20VHDX/README.md). Summary of the process:

| Step | Runs | What it does |
| --- | --- | --- |
| 1 | On host | Download a Windows 11 **Enterprise** ISO with the Media Creation Tool (`/MediaEdition Enterprise`). |
| 2 | On host | Create a Gen 2 template VM (vTPM, checkpoints off). |
| 3 | In VM | Install Windows 11 Enterprise, enter Audit Mode (`CTRL+Shift+F3`). |
| 4 | In VM | Block device encryption, run Windows Update, create `C:\PackTools`. (IntuneWinAppUtil comes from the **Intune Packaging** package at deploy time.) |
| 5 | In VM | Apply the custom Start menu layout (`LayoutModification.xml`). |
| 6 | In VM | Remove bloatware / inbox apps (`Uninstall-WinApps.ps1`). |
| 7 | In VM | Install the AutoPilot module and initialize winget (`Install-Module.ps1`). |
| 8 | In VM | Remove unneeded features, clean WinSxS and caches, compact the OS (`Optimize-Template.ps1`), then **reboot**. |
| 9 | In VM | `Invoke-SysprepPrep.ps1` — removes winget's per-user source cache, disables networking, runs `sysprep /generalize /oobe /shutdown`. |
| 10 | On host | Mount the VHDX offline, run `Remove-TempFiles.ps1`, defrag, then `Optimize-VHD` on a read-only mount. |
| 11 | On host | Test a copy, then upload the finished VHDX to the location referenced by `$DownloadUrl`. |

**Tip:** `Rebuild-TemplateVHDX.ps1` rebuilds the sysprepped VHDX via a WIM into a new disk with 1 MB blocks — typically several GB smaller (20.3 → 15.9 GB measured).

## 2. Configure the installer

Edit the user-configurable block in [Settings.psm1](../../Install%20PAWDeploy/Settings.psm1) **before** packaging or running the installer:

```powershell
$Script:CompanyName  = "COMPANY NAME"   # Registry path + ProgramData folder name (default: DeployIT)
$Script:DownloadUrl  = "Download URL"   # Full URL to the template VHDX built in step 1
$Script:VHDXVersion  = "Win11-2609"     # Version tag stamped to the registry
$Script:LocalInstall = $true            # $true = local install (shortcuts created); $false = Intune/ConfigMgr
```

Full field reference: [CONFIGURATION.md](CONFIGURATION.md).

## 3. Choose which apps and modules guest VMs get

If you want the VM Deploy UI to offer optional winget applications / PowerShell modules per template, define profiles in [Apps.xml](../../Install%20PAWDeploy/Stages/3_Install_VMDeploy/Source/VMDeploy/Apps.xml) and [Modules.xml](../../Install%20PAWDeploy/Stages/3_Install_VMDeploy/Source/VMDeploy/Modules.xml), then reference the profile names from the relevant template in [Config.xml](../../Install%20PAWDeploy/Stages/3_Install_VMDeploy/Source/VMDeploy/Config.xml). Format details: [CONFIGURATION.md](CONFIGURATION.md#appsxml--modulesxml).

This step is optional — templates without an `AppProfile`/`ModuleProfile` simply skip that checklist (Intune OOBE templates intentionally skip both, since app/module delivery happens via Intune post-enrollment).

### Domain-joined VMs

The shipped **Windows 11 - Domain Joined** template in `Config.xml` uses `<VMSwitch>Ethernet Cable</VMSwitch>` — the external switch Stage 2a creates on a physical adapter — instead of Hyper-V's internal `Default Switch`, so the VM can reach a domain controller on the physical network during setup. VM Deploy already prompts for the domain admin account/password whenever a template's `<DomainOrWorkGroup>` is `Domain` — no code changes needed, just the template.

Before using it, edit its placeholders in `Config.xml`:

```xml
<DNSDomain>corp.thefakedomain.com</DNSDomain>
<MachineObjectOU>OU=PrivilegedAccessWorkstations,OU=Admin,DC=corp,DC=thefakedomain,DC=com</MachineObjectOU>
```

Set `DNSDomain` to your real domain and `MachineObjectOU` to the OU new PAWs should land in (or `NA` to let AD pick the default `Computers` container). Copy the `<Template>` block to make separate templates for different OUs (e.g. one per admin tier) if you need that split.

### Remote Desktop / Enhanced Session access

Found during testing (2026-09-22), unrelated to any single feature - two separate, stacked issues
that both had to be fixed before VMConnect's **Enhanced Session** (or network RDP) worked at all:

1. **Remote Desktop was never turned on.** VMDeploy.ps1 has always added the operator to **Remote
   Desktop Users** and created an `.rdp` shortcut, but never actually enabled Remote Desktop itself -
   a fresh Windows install ships with `fDenyTSConnections=1` and the built-in "Remote Desktop"
   firewall rule group disabled. Fixed: VMDeploy.ps1 now sets `fDenyTSConnections=0` and enables that
   firewall rule group for every non-OOBE VM, right where it sets up Remote Desktop Users membership.
2. **No interactive logon had ever completed on the VM.** Enhanced Session only comes up once a user
   has logged on interactively at least once. Every VM is shielded
   (`Set-VMSecurityPolicy -Shielded $true`), which blocks the Basic (console) session on purpose - so
   until the guest was Enhanced Session-ready there was nothing to fall back into, and VMConnect just
   hung. Fixed by priming that first logon during deployment (below).

   Shielding itself is deliberate and stays on: it makes Enhanced Session the *only* way into a
   delivered VM, so a user who wouldn't go and pick Enhanced Session out of a menu can't end up in a
   Basic session instead. It was briefly turned off while diagnosing the hang - turning it off does
   make the hang go away, but only by re-opening the Basic fallback, which hides the real problem
   and loses the forced-Enhanced behaviour.

Both were pre-existing, unrelated to the security baseline feature (reproduced on a plain workgroup
VM with no baseline applied at all) and to anything else in this release - they'd never actually
worked via Enhanced Session before.

**Priming the first logon.** Because a shielded VM has no Basic session to fall back into, the guest
has to be Enhanced Session-ready *before* it's handed over. VMDeploy.ps1 therefore logs on
automatically once at the end of deployment, using the local Administrator credentials already
collected for the unattend file, waits out Windows' first-logon "checking for updates" pass
(including a self-triggered restart, if it causes one, with a bounded grace window), then turns
autologon back off. The password is written to the guest as an LSA secret (the same mechanism
Sysinternals Autologon.exe uses), never as the plaintext `Winlogon\DefaultPassword` registry value,
and the secret is cleared again immediately afterward - it is never left behind. The VM is stopped at
the end of deployment, so there's no logged-on session left behind either.

Confirmed live (SecPack006, 2026-09-22): after priming, Enhanced Session connects on the first
attempt with no hang and no Basic fallback. One thing still happens on that very first connection and
is expected, not a bug: **the first logon signs itself out once, then logs back in cleanly.** That's
Windows finishing first-time profile setup for a brand-new account - the same thing would happen on
physical hardware. Every connection after that is a normal Enhanced Session with no extra steps.

Both ways in give Enhanced Session, without the user choosing anything:

- The `.rdp` shortcut VMDeploy.ps1 drops in `%ProgramData%\Desktop\VMLinks` pins the connection to
  Enhanced Session explicitly (`pcb:s:<VM GUID>;EnhancedMode=1` against port 2179 on the host).
- **Hyper-V Manager → Connect** goes straight to Enhanced Session too, because a shielded VM offers
  no Basic session to land in. (The original "waiting for an enhanced session" hang was this same
  path: VMConnect was already going for Enhanced on its own, with nothing to fall back to while the
  guest wasn't ready yet.)

Because there's no Basic fallback, Enhanced Session Mode must be allowed on the host - otherwise
there is no way to connect at all, rather than just a downgraded session. It's on by default on
Windows client, but disabling it is a documented hardening step, so VM Deploy sets
`Set-VMHost -EnableEnhancedSessionMode $true` on every run and warns if it can't. The per-user
toggle (Hyper-V Manager → Hyper-V Settings → **User** → Enhanced Session Mode) has to stay on too.

### Security baseline

The **Windows 11 - WORKGROUP** template has `<ApplySecurityBaseline>True</ApplySecurityBaseline>` set, which pre-checks **"Apply Windows Client Security Baseline"** in VM Deploy. When checked, VMDeploy.ps1 copies the vendored toolkit from [SecurityBaseline/](../../Install%20PAWDeploy/Stages/3_Install_VMDeploy/Source/VMDeploy/SecurityBaseline/) into the guest after app/module provisioning and runs `Remediate-WindowsClientSecurityBaseline.ps1` with every switch from its `-HardenRecommended` preset applied individually **except `-SetInboundDefaultBlock`** (default-deny inbound on every firewall profile - an unnecessary posture for a VM this tool's own operator needs to reach). None of the applied switches remove the current user from local Administrators. The VM is rebooted automatically if a setting needs it (e.g. SMB1).

`EnableDefenderEdrService` will show as a failed action on a VM that isn't onboarded to Microsoft Defender for Endpoint - the underlying `Sense` service doesn't exist until MDE onboarding happens, so this is expected on a fresh workgroup VM, not a bug. Failed actions are written to the transcript and to the [Event Log](INSTALLATION.md#event-log-readable-without-local-admin) with their reason; the full detail (and a per-run log file) is also on the guest itself under `%ProgramData%\WindowsClientSecurityBaseline\`. The vendored `Set-RegistryDwordValue`/`Set-RegistryStringValue` helpers also carry a small local bugfix for a `Set-StrictMode` crash on registry values that don't exist yet (the common case on a never-managed machine) - see [SecurityBaseline/VENDORED-FROM.md](../../Install%20PAWDeploy/Stages/3_Install_VMDeploy/Source/VMDeploy/SecurityBaseline/VENDORED-FROM.md).

This is offered **only** for templates where nothing else manages policy. **Domain Joined** and **Intune OOBE** get hardening from AD GPO / Intune Configuration Profiles instead — applying this on top there would be redundant, unmanaged local policy that a GPO/MDM refresh could just override anyway, so the checkbox stays disabled (and unchecked) for those templates. Add `<ApplySecurityBaseline>True</ApplySecurityBaseline>` to a template's block in `Config.xml` if you want to offer it somewhere else.

The toolkit is a fixed, vendored copy (not downloaded on each deployment) - see [SecurityBaseline/VENDORED-FROM.md](../../Install%20PAWDeploy/Stages/3_Install_VMDeploy/Source/VMDeploy/SecurityBaseline/VENDORED-FROM.md) for where it came from and how to pull in a newer version from Mikael Nyström.

## 4. Package for deployment

- **Intune:** wrap the `Install PAWDeploy` folder with the Microsoft Win32 Content Prep Tool (`IntuneWinAppUtil.exe`). If you kept the default `CompanyName` (`DeployIT`), you can reuse the pre-built `.intunewin` files in [Default Intune Files/](../../Default%20Intune%20Files/) instead of repackaging.
- **SCCM:** add the `Install PAWDeploy` folder to the Application Library directly (no wrapping needed).
- **Manual/local:** no packaging needed — run `Install-PAWDeploy.ps1` directly from an elevated prompt.

Once packaged, proceed to [INSTALLATION.md](INSTALLATION.md).
