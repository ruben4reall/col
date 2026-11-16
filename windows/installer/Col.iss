; Col for Windows: a per-user installer, no administrator rights needed.
;   iscc /DVersion=3.0.0 /DSource=..\..\artifacts windows\installer\Col.iss
; Source holds win-x64\ and win-arm64\, each with Col.exe and colctl.exe; the PC's architecture picks one.

#ifndef Version
  #define Version "3.0.0"
#endif
#ifndef Source
  #define Source "..\..\artifacts"
#endif

[Setup]
AppId={{6F1C2B9A-5D3E-4A7B-9C21-0C01C0DE3000}
AppName=Col
AppVersion={#Version}
AppVerName=Col {#Version}
AppPublisher=Ruben Catalao
AppPublisherURL=https://getcol.vercel.app
AppSupportURL=https://github.com/ruben4reall/col/issues
AppUpdatesURL=https://github.com/ruben4reall/col/releases
AppCopyright=Copyright (c) 2026 Ruben Catalao
VersionInfoVersion={#Version}.0
VersionInfoDescription=Col for Windows setup
PrivilegesRequired=lowest
DefaultDirName={autopf}\Col
DisableProgramGroupPage=yes
DisableDirPage=auto
ArchitecturesAllowed=x64compatible arm64
ArchitecturesInstallIn64BitMode=x64compatible arm64
MinVersion=10.0.19041
OutputDir={#Source}
OutputBaseFilename=Col-{#Version}-windows-setup
SetupIconFile=..\src\Col\Assets\col.ico
UninstallDisplayIcon={app}\Col.exe
UninstallDisplayName=Col
LicenseFile=..\..\LICENSE
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ChangesEnvironment=yes
ChangesAssociations=yes
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[CustomMessages]
english.StartAtLogin=Open Col when I sign in
french.StartAtLogin=Ouvrir Col à la connexion
english.Options=Options:
french.Options=Options :

[Tasks]
Name: "startup"; Description: "{cm:StartAtLogin}"; GroupDescription: "{cm:Options}"

[Files]
Source: "{#Source}\win-x64\Col.exe"; DestDir: "{app}"; Check: not IsArm64; Flags: ignoreversion
Source: "{#Source}\win-x64\colctl.exe"; DestDir: "{app}"; Check: not IsArm64; Flags: ignoreversion
Source: "{#Source}\win-arm64\Col.exe"; DestDir: "{app}"; Check: IsArm64; Flags: ignoreversion
Source: "{#Source}\win-arm64\colctl.exe"; DestDir: "{app}"; Check: IsArm64; Flags: ignoreversion
Source: "..\..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Col"; Filename: "{app}\Col.exe"; Comment: "Col, a Dynamic Island for Windows"

[Registry]
; Launch at login: the same line Col's own switch writes, so either can turn it off.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Col"; ValueData: """{app}\Col.exe"" --background"; Flags: uninsdeletevalue; Tasks: startup
; col:// links, for this user.
Root: HKCU; Subkey: "Software\Classes\col"; ValueType: string; ValueName: ""; ValueData: "URL:Col"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\col"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\col\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\Col.exe"",0"
Root: HKCU; Subkey: "Software\Classes\col\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\Col.exe"" ""%1"""
; colctl on the user's PATH.
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; Check: NeedsAddPath(ExpandConstant('{app}'))

[Run]
Filename: "{app}\Col.exe"; Description: "{cm:LaunchProgram,Col}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; The agents forget Col before it goes, so no hook calls a command that is not there any more.
Filename: "{app}\colctl.exe"; Parameters: "hooks uninstall --agent all"; Flags: runhidden waituntilterminated; RunOnceId: "DisconnectAgents"
Filename: "{sys}\taskkill.exe"; Parameters: "/IM Col.exe /F"; Flags: runhidden waituntilterminated; RunOnceId: "QuitCol"

[UninstallDelete]
; Col's settings, its log and the lyrics it kept.
Type: filesandordirs; Name: "{localappdata}\Col"

[Code]
function NeedsAddPath(Folder: string): Boolean;
var
  Path: string;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', Path) then
  begin
    Result := True;
    exit;
  end;
  Result := Pos(';' + Uppercase(Folder) + ';', ';' + Uppercase(Path) + ';') = 0;
end;

procedure RemovePath(Folder: string);
var
  Path: string;
  Position: Integer;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', Path) then exit;
  Path := ';' + Path + ';';
  Position := Pos(';' + Uppercase(Folder) + ';', Uppercase(Path));
  if Position = 0 then exit;
  Delete(Path, Position, Length(Folder) + 1);
  Path := Copy(Path, 2, Length(Path) - 2);
  RegWriteExpandStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', Path);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    RemovePath(ExpandConstant('{app}'));
end;
