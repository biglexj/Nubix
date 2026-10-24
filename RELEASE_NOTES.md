# Release Notes - Nubix

Registro de cambios y versiones de Nubix.

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
