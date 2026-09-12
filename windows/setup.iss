#ifndef AppVersion
  #define AppVersion "0.2.2"
#endif
#ifndef AppArch
  #define AppArch "x64"
#endif
[Setup]
AppId={{5D038B59-F065-4DF3-A03A-D270E841D8C1}
AppName=OmaSend
AppVersion={#AppVersion}
AppPublisher=OmaSend
AppPublisherURL=https://github.com/Aayush9029/OmaSend
DefaultDirName={localappdata}\Programs\OmaSend
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=OmaSend_{#AppVersion}_windows_{#AppArch}_Setup
SetupIconFile=OmaSend\AppIcon.ico
UninstallDisplayIcon={app}\OmaSend.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
#if AppArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{userprograms}\OmaSend"; Filename: "{app}\OmaSend.exe"; WorkingDir: "{app}"
[Run]
Filename: "{app}\OmaSend.exe"; Description: "Open OmaSend"; Flags: nowait postinstall skipifsilent
[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "OmaSend"; ValueData: """{app}\OmaSend.exe"" --background"; Flags: uninsdeletevalue; Check: ExistingStartup
[Code]
function ExistingStartup: Boolean;
begin
  Result := RegValueExists(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'OmaSend');
end;
