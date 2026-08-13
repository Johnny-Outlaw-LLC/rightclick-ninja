; Right Click Ninja — Windows installer
; Build: ISCC.exe RightClickNinja.iss

#define MyAppName "Right Click Ninja"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Outlaw Apps"
#define MyAppURL "https://rightclick.ninja"
#define MyAppExeName "RightClickNinja.exe"
#define MyAppId "OutlawApps.RightClickNinja"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\RightClickNinja
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=LICENSE.txt
OutputDir=dist
OutputBaseFilename=RightClickNinja-Setup-{#MyAppVersion}
SetupIconFile=..\branding\rightclick-ninja.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible x86compatible arm64
PrivilegesRequired=lowest
CloseApplications=yes
RestartApplications=no
ChangesAssociations=no
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoProductName={#MyAppName}
VersionInfoCopyright=Copyright (C) 2026 {#MyAppPublisher}
SetupLogging=yes
DisableWelcomePage=no
WizardSizePercent=120
InfoAfterFile=AFTER.txt

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
WelcomeLabel1=Welcome to {#MyAppName} Setup
WelcomeLabel2=This will install {#MyAppName} on your PC.%n%nEveryday file fixes — date shifts first, more tools on the way — all from a right-click.%n%nClick Next to continue.
FinishedLabel=Setup has finished installing {#MyAppName} on your computer.%n%nSelect files in Explorer, then choose Show more options → Right Click Ninja.

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "contextmenu"; Description: "Add &Right Click Ninja to Explorer right-click menu"; GroupDescription: "Shell integration:"; Flags: checkedonce

[Files]
Source: "payload\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
; Explorer context menu (files)
Root: HKCU; Subkey: "Software\Classes\*\shell\RightClickNinja"; ValueType: string; ValueName: ""; ValueData: "Right Click Ninja"; Flags: uninsdeletekey; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\*\shell\RightClickNinja"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#MyAppExeName}"; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\*\shell\RightClickNinja"; ValueType: string; ValueName: "MultiSelectModel"; ValueData: "Player"; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\*\shell\RightClickNinja"; ValueType: string; ValueName: "Position"; ValueData: "Top"; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\*\shell\RightClickNinja\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: contextmenu

; All filesystem objects
Root: HKCU; Subkey: "Software\Classes\AllFilesystemObjects\shell\RightClickNinja"; ValueType: string; ValueName: ""; ValueData: "Right Click Ninja"; Flags: uninsdeletekey; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\AllFilesystemObjects\shell\RightClickNinja"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#MyAppExeName}"; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\AllFilesystemObjects\shell\RightClickNinja"; ValueType: string; ValueName: "MultiSelectModel"; ValueData: "Player"; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\AllFilesystemObjects\shell\RightClickNinja"; ValueType: string; ValueName: "Position"; ValueData: "Top"; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\AllFilesystemObjects\shell\RightClickNinja\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: contextmenu

; Folders
Root: HKCU; Subkey: "Software\Classes\Directory\shell\RightClickNinja"; ValueType: string; ValueName: ""; ValueData: "Right Click Ninja"; Flags: uninsdeletekey; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\Directory\shell\RightClickNinja"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#MyAppExeName}"; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\Directory\shell\RightClickNinja"; ValueType: string; ValueName: "MultiSelectModel"; ValueData: "Player"; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\Directory\shell\RightClickNinja"; ValueType: string; ValueName: "Position"; ValueData: "Top"; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\Directory\shell\RightClickNinja\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: contextmenu

; Clean old Outlaw Update menu keys on install
Root: HKCU; Subkey: "Software\Classes\*\shell\OutlawUpdateDates"; Flags: deletekey
Root: HKCU; Subkey: "Software\Classes\AllFilesystemObjects\shell\OutlawUpdateDates"; Flags: deletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\OutlawUpdateDates"; Flags: deletekey

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
