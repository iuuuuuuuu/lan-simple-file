#ifndef RuntimeDir
  #error RuntimeDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef ShutdownHelper
  #error ShutdownHelper is required
#endif
#ifndef InstallerAppId
  #define InstallerAppId "{{1A37623A-7DAE-48D6-A724-616AF7F0F7CF}"
#endif

[Setup]
AppId={#InstallerAppId}
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
; PrepareToInstall closes only this installation, without the extra RM wizard prompt.
CloseApplications=no
RestartApplications=no
LicenseFile=..\LICENSE
#ifdef InstallerTest
Uninstallable=no
DirExistsWarning=no
#endif

[Files]
Source: "{#ShutdownHelper}"; Flags: dontcopy
Source: "{#RuntimeDir}\lan_simple_file.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RuntimeDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RuntimeDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\LICENSE"; DestDir: "{app}"
Source: "..\README.md"; DestDir: "{app}"
Source: "..\CHANGELOG.md"; DestDir: "{app}"
Source: "{srcexe}"; DestDir: "{app}\installers"; DestName: "lan-simple-file-setup.exe"; Flags: external ignoreversion

[Icons]
#ifndef InstallerTest
Name: "{group}\Lan Simple File"; Filename: "{app}\lan_simple_file.exe"
Name: "{group}\Uninstall"; Filename: "{uninstallexe}"
#endif

[Run]
#ifndef InstallerTest
Filename: "{app}\lan_simple_file.exe"; Description: "Launch Lan Simple File"; Flags: nowait postinstall skipifsilent
#endif

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Helper, Arguments: String;
  Details: AnsiString;
  ExitCode: Integer;
  Started: Boolean;
begin
  Result := '';
  ExtractTemporaryFile('installer_shutdown.exe');
  Helper := ExpandConstant('{tmp}\installer_shutdown.exe');
  Arguments := '"' + ExpandConstant('{app}\lan_simple_file.exe') + '" "' +
    ExpandConstant('{tmp}\shutdown.log') + '"';
  WizardForm.StatusLabel.Caption := 'Closing Lan Simple File...';
  Started := Exec(Helper, Arguments, '', SW_HIDE, ewWaitUntilTerminated, ExitCode);
  if Started and (ExitCode = 5) and not WizardSilent then
    Started := ShellExec('runas', Helper, Arguments, '', SW_HIDE,
      ewWaitUntilTerminated, ExitCode);
  Log(Format('Installed client shutdown: started=%d, result=%d', [Ord(Started), ExitCode]));
  if LoadStringFromFile(ExpandConstant('{tmp}\shutdown.log'), Details) then
    Log('Installed client shutdown details: ' + String(Details));
  if not Started or (ExitCode <> 0) then
    Result := Format('Could not stop Lan Simple File (Windows error %d).', [ExitCode]);
end;

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
