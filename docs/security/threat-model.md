# Modelo de amenazas — Restaurant OS

**Estado:** vigente
**Versión:** 1.1
**Fecha:** 2026-11-25
**Fase:** 0.3
**Ámbito:** cuatro procesos, módulos, navegador, APIs, workers, mensajería, almacenamiento, proveedores y operación.
**Autoridad:** ADR-0020 a ADR-0027; ADR-0011, ADR-0015, ADR-0018 y ADR-0019.
**Documentos relacionados:**

- [Matriz amenaza/control/fase](./threat-control-matrix.md)
- [Registro de riesgos residuales](./residual-risk-register.md)
- [Baseline de seguridad por proceso](./security-baseline-per-process.md)

---

## 1. Propósito y alcance

Este documento identifica activos, actores, fronteras de confianza y amenazas del sistema Restaurant OS.
No reemplaza las pruebas técnicas de seguridad de cada subfase. Cada amenaza aquí registrada
debe tener controles asignados en la [matriz de control](./threat-control-matrix.md) y evidencia
de implementación cuando la subfase correspondiente esté completada.

La aceptación de riesgo corresponde al propietario del producto. No se delega a un agente ni a
un escáner automático.

---

## 2. Activos

### 2.1 Datos

| Activo | Clasificación | Propietario |
|---|---|---|
| Credenciales de usuarios (contraseñas, tokens) | Crítico | IDENTITY |
| Datos de pago (números de tarjeta, tokens PSP) | Crítico | PAYMENTS |
| Datos personales de clientes y empleados | Alto | CUSTOMERS / WORKFORCE |
| Configuración multi-tenant (planes, límites, suscripciones) | Alto | PLATFORM |
| Inventario, recetas y costos | Alto | INVENTORY / PRODUCTION |
| Datos financieros y contables | Alto | FINANCE / BILLING |
| Registros de auditoría | Alto | AUDIT |
| Configuración de sucursales y operación | Medio | ORGANIZATION |
| Catálogo de productos y precios | Medio | CATALOG |
| Secretos de infraestructura (DSN, claves API, certificados) | Crítico | Infraestructura |
| Datos locales de POS: ventas pendientes, catálogos, configuración y colas offline | Alto/Crítico según dato | Módulo propietario / dispositivo |
| Identidades, certificados y claves por dispositivo POS | Crítico | IDENTITY / Infraestructura |
| Backups, WAL, snapshots y claves de recuperación | Crítico | Infraestructura / módulo propietario |
| Objetos, documentos, exportaciones y URLs temporales | Alto/Crítico según contenido | Módulo propietario |
| Entradas, salidas, contexto y credenciales de herramientas de IA | Alto/Crítico según dato | Módulo propietario / proveedor |

### 2.2 Procesos

- Admin Platform Backend: ciclo de vida SaaS, tenants, planes y suscripciones.
- Admin BFF: composición y exposición HTTP/OpenAPI administrativa.
- Public BFF: composición y exposición HTTP/OpenAPI pública y operativa.
- Public Backend: todos los módulos de negocio canónicos.
- Workers y consumidores de mensajería: Outbox, Inbox, Sagas y jobs.

### 2.3 Infraestructura

- PostgreSQL HA (primario + réplicas): almacenamiento autoritativo de datos.
- Redis Cluster: caché distribuida de consultas.
- NATS Core + JetStream: señales efímeras y eventos durables.
- Almacenamiento de objetos: archivos, documentos y exportaciones.
- CI/CD y artefactos: código, imágenes y secretos de despliegue.

---

## 3. Actores

### 3.1 Actores legítimos

