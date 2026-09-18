# Requirements

Prerequisites for both the PAW host (running the installer) and the guest VMs it provisions.

## Host requirements

| Requirement | Detail |
| --- | --- |
| OS | Windows 11 (Pro/Enterprise), with virtualization enabled in firmware (Intel VT-x/AMD-V + SLAT). |
| Rights | Local administrator. Intune runs the installer as **SYSTEM**. |
| PowerShell | 5.1 or later (`#Requires -Version 5.1` in every script). |
| Network adapter | An active physical NIC, used to bind the Hyper-V external switch ("Ethernet Cable"). |
| Free disk space | Enough for the Hyper-V role, the downloaded template VHDX, and every guest VM's differencing/checkpoint disks. |

## Install context (Intune / SCCM)

| Context | Supported |
| --- | --- |
| System | ✅ Preferred |
| Administrator (interactive) | ⚠️ Works, but not recommended |
| User (non-admin) | ❌ Does not work |

## Network access

| Need | Used for |
| --- | --- |
| Access to the VHDX source configured in `$DownloadUrl` (`Settings.psm1`) | Downloading the template VHDX — see supported source types below. |
| `https://aka.ms/downloadazcopy-v10-windows` | Only if the VHDX source is Azure Blob/Files — AzCopy is auto-installed on demand. |
| `api.github.com` and `github.com` (from the **host**) | Fetching the latest winget-cli release for the guest bootstrap. |
| `codeload.github.com` (from the **host**) | **Easy to miss:** GitHub `…/archive/…zip` URLs (used by `<Download>` entries in packages) redirect from `github.com` to this separate host. A proxy that allows `github.com` but not `codeload.github.com` answers **504 Gateway Timeout**, and the download falls back to a cached copy — or fails outright on a host that has never downloaded it. |
| `cdn.winget.microsoft.com` (from the **host**) | The winget client dependencies and the package index (`Microsoft.Winget.Source`), staged on the host and pushed into the guest. |
| `www.powershellgallery.com` (from inside guest VMs) | Installing PowerShell modules during guest provisioning. |
| Vendor download URLs (from inside guest VMs) | winget downloads each application's installer from its publisher during guest provisioning. |

Supported VHDX/config source types (auto-detected from the URL):

| Source type | Example | Method used |
| --- | --- | --- |
| Azure Blob / Azure Files | `https://<account>.blob.core.windows.net/...` | AzCopy (auto-installed) |
| SMB / UNC share | `\\server\share\image.vhdx` | `Copy-Item` |
| HTTP / HTTPS web server | `http://fileserver/image.vhdx` | BITS (falls back to `Invoke-WebRequest`) |

In isolated PAW network segments you may need an internal winget/PSGallery mirror or an outbound allow-list for the guest-VM endpoints above.

## Accounts

- An account to add to the local **Hyper-V Administrators** group (the interactively signed-in user is added automatically during install).
- Domain-join credentials, if guest templates join a domain — see the credential-handling notes in [security/SECURITY-REVIEW.md](../security/SECURITY-REVIEW.md) before using a standing Domain Admin account for this.

## Template VHDX

A pre-built, generalized (sysprepped) Windows 11 Enterprise VHDX must be available at the location configured in `$DownloadUrl`. See [PREPARATION.md](PREPARATION.md) for how to build one, or the full walkthrough in [Create Templade VHDX/README.md](../../Create%20Templade%20VHDX/README.md).
