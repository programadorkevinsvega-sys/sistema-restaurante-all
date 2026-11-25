# ADR-0026: Auditoría de seguridad, detección y respuesta a incidentes

- Estado: **Accepted**
- Fecha: 2026-11-25
- Ámbito: eventos de seguridad, auditoría de acciones sensibles, detección, alertas, investigación, contención y recuperación.
- Complementa: ADR-0003, ADR-0004, ADR-0014, ADR-0015, ADR-0018 y ADR-0020 a ADR-0025.
- Aprobación: aprobada explícitamente por el propietario del producto el 2026-11-25.

## Contexto

Prevenir todos los ataques es imposible. Se necesita detectar actividad sospechosa, conservar evidencia, contener incidentes, recuperar servicios y comunicar lo que corresponda. Logs operativos y trazas no sustituyen auditoría. Tampoco se debe crear una tabla central que rompa ownership por módulo.

## Decisión

### 1. Separar logs, telemetría y auditoría

- Logs operativos describen ejecución y errores.
- Métricas/trazas muestran comportamiento y correlación conforme ADR-0015/0004.
- Auditoría conserva evidencia de quién realizó qué acción, sobre qué ámbito/recurso, cuándo y con qué resultado/contexto mínimo.

Cada tipo tiene propósito, acceso y retención distintos. Logs no sustituyen historial de módulo ni eventos de negocio.

### 2. Ownership

Cada módulo registra acciones de su dominio en su propio mecanismo de auditoría/historial. No se crea schema, tabla ni historial compartido. PLATFORM registra acciones de ciclo SaaS que le pertenecen. BFF registra señales técnicas de borde, no auditoría de negocio. Acceso excepcional de soporte conserva operador, justificación, autorización, alcance, aprobación y resultado. Workers registran identidad de proceso y actor/causa original cuando aplique.

### 3. Eventos detectables

Como mínimo: login exitoso/fallido y anomalías; cambios de MFA/contraseña/recuperación; revocación de sesiones; cambios de roles, permisos y membresías; accesos denegados y BOLA/IDOR; cambios de tenant/sucursal; soporte excepcional; exportaciones/descargas masivas; cambios de secretos/certificados/ACL/red; API keys e integraciones; webhooks inválidos/replay; límites excedidos; cambios de infraestructura/workflows/despliegues; backups/restauraciones/eliminaciones; malware/archivos sospechosos; actividad de IA/herramientas que intente exceder permisos o extraer datos.

No se conserva payload completo si no es necesario.

### 4. Evidencia mínima

Cuando sea seguro: timestamp UTC, tipo de evento/resultado, proceso/servicio/módulo, actor humano o identidad de servicio, tenant/ámbito minimizado, acción/tipo de recurso, correlación, motivo/aprobación para excepciones, origen técnico proporcional y versión de política/configuración relevante.

Nunca registrar contraseñas, tokens, secretos, claves privadas, cookies, datos completos de tarjetas, payloads personales sensibles ni documentos completos como sustituto de referencia controlada.

### 5. Integridad y acceso

Acceso de mínimo privilegio, separado del permiso para ejecutar negocio. Proteger evidencias contra modificación/borrado no autorizado. Exportar auditoría requiere autorización, motivo y trazabilidad. Retención por categoría/finalidad/jurisdicción conforme ADR-0018; no indefinida. Mensajería durable respeta Outbox/Inbox y ownership. No prometer WORM/inmutabilidad criptográfica sin mecanismo seleccionado. La caída de telemetría no elimina historial que el módulo debe conservar.

### 6. Detección y alertas

Detectar ráfagas de autenticación fallida, cambios privilegiados anómalos, accesos entre tenants, exportaciones inusuales, cambios de ACL/secretos/certificados, firmas inválidas/replay, abuso de API/cuotas, workers anómalos, fallos de backup/borrado y señales de compromiso de dependencias/pipelines.

Cada alerta tendrá severidad, propietario, señal, ventana/umbral, pasos de triage y runbook. Los umbrales se dimensionan con pruebas/telemetría, no se fijan universalmente aquí.

### 7. Ciclo de respuesta

1. Preparación: inventario, responsables, contactos, accesos de emergencia, backups y runbooks.
2. Detección/registro: validar señal, abrir incidente, asignar severidad y preservar evidencia.
3. Triage: identificar activos, tenants, procesos, datos, alcance y posible exfiltración.
4. Contención: revocar credenciales/sesiones, bloquear integración, aislar tenant/proceso o restringir tráfico.
5. Erradicación: corregir causa, parchear, reconstruir artefactos y rotar secretos.
6. Recuperación: restaurar, reconciliar operaciones y verificar integridad.
7. Comunicación: informar responsables, tenants, proveedores y autoridades cuando corresponda.
8. Postmortem: causa, impacto, cronología, decisiones y acciones correctivas.

Contener sin destruir evidencia ni eliminar datos bajo legal hold.

### 8. Severidad y escalamiento

Clasificar por confidencialidad, integridad, disponibilidad, tenants/personas afectados, privilegios comprometidos, exposición de datos, impacto financiero y propagación. Definir tiempos objetivo y responsables antes de producción. No se fijan números universales sin conocer equipo, contratos y mercados.

### 9. Datos personales

Evaluar si hay datos personales y roles de cada parte. Coordinar con tenant cuando aplique. Determinar obligaciones y plazos de notificación con revisión jurídica por jurisdicción; no asumir un plazo global. Conservar decisiones y comunicaciones mínimas conforme ADR-0018.

### 10. Ejercicios

Probar revocación de credenciales/sesiones; compromiso de secreto, cuenta privilegiada, dependencia y proveedor; aislamiento de tenant; bloqueo de integración; restauración/reconciliación; tabletop de ransomware, exfiltración y caída regional; calidad de alertas y runbooks.

## Alternativas consideradas

Solo logs técnicos; tabla global de auditoría; payloads completos; respuesta reactiva únicamente; retención indefinida: rechazados por insuficiencia, ruptura de ownership o riesgo de privacidad.

## Consecuencias

Mejora detección, trazabilidad, contención y recuperación. Requiere responsables, almacenamiento, runbooks, ejercicios y revisión legal; alertas mal calibradas causan fatiga.

## Límites

No selecciona SIEM/SOC, proveedor de logs, sistema de tickets, autoridad ni plazos legales. No crea tablas, schemas, dashboards, alertas ni procedimientos desplegados.

## Plan futuro

Definir catálogo de eventos/owners; esquema y redacción; severidades y escalamiento; detección/alertas; runbooks/comunicaciones; ejercicios; revisión de retención por mercado.

## Estado de implementación

Accepted. La decisión está aprobada; no implementa auditoría, SIEM, detección, alertas, runbooks ni equipo de respuesta.
