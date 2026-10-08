# Launches Marginalia using the project's virtual environment (no console window).

# Allow Activate.ps1 to run. Scope "Process" means this only affects this one
# PowerShell session and never changes your system-wide execution policy.
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue

$ProjectDir = $PSScriptRoot
Set-Location $ProjectDir

# Finds the venv folder (.venv or venv)
$Venv = @(".venv", "venv") |
    ForEach-Object { Join-Path $ProjectDir $_ } |
    Where-Object { Test-Path (Join-Path $_ "Scripts\Activate.ps1") } |
    Select-Object -First 1

if (-not $Venv) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "No virtual environment (.venv or venv) found in:`n$ProjectDir",
        "Marginalia", "OK", "Error") | Out-Null
    exit 1
}

. (Join-Path $Venv "Scripts\Activate.ps1")

# pythonw = no console window. It resolves to the venv's copy after activation.
Start-Process -FilePath "pythonw.exe" -ArgumentList "main.py" -WorkingDirectory $ProjectDir
