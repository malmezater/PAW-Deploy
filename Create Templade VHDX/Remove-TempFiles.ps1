$drive = "D:"

Write-Host "Starting cleanup on $drive..." -ForegroundColor Cyan

# Windows Update
Stop-Service -Name wuauserv -Force
Remove-Item "$drive\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
Start-Service -Name wuauserv

# Temp files
Remove-Item "$drive\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem "$drive\Users" -Directory | ForEach-Object {
    Remove-Item "$($_.FullName)\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
}

# Prefetch & Logs
Remove-Item "$drive\Windows\Prefetch\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$drive\Windows\Logs\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$drive\Windows\System32\winevt\Logs\*" -Force -ErrorAction SilentlyContinue

# Recycle Bin
Get-ChildItem "$drive\`$Recycle.Bin" -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Basic cleanup done. Running DISM component cleanup (this may take a while)..." -ForegroundColor Cyan
DISM /Image:$drive\ /Cleanup-Image /StartComponentCleanup /ResetBase

Write-Host "All done!" -ForegroundColor Green