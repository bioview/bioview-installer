# Acquire the three BioView packages and install them (plus deps + PyInstaller +
# uhd) into a fresh virtualenv for the Windows PyInstaller build.
#
# Usage: prepare_env.ps1 -BuildDir <dir> [-PythonBin python]
param(
    [Parameter(Mandatory = $true)][string]$BuildDir,
    [string]$PythonBin = "python"
)
$ErrorActionPreference = "Stop"

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallerDir = Split-Path -Parent $Here

$SrcDir = Join-Path $BuildDir "src"
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
if (Test-Path $SrcDir) { Remove-Item $SrcDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $SrcDir | Out-Null

Write-Host "=== Acquiring BioView packages ===" -ForegroundColor Cyan
& $PythonBin "$Here\buildcfg.py" packages | ForEach-Object {
    $parts = $_.Split("|")
    $name = $parts[0]; $git = $parts[1]; $ref = $parts[2]; $local = $parts[3]
    $dest = Join-Path $SrcDir $name
    $localAbs = Join-Path $InstallerDir $local
    if ($local -and (Test-Path $localAbs)) {
        Write-Host ">> Using local checkout for $name ($localAbs)"
        robocopy $localAbs $dest /E /XD .git .venv venv dist build __pycache__ | Out-Null
    } else {
        Write-Host ">> Cloning $name from $git @ $ref"
        if ($ref) { git clone --depth 1 --branch $ref $git $dest }
        else { git clone --depth 1 $git $dest }
    }
}

Write-Host "=== Creating virtualenv ===" -ForegroundColor Cyan
$Venv = Join-Path $BuildDir "venv"
if (Test-Path $Venv) { Remove-Item $Venv -Recurse -Force }
& $PythonBin -m venv $Venv
$Py = Join-Path $Venv "Scripts\python.exe"

& $Py -m pip install --upgrade pip wheel "pyinstaller>=6.10"

# The uhd PyPI wheel requires numpy<2.0. bioview-server pulls scipy first, which
# otherwise installs numpy 2.x; scipy then fails at runtime in the PyInstaller bundle
# (AttributeError: module 'numpy' has no attribute 'long').
Write-Host "=== Pinning scientific stack (numpy<2 for uhd + PyInstaller) ===" -ForegroundColor Cyan
& $Py -m pip install `
    "numpy>=1.26,<2.0" `
    "scipy>=1.16.1,<2.0.0" `
    "h5py>=3.14.0,<4.0.0"

Write-Host "=== Installing BioView packages (common -> server -> client) ===" -ForegroundColor Cyan
& $Py -m pip install (Join-Path $SrcDir "bioview-common")
& $Py -m pip install (Join-Path $SrcDir "bioview-server")
& $Py -m pip install (Join-Path $SrcDir "bioview-client")

$UhdVersion = (& $PythonBin "$Here\buildcfg.py" get uhd.version).Trim()
Write-Host "=== Installing uhd==$UhdVersion from PyPI ===" -ForegroundColor Cyan
try { & $Py -m pip install "uhd==$UhdVersion" }
catch { Write-Warning "uhd pip install failed (USRP support will be unavailable)" }

Write-Host "=== Verifying scipy/numpy import ===" -ForegroundColor Cyan
& $Py -c "import numpy, scipy.signal; print('numpy', numpy.__version__, 'scipy', scipy.__version__)"

Write-Host "=== Environment ready: $Venv ===" -ForegroundColor Green
