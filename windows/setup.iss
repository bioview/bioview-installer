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
; The recording type the suite owns; opening one starts the Viewer role.
#ifndef DocExt
  #define DocExt "bvr"
#endif
#ifndef DocDesc
  #define DocDesc "BioView recording"
#endif
#define RecordingProgId "BioView.Recording"

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
; One exe, three apps: each shortcut is the same binary pinned to a --role.
Name: "{group}\BioView Monitor"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\BioView Configurator"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--role configurator"
Name: "{group}\BioView Viewer"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--role viewer"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\BioView Monitor"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{autodesktop}\BioView Viewer"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--role viewer"; Tasks: desktopicon

[Registry]
; Associate BioView config files with the Monitor (launcher forwards the path).
Root: HKA; Subkey: "Software\Classes\.bvi"; ValueType: string; ValueName: ""; ValueData: "BioView.Experiment"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\BioView.Experiment"; ValueType: string; ValueName: ""; ValueData: "BioView Experiment"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\BioView.Experiment\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"
Root: HKA; Subkey: "Software\Classes\BioView.Experiment\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" --config-file ""%1"""

; Associate recordings with the Viewer role. "%1" must stay quoted -- recordings
; routinely live under paths with spaces.
Root: HKA; Subkey: "Software\Classes\.{#DocExt}"; ValueType: string; ValueName: ""; ValueData: "{#RecordingProgId}"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.{#DocExt}\OpenWithProgids"; ValueType: string; ValueName: "{#RecordingProgId}"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\{#RecordingProgId}"; ValueType: string; ValueName: ""; ValueData: "{#DocDesc}"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\{#RecordingProgId}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"
Root: HKA; Subkey: "Software\Classes\{#RecordingProgId}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" --role viewer ""%1"""

; Listed under "Open with" even when another app owns the extension.
Root: HKA; Subkey: "Software\Classes\Applications\{#MyAppExeName}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\{#MyAppExeName}\SupportedTypes"; ValueType: string; ValueName: ".{#DocExt}"; ValueData: ""; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\{#MyAppExeName}\SupportedTypes"; ValueType: string; ValueName: ".bvi"; ValueData: ""; Flags: uninsdeletekey

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
