# Install-Readme

## Before You Start

Edit the following settings in `Settings.psm1` (located in the `Install PAWDeploy` folder) before packaging or deploying.

| Setting | Description |
| --- | --- |
| `CompanyName` | Name used for the registry path and ProgramData folder. Default: `DeployIT`. |
| `DownloadUrl` | Source of the Windows 11 VHDX (see supported formats below). |
| `VHDXVersion` | Version tag for the VHDX — change if you use a different image (e.g. `Win11-24H2`). Default: `Win11-25H2`. |
| `LocalInstall` | `$true` = local/manual install (Start Menu shortcuts created). `$false` = Intune / ConfigMgr (no shortcuts). |

### Supported Download Sources

The installer auto-detects the transfer method from `$DownloadUrl`:

| Source type | Example | Method used |
| --- | --- | --- |
| Azure Blob / Azure Files | `https://<account>.blob.core.windows.net/...` | AzCopy (auto-installed) |
| SMB / UNC share | `\\server\share\image.vhdx` | `Copy-Item` |
| HTTP / HTTPS web server | `http://fileserver/image.vhdx` | BITS (Invoke-WebRequest fallback) |

---

## Intune Deployment

### Install command

```
PowerShell -ExecutionPolicy ByPass -NoProfile -File Install-PAWDeploy.ps1
```

### Install behavior

| Context | Supported |
| --- | --- |
| System | ✅ Preferred |
| Administrator | ⚠️ Works, but not recommended |
| User | ❌ Does not work |

### Detection rules

The installer writes multiple registry values under `HKLM\SOFTWARE\<CompanyName>\VMDeploy`.
Full list in [VMDeploy-Detections.txt](VMDeploy-Detections.txt).

| Setting | Value |
| --- | --- |
| Use a custom detection script | No |
| Run script as 32-bit process on 64-bit clients | No |
| Enforce script signature check and run script silently | No |

---

## SCCM Deployment

1. Add the `Install VMDeploy` folder to the Application Library.
2. Create an application (e.g. **Install VMDeploy**) using the install command above.

---

## Running VM Deploy and VM Remove (SCCM / Intune)

Create two separate applications to let users deploy and remove VMs after installation:

| Application | Command |
| --- | --- |
| Deploy Windows | `PowerShell -ExecutionPolicy ByPass -NoProfile -File "C:\ProgramData\VMDeploy\VMDeploywUI.ps1"` |
| Destroy VM | `PowerShell -ExecutionPolicy ByPass -NoProfile -File "C:\ProgramData\VMDeploy\VMRemovewUI.ps1"` |

---

## Local / Manual Install

When `LocalInstall = $true` in `Settings.psm1`, two **Run as Administrator** shortcuts are created in the Start Menu during installation.

> These shortcuts are **not** created when `LocalInstall = $false` (Intune or ConfigMgr deployments).
