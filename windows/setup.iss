; Inno Setup script for BioView.
; Values are supplied by scripts/build_windows.ps1 via /D defines; the #ifndef
; fallbacks let you also open this file directly in the Inno Setup IDE.

#ifndef MyAppName
  #define MyAppName "BioView"
#endif
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef MyAppPublisher
  #define MyAppPublisher "BioView"
#endif
#ifndef MyAppExeName
  #define MyAppExeName "BioView.exe"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\pyinstaller_dist\BioView"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif
; Installer bundle icon (the wordmark variant). Supplied by build_windows.ps1 via
; /DSetupIconFile; the fallback lets the file open directly in the Inno IDE.
#ifndef SetupIconFile
  #define SetupIconFile "..\assets\installer.ico"
#endif

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir={#OutputDir}
OutputBaseFilename={#MyAppName}-{#MyAppVersion}-Setup
SetupIconFile={#SetupIconFile}
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ChangesAssociations=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"

[Files]
; The entire PyInstaller one-dir output (BioView.exe + _internal + bundled UHD).
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\BioView Monitor"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\BioView Configurator"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--role configurator"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\BioView Monitor"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; Associate .bview experiment files with the Monitor (launcher forwards the path).
Root: HKA; Subkey: "Software\Classes\.bview"; ValueType: string; ValueName: ""; ValueData: "BioView.Experiment"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\BioView.Experiment"; ValueType: string; ValueName: ""; ValueData: "BioView Experiment"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\BioView.Experiment\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"
Root: HKA; Subkey: "Software\Classes\BioView.Experiment\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" --config-file ""%1"""

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