| Actor | Nivel de confianza | Descripción |
|---|---|---|
| Operador de plataforma | Alto (interno) | Administra tenants, planes y la plataforma SaaS |
| Administrador de tenant | Medio-alto | Configura su empresa, usuarios y sucursales |
| Empleado de sucursal | Medio | Cajero, mesero, cocinero con permisos acotados por rol |
| Cliente final | Bajo | Consulta menú, realiza pedidos, gestiona su cuenta |
| Proceso de servicio (service-to-service) | Medio | Comunicación gRPC entre los cuatro procesos |
| Worker/consumidor interno | Medio | Procesa Outbox, Inbox, Sagas y jobs periódicos |
| Proveedor externo | Bajo-medio | PSP, correo, SMS, integraciones de hardware |

### 3.2 Actores adversarios

- Atacante externo no autenticado: explora superficies públicas.
- Atacante autenticado de bajo privilegio: intenta escalar o cruzar tenants.
- Tenant malicioso: intenta acceder a datos de otros tenants.
- Proveedor comprometido: callback, webhook o respuesta de API manipulada.
- Insider: empleado o colaborador con acceso legítimo que abusa de él.
- Atacante de supply chain: dependencia, imagen de contenedor o workflow comprometido.
- Atacante con acceso físico a un dispositivo POS perdido, robado o desatendido.
- Dispositivo POS comprometido, clonado o fuera de inventario que intenta sincronizar.
- Proveedor de IA, extensión o herramienta externa comprometida o con permisos excesivos.

---

## 4. Fronteras de confianza

```text
[Navegador / App cliente]
        │ HTTPS / TLS
        ▼
[Admin BFF / Public BFF]          ← frontera 1: borde público
        │ gRPC + mTLS
        ▼
[Admin Platform Backend]          ← frontera 2: backend PLATFORM
[Public Backend]                  ← frontera 2: backend dominio
        │
        ├── PostgreSQL             ← frontera 3: datos autoritativos
        ├── Redis Cluster          ← frontera 3: caché
        ├── NATS Core/JetStream    ← frontera 3: mensajería
        └── Almacenamiento objetos ← frontera 3: archivos

[Proveedores externos]            ← frontera 4: terceros no confiables
[CI/CD]                           ← frontera 5: pipeline de despliegue
```

Cada frontera requiere autenticación, autorización y validación independiente.
Un control en la frontera 1 no sustituye los controles en la frontera 2.

---

## 5. Amenazas por categoría STRIDE

### 5.1 Suplantación (Spoofing)

| ID | Amenaza | Superficie | Severidad |
|---|---|---|---|
| S-01 | Robo o reutilización de token de sesión | BFF → Backend | Alta |
| S-02 | Suplantación de identidad de servicio entre procesos | gRPC inter-proceso | Alta |
| S-03 | Credenciales de usuario comprometidas (phishing, fuerza bruta) | Frontera pública | Alta |
| S-04 | Callback de proveedor externo falsificado (PSP, webhook) | Frontera proveedores | Alta |
| S-05 | Worker con identidad no verificada procesando mensajes | NATS/Outbox | Media |
| S-06 | Dispositivo POS clonado, revocado o no enrolado que suplanta un dispositivo autorizado al sincronizar | POS / identidad de dispositivo | Alta |

### 5.2 Manipulación (Tampering)

| ID | Amenaza | Superficie | Severidad |
|---|---|---|---|
| T-01 | Inyección SQL en consultas no parametrizadas | Backend → PostgreSQL | Crítica |
| T-02 | Manipulación de precios, descuentos o cálculos en tránsito | BFF → Backend | Alta |
| T-03 | Modificación de eventos en tránsito o replay de mensajes | NATS JetStream | Alta |
| T-04 | Alteración de archivos subidos (documentos, imágenes) | Almacenamiento objetos | Media |
| T-05 | Modificación de dependencias o artefactos en CI/CD | Pipeline | Alta |
| T-06 | Alteración, borrado, reordenamiento o replay de la cola local de operaciones offline | POS / almacenamiento local / sincronización | Crítica |
| T-07 | Envenenamiento o contaminación de caché con datos de otro tenant, usuario o versión de permisos | Redis / caché de aplicación | Alta |
| T-08 | Alteración, sustitución o restauración maliciosa de backups, WAL o snapshots | Backups / recuperación | Crítica |

