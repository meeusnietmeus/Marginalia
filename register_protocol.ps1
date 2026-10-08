# Teaches Windows that marginalia:// links open Marginalia (the browser extension uses them to say
# "write a note about this video, at this moment"). Run this once:
#
#   powershell -ExecutionPolicy Bypass -File .\register_protocol.ps1
#
# It writes only to your own part of the registry (HKEY_CURRENT_USER), no admin rights needed.
# Run it again after moving the project folder. To undo it:
#
#   powershell -ExecutionPolicy Bypass -File .\register_protocol.ps1 -Unregister

param([switch]$Unregister)

$Key = "HKCU:\Software\Classes\marginalia"

if ($Unregister) {
    if (Test-Path $Key) { Remove-Item -Path $Key -Recurse -Force }
    Write-Host "marginalia:// links no longer open Marginalia."
    exit 0
}

$ProjectDir = $PSScriptRoot
$Pythonw = @(".venv", "venv") |
    ForEach-Object { Join-Path $ProjectDir "$_\Scripts\pythonw.exe" } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1
if (-not $Pythonw) { Write-Error "No venv found (.venv or venv) in $ProjectDir"; exit 1 }

# pythonw: no console window. "%1" is the whole link; the app reads it with --open.
$Command = "`"$Pythonw`" `"$ProjectDir\main.py`" --open `"%1`""

New-Item -Path $Key -Force | Out-Null
Set-ItemProperty -Path $Key -Name "(Default)" -Value "URL:Marginalia"
Set-ItemProperty -Path $Key -Name "URL Protocol" -Value ""
New-Item -Path "$Key\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path "$Key\DefaultIcon" -Name "(Default)" -Value "$ProjectDir\marginalia.ico"
New-Item -Path "$Key\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "$Key\shell\open\command" -Name "(Default)" -Value $Command

Write-Host "marginalia:// links now open Marginalia:"
Write-Host "  $Command"
