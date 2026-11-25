# Estándar FinOps y gestión de costos tecnológicos

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica a costos cloud, licencias, infraestructura, proveedores y operación técnica.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.
- Mantener responsabilidades, límites de confianza y propiedad explícitos.
- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.
- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Asignar dueño y etiquetas de costo por producto, ambiente, equipo y unidad de negocio cuando sea posible.
- Definir presupuestos, forecast, alertas, límites y tratamiento de anomalías.
- Medir costo por unidad de valor (usuario, transacción, tenant, job) además del gasto total.
- Evaluar costo total de propiedad: licencias, operación, personal, transferencia, backups, observabilidad y egreso.
- Optimizar con evidencia sin comprometer seguridad, durabilidad, privacidad o SLO.
- Definir políticas de recursos huérfanos, ambientes temporales, retención y apagado programado.
- Revisar descuentos/compromisos, lock-in y riesgo de capacidad mínima.
- Incorporar costos estimados y costos reales en decisiones arquitectónicas y ADR.

## 4. Antipatrones

- Adoptar herramientas sin requisitos ni evaluación de operación.
- Confiar en controles exclusivamente del cliente cuando el servidor debe hacer cumplir la regla.
- Registrar datos sensibles innecesarios o exponerlos en logs/telemetría.
- Ignorar fallos parciales, cambios de versión, límites de capacidad o dependencias externas.
- Considerar la existencia de documentación como prueba de implementación.

## 5. Verificación y evidencia

El proyecto DEBE definir pruebas automatizadas y controles manuales proporcionales al riesgo. Conservar resultados, configuración, responsables, excepciones y evidencias reproducibles. La conformidad se registra requisito por requisito en la matriz del proyecto.

## 6. Decisiones específicas

Las tecnologías, versiones, topologías, proveedores, umbrales y SLO se seleccionan en ADR o especificaciones del proyecto. No se heredan de ejemplos de esta biblioteca.

## 7. Revisión

Revisar ante cambios de alcance, amenazas, plataforma, proveedor, regulación, incidentes o evolución significativa del estándar.