### 5.3 Repudio (Repudiation)

| ID | Amenaza | Superficie | Severidad |
|---|---|---|---|
| R-01 | Operaciones financieras sin trazabilidad de actor | PAYMENTS / CASH | Alta |
| R-02 | Cambios de configuración de tenant sin registro | PLATFORM | Alta |
| R-03 | Acceso excepcional de soporte sin auditoría | Todos los módulos | Alta |
| R-04 | Operaciones offline ejecutadas, descartadas o sincronizadas sin secuencia y trazabilidad reconciliable | POS / AUDIT / sincronización | Alta |

### 5.4 Divulgación de información (Information Disclosure)

| ID | Amenaza | Superficie | Severidad |
|---|---|---|---|
| D-01 | BOLA/IDOR — acceso a recursos de otro tenant | Todos los módulos | Crítica |
| D-02 | Escalada horizontal entre usuarios del mismo tenant | IDENTITY / módulos | Alta |
| D-03 | Fuga de datos en logs, trazas o respuestas de error | Todos los procesos | Alta |
| D-04 | Exfiltración masiva mediante scraping o exportaciones | Public BFF / ANALYTICS | Alta |
| D-05 | Secretos expuestos en código, logs o artefactos | CI/CD / Repositorio | Crítica |
| D-06 | Datos de pago completos fuera de flujo PCI | PAYMENTS | Crítica |
| D-07 | SSRF desde URLs o importaciones controladas por usuario | Public Backend / BFF | Alta |
| D-08 | Exposición de datos locales al perderse, robarse o compartirse un dispositivo POS | POS / almacenamiento local | Alta |
| D-09 | Bucket, objeto o URL de descarga expuestos sin autorización o con alcance excesivo | Object storage | Alta |
| D-10 | Exfiltración de backups, WAL, snapshots o exportaciones de recuperación | Backups / almacenamiento | Crítica |
| D-11 | Envío de datos personales, financieros, secretos o información multi-tenant a proveedor/modelo de IA sin base y control aprobados | Integración IA / proveedor | Alta |

### 5.5 Denegación de servicio (Denial of Service)

| ID | Amenaza | Superficie | Severidad |
|---|---|---|---|
| DS-01 | DDoS volumétrico sobre BFF o endpoints públicos | Frontera pública | Alta |
| DS-02 | Agotamiento de conexiones PostgreSQL por pool no limitado | Backend → PostgreSQL | Alta |
| DS-03 | Bomba de descompresión o payload excesivo en upload | Almacenamiento / BFF | Media |
| DS-04 | Abuso de endpoints costosos (reportes, exportaciones, IA) | Public BFF / ANALYTICS | Media |
| DS-05 | Flood de mensajes en NATS que satura workers | NATS → Workers | Media |
| DS-06 | Sincronización offline masiva, repetida o malformada que agota API, broker, workers o base de datos | POS / BFF / NATS / workers | Alta |
| DS-07 | Ransomware, borrado o fallo de restauración que impide recuperar datos y servicio | Backups / almacenamiento / operación | Crítica |

### 5.6 Elevación de privilegios (Elevation of Privilege)

| ID | Amenaza | Superficie | Severidad |
|---|---|---|---|
| E-01 | Escalada vertical: usuario accede a operaciones de administrador | IDENTITY / RBAC | Crítica |
| E-02 | Tenant estándar accede a operaciones de operador de plataforma | PLATFORM | Crítica |
| E-03 | Mass assignment: campos de tenant, rol o estado interno en escrituras HTTP | BFF → Backend | Alta |
| E-04 | Worker o consumidor ejecuta operación sin contexto de tenant válido | Workers / Consumers | Alta |
| E-05 | Workflow CI/CD con permisos excesivos modifica producción | CI/CD | Alta |
| E-06 | XSS que eleva privilegios mediante token robado en navegador | Frontera pública | Alta |
| E-07 | CSRF en operaciones de estado sobre APIs no protegidas | BFF público | Media |
| E-08 | Enrolamiento, reasignación o elevación de privilegios de un dispositivo POS sin autorización administrativa | Gestión de dispositivos | Alta |
| E-09 | Agente, modelo o herramienta de IA ejecuta acciones fuera de su alcance o sin confirmación requerida | Integración IA / herramientas | Alta |

