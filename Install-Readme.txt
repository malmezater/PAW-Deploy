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
Begin with changing the 3 following things in settings under "Install VMDeploy". 

Company Name: Change this if you want another name than DeployIT.
Download URL: Change this to the URL where you can download your Windows Image.
Win11-25H2: Change this if you using another Windows image.

SCCM Installation:
Add the folder "Install VMDeply" in Application Library.
Create an application called "Install VMDeploy" or whatever you like it to be called.
Install VMDeploy with the settings above.

Intune Installation:
Use the intunewim file under "Install VMDeploy Company Portal" with the install settings above.

Recommended with SCCM/Intune:
To add and remove VM's, create two applications called, VMDeploy and VM-Remove (Or what ever name you like).
Create another two applications one for Deployment and one for Remove VM's. 
The path for VMDeploy is "C:\ProgramData\VMDeploy\" and you will find "VMDeploywUI.ps1" (Deploy VM) and "VMRemovewUI.ps1" (Remove VM).

Powershell should run the files with something like this:
Deploy VM = "PowerShell -ExecutionPolicy ByPass -NoProfile -File "C:\ProgramData\VMdeploy\VMDeploywUI.ps1"
Remove VM = "PowerShell -ExecutionPolicy ByPass -NoProfile -File "C:\ProgramData\VMdeploy\VMRemovewUI.ps1"

Run as local Admin:
Two shortcuts are created during installation, this shortcuts is to start powershell scripts to deploy or remove VM's.
The shortcuts are NOT created for the Intune deployment!
