# Estándar de auditoría de seguridad y respuesta a incidentes

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Proporcionar trazabilidad confiable de acciones relevantes y capacidad organizada para detectar, contener, investigar y recuperar incidentes de seguridad.

## Auditoría

- Definir eventos auditables según riesgo: autenticación, cambios de permisos, acceso administrativo, cambios de configuración, operaciones financieras críticas, exportaciones, eliminación y acciones sensibles.
- Registrar actor o identidad de servicio, acción, recurso, resultado, timestamp confiable, contexto mínimo y correlación.
- Distinguir auditoría de negocio, logs operativos y eventos de seguridad; pueden compartir infraestructura, pero conservan finalidades y controles distintos.
- Proteger integridad, acceso, retención y consulta de registros; impedir que una identidad auditada pueda alterar o borrar unilateralmente su evidencia.
- Evitar registrar contraseñas, tokens, secretos, datos de pago o payloads sensibles completos.
- Definir sincronización horaria, zona UTC, precisión y tratamiento de eventos tardíos.
- Registrar acceso y exportación de la propia auditoría.
- Definir retención por finalidad, obligación y jurisdicción; no asumir conservación ilimitada.
- Asegurar que los eventos permitan reconstruir secuencias sin convertir identificadores de alta cardinalidad en etiquetas de métricas.

## Respuesta a incidentes

- Mantener un plan con severidades, roles, autoridad de decisión, contactos, escalamiento y canales fuera de banda.
- Definir detección, triage, contención, erradicación, recuperación, comunicación y revisión posterior.
- Preservar evidencia y cadena de custodia cuando sea necesario.
- Disponer de procedimientos para revocar credenciales, bloquear sesiones, aislar workloads, suspender integraciones y rotar claves.
- Coordinar respuesta técnica, legal, privacidad, proveedores y negocio según el incidente.
- Evaluar obligaciones de notificación y plazos por jurisdicción y contrato.
- Mantener runbooks para escenarios relevantes: exposición de secretos, ransomware, acceso indebido, exfiltración, vulnerabilidad explotada, pérdida de datos y compromiso de proveedor.
- Ejecutar ejercicios tabletop y simulaciones técnicas; registrar acciones correctivas y responsables.
- La recuperación debe validar integridad y eliminar persistencia del atacante antes de reabrir servicios.

## Verificación

Pruebas de integridad de auditoría, permisos de consulta, detección y alertas, simulacros de incidentes, revocación de credenciales y revisión de lecciones aprendidas.
