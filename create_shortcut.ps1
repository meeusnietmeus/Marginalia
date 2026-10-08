# Creates a "Marginalia" shortcut on your Desktop. Run this once:
#
#   powershell -ExecutionPolicy Bypass -File .\create_shortcut.ps1
#
# The shortcut starts the venv's pythonw.exe itself: no PowerShell in between, which saves a
# quarter of a second at every start, never flashes a console and pins to the taskbar cleanly.
# Add -ViaPowerShell to go through run_todo.ps1 instead (it finds the venv each time it runs).

param([switch]$ViaPowerShell)

$ProjectDir = $PSScriptRoot
$Desktop = [Environment]::GetFolderPath("Desktop")   # also correct if your Desktop is in OneDrive
$ShortcutPath = Join-Path $Desktop "Marginalia.lnk"

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($ShortcutPath)
$shortcut.WorkingDirectory = $ProjectDir
$shortcut.Description = "Marginalia: read, annotate and plan your studies"
$shortcut.IconLocation = "$ProjectDir\marginalia.ico"

if (-not $ViaPowerShell) {
    $Pythonw = @(".venv", "venv") |
        ForEach-Object { Join-Path $ProjectDir "$_\Scripts\pythonw.exe" } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1
    if (-not $Pythonw) { Write-Error "No venv found (.venv or venv) in $ProjectDir"; exit 1 }

    $shortcut.TargetPath = $Pythonw
    $shortcut.Arguments = "`"$ProjectDir\main.py`""
}
else {
    # -ExecutionPolicy Bypass applies to this launch only, so Activate.ps1 is allowed to run.
    $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ProjectDir\run_todo.ps1`""
    $shortcut.WindowStyle = 7   # minimized
}

$shortcut.Save()
Write-Host "Created: $ShortcutPath"
