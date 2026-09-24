# PAW-Deploy Security Review

**Scope:** `Install PAWDeploy/` (host installer, stages 1-4), the `VMDeploy` guest-provisioning
tool it ships (`VMDeploy.ps1`, `VMDeploywUI.ps1`, `VMRemovewUI.ps1`, the `VIA*Module.psm1`
libraries), `Create Templade VHDX/`, and the `Default Intune Files/` wrappers.
**Method:** Manual static review of every PowerShell script and XML config in the repository
(source review only — no dynamic/runtime testing was performed against a live deployment).
**Reviewer:** Security review conducted at the user's request, 2026-08-21.
**Version reviewed:** Installer v2.2.3 (commit `26aaf43`).
**Remediation pass:** 2026-09-18, against the then-current `main` (v2.3.0). Findings are annotated
below with their resolution status; the code changes referenced as "2.3.1" have not yet had a
version bump applied to `ScriptVersion`/`VMDeployVersion` — do that (and rebuild the `.intunewin`
packages) before repackaging for redeployment.

## Executive summary

PAW-Deploy automates turning a Windows 11 endpoint into a Hyper-V host for
Privileged Access Workstation (PAW) virtual machines, and separately automates
building the guest VMs themselves (domain-join, BitLocker, app/module install).
The overall architecture — idempotent, registry-stamped stages; TPM-backed
BitLocker; Shielded VM policy on deployed guests — reflects real security intent.

However, the review found **two critical-severity issues** that undermine the
core promise of a PAW (that it isolates and protects privileged credentials),
plus a number of high/medium issues around supply-chain integrity, credential
handling, and host attack surface. None of these require exotic access to
exploit — they trigger through the tool's own normal, documented workflow.

| # | Finding | Severity | Location | Status |
|---|---|---|---|---|
| 1 | PowerShell command injection via unsanitized GUI input | **Critical** | `VMDeploywUI.ps1:400-446` | **Fixed** (2.3.1) |
| 2 | Domain Admin / local Administrator passwords persist in cleartext inside every deployed guest | **Critical** | `Functions/VIADeployModule.psm1` (all `New-VIAUnattendXML*` functions), `VMDeploy.ps1:275-286` | **Fixed** (2.3.1) |
| 3 | AutoLogon leaves a plaintext password in the guest registry | High | `Functions/VIADeployModule.psm1:731-740` | **Fixed** (2.3.1) |
| 4 | No integrity/signature verification of the golden VHDX image or AzCopy binary | High | `Stages/4_Download_Windows_VHDX/download-vhdx.ps1` | **Fixed** (2.3.1) |
| 5 | Deployment config and VHD source fetched over unauthenticated HTTP/UNC | Medium | `VMDeploy.ps1:114-132`, `download-vhdx.ps1:29-44` | **Fixed** (2.3.1) |
| 6 | Credentials transit a world-readable plaintext temp file | Medium | `VMDeploywUI.ps1:426-432` | **Fixed** (2.3.1) |
| 7 | Logged-in user and a non-expiring-password service account both granted Hyper-V Administrators (host-admin-equivalent) | Medium | `Stages/2_Install_VMDeploy-configuration/Add-HyperVAdmin.ps1` | Open — access-model decision, see note below |
| 8 | PAW host firewall rules permanently weakened for Hyper-V remoting | Medium | `Stages/2_Install_VMDeploy-configuration/Set-FirewallRules.ps1` | **Fixed** (2.3.1, opt-in) |
| 9 | No script signing; execution relies on `-ExecutionPolicy Bypass` everywhere | Medium | repo-wide | Open — needs a code-signing cert, see note below |
| 10 | External VMSwitch auto-binds to "first Up adapter" with no operator confirmation | Low | `Configure-PAWNetwork.ps1:34` | Mitigated (2.3.0) — explicit `VMSwitchAdapterName` setting added; still defaults to "first Up" with a warning if unset |
| 11 | RDP shortcut disables NLA / security layer | Low | `VMDeploy.ps1:388-446` | Open — accepted, loopback-only |
| 12 | No BitLocker recovery-key escrow for guest VMs | Low | `VMDeploy.ps1:333-356` | **Rejected by design**, see note below |
| 13 | PSGallery module/app install has no allow-list or signature pinning | Low | `VMDeploy.ps1:586-647`, `Modules.xml` | **Fixed** (2.3.1, opt-in) |

