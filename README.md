# Nubix

Aplicación de escritorio para bibliotecas de archivos con Tauri 2, Rust, TypeScript y Rclone. Ventana inicial 800 × 600, tema oscuro y acento #00C9B9. Google Drive es el primer proveedor. El nombre es provisional.

## Renombrado (2026-10-23)

La app se llamaba **NubeSync** hasta el 23 de octubre de 2026 y ahora se llama
**Nubix**. El cambio afecta al nombre visible, al identificador de Tauri
(`com.biglexj.nubix`), al ejecutable (`nubix.exe`), a la carpeta de instalación
(`%LOCALAPPDATA%\Programs\Nubix`), al directorio de datos de la app y a la
carpeta de historial en Drive (`.Nubix-history`). La pieza de marca no cambia:
el glifo del icono es un sobre, no una letra.

El `AppId` del instalador Inno **se mantiene** (`{0DFE6BB9-EC52-4B22-B5CE-9A84117D4EAD}`),
a propósito: al no cambiar, la instalación existente se actualiza en el sitio
en lugar de dejar dos entradas en «Agregar o quitar programas».

Para una instalación previa al renombrado:

- la configuración de Rclone y los tokens OAuth siguen en
  `%APPDATA%\com.biglexj.nubesync`; hay que copiarlos a
  `%APPDATA%\com.biglexj.nubix` o volver a importar el JSON OAuth;
- el historial de versiones en Drive queda bajo `.NubeSync-history`: no se
  borra ni se migra, y las versiones nuevas se escriben en `.Nubix-history`;
- el nombre antiguo sigue bloqueado como destino, para que nadie apunte una
  carpeta dentro del historial.

## Funciones de la versión 0.2

- Conectar Google Drive importando un JSON OAuth de una aplicación de escritorio; autorización en el navegador mediante Rclone.
- Importar una conexión de Google Drive ya existente en la configuración predeterminada de Rclone. La original permanece intacta.
- Varias cuentas y destinos por carpeta. Desconexión de las credenciales locales; revocación en Google separada y explicada en la interfaz.
- Elegir una carpeta real de Drive por ID, navegar por niveles y escribir una subcarpeta de destino. La ruta final se muestra antes de guardar.
- Comparar con `rclone copy --dry-run --checksum --combined`: iguales, nuevos, modificados y solo en Drive. Los nombres duplicados detectados por Rclone detienen la operación.
- Subir los cambios después de revisar. `copy` conserva lo que exista solo en Drive; `--backup-dir` mueve las versiones reemplazadas al historial fuera del destino, bajo `.Nubix-history/<id de carpeta>/<id de ejecución>`.
- Comprobar de nuevo después de subir. Estado con fecha de comprobación, no porcentaje ficticio.
- Cancelación del proceso de Rclone, tiempos de espera y errores sin tokens ni respuestas OAuth en la interfaz. Durante una operación debe cancelarse antes de cerrar.
- Configuración de carpetas guardada también en los datos de la aplicación; se recupera al reabrir o cambiar de la vista de desarrollo al ejecutable autónomo.
- La subida inicial de las tres carpetas usa `work/upload-library.ps1` en un proceso oculto independiente. La interfaz consulta su avance y permite cancelarlo; esta subida continúa si se cierra la ventana, mientras el equipo siga encendido. Cada carpeta se verifica con `rclone check --one-way` al terminar. No es una programación recurrente.

## Primera conexión

En la **ventana de escritorio** de Nubix, pulsa **Conectar cuenta**. La pestaña del navegador es una vista de la interfaz; no dispone de los comandos nativos de Tauri.

