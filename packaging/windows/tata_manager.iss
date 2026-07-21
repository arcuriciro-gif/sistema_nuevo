; Inno Setup — Tata.Manager (Capacidad 5, sin Authenticode).
; Compilar en Windows con Inno Setup 6:
;   iscc packaging\windows\tata_manager.iss
; Requiere haber corrido: flutter build windows --release

#define MyAppName "Tata.Manager"
#define MyAppVersion "1.1.0"
#define MyAppPublisher "El Tata Manager"
#define MyAppExeName "Tata.Manager.exe"
#define MyBuildDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{A7E4C2B1-9F3D-4E8A-B6C5-1D2E3F4A5B6C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\Instalador_Windows_Setup
OutputBaseFilename=TataManager_Setup_{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
; Firma Authenticode: diferida (ops / certificado comercial)

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear icono en el escritorio"; GroupDescription: "Accesos directos:"

[Files]
Source: "{#MyBuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Nota: no incluir secretos ni keystores

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall skipifsilent
