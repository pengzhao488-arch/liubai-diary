#define AppVersion "0.1.1"
[Setup]
AppId={{A923B30F-6C62-41CC-9964-10AF3B5B78C1}
AppName=Liubai Diary
AppVersion={#AppVersion}
AppPublisher=Liubai Diary
DefaultDirName={localappdata}\Programs\LiubaiDiary
DefaultGroupName=Liubai Diary
PrivilegesRequired=lowest
OutputDir=..\installer
OutputBaseFilename=LiubaiDiary-Windows11-Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\Liubai Diary"; Filename: "{app}\liubai_diary.exe"
Name: "{autodesktop}\Liubai Diary"; Filename: "{app}\liubai_diary.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\liubai_diary.exe"; Description: "Launch Liubai Diary"; Flags: nowait postinstall skipifsilent
