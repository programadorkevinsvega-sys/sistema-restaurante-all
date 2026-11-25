# Estándar de IA generativa y sistemas de agentes

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica a modelos generativos, asistentes, agentes autónomos, RAG y funciones que usan modelos externos o locales.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.

- Mantener responsabilidades, límites de confianza y propiedad explícitos.

- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.

- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Definir propósito permitido, límites de autonomía, impacto, usuarios afectados y responsable humano.

- Clasificar datos de entrada/salida; no enviar secretos o datos personales a proveedores sin base legal, contrato y controles.

- Tratar prompts, documentos recuperados, herramientas y salidas como entradas no confiables; defender contra prompt injection y exfiltración.

- Aplicar autorización en cada herramienta y operación; el modelo nunca es autoridad de permisos.

- Limitar herramientas, scopes, destinos de red, presupuesto, tokens, tiempo, iteraciones y acciones destructivas.

- Exigir confirmación humana para acciones irreversibles, financieras, legales o de alto impacto.

- Evaluar calidad, factualidad, sesgos, seguridad, robustez y regresión con datasets versionados.

- Registrar modelo/proveedor/versión, prompt versionado, herramientas y trazas sin retener datos sensibles innecesarios.

- Definir fallback, degradación, revisión humana, monitoreo de drift y procedimiento de incidente.

- Evaluar licencias, propiedad intelectual, procedencia de datos y términos del proveedor.

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

## 8. Amenazas y escenarios de fallo específicos

Evaluar prompt injection directo/indirecto, recuperación de instrucciones maliciosas, tool abuse, exfiltración, escalada de privilegios, fuga cross-tenant, salida no validada, alucinación, automatización de daño, denegación de servicio por loops/costo y cambio de comportamiento del modelo/proveedor.

## 9. Pruebas de aceptación mínimas

- Ejecutar red team de prompt injection en instrucciones, RAG, archivos, web y salidas de herramientas.

- Verificar autorización independiente del modelo en cada herramienta, recurso, tenant y acción.

- Probar extracción de secretos/datos personales y confirmar que logs/trazas se minimizan y redactan.

- Ensayar límites de tokens, presupuesto, iteraciones, timeout, destinos de red y fallback.

- Evaluar datasets versionados para factualidad, robustez, sesgos, refusals, regresiones y comportamiento fuera de alcance.

- Probar confirmación humana, cancelación, reversión y audit trail en acciones de alto impacto.

- Verificar procedencia, versión, licencia, retención y condiciones de entrenamiento del proveedor/modelo.

## 10. Operación y evidencias

Conservar model/system card, threat model, evaluación de proveedor, versiones de prompts/modelos/herramientas, resultados de red team, trazas saneadas, métricas de calidad/costo y runbook de incidente/rollback.
