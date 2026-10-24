# ☁️ Nubix 0.2.0

Conexión con Google Drive, comparación de archivos antes de subir y un instalador de Windows modernizado.

## 📝 Resumen

Nubix 0.2.0 conecta Google Drive con Rclone desde una ventana de escritorio: importa o crea la autorización de la cuenta, elige las carpetas de destino, compara qué archivos cambiaron y sube los cambios después de revisar, conservando un historial de las versiones reemplazadas.

## 🔔 Novedades destacadas

- ☁️ **Conexión con Google Drive**: Importa un JSON OAuth de una aplicación de escritorio o una conexión ya existente en la configuración predeterminada de Rclone.
- 📁 **Carpetas de destino**: Varias cuentas y destinos por carpeta, con navegación por niveles y la ruta final visible antes de guardar.
- 🔍 **Comparación antes de subir**: Distingue los archivos iguales, nuevos, modificados y los que solo están en Drive antes de mover nada.
- 🛠️ **Instalador de Windows modernizado (Inno Setup)**: Pantalla única de entrada, progreso y éxito nativos, tema claro/oscuro automático, instalación por usuario sin elevación y actualización sin instalación paralela.

## 📦 Windows x64

`release\Nubix-Setup-0.2.0.exe` (3.859.039 B) — SHA256 `9bca8690def255454628c16e84813594c30e3092ddea1ed0f9515eba7ec4047d`

La instalación es por usuario y sin elevación, en `%LOCALAPPDATA%\Programs\Nubix`. Si venías del instalador anterior (NSIS), desinstálalo antes: el procedimiento está en `packaging\windows\MIGRATION.md`.
