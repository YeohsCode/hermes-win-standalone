; Hermes Windows Offline Installer - Inno Setup Script
; Packages the upstream Hermes Desktop App (Electron) + pre-built runtime
; for fully offline installation on Windows.

#define MyAppName "Hermes"
#define MyAppVersion "3.0.2"
#define MyAppPublisher "Hermes"
#define MyAppURL "https://github.com/NousResearch/hermes-agent"
#define MyAppExeName "Hermes.exe"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=..\build
OutputBaseFilename=HermesSetup-{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Types]
Name: "full"; Description: "Full installation (all features)"
Name: "core"; Description: "Core only (Desktop App + Agent)"
Name: "custom"; Description: "Custom installation"; Flags: iscustom

[Components]
Name: "core"; Description: "Hermes Core (Desktop App + Agent Runtime)"; Types: full core custom; Flags: fixed
Name: "browser"; Description: "Browser Automation (Playwright + Chromium, ~300MB)"; Types: full
Name: "voice"; Description: "Voice / Speech (STT + TTS, ~500MB)"; Types: full

[Files]
; Electron Desktop App (unpacked)
Source: "..\build\electron-app\*"; DestDir: "{app}"; Components: core; Flags: ignoreversion recursesubdirs createallsubdirs
; Pre-built runtime (hermes-agent source + venv + PortableGit)
Source: "..\build\runtime-bundle\hermes-agent\*"; DestDir: "{localappdata}\hermes\hermes-agent"; Components: core; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\build\runtime-bundle\git\*"; DestDir: "{localappdata}\hermes\git"; Components: core; Flags: ignoreversion recursesubdirs createallsubdirs
; Optional browser automation deps
Source: "..\build\browser-bundle\*"; DestDir: "{localappdata}\hermes\browser"; Components: browser; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
; Optional voice deps
Source: "..\build\voice-bundle\*"; DestDir: "{localappdata}\hermes\voice"; Components: voice; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
; Helper scripts
Source: "scripts\setup-hermes.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "scripts\uninstall.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"
Name: "autostart"; Description: "Start Hermes at Windows login"; GroupDescription: "Startup options:"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Hermes"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Hermes"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\scripts\uninstall.ps1"" -InstallDir ""{app}"""; Flags: runhidden

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    WizardForm.StatusLabel.Caption := 'Configuring Hermes Agent...';
    if not Exec('powershell.exe',
                '-ExecutionPolicy Bypass -File "' + ExpandConstant('{app}') + '\scripts\setup-hermes.ps1" -InstallDir "' + ExpandConstant('{app}') + '"',
                '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    begin
      MsgBox('Failed to execute setup script.', mbError, MB_OK);
      Exit;
    end;

    if ResultCode <> 0 then
    begin
      MsgBox('Hermes setup encountered an issue (error ' + IntToStr(ResultCode) + ').' + #13#10 +
             'The application files have been installed. You may need to configure manually.',
             mbError, MB_OK);
    end;
  end;
end;
