# Migración del instalador de Nubix: de NSIS (Tauri) a EXE (Inno Setup)

> **Nota de renombrado (2026-10-23).** La app se llamaba **NubeSync** hasta el
> 23 de octubre de 2026. Este documento conserva el nombre antiguo **solo** en
> las referencias al instalador NSIS anterior, que existe en disco con ese
> nombre. Todo lo que corresponde a la app actual usa **Nubix**.

## Qué cambia

| | Antes (NSIS de Tauri v2) | Ahora (Inno Setup 6.7) |
| --- | --- | --- |
| Formato | `NubeSync-Setup-0.2.0.exe` generado por Tauri (NSIS) | EXE autónomo de Inno Setup 6.7 (`Nubix-Setup-<versión>.exe`) |
| Motor | NSIS | Inno Setup (no depende de NSIS ni de Windows Installer) |
| Instalación | Por usuario (`currentUser`) | Por usuario (`PrivilegesRequired=lowest`), sin UAC |
| Carpeta | `%LOCALAPPDATA%\NubeSync` | `%LOCALAPPDATA%\Programs\Nubix` |
| Identidad | Clave de desinstalación `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\NubeSync` | `AppId {0DFE6BB9-EC52-4B22-B5CE-9A84117D4EAD}` → clave `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{0DFE6BB9-EC52-4B22-B5CE-9A84117D4EAD}_is1` |
| Desinstalador | `%LOCALAPPDATA%\NubeSync\uninstall.exe` | `unins000.exe` en la carpeta de instalación |
| Pantallas | Asistente NSIS (instalación, componentes, acabado) | Una sola pantalla de entrada, progreso y éxito |

Datos de la tabla verificados en la plantilla NSIS que usa Tauri v2
(`crates/tauri-bundler/.../nsis/installer.nsi`, embebida en el CLI de Tauri):
`UNINSTKEY = Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCTNAME}`,
`INSTALLDIR = $LOCALAPPDATA\${PRODUCTNAME}` en modo `currentUser`, y
`WriteUninstaller "$INSTDIR\uninstall.exe"`.

## Por qué hay que desinstalar el NSIS antes

El NSIS y el EXE de Inno son dos instalaciones **independientes** y, como usan
carpetas distintas, conviven sin avisar:

- el NSIS deja `%LOCALAPPDATA%\NubeSync` y el EXE de Inno deja
  `%LOCALAPPDATA%\Programs\Nubix`;
- quedan **dos copias de la aplicación**, **dos accesos directos** en el menú
  Inicio y **dos entradas** en «Agregar o quitar programas»;
- la copia antigua sigue en el disco y se puede seguir ejecutando, con dos
  procesos distintos usando los mismos datos.

Este instalador **no borra la instalación anterior ni los datos del usuario**:
es una decisión deliberada para no perder configuraciones de Rclone ni tokens.

## Procedimiento

### 1. Comprobar si hay una instalación anterior (NSIS)

```powershell
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' `
  -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -like '*NubeSync*' } |
  Select-Object PSChildName, DisplayName, DisplayVersion, InstallLocation, UninstallString
