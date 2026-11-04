---
trigger: always_on
---

# Instrucciones del proyecto — Nubix

## Documentación Core — entrada compartida

Consultar primero [Documentación Core](../../../Docs/README.md) y seleccionar solo los módulos pertinentes. Los estándares compartidos se mantienen allí; este archivo conserva el alcance y los contratos específicos del proyecto.

- [Calidad y entrega proporcionales](../../../Docs/global/quality/quality-baseline.md): build para ajustes visuales pequeños; pruebas pertinentes para elementos, lógica o páginas nuevos y cambios grandes; revisión acotada para documentación.
- [Procesos según alcance](../../../Docs/global/documentation/process-workflow.md): no añadir fases, archivos ni nuevas aprobaciones por rutina a ajustes pequeños ya autorizados.
- [Diseño común](../../../Docs/global/design/design_system.md) y [textos de interfaz](../../../Docs/global/design/interface-writing.md): contenido preciso, espacio útil, mínimo scroll innecesario, conservando la identidad del producto.
- [Estilo de comunicación](../../../Docs/global/agents/communication-style.md): registro «Scientific Elegant» en resúmenes y cierres; no aplica a los textos de interfaz.
- [Reglas de trabajo del agente](../../../Docs/global/documentation/agent-working-rules.md): entrada única, límite de 12.000 caracteres por archivo de reglas y commits de resguardo.
- [Comandos mediante Mise](../../../Docs/global/architecture/mise-command-standard.md) y [scripts y alias](../../../Docs/global/architecture/command-scripts-standard.md): Mise es la interfaz de comandos; `npm run …` es implementación, no interfaz.
- [Base de lanzamientos](../../../Docs/global/releases/release-baseline.md) y [protocolo de lanzamiento](../../../Docs/global/releases/protocolo_lanzamiento_actualizacion.md): versionado, artefactos e inmutabilidad de lo publicado.
- [Soporte oficial y diálogo «Acerca de»](../../../Docs/features/official-support/official-support-baseline.md): autoría, licencia y enlaces oficiales del ecosistema.
- [Diagnósticos reutilizables](../../../Docs/troubleshooting/README.md) y [promoción a Core](../../../Docs/global/documentation/core-promotion-workflow.md): documentar en Core los fallos confirmados o aprendizajes generalizables y enlazarlos desde el proyecto; mantener locales los detalles exclusivos.

En estos criterios comunes, aplicar las bases vigentes enlazadas en lugar de copias históricas de este archivo. Respetar la dirección actual de Biglex y los contratos específicos del producto; ante una contradicción, comprobar la implementación vigente y resolverla explícitamente. Las skills generales importadas son apoyo técnico, no una autoridad para redefinir estas reglas.

Entrada única de instrucciones: `.agents/rules/base.md`. No se crean `AGENTS.md` ni `agent.md` equivalentes en la raíz.

## Contratos locales de Nubix

- Aplicación de escritorio para bibliotecas de archivos con **Tauri 2 + Rust + TypeScript + Rclone**. Windows primero; arquitectura de escritorio preparada para macOS y Linux.
- Ventana inicial 800 × 600, tema oscuro y acento `#00C9B9`. Google Drive es el primer proveedor.
- **El nombre visible es provisional**: el renombrado de NubeSync a Nubix (2026-10-23) conservó el `AppId` del instalador Inno a propósito, para que las instalaciones existentes se actualicen en el sitio. La historia del renombrado y la migración de `%APPDATA%\com.biglexj.nubesync` a `%APPDATA%\com.biglexj.nubix` están en [README.md](../../README.md).
- No inventar estados de sincronización ni datos de cuenta. Separar la configuración guardada de las operaciones realmente implementadas.
- Preservar archivos locales y remotos: no activar eliminaciones en carpetas reales sin revisión previa de los cambios.
- La espera persistente de eliminaciones, la conservación en nube y el historial recuperable son requisitos del motor futuro, no funciones disponibles.
- Validar disco y origen, identidad del destino y cambio de equipo antes de permitir eliminaciones.

## Comandos

Mise es la interfaz del proyecto: `mise dev`, `mise build`, `mise check`, `mise test`, `mise release` y `mise publish`. `mise release` prepara el instalador Inno Setup en `release/` y no publica; `mise publish` es la única vía de publicación y exige autorización explícita.
