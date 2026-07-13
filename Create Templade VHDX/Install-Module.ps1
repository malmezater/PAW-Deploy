$Modules = @( 
    "WindowsAutoPilotIntune" 
) 

$Scripts = @( 

    "Get-WindowsAutoPilotInfo" 

) 

foreach ($item in $Modules) { 

    Install-Module -Name $item -Scope AllUsers -Force 

} 

foreach ($item in $Scripts) { 

    Install-Script -Name $item -Scope AllUsers -Force 

} 