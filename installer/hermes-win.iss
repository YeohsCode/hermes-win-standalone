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
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Hermes"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\scripts\uninstall.ps1"""; Flags: runhidden

[Code]
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
  WslReady: Boolean;
begin
  Result := True;
  WslReady := False;

  // wsl --status works on both inbox WSL (Win10) and Store WSL (Win11).
  if Exec('wsl', '--status', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    if ResultCode = 0 then
      WslReady := True;
  end;

  // Fallback: wsl --list succeeds if WSL is functional at all
  if not WslReady then
  begin
    if Exec('wsl', '--list --quiet', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    begin
      if ResultCode = 0 then
        WslReady := True;
    end;
  end;

  if not WslReady then
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

// Post-install: run WSL2 check and distro import with proper error handling.
// Using CurStepChanged instead of [Run] so we can abort import if check fails.
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    // Step 1: Ensure WSL2 features are enabled and configured
    WizardForm.StatusLabel.Caption := 'Checking WSL2 status...';
    if not Exec('powershell.exe',
                '-ExecutionPolicy Bypass -File "' + ExpandConstant('{app}') + '\scripts\check-wsl2.ps1"',
                '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    begin
      MsgBox('Failed to execute WSL2 check script.', mbError, MB_OK);
      Exit;
    end;

    if ResultCode = 3010 then
    begin
      MsgBox('Windows features were enabled for WSL2. Please restart your computer and run the installer again to complete setup.',
             mbInformation, MB_OK);
      Exit;
    end;

    if ResultCode <> 0 then
    begin
      MsgBox('WSL2 check failed (error ' + IntToStr(ResultCode) + ').' + #13#10 +
             'Please ensure WSL2 and VirtualMachinePlatform are enabled, then run the installer again.',
             mbError, MB_OK);
      Exit;
    end;

    // Step 2: Import HermesLinux distro (only if WSL2 check passed)
    WizardForm.StatusLabel.Caption := 'Setting up HermesLinux environment (may take a few minutes)...';
    if not Exec('powershell.exe',
                '-ExecutionPolicy Bypass -File "' + ExpandConstant('{app}') + '\scripts\import-distro.ps1" -InstallDir "' + ExpandConstant('{app}') + '"',
                '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    begin
      MsgBox('Failed to execute distro import script.', mbError, MB_OK);
      Exit;
    end;

    if ResultCode <> 0 then
    begin
      MsgBox('HermesLinux setup failed (error ' + IntToStr(ResultCode) + ').' + #13#10 +
             'The application files have been installed. You can try running the import manually or re-install.',
             mbError, MB_OK);
    end;
  end;
end;
