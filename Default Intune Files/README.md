# Default Intune Files

De färdigpaketerade `.intunewin`-filerna i den här mappen kan användas direkt i Intune **om du använder standardvärdena** i `Settings.psm1`.

## Standardvärden

| Inställning | Standardvärde |
|---|---|
| `CompanyName` | `DeployIT` |
| `LocalInstall` | `$false` (Intune-läge, inga genvägar skapas) |

Loggar skrivs till `C:\ProgramData\DeployIT\Logs\`.

---

## Run VMDeploy

Startar VMDeploy-gränssnittet (`PAWDeploywUI.ps1`) för att skapa virtuella maskiner.

| Fält i Intune | Värde |
|---|---|
| **Installationskommando** | `powershell.exe -ExecutionPolicy Bypass -File Run-VMDeploy.ps1` |
| **Avinstallationskommando** | *(använd Remove VMDeploy nedan)* |
| **Identifieringsregel** | Fil finns: `C:\ProgramData\DeployIT\Check\Run-PAWDeploy.txt` |

---

## Remove VMDeploy

Startar VMDeploy-gränssnittet (`VMRemovewUI.ps1`) för att ta bort virtuella maskiner.

| Fält i Intune | Värde |
|---|---|
| **Installationskommando** | `powershell.exe -ExecutionPolicy Bypass -File Remove-VMDeploy.ps1` |
| **Identifieringsregel** | Fil finns: `C:\ProgramData\DeployIT\Check\Remove-PAWDeploy.txt` |

---

## Anpassade värden

Om du har ändrat `CompanyName` eller andra värden i `Settings.psm1` behöver du paketera om filerna med **IntuneWinAppUtil** och uppdatera identifieringsreglerna ovan.
