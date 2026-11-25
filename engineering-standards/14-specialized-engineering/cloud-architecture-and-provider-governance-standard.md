# Estándar de arquitectura cloud y gobierno de proveedores

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica a nube pública, privada, híbrida y servicios gestionados.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.

- Mantener responsabilidades, límites de confianza y propiedad explícitos.

- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.

- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Evaluar requisitos de residencia, soberanía, cumplimiento, latencia, disponibilidad y salida antes de elegir región/proveedor.

- Definir estructura de cuentas/proyectos, entornos, redes, límites administrativos y separación de producción.

- Aplicar identidad federada, MFA, roles temporales, mínimo privilegio y prohibición de credenciales raíz de uso cotidiano.

- Seleccionar servicios gestionados según responsabilidad compartida, soporte, SLA, límites y lock-in.

- Diseñar backup/exportación, portabilidad de datos, recuperación y estrategia de salida probada.

- Controlar regiones, egress, endpoints públicos, DNS, cifrado y exposición accidental.

- Definir cuotas, presupuestos, etiquetas, alertas y ownership de costos.

- Revisar contratos, subprocesadores, incidentes, cambios de servicio, fin de vida y dependencia de proveedor.

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

## Amenazas y escenarios de fallo específicos

Evaluar compromiso de cuenta raíz/administrativa, exposición pública por configuración, región equivocada, dependencia de servicio gestionado, suspensión de cuenta, outage regional, cambios unilaterales de proveedor, egress costoso y pérdida de portabilidad.

## Pruebas de aceptación mínimas

- Revisar IAM federado/MFA, cuentas de emergencia, límites administrativos y separación de entornos.

- Escanear exposición pública, egress, cifrado, logging, regiones y políticas de red.

- Ejecutar restauración/exportación independiente y simulacro de salida del proveedor.

- Probar caída regional/servicio gestionado y validar RTO/RPO, límites y procedimiento alternativo.

- Revisar contrato, subprocesadores, ubicación, SLA, notificación de incidentes y fin de vida.

## Operación y evidencias

Conservar mapa de responsabilidad compartida, inventario de cuentas/servicios/regiones, matriz de proveedores, auditorías IAM, costos, pruebas de salida/recuperación y runbooks.
