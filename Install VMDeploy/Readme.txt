Install command
PowerShell -ExecutionPolicy ByPass -NoProfile -File install-vmdeploy.ps1

Install behavior
System (prefered)
Administrator (Works but not recommended)
User (Does not work!)

Detection rules
Creates multiplie registry values under HKLM\Software\DeployIT\VMDeploy.
You will find them in "VMDeploy-Detections.txt". 

Rules format
Use a custom detection script
Run script as 32-bit process on 64-bit clients
No
Enforce script signature check and run script silently
No

INFORMATION
IF using SCCM/Intune company portal, recommended to remove the shortcuts created for VMDeploy. 
This should then be started from Company Portal instead.

SCCM/Intune Deployment:
Create an application called "Install VMDeploy" or whatever you like it to be called.

To add and remove VM's, create two applications called, VMDeploy and VM-Remove (Or what ever name you like).
Use the powershell scripts in "Company Portal" folder to launch the applications.
