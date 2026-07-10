# Default Intune Files

The pre-packaged `.intunewin` files in this folder can be used directly in Intune **if you are using the default values** in `Settings.psm1`.

## Default Values

| Setting | Default value |
|---|---|
| `CompanyName` | `DeployIT` |
| `LocalInstall` | `$false` (Intune mode, no shortcuts are created) |

Logs are written to `C:\ProgramData\DeployIT\Logs\`.

---

## Run VMDeploy

Launches the VMDeploy UI (`PAWDeploywUI.ps1`) to create virtual machines.

| Intune field | Value |
|---|---|
| **Install command** | `powershell.exe -ExecutionPolicy Bypass -File Run-VMDeploy.ps1` |
| **Uninstall command** | *(use Remove VMDeploy below)* |
| **Detection rule** | File exists: `C:\ProgramData\DeployIT\Check\Run-PAWDeploy.txt` |

---

## Remove VMDeploy

Launches the VMDeploy UI (`VMRemovewUI.ps1`) to remove virtual machines.

| Intune field | Value |
|---|---|
| **Install command** | `powershell.exe -ExecutionPolicy Bypass -File Remove-VMDeploy.ps1` |
| **Detection rule** | File exists: `C:\ProgramData\DeployIT\Check\Remove-PAWDeploy.txt` |

---

## Custom Values

If you have changed `CompanyName` or other values in `Settings.psm1`, you will need to repackage the files using **IntuneWinAppUtil** and update the detection rules above.
