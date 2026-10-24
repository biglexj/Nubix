; ============================================================================
;  identity.iss - Identidad de Nubix para el instalador Inno Setup.
;  Copia local de la plantilla compartida (D:\Proyectos\biglexj\Scripts\tools\inno\
;  identity.iss). Este repositorio es autocontenido: no incluye esa carpeta.
;
;  MyAppId: GUID propio y estable. No es ningun UpgradeCode de MSI (Windows
;  Installer no lo reconoceria como actualizacion) y no es el identificador del
;  instalador NSIS de Tauri ("com.biglexj.nubesync", nombre anterior a la marca
;  Nubix), con el que coexistio. Se conserva el GUID de la epoca NubeSync a
;  proposito: al no cambiar, la instalacion existente se actualiza en el sitio
;  en lugar de dejar dos entradas en «Agregar o quitar programas».
;  Ver MIGRATION.md.
; ============================================================================
#ifndef MyAppName
  #define MyAppName "Nubix"
#endif
#ifndef MyAppId
  ; Llaves dobles: Inno Setup las lee como un literal (no como una constante).
  ; La clave de desinstalacion sera {0DFE6BB9-EC52-4B22-B5CE-9A84117D4EAD}_is1.
  #define MyAppId "{{0DFE6BB9-EC52-4B22-B5CE-9A84117D4EAD}"
#endif
#ifndef MyAppDirectory
  #define MyAppDirectory "Nubix"
#endif
#ifndef MyAppExe
  ; El binario lo produce Cargo con el nombre del paquete (nubix).
  #define MyAppExe "nubix.exe"
#endif
#ifndef MyAppIcon
  ; Copia local de src-tauri\icons\icon.ico (PNG transparente de la app).
  #define MyAppIcon "Nubix.ico"
#endif
#ifndef MyAppTheme
  #define MyAppTheme "dynamic"
#endif

#ifndef MyAppSubtitle
  #define MyAppSubtitle "Tus carpetas y tu nube, conectadas."
#endif
