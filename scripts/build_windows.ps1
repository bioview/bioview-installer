# Build the Windows BioView one-dir bundle and wrap it in an Inno Setup installer.
#
# One exe, three shortcuts: the frozen binary dispatches on --role to the Monitor,
# the Configurator or the Viewer, so this Setup.exe installs the whole suite.
#
# Hybrid UHD: the official `uhd` PyPI wheel ships libuhd DLLs, the python bindings
# and the FPGA images, so a plain `pip install uhd` (done in prepare_env.ps1) gives
# a self-contained USRP stack. PyInstaller then collects all of it.
#
# Output: dist\<App>-<version>-Setup.exe
param(
    [string]$PythonBin = "python"
)
$ErrorActionPreference = "Stop"

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallerDir = Split-Path -Parent $Here
$BuildDir = Join-Path $InstallerDir "build\windows"
$DistDir = Join-Path $InstallerDir "dist"

$AppName = (& $PythonBin "$Here\buildcfg.py" get app.name).Trim()
$AppVersion = (& $PythonBin "$Here\buildcfg.py" get app.version).Trim()
$AppPublisher = (& $PythonBin "$Here\buildcfg.py" get app.publisher).Trim()
$DocExt = (& $PythonBin "$Here\buildcfg.py" get document.extension).Trim()
$DocDesc = (& $PythonBin "$Here\buildcfg.py" get document.description).Trim()

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

# --- 1. Environment (installs packages + uhd wheel + PyInstaller) ----------
& "$Here\prepare_env.ps1" -BuildDir $BuildDir -PythonBin $PythonBin
$Py = Join-Path $BuildDir "venv\Scripts\python.exe"

# --- 2. PyInstaller (one-dir) --------------------------------------------
$IconPath = Join-Path $InstallerDir ((& $PythonBin "$Here\buildcfg.py" get assets.icon_ico).Trim())
$IconArgs = @()
if (Test-Path $IconPath) { $IconArgs = @("--icon", $IconPath) }

$PyiDist = Join-Path $BuildDir "pyinstaller_dist"
Write-Host "=== Running PyInstaller ===" -ForegroundColor Cyan
& $Py -m PyInstaller --noconfirm --clean --windowed `
    --name $AppName `
    --distpath $PyiDist `
    --workpath (Join-Path $BuildDir "pyinstaller_work") `
    --specpath $BuildDir `
    @IconArgs `
    --collect-all uhd `
    --collect-all pyqtgraph `
    --collect-all numpy `
    --collect-all scipy `
    --collect-all h5py `
    --collect-all pygame `
    --collect-submodules bioview_common `
    --collect-submodules bioview_server `
    --collect-submodules bioview_client `
    --collect-data bioview_client `
    --collect-submodules bioview_viewer `
    --collect-data bioview_viewer `
    --hidden-import qtawesome `
    --hidden-import qdarktheme `
    --hidden-import scipy.signal `
    --hidden-import scipy.ndimage `
    --hidden-import scipy.special `
    "$Here\pyinstaller_entry.py"

$AppDir = Join-Path $PyiDist $AppName
if (-not (Test-Path $AppDir)) { Write-Error "PyInstaller output not found: $AppDir" }

# A bundle without the Viewer would still install and still start -- the failure
# would only show when someone opened a recording, so check it here instead.
& $Py -c "import bioview_viewer" 2>$null
if ($LASTEXITCODE -ne 0) { Write-Error "bioview_viewer not importable; the Viewer role would be dead" }

# --- 3. Inno Setup --------------------------------------------------------
$Inno = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $Inno)) { Write-Error "Inno Setup not found at $Inno" }

# The installer bundle icon uses the wordmark variant (favicon_text.svg).
$InstallerIcon = Join-Path $InstallerDir ((& $PythonBin "$Here\buildcfg.py" get assets.installer_ico).Trim())
$InstallerIconDefine = @()
if (Test-Path $InstallerIcon) { $InstallerIconDefine = @("/DSetupIconFile=$InstallerIcon") }

Write-Host "=== Building installer with Inno Setup ===" -ForegroundColor Cyan
& $Inno `
    "/DMyAppName=$AppName" `
    "/DMyAppVersion=$AppVersion" `
    "/DMyAppPublisher=$AppPublisher" `
    "/DMyAppExeName=$AppName.exe" `
    "/DDocExt=$DocExt" `
    "/DDocDesc=$DocDesc" `
    "/DSourceDir=$AppDir" `
    "/DOutputDir=$DistDir" `
    @InstallerIconDefine `
    "$InstallerDir\windows\setup.iss"

Write-Host "=== SUCCESS: $DistDir\$AppName-$AppVersion-Setup.exe ===" -ForegroundColor Green
