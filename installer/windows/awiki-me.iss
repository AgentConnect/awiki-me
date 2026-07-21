#define MyAppName "AWiki Me"
#define MyAppPublisher "AWiki"
#define MyAppExeName "AWikiMe.exe"
#define MyAppGuid "6D68B66D-87E1-4F18-93C5-AE56D58C5211"
#define MyAppId "{{" + MyAppGuid + "}"
#define MyUninstallKey "Software\Microsoft\Windows\CurrentVersion\Uninstall\{" + MyAppGuid + "}_is1"
#define MyAppUserModelId "AWiki.AWikiMe"

#ifndef MyAppSourceDir
  #error MyAppSourceDir must point to the Flutter Windows Release directory
#endif
#ifndef MySetupIcon
  #error MySetupIcon must point to the AWiki .ico file
#endif
#ifndef MyAppVersion
  #error MyAppVersion is required
#endif
#ifndef MyBuildNumber
  #error MyBuildNumber is required
#endif
#ifndef MyVersionInfoVersion
  #error MyVersionInfoVersion is required
#endif
#ifndef MyOutputDir
  #define MyOutputDir "."
#endif
#ifndef MyOutputBaseFilename
  #define MyOutputBaseFilename "AWiki-Me-windows-x64"
#endif

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
CloseApplications=no
Compression=lzma2/ultra64
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
MinVersion=10.0.19045
OutputBaseFilename={#MyOutputBaseFilename}
OutputDir={#MyOutputDir}
PrivilegesRequired=lowest
RestartApplications=no
SetupIconFile={#MySetupIcon}
SolidCompression=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoDescription={#MyAppName} Windows x64 installer
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyVersionInfoVersion}
VersionInfoVersion={#MyVersionInfoVersion}
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; AppUserModelID: "{#MyAppUserModelId}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; AppUserModelID: "{#MyAppUserModelId}"

[Code]
function NumericVersionPart(const Value: String; Index: Integer): Integer;
var
  Cursor: Integer;
  Part: Integer;
  CurrentIndex: Integer;
begin
  Cursor := 1;
  Part := 0;
  CurrentIndex := 0;
  while (Cursor <= Length(Value)) and (CurrentIndex <= Index) do
  begin
    if (Value[Cursor] >= '0') and (Value[Cursor] <= '9') then
      Part := (Part * 10) + Ord(Value[Cursor]) - Ord('0')
    else if Value[Cursor] = '.' then
    begin
      if CurrentIndex = Index then
      begin
        Result := Part;
        exit;
      end;
      CurrentIndex := CurrentIndex + 1;
      Part := 0;
    end
    else
      break;
    Cursor := Cursor + 1;
  end;
  if CurrentIndex = Index then
    Result := Part
  else
    Result := 0;
end;

function CompareVersions(const Left, Right: String): Integer;
var
  Index: Integer;
  LeftPart: Integer;
  RightPart: Integer;
begin
  Result := 0;
  for Index := 0 to 3 do
  begin
    LeftPart := NumericVersionPart(Left, Index);
    RightPart := NumericVersionPart(Right, Index);
    if LeftPart < RightPart then
    begin
      Result := -1;
      exit;
    end;
    if LeftPart > RightPart then
    begin
      Result := 1;
      exit;
    end;
  end;
end;

function InitializeSetup(): Boolean;
var
  InstalledVersion: String;
begin
  Result := True;
  if RegQueryStringValue(
       HKCU,
       '{#MyUninstallKey}',
       'DisplayVersion',
       InstalledVersion) then
  begin
    if CompareVersions('{#MyAppVersion}', InstalledVersion) < 0 then
    begin
      SuppressibleMsgBox(
        'A newer version of {#MyAppName} is already installed. Downgrade is not allowed.',
        mbCriticalError,
        MB_OK,
        IDOK);
      Result := False;
    end;
  end;
end;

function RequestRunningAppShutdown(): Boolean;
var
  ExistingExe: String;
  ResultCode: Integer;
begin
  Result := True;
  ExistingExe := ExpandConstant('{app}\{#MyAppExeName}');
  if FileExists(ExistingExe) then
    Result := Exec(
      ExistingExe,
      '--shutdown-for-update',
      '',
      SW_HIDE,
      ewWaitUntilTerminated,
      ResultCode) and (ResultCode = 0);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not RequestRunningAppShutdown() then
    Result := '{#MyAppName} could not exit safely. Close the app and retry the installation.';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usUninstall) and
     (not RequestRunningAppShutdown()) then
    RaiseException(
      '{#MyAppName} could not exit safely. Close the app and retry the uninstall.');
end;