Findings 1 and 2 were blocking for any production rollout and are now fixed — repackage and
redeploy (see "Fixed in 2.3.1" below) before relying on this for production PAW rollouts.

---

## Critical findings

### 1. PowerShell command injection via unsanitized GUI input
**File:** `Install PAWDeploy/Stages/3_Install_VMDeploy/Source/VMDeploy/VMDeploywUI.ps1:400-446`

> **Fixed in 2.3.1.** `OkButtonSelected` now passes a `[string[]]` argument array to
> `Start-Process -FilePath ... -ArgumentList` with an explicit `-File`, instead of one
> interpolated command-line string with no `-File`/`-Command`. Each value reaches
> `VMDeploy.ps1` as a discrete process argument and is never re-parsed as PowerShell input.
> Input validation was also added for VM name, IP/gateway/DNS/subnet, VLAN id and domain account
> (`Test-VMDeploy*` helpers in `VMDeploywUI.ps1`), closing the functional bugs (spaces/metacharacters
> breaking deployments) the recommendation called out.

`OkButtonSelected` builds a command line by directly interpolating raw text-box
input (`VMName`, IP/gateway/DNS/subnet fields, `DomainAdmin`, `vlanid`) into a
single string, then launches it with:

```powershell
$ScriptToRun = "$RootFolder\VMDeploy.ps1"
$Argument = "$ScriptToRun $ScriptArguments"
Start-Process PowerShell -ArgumentList "$Argument" -Verbose
```

Two problems compound here:

