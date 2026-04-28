Install command
PowerShell -ExecutionPolicy ByPass -NoProfile -File install-vmdeploy.ps1

Install behavior
System (prefered)
Administrator (Works but not recommended)
User (Does not work!)

Detection rules
Creates multiplie registry values under HKLM\Software\DeployIT\VMDeploy.

Rules format
Use a custom detection script
Run script as 32-bit process on 64-bit clients
No
Enforce script signature check and run script silently
No

INFORMATION
