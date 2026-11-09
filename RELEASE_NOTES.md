# Release Notes - Nubix

Registro de cambios y versiones de Nubix.

## [0.2.1] - 2026-11-09

### Resumen
Versión que introduce el **Panel de Ajustes**, **Bandeja del Sistema (System Tray)** con opción de **minimizar al pulsar ✕**, **Inicio automático con Windows (Autorun)**, **Nubix Ignore** (lista negra de exclusión estilo `.gitignore`), selector desplegable (`<select>`) estilizado en tema oscuro, dimensiones optimizadas de ventana y modal, centrado automático y resolución del entorno de desarrollo.

### Detalles
- **Panel de Ajustes**: Nuevo acceso en la cabecera mediante icono de engranaje (⚙️) junto a la etiqueta del proveedor. Permite configurar el comportamiento de la ventana al cerrar, la activación de inicio automático con Windows y consultar detalles de versión y motor Rclone.
- **Bandeja del Sistema (System Tray)**: Icono residente en el área de notificación de Windows con menú contextual («Abrir Nubix», «Ajustes…», «Salir de Nubix») y restauración rápida con clic izquierdo.
- **Minimizar al pulsar ✕ (Close to Tray)**: Al cerrar la ventana principal mediante el botón ✕, Nubix se mantiene activo en segundo plano en la bandeja del sistema sin interrumpir tareas pendientes ni perder el estado.
- **Inicio automático con Windows (Autorun)**: Configuración opcional mediante el registro del usuario (`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`), iniciando en segundo plano de manera silenciosa en la bandeja.
- **Selector desplegable estilizado en tema oscuro**: Se implementó la API estándar Customizable Select (`appearance: base-select`, `select::picker(select)` y estados de opción), sustituyendo el menú emergente nativo claro por un selector integrado con el fondo `#141c21` y acento `#00c9b9`, con maquetación flexible que asegura la flecha indicadora (`▼`) alineada en el extremo derecho sin saltos de línea.
- **Protección de Instancia Única (Single-Instance Lock)**: Integración de `tauri-plugin-single-instance` para evitar bloqueos del directorio de datos de WebView2 (`0x800700AA`). Al abrir una segunda instancia, la invocación activa y enfoca la ventana existente desde la bandeja y termina limpiamente.
- **Vinculación rápida en configuración de carpetas**: Cuando aún no hay cuentas conectadas en el equipo, el selector ofrece un botón directo («Conectar…») para abrir de inmediato el asistente de conexión sin confusiones.
- **Nubix Ignore (Lista negra estilo .gitignore)**: Cada carpeta puede definir reglas de exclusión personalizadas directamente desde la ventana de configuración (ej. `node_modules/`, `target/`, `*.png`, `*.jpg`). Además, si existe un archivo `.nubixignore` en la raíz de la carpeta local, sus reglas se aplican automáticamente tanto en la fase de comparación (`compare` / `--dry-run`) como en la de subida (`upload`), omitiendo por completo carpetas completas, archivos y formatos no deseados.
- **Ventana centrada y dimensiones ampliadas**: Se estableció el tamaño en 850 × 640 y centrado estricto al arrancar, ampliando también el ancho modal (560px) para evitar desplazamientos forzados.
- **Scrollbar fina y estilizada global**: Se implementó una barra de desplazamiento delgada de 6px con extremos redondeados, pista transparente y acento interactivo sobre el tema oscuro en todo el entorno.
- **Cierre por clic en espacio vacío (Light dismiss)**: La ventana modal se cierra al hacer clic sobre el fondo exterior (backdrop), garantizando la continuidad fluida de trabajo.
- **Corrección del ciclo en `mise dev`**: Se reestructuraron los scripts en `package.json` y `tauri.conf.json` para que el levantador Vite inicie correctamente en `beforeDevCommand` y Tauri dev no se llame a sí mismo recursivamente.

**Artefactos:**
- `Nubix-Setup-0.2.1.exe` (3.988.346 B) — SHA256 `5d0133a63e47c500309e3c67a39220aae99cd35b493395a8ded6879d6d0d60de`

## [0.2.0] - 2026-10-22

### Resumen
Nubix 0.2.0 es la primera versión de la aplicación de escritorio para bibliotecas de archivos: conecta Google Drive con Rclone, permite elegir las carpetas de destino, comparar qué hay en el equipo y en la nube y subir los cambios solo después de revisarlos, sin salir de la interfaz.

### Detalles
- **Nombre de la marca**: la app se llamaba **NubeSync** hasta el 23 de octubre de 2026 y ahora se llama **Nubix**. El cambio alcanza el nombre visible, el identificador de Tauri (`com.biglexj.nubix`), el ejecutable (`nubix.exe`), la carpeta de instalación (`%LOCALAPPDATA%\Programs\Nubix`), el directorio de datos y la carpeta de historial en Drive (`.Nubix-history`). El `AppId` del instalador no cambia, para que la instalación existente se actualice en el sitio.
- **Conexión con Google Drive**: Importación de un JSON OAuth de una aplicación de escritorio o de una conexión ya existente en la configuración predeterminada de Rclone, sin modificar la original.
- **Carpetas de destino**: Varias cuentas y destinos por carpeta, elección de una carpeta real de Drive por ID y escritura de subcarpetas de destino con la ruta final visible antes de guardar.
- **Comparación antes de subir**: `rclone copy --dry-run --checksum --combined` separa los archivos iguales, nuevos, modificados y los que solo están en Drive; los nombres duplicados detienen la operación.
- **Instalador de Windows modernizado (Inno Setup)**: El instalador EXE de Windows se genera ahora con la plantilla propia de Biglex en Inno Setup, con una pantalla única de entrada (presentación, ruta editable y botón principal), progreso y éxito nativos, tema claro/oscuro automático según Windows, esquinas nativas de Windows 11 e ícono centrado. La instalación es por usuario y sin elevación, la actualización se aplica en el mismo directorio (`%LOCALAPPDATA%\Programs\Nubix`) sin instalar en paralelo, y la coexistencia con el instalador anterior (NSIS de Tauri, que debe desinstalarse antes) queda documentada en `packaging\windows\MIGRATION.md`.

**Artefactos:**
- `Nubix-Setup-0.2.0.exe` (3.859.039 B) — SHA256 `9bca8690def255454628c16e84813594c30e3092ddea1ed0f9515eba7ec4047d`
