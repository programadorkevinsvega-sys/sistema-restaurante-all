# Estándar de SRE, SLI, SLO y confiabilidad del servicio

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica a servicios operados de forma continua y con objetivos medibles de confiabilidad.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.

- Mantener responsabilidades, límites de confianza y propiedad explícitos.

- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.

- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Definir SLIs centrados en experiencia/resultado: disponibilidad, latencia, corrección, frescura y durabilidad según servicio.

- Establecer SLO con ventana, población, exclusiones justificadas y dueño; distinguir SLO interno de SLA contractual.

- Usar error budget para equilibrar cambios y confiabilidad; definir políticas ante agotamiento.

- Diseñar guardias, escalamiento, severidades, comunicación, runbooks y postmortems sin culpa.

- Priorizar alertas accionables basadas en síntomas y burn rate; evitar alert fatigue.

- Medir dependencias y objetivos end-to-end; no sumar disponibilidad nominal de componentes sin análisis.

- Realizar pruebas de carga, failover, restauración y ejercicios operativos.

- Mantener capacidad, límites, degradación controlada y eliminación de toil.

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

Evaluar alertas sin acción, saturación de guardias, error budgets mal definidos, dependencia común, cascadas, degradación silenciosa, métricas sesgadas, falta de capacidad, runbooks obsoletos y objetivos imposibles de cumplir.

## 9. Pruebas de aceptación mínimas

- Validar que cada SLI tenga consulta reproducible, fuente, población y exclusiones explícitas.

- Simular burn rate y verificar alertas/escalamiento en ventanas acordadas.

- Ejecutar ejercicios de failover, restauración y respuesta a incidentes con medición de RTO/RPO.

- Comprobar que el error budget desencadena la política documentada y que excepciones quedan auditadas.

- Revisar alertas con on-call para comprobar accionabilidad, severidad y runbook.

- Comparar SLO end-to-end con dependencias y medir impacto de degradación parcial.

## 10. Operación y evidencias

Conservar catálogo de servicios/owners, SLI/SLO versionados, error budget, resultados de ejercicios, postmortems, calendario de guardias, runbooks probados y acciones de reducción de toil.
