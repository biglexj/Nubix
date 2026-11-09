# ☁️ Nubix 0.2.1

Panel de Ajustes, Bandeja del Sistema, Autorun, Instancia Única, Nubix Ignore y selectores oscuros estilizados.

## 📝 Resumen

Nubix 0.2.1 amplía la experiencia de escritorio incorporando un **Panel de Ajustes** con icono en cabecera (⚙️), soporte de **Bandeja del Sistema (System Tray)** con opción de **minimizar al pulsar ✕**, **Inicio automático con Windows (Autorun)** nativo, **Protección de Instancia Única** (`tauri-plugin-single-instance`), **Nubix Ignore** (lista negra estilo `.gitignore`), selector desplegable (`<select>`) con flecha derecha alineada en tema oscuro, dimensiones y centrado de ventana optimizados, y enlace directo de conexión rápida en la configuración de carpetas.

## 🔔 Novedades destacadas

- ⚙️ **Panel de Ajustes**: Configura de forma centralizada el arranque del sistema y el comportamiento de la ventana al cerrar.
- 🗔 **Bandeja del Sistema (System Tray) y Minimizar en ✕**: Cierra la ventana sin terminar Nubix; la app permanece activa en el área de notificación de Windows con menú contextual y reactivación instantánea.
- 🔒 **Protección de Instancia Única (Single-Instance)**: Previene errores de colisión en WebView2 (`0x800700AA`); cualquier nuevo lanzamiento restaura y enfoca la ventana existente.
- 🚀 **Inicio con Windows (Autorun)**: Nubix se inicia opcionalmente con el encendido del equipo de forma silenciosa en segundo plano.
- 🎨 **Selectores desplegables oscuros integrados**: Implementación de Customizable Select (`appearance: base-select`, `select::picker(select)`) con maquetación flexible que asegura la flecha indicadora (`▼`) alineada a la derecha sin saltos de línea.
- 🔗 **Conexión rápida de cuentas**: Si no hay cuentas vinculadas, el configurador de carpetas ofrece acceso inmediato al asistente de conexión sin bloqueos ambiguos.
- 🚫 **Nubix Ignore (.gitignore style)**: Define reglas de exclusión por carpeta o formato (`node_modules/`, `target/`, `*.png`, `*.jpg`) tanto en interfaz como vía `.nubixignore`.
- 📐 **Ventana centrada y dimensiones ampliadas**: Tamaño a 850 × 640 centrado en pantalla y modal a 560px para mayor legibilidad.
- 🖱️ **Scroll fino y cierre modal por clic exterior**: Desplazamiento sutil de 6px y cierre modal por clic en espacio vacío (light dismiss).

## 📦 Windows x64

`release\Nubix-Setup-0.2.1.exe` (3.988.346 B) — SHA256 `5d0133a63e47c500309e3c67a39220aae99cd35b493395a8ded6879d6d0d60de`

La instalación es por usuario y sin elevación, en `%LOCALAPPDATA%\Programs\Nubix`.
