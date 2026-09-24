# Vendored from DeploymentBunny/Files

`Check-WindowsClientSecurityBaseline.ps1`, `Remediate-WindowsClientSecurityBaseline.ps1` and
`README.md` in this folder are copied from Mikael Nyström's public toolkit, with one local bugfix
(see below):

- Source: https://github.com/DeploymentBunny/Files/tree/master/Tools/CheckWindowsClientSecurityBaseline
- Commit: `8a9a4936920450877b44254ec03b85816e3253f4`
- Vendored: 2026-09-22
- Script version at time of vendoring: 1.6.8 (2026-05-07), per `Remediate-WindowsClientSecurityBaseline.ps1`'s own `.Notes` block.

## Local patch: `Set-RegistryDwordValue` / `Set-RegistryStringValue`

Found on first real test (2026-09-22): the script sets `Set-StrictMode -Version Latest`, and both
helpers read the current value as `(Get-ItemProperty -Path $Path -Name $Name -ErrorAction
SilentlyContinue).$Name`. When `$Name` doesn't exist yet under `$Path` - the normal case on a fresh,
never domain/GPO-managed machine, i.e. exactly this toolkit's target audience -
`Get-ItemProperty -ErrorAction SilentlyContinue` returns `$null`, and `$null.$Name` throws "The
property '...' cannot be found on this object" under Strict Mode. This made 8 of the 13
`-HardenRecommended` actions fail on a stock Windows 11 workgroup VM (WDigest, NTLM×3, SmartScreen×2,
Defender Antivirus, multicast) - reproduced and confirmed against a live PowerShell session before
patching.

Fixed in both functions by reading the value with `Get-ItemPropertyValue` in a `try/catch` instead,
which returns/throws cleanly regardless of Strict Mode:

```powershell
$current = $null
try { $current = Get-ItemPropertyValue -Path $Path -Name $Name -ErrorAction Stop } catch { }
```

This is the same idiom `Settings.psm1`'s own `Get-DeployStamp` already uses, for the same reason.
Worth reporting upstream to Mikael Nyström - if a newer version already fixes this, drop the patch
when updating.

## Why vendored instead of downloaded on demand

Unlike `Get-AzCopyPath` in `Stages/4_Download_Windows_VHDX/download-vhdx.ps1`, these scripts have no
Authenticode signature to verify before running - so unlike AzCopy, they are not auto-fetched from
the internet on every deployment. A fixed, reviewed copy in source control avoids running unpinned
third-party code with administrator rights inside every deployed VM.

## Updating

To pick up a newer version from Mikael Nyström, replace the two `.ps1` files (and `README.md`) with
the current versions from the source URL above, review the diff, and update the commit/date/version
in this file.

VMDeploy.ps1 calls `Remediate-WindowsClientSecurityBaseline.ps1` with every `-HardenRecommended`
switch applied individually **except `-SetInboundDefaultBlock`** (see the comment in `VMDeploy.ps1`
right before the call for why) - if a future version renames one of those switches or changes what
it does, check [docs/setup/PREPARATION.md](../../../../../docs/setup/PREPARATION.md#security-baseline)
still matches before rolling it out. Remember to re-apply the `Set-RegistryDwordValue`/
`Set-RegistryStringValue` patch above too, unless the new version already fixes it upstream.
