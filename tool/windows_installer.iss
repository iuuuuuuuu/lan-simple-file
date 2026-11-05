#ifndef RuntimeDir
  #error RuntimeDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef AppVersion
  #define AppVersion "0.1.0-beta.4"
#endif

[Setup]
AppId={{1A37623A-7DAE-48D6-A724-616AF7F0F7CF}
AppName=Lan Simple File
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\LanSimpleFile
DefaultGroupName=Lan Simple File
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=lan-simple-file-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\lan_simple_file.exe
CloseApplications=no
LicenseFile=..\LICENSE

[Files]
Source: "{#RuntimeDir}\lan_simple_file.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RuntimeDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RuntimeDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\LICENSE"; DestDir: "{app}"
Source: "..\README.md"; DestDir: "{app}"
Source: "..\CHANGELOG.md"; DestDir: "{app}"
Source: "{srcexe}"; DestDir: "{app}\installers"; DestName: "lan-simple-file-setup.exe"; Flags: external ignoreversion

[Icons]
Name: "{group}\Lan Simple File"; Filename: "{app}\lan_simple_file.exe"
Name: "{group}\Uninstall"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\lan_simple_file.exe"; Description: "Launch Lan Simple File"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Command: String;
begin
  if CurUninstallStep = usUninstall then
    if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run',
        'LanSimpleFile', Command) then
      if CompareText(Command, '"' + ExpandConstant('{app}\lan_simple_file.exe') + '"') = 0 then
        RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'LanSimpleFile');
end;