```

Si no devuelve nada, no hay nada que desinstalar: se puede instalar el EXE
directamente.

### 2. Desinstalar el NSIS **sin borrar los datos del usuario**

**Opción A — desde la interfaz (la más segura):**

1. «Configuración» → «Aplicaciones» → «Aplicaciones instaladas».
2. Buscar **NubeSync** y pulsar «Desinstalar».
3. **No marcar la casilla de borrar los datos de la aplicación** si aparece.

**Opción B — desde la línea de comandos** (la instalación anterior era por
usuario, así que no necesita elevación):

```powershell
& "$env:LOCALAPPDATA\NubeSync\uninstall.exe" /S
```

> El desinstalador de NSIS tiene una opción que borra
> `%APPDATA%\com.biglexj.nubesync` y `%LOCALAPPDATA%\com.biglexj.nubesync`.
> En modo silencioso (`/S`) esa limpieza **sí se ejecuta**. Si se usa esta
> opción hay que respaldar antes los datos de Rclone.

**Opción C — con `winget`**, si se había instalado con él:

```powershell
winget uninstall --name NubeSync
```

### 3. Comprobar que los datos siguen intactos

Los datos de la app (configuración de Rclone, tokens OAuth y preferencias)
vivían en `%APPDATA%\com.biglexj.nubesync`, y la configuración de Rclone en
`%APPDATA%\com.biglexj.nubesync\cloud`. Después de desinstalar el NSIS deben
seguir ahí:

```powershell
Test-Path "$env:APPDATA\com.biglexj.nubesync"      # debe ser True
Test-Path "$env:APPDATA\com.biglexj.nubesync\cloud" # debe ser True
```

Con el renombrado, la app actual usa `%APPDATA%\com.biglexj.nubix` (y
`%APPDATA%\com.biglexj.nubix\cloud`). Para no perder la cuenta conectada hay
que **copiar** los datos al directorio nuevo antes de arrancar Nubix:

```powershell
Copy-Item "$env:APPDATA\com.biglexj.nubesync" "$env:APPDATA\com.biglexj.nubix" -Recurse
```

### 4. Instalar el EXE de Inno Setup

```powershell
.\release\Nubix-Setup-0.2.0.exe
```

Instalación **por usuario**: no pide elevación y deja la aplicación en
`%LOCALAPPDATA%\Programs\Nubix`.

### 5. Comprobar que no quedan dos instalaciones

```powershell
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' `
  -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -like '*Nubix*' -or $_.DisplayName -like '*NubeSync*' } |
  Select-Object PSChildName, DisplayName, DisplayVersion, InstallLocation
```

Debe devolver **una sola** entrada (la de Inno Setup, con el nombre Nubix). La
entrada antigua de NSIS (`...Uninstall\NubeSync`) debe estar eliminada.

## Actualizaciones futuras

A partir de la primera versión instalada con el EXE, las actualizaciones ya no
requieren este procedimiento: basta con ejecutar el EXE nuevo. Inno Setup
detecta la instalación anterior por `AppId`, la actualiza en el mismo sitio y
sustituye los archivos. El `AppId` de `packaging\windows\identity.iss` no se
debe cambiar.

> El `AppId` **no se cambió** con el renombrado a Nubix, precisamente para que
> la instalación existente se actualice en el sitio y no quede una entrada
> antigua de NubeSync junto a la nueva.

## Comportamiento del desinstalador de Inno Setup

- **No borra datos del usuario.** El `setup.iss` no declara ninguna entrada
  `[UninstallDelete]`: al desinstalar se retira la carpeta de la aplicación, el
  acceso directo y la clave de registro, y nada más.
- `%APPDATA%\com.biglexj.nubix` (configuración de Rclone, tokens y
  preferencias) **permanece** tras desinstalar.
- Si en el futuro se quiere añadir una limpieza de datos, debe ser explícita y
  opcional (por ejemplo, una casilla en la pantalla final), nunca implícita.

## Manifiestos de winget

**No existen manifiestos de winget en este repositorio** (no hay carpeta
`manifests/`, ni archivos YAML de paquete). Por tanto **no hay ningún tipo de
paquete (`msi`/`exe`) que actualizar**. Si más adelante se publica un manifiesto
de winget para Nubix, debe declarar el instalador nuevo como tipo **`exe`**
(ya no es un MSI) y apuntar al artefacto `Nubix-Setup-<versión>.exe`.

## Requisitos que no se conservaron del instalador de Tauri (NSIS)

- **Firma digital**: el EXE de Inno Setup no va firmado por sí mismo.
- **Actualización automática en segundo plano**: ninguno de los dos
  instaladores la tiene; hay que ejecutar el instalador nuevo. Inno Setup
  resuelve el cierre de la aplicación abierta con `CloseApplications=yes`.
- **Acceso directo en el escritorio**: el NSIS de Tauri lo creaba; el EXE de
  Inno Setup solo crea el acceso directo del menú Inicio
  (`{autoprograms}\Nubix`). Añadir el de escritorio es una línea en
  `[Icons]`, sin crear páginas extra en el asistente.