---

## 6. Amenazas específicas del dominio restaurante

| ID | Amenaza | Superficie | Severidad |
|---|---|---|---|
| DOM-01 | Manipulación de precios de productos en CATALOG sin autorización | CATALOG / SALES | Alta |
| DOM-02 | Ajuste fraudulento de inventario para ocultar mermas | INVENTORY | Alta |
| DOM-03 | Anulación o modificación de pagos ya confirmados | PAYMENTS / CASH | Crítica |
| DOM-04 | Acceso cruzado entre sucursales del mismo tenant | ORGANIZATION / módulos | Alta |
| DOM-05 | Receta de producción modificada sin trazabilidad de versión | PRODUCTION | Media |
| DOM-06 | Venta offline duplicada, perdida o aplicada con precios, impuestos, inventario o estado de pago inconsistentes al reconciliar | POS / SALES / CASH / INVENTORY | Crítica |
| DOM-07 | Sincronización de operación offline atribuida a tenant o sucursal distintos de la asignación vigente del dispositivo | POS / identidad / multi-tenant | Crítica |

---

## 7. Notas de implementación y estado

Este modelo de amenazas es un documento vivo. Se actualiza cuando:

- Se incorpora una nueva superficie, proceso o proveedor.
- Se acepta un ADR que modifica fronteras o controles.
- Una prueba de seguridad revela una amenaza no considerada.
- Se cierra o acepta formalmente un riesgo residual.

Las amenazas específicas de operación offline incluyen seguridad del dispositivo, almacenamiento local, identidad enrolada, secuencia, idempotencia, reconciliación y revocación. El dispositivo puede conservar una cola temporal, pero no se convierte en autoridad para permisos, tenant, precios vigentes ni estado final de negocio.

Cada amenaza tiene controles asignados en [threat-control-matrix.md](./threat-control-matrix.md), incluidos criterios de prueba y evidencia requerida.
Los riesgos sin control implementado se registran en [residual-risk-register.md](./residual-risk-register.md).
La línea base de controles por proceso está en [security-baseline-per-process.md](./security-baseline-per-process.md).

---

## 8. Referencias normativas

- [ADR-0020: Marco integral de seguridad](../adr/0020-integral-security-and-defense-in-depth.md)
- [ADR-0021: Autorización, RBAC/ABAC y aislamiento multi-tenant](../adr/0021-authorization-rbac-abac-and-tenant-isolation.md)
- [ADR-0022: Seguridad del frontend, sesiones y APIs de borde](../adr/0022-frontend-browser-session-and-api-security.md)
- [ADR-0023: Seguridad de infraestructura, redes, secretos y criptografía](../adr/0023-infrastructure-network-secrets-and-cryptography-security.md)
- [ADR-0024: Desarrollo seguro, CI/CD y cadena de suministro](../adr/0024-secure-development-cicd-and-software-supply-chain.md)
- [ADR-0025: Protección contra abuso de APIs, bots, DDoS y extracción](../adr/0025-api-abuse-bots-ddos-and-data-exfiltration-protection.md)
- [ADR-0026: Auditoría de seguridad, detección y respuesta a incidentes](../adr/0026-security-audit-detection-and-incident-response.md)
- [ADR-0027: Seguridad de archivos, documentos y almacenamiento de objetos](../adr/0027-secure-file-document-and-object-storage-handling.md)
- [ADR-0011: Protección de contraseñas y autenticación](../adr/0011-password-hashing-and-authentication-security.md)
- [ADR-0019: Validación de entradas y contratos de datos](../adr/0019-input-validation-and-data-integrity.md)
