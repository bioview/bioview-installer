$ErrorActionPreference = "Stop"

# --- 0. CONFIG LOADING ---
$ConfigFile = "build_config.json"
if (-not (Test-Path $ConfigFile)) { Write-Error "$ConfigFile not found!"; exit }

$Config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$AppName = $Config.app_name
$AppVersion = $Config.app_version
$GuiFolder = $Config.gui_folder_name
$EntryPoints = $Config.gui_entry_points # This is now an object/hashtable
$Repos = $Config.repos
$AssetRepo = $Config.assets_config.repo_name
$AssetPathRel = $Config.assets_config.path_inside_repo

$BuildDir = Join-Path $PWD "build_temp"
$DistDir = Join-Path $PWD "dist"
$AssetFullPath = Join-Path $BuildDir "$AssetRepo\$AssetPathRel"

Write-Host "=== Building $AppName v$AppVersion for Windows ===" -ForegroundColor Cyan

# --- 1. PREREQUISITES ---
function Test-Command ($cmd) { return (Get-Command $cmd -ErrorAction SilentlyContinue) }

if (-not (Test-Command "python")) {
    Write-Host "Installing Python..." -ForegroundColor Yellow
    winget install -e --id Python.Python.3.11 --accept-package-agreements --accept-source-agreements
    Write-Host "Python installed. RESTART SCRIPT." -ForegroundColor Red; exit
}
if (-not (Test-Command "git")) {
    Write-Host "Installing Git..." -ForegroundColor Yellow
    winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements
    Write-Host "Git installed. RESTART SCRIPT." -ForegroundColor Red; exit
}
$InnoPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $InnoPath)) {
    Write-Host "Installing Inno Setup..." -ForegroundColor Yellow
    $Installer = "innosetup.exe"
    Invoke-WebRequest -Uri "https://files.jrsoftware.org/is/6/innosetup-6.2.2.exe" -OutFile $Installer
    Start-Process -FilePath $Installer -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART" -Wait
    Remove-Item $Installer
}

# --- 2. CLONE & SETUP ---
Write-Host "--- Setting up Environment ---" -ForegroundColor Cyan
if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force }
New-Item -ItemType Directory -Path $BuildDir | Out-Null
if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Path $DistDir | Out-Null }

$Repos.PSObject.Properties | ForEach-Object {
    $FolderName = $_.Name
    $Url = $_.Value
    Write-Host "Cloning $FolderName..."
    git clone $Url "$BuildDir\$FolderName"
}

Write-Host "Creating Virtualenv..."
python -m venv "$BuildDir\venv"
$Pip = "$BuildDir\venv\Scripts\pip.exe"
$Python = "$BuildDir\venv\Scripts\python.exe"
& $Pip install --upgrade pip wheel pyinstaller

# --- 3. INSTALL PACKAGES ---
Write-Host "--- Installing Packages ---" -ForegroundColor Cyan
$Repos.PSObject.Properties | ForEach-Object {
    $FolderName = $_.Name
    $ReqPath = "$BuildDir\$FolderName\requirements.txt"
    if (Test-Path $ReqPath) { & $Pip install -r $ReqPath }
    & $Pip install "$BuildDir\$FolderName"
}

# --- 4. BUILD LOOP ---
Write-Host "--- Building Executables ---" -ForegroundColor Cyan
Push-Location "$BuildDir\$GuiFolder"

# Handle Icon
$IconArg = ""
$IconPath = Join-Path $AssetFullPath "icon.ico"
if (Test-Path $IconPath) { $IconArg = "--icon=`"$IconPath`"" }

# Initialize Inno Setup Lists
$InnoFiles = ""
$InnoIcons = ""

# Loop through Entry Points
$EntryPoints.PSObject.Properties | ForEach-Object {
    $Label = $_.Name
    $ScriptPath = $_.Value
    
    Write-Host ">> Building $Label..."

    # Handle entry point path separators
    $FullEntryPath = $ScriptPath -replace "/", "\"
    
    if (-not (Test-Path $FullEntryPath)) { 
        Write-Warning "$FullEntryPath not found. Skipping."
        return 
    }

    # Run PyInstaller
    $CmdString = "`"$Python`" -m PyInstaller --noconsole --onefile --clean --name `"$Label`" $IconArg `"$FullEntryPath`""
    cmd /c $CmdString

    # Move EXE
    $ExeSrc = "dist\$Label.exe"
    if (Test-Path $ExeSrc) {
        Move-Item $ExeSrc "$DistDir\$Label.exe" -Force
        
        # Add to Inno Setup lists
        # Source: "PathToExe"; DestDir: "{app}"; Flags: ignoreversion
        $InnoFiles += "Source: `"$DistDir\$Label.exe`"; DestDir: `"{app}`"; Flags: ignoreversion`r`n"
        
        # Name: "{autoprograms}\Label"; Filename: "{app}\Label.exe"
        $InnoIcons += "Name: `"{autoprograms}\\$Label`"; Filename: `"{app}\\$Label.exe`"`r`n"
        $InnoIcons += "Name: `"{autodesktop}\\$Label`"; Filename: `"{app}\\$Label.exe`"; Tasks: desktopicon`r`n"
        
    } else { Write-Error "Build failed for $Label" }
}

Pop-Location

# --- 5. PACKAGING ---
Write-Host "--- Creating Installer ---" -ForegroundColor Cyan
$IssFile = "$DistDir\setup.iss"
$OutputBase = "${AppName}_${AppVersion}_Setup"

$SetupIconLine = ""
if (Test-Path $IconPath) { $SetupIconLine = "SetupIconFile=$IconPath" }

$IssContent = @"
[Setup]
AppName=$AppName
AppVersion=$AppVersion
DefaultDirName={autopf}\\$AppName
OutputBaseFilename=$OutputBase
OutputDir=$DistDir
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
$SetupIconLine

[Files]
$InnoFiles

[Icons]
$InnoIcons

[Tasks]
Name: "desktopicon"; Description: "Create &desktop icons"; GroupDescription: "Additional icons:"
"@

Set-Content -Path $IssFile -Value $IssContent
& $InnoPath "$IssFile"

Write-Host "=== SUCCESS: Installer at $DistDir\$OutputBase.exe ===" -ForegroundColor Green
