; Hermes Windows Standalone - Inno Setup Script
; Builds a standalone installer for Hermes AI Agent on Windows

#define MyAppName "Hermes"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Hermes"
#define MyAppURL "https://github.com/YeohsCode/hermes-win-standalone"
#define MyAppExeName "hermes-desktop.exe"

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
Name: "core"; Description: "Core only (chat + web UI)"
Name: "custom"; Description: "Custom installation"; Flags: iscustom

[Components]
Name: "core"; Description: "Hermes Core (Agent + Web UI)"; Types: full core custom; Flags: fixed
Name: "browser"; Description: "Browser Automation (Playwright + Chromium, ~300MB)"; Types: full
Name: "voice"; Description: "Voice / Speech (STT + TTS, ~500MB)"; Types: full
Name: "messaging"; Description: "Messaging Platforms (Telegram, Discord, Slack, etc., ~50MB)"; Types: full

[Files]
; Tauri application
Source: "..\tauri-app\src-tauri\target\release\hermes-desktop.exe"; DestDir: "{app}"; Flags: ignoreversion
; Core WSL rootfs
Source: "..\wsl-distro\output\rootfs-core.tar.gz"; DestDir: "{app}\wsl"; Components: core; Flags: ignoreversion
; Optional layers
Source: "..\wsl-distro\output\layer-browser.tar.gz"; DestDir: "{app}\wsl"; Components: browser; Flags: ignoreversion
Source: "..\wsl-distro\output\layer-voice.tar.gz"; DestDir: "{app}\wsl"; Components: voice; Flags: ignoreversion
Source: "..\wsl-distro\output\layer-messaging.tar.gz"; DestDir: "{app}\wsl"; Components: messaging; Flags: ignoreversion
; Helper scripts
Source: "scripts\*"; DestDir: "{app}\scripts"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"
Name: "autostart"; Description: "Start Hermes at Windows login"; GroupDescription: "Startup options:"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Hermes"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\scripts\check-wsl2.ps1"""; StatusMsg: "Checking WSL2 status..."; Flags: runhidden
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\scripts\import-distro.ps1"" -InstallDir ""{app}"""; StatusMsg: "Setting up HermesLinux environment..."; Flags: runhidden
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Hermes"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\scripts\uninstall.ps1"""; Flags: runhidden

[Code]
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  // Check if WSL2 is available
  if not Exec('wsl', '--version', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    if MsgBox('WSL2 is not enabled on this system.' + #13#10 + #13#10 +
              'Hermes requires WSL2 to run. Would you like to enable it now?' + #13#10 +
              '(This requires a system restart)', mbConfirmation, MB_YESNO) = IDYES then
    begin
      Exec('powershell.exe', '-ExecutionPolicy Bypass -Command "wsl --install --no-distribution"',
           '', SW_SHOW, ewWaitUntilTerminated, ResultCode);
      MsgBox('WSL2 has been enabled. Please restart your computer and run this installer again.',
             mbInformation, MB_OK);
      Result := False;
    end else
    begin
      Result := False;
    end;
  end;
end;
