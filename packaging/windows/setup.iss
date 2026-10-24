; ============================================================================
;  setup.iss - Instalador de Windows de Nubix (Inno Setup 6.7+)
; ----------------------------------------------------------------------------
;  Plantilla base: D:\Proyectos\biglexj\Scripts\tools\inno\BiglexModern.iss
;  (copiada y adaptada; este repositorio NO depende de la carpeta compartida:
;   los cuatro archivos .iss viven en packaging\windows).
;
;  Pantalla unica de entrada (logo, nombre, ubicacion de instalacion y un
;  unico boton principal) -> progreso nativo -> pantalla de exito nativa.
;  Sin bienvenida, sin licencia, sin grupo de programa, sin "listo para instalar".
;
;  version.iss lo regenera scripts\packaging\Build-Installer.ps1 con la version
;  real del proyecto (src-tauri\tauri.conf.json -> version):
;      #define MyAppVersion "0.2.0"
;
;  Compilar (lo hace Build-Installer.ps1):
;      & "D:\Proyectos\biglexj\Scripts\tools\InnoSetup\ISCC.exe" setup.iss /O<release>
; ============================================================================

#include "version.iss"
#include "identity.iss"

[Setup]
; --- IDENTIDAD DE ACTUALIZACION: unica y estable por app -------------------
; GUID propio de Nubix. No reutiliza ningun UpgradeCode de MSI: Windows
; Installer no reconoceria la actualizacion. Ver MIGRATION.md.
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=Biglex
AppPublisherURL=https://biglexj.com
AppSupportURL=https://biglexj.com
DefaultDirName={localappdata}\Programs\{#MyAppDirectory}
DefaultGroupName={#MyAppName}
; --- Pantallas: solo la nuestra + progreso + exito --------------------------
DisableWelcomePage=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
OutputDir=Output
OutputBaseFilename={#MyAppDirectory}-Setup-{#MyAppVersion}
SetupIconFile={#MyAppIcon}
UninstallDisplayIcon={app}\{#MyAppExe}
UninstallDisplayName={#MyAppName}
Compression=lzma2/max
SolidCompression=yes
ShowLanguageDialog=no
; --- Identidad visual moderna + tema claro/oscuro automatico (IS 6.6+) ---
WizardStyle=modern {#MyAppTheme}
#if MyAppTheme == "dark"
WizardBackColor=#15191C
WizardImageBackColor=#15191C
#else
WizardBackColor=#F7F9FA
WizardImageBackColor=clWhite
#endif
WizardBackColorDynamicDark=#15191C
WizardImageBackColorDynamicDark=#15191C
; --- Instalacion por usuario (sin privilegios de administrador) -------------
; PrivilegesRequiredOverridesAllowed se deja vacio a proposito: abrir el
; dialogo "Seleccion del Modo de Instalacion" anade una pantalla extra.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; --- Comportamiento --------------------------------------------------------
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
VersionInfoDescription={#MyAppName} instalador
VersionInfoProductName={#MyAppName}
VersionInfoCompany=Biglex

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Messages]
spanish.FinishedHeadingLabel=Instalación completada
spanish.FinishedLabel={#MyAppName} se instaló correctamente.
spanish.FinishedLabelNoIcons={#MyAppName} se instaló correctamente.
spanish.ClickFinish=Pulsa Finalizar para cerrar el instalador.

[CustomMessages]
spanish.RunApp=Ejecutar {#MyAppName}

[Files]
; El ejecutable y sus recursos los deja preparados Build-Installer.ps1 en
; build\inno-staging\app.
Source: "..\..\build\inno-staging\app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Icono extraido explicitamente por la UI; no se instala en la carpeta temporal.
Source: "{#MyAppIcon}"; Flags: dontcopy

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; WorkingDir: "{app}"

[Run]
; Lanza la app via el shell del escritorio: heredar el contexto del instalador
; hace que el proceso falle con 0xc00004bc. explorer.exe vive en {win}, no en {sys}.
Filename: "{win}\explorer.exe"; Parameters: """{app}\{#MyAppExe}"""; Description: "{cm:RunApp}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

; Si ya hay eventos en la app, integrar estas llamadas sin borrar sus hooks.
#include "BiglexModernUI.iss"

[Code]
procedure InitializeWizard();
begin
  ModernInitialize;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  ModernPageChanged(CurPageID);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := ModernNextButtonClick(CurPageID);
  if not Result then Exit;
end;

[Code]
procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  ModernCancelButtonClick(CurPageID, Cancel, Confirm);
end;
