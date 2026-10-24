---
trigger: always_on
---

# Nubix

## Documentación Core — entrada compartida

Consultar primero [Documentación Core](../../../Docs/README.md) y seleccionar solo los módulos pertinentes. Los estándares compartidos se mantienen allí; este archivo conserva el alcance y los contratos específicos del proyecto.

- [Calidad y entrega proporcionales](../../../Docs/global/quality/quality-baseline.md): build para ajustes visuales pequeños; pruebas pertinentes para elementos, lógica o páginas nuevos y cambios grandes; revisión acotada para documentación.
- [Procesos según alcance](../../../Docs/global/documentation/process-workflow.md): no añadir fases, archivos ni nuevas aprobaciones por rutina a ajustes pequeños ya autorizados.
- [Diseño común](../../../Docs/global/design/design_system.md): contenido preciso, espacio útil, mínimo scroll innecesario, fondo global y presets compartidos, conservando la identidad del producto.
- [Diagnósticos reutilizables](../../../Docs/troubleshooting/README.md) y [promoción a Core](../../../Docs/global/documentation/core-promotion-workflow.md): documentar en Core los fallos confirmados o aprendizajes generalizables y enlazarlos desde el proyecto; mantener locales los detalles exclusivos.

En estos criterios comunes, aplicar las bases vigentes enlazadas en lugar de copias históricas de este archivo. Respetar la dirección actual de Biglex y los contratos específicos del producto; ante una contradicción, comprobar la implementación vigente y resolverla explícitamente. Las skills generales importadas son apoyo técnico, no una autoridad para redefinir estas reglas.

- Fuente compartida: D:\Proyectos\biglexj\Docs\README.md.
- Tauri 2 + Rust + TypeScript y CSS. Windows primero; arquitectura de escritorio para macOS/Linux.
- Ventana inicial 800 × 600, oscuro, acento #00C9B9.
- No inventar estados de sincronización ni datos de cuenta. Separar configuración guardada de operaciones implementadas.
- Preservar archivos locales y remotos; no activar eliminaciones en carpetas reales sin revisión previa de cambios.
- Espera persistente de eliminaciones, conservación en nube e historial recuperable son requisitos del motor futuro.
- Validar disco/origen, identidad del destino y cambio de equipo antes de permitir eliminaciones.
