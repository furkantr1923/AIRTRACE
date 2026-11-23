; AIRTRACE Windows kurulum betiği (Inno Setup 6)
; CI tarafından derlenir: ISCC /DAppVersion=1.0.0 /DSourceDir=<release klasörü> installer\airtrace.iss

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{6E1C9B54-3A7D-4F2B-9C0E-5A1B7C3D9E21}
AppName=AIRTRACE
AppVersion={#AppVersion}
AppVerName=AIRTRACE {#AppVersion}
AppPublisher=Furkan Baykal
AppPublisherURL=https://github.com/furkantr1923/airtrace
AppSupportURL=https://github.com/furkantr1923/airtrace
DefaultDirName={autopf}\AIRTRACE
DefaultGroupName=AIRTRACE
DisableProgramGroupPage=yes
; Yönetici izni gerekmez; kullanıcı isterse tüm kullanıcılar için kurabilir.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputBaseFilename=AIRTRACE_Setup
OutputDir=..\dist
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\AIRTRACE.exe
UninstallDisplayName=AIRTRACE
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\AIRTRACE"; Filename: "{app}\AIRTRACE.exe"
Name: "{group}\AIRTRACE'yı Kaldır"; Filename: "{uninstallexe}"
Name: "{autodesktop}\AIRTRACE"; Filename: "{app}\AIRTRACE.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\AIRTRACE.exe"; Description: "{cm:LaunchProgram,AIRTRACE}"; Flags: nowait postinstall skipifsilent