1. Crea o selecciona un proyecto en [Google Cloud](https://console.cloud.google.com/).
2. Activa Google Drive API.
3. Configura Google Auth Platform: marca, correo de soporte, audiencia externa y tu correo como usuario de prueba.
4. En Acceso a los datos, añade `https://www.googleapis.com/auth/drive`.
5. En Clientes, crea un cliente OAuth de tipo **Aplicación de escritorio** y descarga su JSON.
6. En Nubix, **Importar JSON OAuth y conectar**. Completa el inicio de sesión y el consentimiento en tu navegador.

Consulta la [guía oficial de Rclone](https://rclone.org/drive/#making-your-own-client-id). El cliente compartido de Rclone está siendo retirado durante 2026; por eso esta aplicación usa un cliente propio. El permiso `drive` permite acceder al contenido de Drive; el destino seleccionado limita las operaciones de la aplicación, no el alcance concedido por Google.

Las configuraciones de Rclone y sus tokens se guardan en `app_data_dir/cloud`, fuera del código fuente. Los tokens no llegan al frontend ni se imprimen. Los archivos se guardan con permisos 0600 en Unix; en Windows heredan los permisos del directorio de datos del usuario. Son configuraciones locales de Rclone, no un almacén cifrado. No compartir ese directorio ni el JSON OAuth.

## Destinos

Sin elegir otra carpeta raíz, `Imágenes/01_Branding` significa **Mi unidad / Imágenes / 01_Branding**. Si seleccionas una raíz existente, la subcarpeta se interpreta dentro de ella. Las nuevas rutas se crean al subir; la navegación y la simulación no crean carpetas en Drive. Si una conexión importada tiene raíz restringida o unidad compartida, la interfaz lo indica.

## Pendiente

Espejo con eliminaciones diferidas, conservación selectiva, restauración desde la interfaz, preparación y descarga en otro equipo, sincronización bidireccional y otros proveedores. Los ajustes de espera se conservan, pero aún no se aplican: todas las subidas actuales usan copia y no eliminan archivos exclusivos de Drive. La subida inicial muestra el progreso real de Rclone; la programación recurrente sigue pendiente.

La espera debe contar desde la primera detección válida y guardar un registro persistente. No se implementa con `--delete-after`. Antes de permitir eliminaciones deben comprobarse disco/origen, identidad del destino, cambios masivos y preparación del equipo. No ejecutar espejos simultáneos desde dos equipos contra el mismo destino.

## Desarrollo y validación

Para abrir la aplicación ya compilada en Windows, usa `Nubix.lnk` en la carpeta del proyecto. El ejecutable autónomo incluye la interfaz y no necesita Vite ni una terminal abierta; requiere Rclone instalado en PATH. La configuración y el avance se guardan fuera del proyecto.

```powershell
npm install
npm run tauri dev
```

- `npm run build`: TypeScript y Vite.
- `npm run icons:generate`: regenera `src-tauri\icons` y `packaging\windows\Nubix.ico` desde la fuente canónica del repositorio. Solo actúa si la fuente cambió o falta algún derivado.
- `cargo test --manifest-path src-tauri/Cargo.toml --lib`: validación de rutas/ID, redacción de errores, deserialización de ID de Drive y prueba con Rclone real en carpetas temporales. Comprueba dry-run, diferencias de contenido de igual tamaño y conservación de versiones/archivos exclusivos del destino.
- `cargo build --manifest-path src-tauri/Cargo.toml`: ejecutable de desarrollo.
- `npm run tauri build -- --no-bundle`: ejecutable autónomo del sistema actual.

## Identidad visual

- **Icono canónico del repositorio**: `assets\branding\icons\icon-transparent.png`. Es la exportación versionada de la pieza de marca y la única fuente desde la que se generan los derivados; el build nunca depende de la unidad `D:`.
- **Original creativo externo**: `D:\Imágenes\03_Proyectos\02_Development\Icons\Applications\Nubix\` (`Nubix.af` editable, `Nubix.webp` con fondo y `Nubix-transparent.webp` sin fondo).
- **Variante con fondo**: `assets\branding\icons\icon-brand.png`. Se reserva para marketing, tiendas o lienzos que exijan fondo; no sustituye a la transparente en superficies del sistema.
- **Derivados**: `src-tauri\icons\*` (ventana, ejecutable y recursos de Tauri) y `packaging\windows\Nubix.ico` (instalador). Se regeneran con `npm run icons:generate`.
- La variante transparente es la que se usa en superficies compactas: barra de tareas, bandeja, título de ventana, ejecutable y accesos directos.

Referencia: [Asset Organization Standard](../Docs/global/architecture/asset-organization-standard.md).

## Instalador de Windows

El instalador es un EXE autónomo de Inno Setup 6.7 con la plantilla compartida **Biglex Modern 2.0**: una sola pantalla de entrada (ruta de instalación editable y un botón «Instalar Nubix»), progreso y éxito nativos. Se instala por usuario, sin elevación, en `%LOCALAPPDATA%\Programs\Nubix`.

- `packaging\windows\`: copia local de la plantilla (`setup.iss`, `BiglexModernUI.iss`, `identity.iss`, `version.iss`) e icono. El repositorio es autocontenido: no incluye `Scripts\tools\inno`.
- `packaging\windows\MIGRATION.md`: convivencia con el instalador NSIS de Tauri, desinstalación del anterior sin borrar datos del usuario.
- `scripts\packaging\Build-Installer.ps1`: regenera `version.iss` con la versión real, compila la app con Tauri (`--no-bundle`, solo en Windows), prepara el staging y compila el instalador con ISCC.

```powershell
.\scripts\packaging\Build-Installer.ps1
```

El instalador queda en `release\Nubix-Setup-<versión>.exe`.

### Validación del instalador

- `scripts\packaging\Test-Installer.ps1`: pruebas funcionales con la interfaz real (teclado, ruta editable, selector de carpeta, instalación, desinstalación, actualización con el mismo `AppId` y capturas en tema oscuro y claro). Fases: `entry`, `install`, `silent`, `upgrade`, `uninstall`, `themes`, `longpath`.
- `scripts\packaging\Test-DpiScaling.ps1`: comprueba el área cliente y la posición de los controles a distintas escalas de DPI. Cambia la escala del monitor mientras dura la prueba y la restaura al terminar.
- `scripts\packaging\Measure-Icon.ps1`: mide por píxeles el centrado del ícono (glifo dentro de la caja) a partir de una captura.

Estado verificado en esta máquina (2026-10-22, instalador 0.2.0). **Con el
renombrado a Nubix (2026-10-23) el instalador se reconstruyó** como
`release\Nubix-Setup-0.2.0.exe` (3.859.039 B, SHA256
`9bca8690def255454628c16e84813594c30e3092ddea1ed0f9515eba7ec4047d`); el
`AppId` es el mismo, así que la instalación existente se actualiza en el sitio.
Los resultados siguientes son de la validación del 22 de octubre, con el
nombre anterior: el texto de la interfaz cambió («Instalar Nubix»), de modo
que las fases `entry` e `install` conviene repetirlas para dejar evidencia del
nombre vigente.

- `entry` 13/13: área cliente 560 × 444 a 96 DPI, foco inicial en el campo de ruta, ciclo Tab ruta → carpeta → instalar, botones nativos fuera del recorrido, Shift+Tab inverso, Enter y Espacio abren el selector de carpeta, Escape lo cierra, la X cancela.
- `longpath` 4/4: ruta de 79 a 122 caracteres admitida; ruta relativa rechazada con aviso y sin instalar nada.
- `silent` 3/3 y `upgrade` 3/3: una sola entrada en «Agregar o quitar programas», sin instalación paralela (mismo `AppId`).
- `uninstall` 5/5: retira carpeta, entrada y acceso directo, y **conserva** `%APPDATA%\com.biglexj.nubix`.
- Ícono: el `.ico` regenerado el 2026-10-23 con la pieza de marca deja el glifo en 30 × 34 en (5,3) dentro de la caja de 40 × 40 del logo, desvío 0/0, y en 16 × 18 en (2,1) dentro de la caja de 20 × 20 de la cabecera, desvío 0/0 (antes 24 × 28 en (4,2), desvío −4/−4). La captura `01-entrada.png` es del 2026-10-22 y muestra el icono anterior: la fase `entry` debe repetirse para dejar evidencia del icono vigente.
- `install` 9/10: la ruta editada a mano se respeta, Enter instala y Enter en «Finalizar» cierra la pantalla de éxito y lanza la app. Falla la comprobación de la ventana de la app: el proceso arranca, pero se bloquea antes de crearla cuando lo lanza el propio instalador (hilo principal en espera ALPC, sin proceso de WebView2); el mismo ejecutable lanzado directamente muestra la ventana en unos 2 s.

Pendiente: escalado 125/150/200 % sin verificar físicamente (cambiar la escala del monitor alteraría el escritorio compartido) y aceptación visual humana no verificada.

Validación en Windows y navegador a 800 × 600. Sin validación con una cuenta real de Google todavía: requiere aportar el cliente OAuth y completar el consentimiento. macOS y Linux requieren su propia compilación y prueba. La persistencia de tamaño/posición e instancia única están pendientes.

## Licencia

Distribuido bajo la Licencia MIT. Consulta el archivo [LICENSE](LICENSE) para más detalles.