- None of the interpolated fields are validated, whitelisted, or escaped.
- The invocation has **no `-File` or `-Command` switch**. When `powershell.exe`
  is started this way, the entire trailing string is parsed and *executed* as
  interactive PowerShell input (the CLI's implicit-command mode), not passed
  as literal arguments to a script. That means `;`, backticks, `$(...)`, and
  pipes typed into any of those text boxes run as live PowerShell.

Because the shortcut that launches `VMDeploywUI.ps1` ("Deploy Windows.lnk",
created in `Stages/3_Install_VMDeploy/Install-VMDeploy.ps1:61-64`) has its
run-as-administrator bit set, the GUI process — and therefore the injected
command — executes with local Administrator rights, on the very host meant to
be hardened as a PAW.

**Impact:** Local privilege-context code execution triggered by a single
crafted VM name (e.g. `x`; `Start-Process cmd`; `#`). This is exploitable by
anyone who can type into the GUI, including malware driving the UI
programmatically, and it also silently corrupts legitimate deployments whose
input happens to contain spaces or PowerShell metacharacters.

**Recommendation:** Never assemble a command line by string concatenation.
Either:
- call `VMDeploy.ps1` with `Start-Process -FilePath PowerShell.exe -ArgumentList $argArray` where `$argArray` is a **string array** (one element per parameter/value, no manual quoting), or
- switch entirely to the `-DataFromFile` / `Export-Clixml` pattern already used for passwords (see Finding 6) so no user input ever crosses a command-line boundary, or
- invoke the script in-process via `& $ScriptToRun @paramHashtable` (splatting) instead of spawning a shell.

Add input validation (hostname character set, IP format) regardless, since it
also fixes real functional bugs (spaces/quotes breaking deployments today).

---

### 2. Domain Admin / local Administrator passwords persist in cleartext inside every deployed guest
**Files:**
`Functions/VIADeployModule.psm1` — `New-VIAUnattendXML`, `New-VIAUnattendXMLClient`, `New-VIAUnattendXMLClientfor1709` (all three build the same pattern)
`VMDeploy.ps1:275-286` (writes the file into the guest VHD, never removes it from inside the guest)

> **Fixed in 2.3.1.** `SetupComplete.cmd` (already generated and run once, post-first-logon, inside
> every guest) now also deletes `Windows\Panther\Unattend.xml`,
> `Windows\Panther\unattend.xml` and `Windows\System32\Sysprep\Panther\unattend.xml` from the guest,
> in addition to its existing "mark deployment done" step. No behavior change to the deployment
> flow — the hook already ran post-setup, it just also scrubs itself now. The recommendation to
> prefer a low-privilege, single-use domain-join account over an actual Domain Admin account is
> an operational choice for the account used in `Config.xml`/the GUI, not something the tool can
> enforce in code — still worth applying.

The unattend answer file generated for every VM sets:

```xml
<Credentials>
    <Username>$DomainAdmin</Username>
    <Domain>$DomainAdminDomain</Domain>
    <Password>$DomainAdminPassword</Password>
</Credentials>
...
<AdministratorPassword>
    <Value>$AdminPassword</Value>
    <PlainText>True</PlainText>
</AdministratorPassword>
```

`VMDeploy.ps1` mounts the new VM's disk, copies this file to
`Windows\Panther\Unattend.xml` **inside the guest VHD**, then dismounts. It
only deletes the *host-side* temporary copy (`$VIAUnattendXML.FullName`) —
the copy that ships inside the guest at `C:\Windows\Panther\Unattend.xml`
(and typically also cached under `C:\Windows\System32\Sysprep\Panther\`) is
never scrubbed after Windows Setup consumes it.

This is a long-documented Windows anti-pattern (Microsoft's own guidance is
to delete unattend files after setup, or avoid `PlainText=True`): any user or
process that later gets a shell on the guest — including a lower-privileged
account, or anyone who mounts the VHD offline — can read the file directly.
No decryption is required; `PlainText=True` and the domain-join credentials
block are stored as literal readable text.

**Impact:** For any template using domain join, the Domain Admin (or
domain-join) account password used to provision the VM is recoverable from
every single guest built from that template — potentially hundreds of VMs
over the life of the tool, each one a standing credential-exposure liability.
This directly undermines the reason a PAW exists (see the companion
[PAW-CONCEPT.md](PAW-CONCEPT.md) document): a PAW's guest VMs are precisely
where the organization's highest-value credentials get typed and cached, so
leaving them recoverable in plaintext on disk defeats the model.

**Recommendation:**
- After OOBE completes (the existing `SetupComplete.cmd` hook already runs
  code post-setup — extend it), delete `C:\Windows\Panther\Unattend.xml` and
  `C:\Windows\Panther\unattend.xml` under `C:\Windows\System32\Sysprep\Panther\`
  from inside the guest.
- Prefer a low-privilege, single-use domain-join account over an actual
  Domain Admin account for `$DomainAdminPassword`, and rotate/disable it
  after joins.
- Where possible, avoid embedding the local Administrator password in the
  unattend file at all — set it via a post-OOBE `Invoke-Command` (which the
  script already has a PowerShell Direct session for) instead of baking it
  into the image.

---

## High-severity findings

### 3. AutoLogon leaves a plaintext password in the guest registry
**File:** `Functions/VIADeployModule.psm1:731-740` (`New-VIAUnattendXMLClientfor1709`)

> **Fixed in 2.3.1.** Rather than dropping AutoLogon (which some templates rely on to reach a
> desktop automatically on first boot), the same `SetupComplete.cmd` extension from Finding 2 now
> also deletes the `Winlogon\DefaultPassword` value and disables `AutoAdminLogon` after the
> one-time logon completes, so the plaintext password doesn't stay in the registry past first boot.

```xml
<AutoLogon>
 <Enabled>true</Enabled>
 <Username>Administrator</Username>
 <Password><Value>$AdminPassword</Value><PlainText>true</PlainText></Password>
 <LogonCount>1</LogonCount>
</AutoLogon>
```

Windows Setup persists AutoLogon credentials to
`HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\DefaultPassword`
in cleartext, and does not reliably clear that value once `LogonCount` is
exhausted. Combined with Finding 2, this is a second standing location the
same Administrator password can be recovered from on the guest.

**Recommendation:** Either drop AutoLogon entirely (PowerShell Direct/PS
Remoting is already used for all post-boot automation and doesn't need an
interactive auto-logged-in session), or add a SetupComplete step that clears
`DefaultPassword`/`AutoAdminLogon` after first boot.

### 4. No integrity/signature verification of the golden VHDX image or AzCopy binary
**File:** `Stages/4_Download_Windows_VHDX/download-vhdx.ps1`

- `Get-AzCopyPath` (lines 46-66) downloads `azcopy.exe` from
  `https://aka.ms/downloadazcopy-v10-windows` and runs it with no hash or
  Authenticode check.
- `Invoke-VHDXDownload` (lines 68-101) fetches the Windows 11 template VHDX
  (via AzCopy, SMB `Copy-Item`, or BITS/`Invoke-WebRequest`) and writes it
  straight to `$VHDXDownloadPath` with no post-download hash comparison
  against a known-good manifest.

> **Fixed in 2.3.1 (AzCopy).** `Get-AzCopyPath` now verifies `azcopy.exe`'s Authenticode signature
> (`Status -eq 'Valid'` and signed by Microsoft) before it's copied into the trusted `Tools\AzCopy`
> location and run. **Already mitigated in 2.3.0 (VHDX):** `download-vhdx.ps1` verifies
> `$VHDXSha256` via `Get-FileHash` when the setting is populated — it remains optional (empty by
> default), so set `VHDXSha256` in `Settings.psm1` to actually get the check; an unset hash still
> only produces a warning, not a hard failure.

This VHDX becomes the base image for *every* VM the tool ever deploys.
**Recommendation:** Publish a SHA-256 (or better) checksum alongside the VHDX
at the source, and have `download-vhdx.ps1` verify it (`Get-FileHash`) before
stamping the registry as successful. Pin/verify the AzCopy download the same
way, or vendor a known-good copy instead of fetching it live.

---

## Medium-severity findings

### 5. Deployment config and VHD source fetched over unauthenticated HTTP/UNC
**Files:** `VMDeploy.ps1:114-132`, `download-vhdx.ps1:29-44`

`Get-DownloadMethod` explicitly accepts plain `http://` as a valid transport
(`^https?://`), and the top of `VMDeploy.ps1` fetches its XML config via
`(New-Object System.Net.WebClient).DownloadString($XMLDatafile)` for both
`'http'` and `'unc'` sources with no TLS enforcement and no
integrity/signature check on the returned XML (which controls the domain-join
target, `MachineObjectOU`, VHD source path, etc.). An attacker positioned on
the network path, or with write access to a permissive SMB share, could
rewrite the config to redirect deployments or substitute a malicious VHD.

> **Fixed in 2.3.1.** For `Source = 'http'`, `VMDeploy.ps1` now throws unless `XMLFile` starts with
> `https://` and fetches it with `Invoke-WebRequest` (TLS 1.2 forced) instead of a raw `WebClient`.
> For `Source = 'unc'`, it now reads the path with `Get-Content -Raw` — a UNC path is a filesystem
> path, not an HTTP endpoint, so `WebClient` was never the right tool there; the trust boundary is
> the SMB share ACLs, same as `'local'`. `Get-DownloadMethod` in `download-vhdx.ps1` (which selects
> the VHDX transport, not the config transport) is unchanged — it still accepts `http://` for the
> VHDX itself, covered by the Finding 4 hash check instead.

**Recommendation:** Require HTTPS for the `http` config source (or remove
plain-HTTP support), validate the TLS certificate, and consider signing
`Config.xml`/`LConfig.xml`.

### 6. Credentials transit a world-readable plaintext temp file
**File:** `VMDeploywUI.ps1:426-432`

```powershell
$DataToExport = @{ AdminPassword=$AdminPassword; DomainAdminPassword=$DomainAdminPassword; ... }
$DataToExport | Export-Clixml -Path "$env:TEMP\vmdeploy.xml"
```

This correctly keeps passwords out of the command line (a good design choice
already present in the tool), but because the values are plain `[string]`
rather than `SecureString`, `Export-Clixml` serializes them as literal
readable text (no DPAPI protection) to a file under `%TEMP%`. `VMDeploy.ps1`
does delete it after import (`VMDeploy.ps1:186`), but there is a window
between write and read, and a crash/early-exit before that line would leave
the file behind.

> **Fixed in 2.3.1.** `AdminPassword`/`DomainAdminPassword` are now converted to `SecureString`
> before `Export-Clixml` — DPAPI-encrypts them at rest, bound to the current user+machine, so the
> file is unreadable outside that context. `VMDeploy.ps1` decrypts them back to plain strings
> immediately on import (every other consumer already expects plain strings) and the
> import+delete is wrapped in `try/finally`, so `%TEMP%\vmdeploy.xml` is always removed even on a
> crash/early-exit.

**Recommendation:** Convert the passwords to `SecureString` before export
(DPAPI-encrypts them at rest, bound to the user/machine), and wrap the
import/delete in `try/finally` so the temp file is always removed even on
failure.

### 7. Logged-in user and a non-expiring-password service account both granted Hyper-V Administrators
**File:** `Stages/2_Install_VMDeploy-configuration/Add-HyperVAdmin.ps1`

The installer adds the interactively signed-in user to **Hyper-V
Administrators** (SID `S-1-5-32-578`) and creates a local `Hypervuser`
account, also added to that group, with `PasswordNeverExpires:$true`.
Hyper-V Administrators is functionally local-admin-equivalent — members can
attach to, clone, or modify any VM on the host, which is enough to extract
secrets from or tamper with any guest, including ones running privileged PAW
tooling. A standing, non-expiring-password local account in that group is a
persistent high-value target with no rotation story.

**Recommendation:** Treat Hyper-V Administrators membership like local admin
in your access model (PIM/JIT elevation rather than standing membership where
feasible). Enforce rotation on `Hypervuser` (or eliminate the account if it
isn't actually needed), and document/monitor it as a privileged local
account.

> **Open — organizational decision, not fixed in code.** Whether the operator gets standing
> Hyper-V Administrators membership (vs. JIT/PIM elevation) and whether `Hypervuser` exists at all
> is an access-model choice for the deploying organization, not something VMDeploy can decide for
> them. `CreateHyperVUser` in `Settings.psm1` already lets an operator disable the `Hypervuser`
> account entirely; the recommendation to prefer JIT/PIM elevation over standing membership stands.

### 8. PAW host firewall rules permanently weakened for Hyper-V remoting
**File:** `Stages/2_Install_VMDeploy-configuration/Set-FirewallRules.ps1`, rules defined in `Settings.psm1`

The installer disables `VIRT-WMI-RPCSS-In-TCP-NoScope`,
`VIRTCL-WMI-RPCSS-In-TCP-NoScope`, and `VIRT-REMOTEDESKTOP-In-TCP-NoScope`
inbound firewall rules — opening WMI/RPC and enhanced-session RDP listeners
on the **host**, not the guest — and there is no scoping to a management
subnet. A PAW's core value proposition is a minimized host attack surface;
permanently widening inbound listeners on the admin endpoint itself cuts
against that.

**Recommendation:** Re-scope these rules to trusted management IP ranges
instead of disabling them outright (`Set-NetFirewallRule -RemoteAddress
<mgmt-subnet>`), or confirm (and document) that remote/non-loopback Hyper-V
administration of the PAW host is actually a required use case before
opening it by default.

> **Fixed in 2.3.1 (opt-in).** A new `FirewallScopeSubnet` setting in `Settings.psm1` (empty by
> default) lets an operator scope these rules to a management subnet
> (`Set-NetFirewallRule -RemoteAddress $FirewallScopeSubnet`, rule stays **enabled**) instead of
> disabling them outright. Left unset, Stage 2b keeps today's disable-outright behavior — set
> `FirewallScopeSubnet` to actually close this gap; a warning is now logged at deploy time when it
> isn't set, calling out that the rule is being opened to the whole network.

### 9. No script signing; execution relies on `-ExecutionPolicy Bypass` everywhere
**Files:** every stage invocation in `Install-PAWDeploy.ps1`, `Install-VMDeploy.ps1` shortcuts, `Default Intune Files/*`

Every `PowerShell.exe` invocation in the repo uses
`-ExecutionPolicy Bypass -NoProfile`, and no `.ps1`/`.psm1` file is
Authenticode-signed. This is normal for Intune Win32 app packaging, but it
means the only thing standing between "this is the vendor's script" and
"this is a tampered script" is the integrity of the Intune content pipeline
and `C:\ProgramData\VMDeploy` ACLs — there's no cryptographic verification at
execution time. Note also that `Install-VMDeploy.ps1:51` uses `Robocopy ...
/copyall`, which preserves source ACLs (including owner) onto the
destination; if the packaged source ever has permissive ACLs, they carry
straight through to `C:\ProgramData\VMDeploy`.

**Recommendation:** Sign the scripts and move production deployments toward
`AllSigned`/`RemoteSigned`, and explicitly set (don't just inherit) a
restrictive ACL on `C:\ProgramData\VMDeploy` and `C:\ProgramData\<Company>`
after install (Administrators/SYSTEM: full control, Users: read+execute, no
write).

> **Open — needs a code-signing certificate, not fixed in code.** Signing every script and moving
> to `AllSigned`/`RemoteSigned` requires an Authenticode certificate and a signing process the
> deploying organization has to own; there's nothing to change in the repository itself until
> that's in place. The ACL follow-up (explicit lockdown of `C:\ProgramData\VMDeploy` after
> `Install-VMDeploy.ps1`'s `Robocopy /copyall`) was considered during this pass and deliberately
> deferred alongside it rather than done partially.

---

## Low-severity findings

### 10. External VMSwitch auto-binds to "first Up adapter" with no confirmation
**File:** `Stages/2_Install_VMDeploy-configuration/Configure-PAWNetwork.ps1:34`

```powershell
$NetAdapter = Get-NetAdapter -Physical | Where-Object Status -EQ "Up" | Select-Object -First 1
```

On a multi-NIC host this can silently bind the "Ethernet Cable" external
switch to whichever adapter happens to be first/Up, which may not be the
adapter the operator intended to dedicate to guest VM traffic — risking guest
and host-management traffic sharing the same uplink, which works against
network isolation, one of the PAW model's core controls.

**Recommendation:** Make the adapter selection explicit (a `Settings.psm1`
value or an interactive prompt) rather than implicit "first one up."

> **Mitigated in 2.3.0.** `VMSwitchAdapterName` in `Settings.psm1` lets an operator pin the
> adapter explicitly; `Configure-PAWNetwork.ps1` uses it when set. Left empty, it still falls back
> to "first physical adapter that is Up" — now at least with a warning logged when more than one
> is Up — so this is an improvement, not a full fix; set `VMSwitchAdapterName` to close it
> completely.

### 11. RDP shortcut disables NLA / security layer
**File:** `VMDeploy.ps1:388-446` (`$RDPFileTemplate`)

The generated `.rdp` file sets `authentication level:i:0` and `negotiate
security layer:i:0`, disabling NLA and falling back to the legacy RDP
Standard Security Layer instead of TLS. Risk is limited today because the
file targets `localhost:2179` (the VMConnect enhanced-session loopback
channel), but it's worth an explicit, documented exception rather than a
silent default — especially since nothing prevents a future change from
repointing these `.rdp` files at a network address.

### 12. No BitLocker recovery-key escrow for guest VMs
**File:** `VMDeploy.ps1:333-356`

Guests get `Enable-BitLocker -TpmProtector` with a `RecoveryPasswordProtector`
fallback only if TPM setup fails, but the recovery key/password is never
exported or escrowed anywhere (no AD/Entra ID backup, no export to the host).
If a guest's vTPM state is ever lost (VM export/import, host rebuild,
Shielded VM key issues), the disk becomes unrecoverable. This is an
availability/recoverability gap rather than a confidentiality one.

**Recommendation:** Add `Backup-BitLockerKeyProtector` (to AD) or export the
recovery password to a secured location as part of the provisioning flow.

> **Rejected by design — not fixed.** Exporting the recovery password to the host (or anywhere
> the host can read) would let anyone who compromises the host, or who obtains the VHDX file,
> decrypt the guest without the TPM — defeating the reason the guest's disk is encrypted in the
> first place. For this tool's PAW threat model, the guest/host is treated as untrusted to hold
> its own recovery secret, so this is an accepted availability trade-off (a lost vTPM state means
> a lost VM), considered and deliberately kept, not overlooked. `Backup-BitLockerKeyProtector` to
> AD remains a reasonable option for domain-joined templates where AD is the trust anchor — that's
> an operator/environment choice this tool doesn't make for you.

### 13. PSGallery module/app install has no allow-list or signature pinning
**File:** `VMDeploy.ps1:586-647`, `Modules.xml`

Guest provisioning runs `Install-Module -Force -AllowClobber -Repository
PSGallery` for every module listed in the selected profile (by default:
`Az`, `Microsoft.Graph`, `ExchangeOnlineManagement`, etc.) with no
`Get-AuthenticodeSignature`/publisher check. This is standard PSGallery
supply-chain exposure (typosquatting, dependency confusion, compromised
maintainer accounts), but it's worth calling out given these VMs are
explicitly meant to run privileged administrative tooling.

**Recommendation:** Consider an internal PowerShell repository mirror with
curated/pinned module versions for the default profiles, or at minimum pin
`-RequiredVersion` in `Modules.xml` instead of always installing latest.

> **Fixed in 2.3.1 (opt-in).** `<Module>` nodes in `Modules.xml`/package files now accept an
> optional `Version` attribute; when set, VM Deploy passes `-RequiredVersion` instead of always
> installing latest. Unpinned modules keep installing latest, same as before — pin `Version` per
> module to close this gap for that module. An internal PSGallery mirror remains a further step
> beyond what this tool can decide on its own (it needs repository infrastructure the deploying
> organization would have to stand up).

---

## What the review found done well

- Idempotent, registry-stamped install stages make the installer safe to
  re-run and easy to reason about for Intune detection rules.
- BitLocker (TPM-backed, `Aes256`, `UsedSpaceOnly`) is enabled automatically
  on every deployed guest, with a sane fallback protector.
- `Set-VMSecurityPolicy -Shielded $true` is applied to non-OOBE guests after
  initial setup, which is genuinely good practice for protecting VM state
  against a compromised/malicious Hyper-V host operator.
- Automatic checkpoints are disabled on deployed VMs, avoiding stale
  credential/state leakage through forgotten checkpoint files.
- The `Hypervuser` creation dialog enforces a 15-character minimum password
  interactively before account creation.
- Passwords are already kept out of the process command line via the
  `-DataFromFile`/`Export-Clixml` pattern (Finding 6 only asks that the
  serialized values also be `SecureString`-protected, not that the pattern
  change).

## Suggested remediation order

1. ~~Fix Finding 1 (command injection)~~ — it's a straightforward code change and blocks the most severe exploitation path. **Done, 2.3.1.**
2. ~~Fix Finding 2 and 3 (persisted plaintext credentials)~~ — add a post-OOBE cleanup step; this is the change most directly tied to *why* a PAW exists. **Done, 2.3.1.**
3. ~~Add hash verification to Finding 4 (image/tooling integrity)~~ before the next template refresh. **Done for AzCopy, 2.3.1; VHDX SHA256 check exists since 2.3.0 but stays optional — set `VHDXSha256`.**
4. Work through the Medium findings as part of normal hardening backlog; none block usage individually, but 5-9 compound into a materially weaker PAW than the design intends. **5, 6 and 8 fixed in 2.3.1 (8 is opt-in — set `FirewallScopeSubnet`); 7 and 9 remain open organizational/infrastructure decisions (access model, code-signing cert) — see the notes on those findings above.**

### Remaining open items (not code fixes)

- **Finding 7** — decide the access model for Hyper-V Administrators / `Hypervuser` (standing
  membership vs. JIT/PIM elevation).
- **Finding 9** — obtain a code-signing certificate and move to `AllSigned`/`RemoteSigned`; lock
  down `C:\ProgramData\VMDeploy` ACLs explicitly post-install.
- **Finding 11** — accepted (RDP NLA disabled, but loopback-only today).
- **Finding 12** — accepted by design; do not export BitLocker recovery keys to the host for this
  tool's threat model (see the note on that finding above).
