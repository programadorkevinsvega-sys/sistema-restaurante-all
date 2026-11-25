# Modelo de red y matriz de flujos permitidos

**Estado:** diseño aprobado — subfase 0.7
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.7
**Autoridad:** ADR-0020, ADR-0023
**Documentos relacionados:**

- [Política de secretos](./secrets-policy.md)
- [Política TLS/criptográfica](./tls-crypto-policy.md)
- [Baseline de contenedores](./container-baseline.md)

---

## 1. Propósito y límites

Define la topología de redes, zonas de confianza y matriz de flujos permitidos entre
componentes. No configura firewalls, security groups, VPCs ni infraestructura real.
La tecnología concreta de red (VPC, NSG, Cilium, etc.) se decide en el diseño de despliegue.

---

## 2. Zonas de red

Cada zona tiene propósito exclusivo. El tráfico entre zonas requiere regla explícita;
todo lo no permitido está denegado por defecto.

| Zona | Componentes | Acceso externo |
|---|---|---|
| `public-ingress` | Load balancer / API Gateway | Sí — solo puertos 443 |
| `app` | Admin BFF, Public BFF, Admin Platform Backend, Public Backend | No directo |
| `data` | PostgreSQL primario + standbys, Redis Cluster, NATS | No directo |
| `messaging` | NATS Core/JetStream, workers Outbox/Inbox | No directo |
| `storage` | Object storage (archivos, backups) | No directo |
| `observability` | Prometheus, Loki, Tempo, Grafana, OTel Collector | No directo; acceso solo desde `ops` |
| `ops` | Bastion/VPN, herramientas de administración, CI/CD runners | Acceso humano controlado + MFA |
| `backup` | Destinos de backup PostgreSQL, Redis snapshots | No directo; solo desde `ops` |

---

## 3. Matriz de flujos permitidos

### 3.1 Entrada pública → BFF

| Origen | Destino | Puerto | Protocolo | Condición |
|---|---|---|---|---|
| Internet (clientes web/móvil) | Load balancer `public-ingress` | 443 | HTTPS/TLS 1.2+ | — |
| `public-ingress` | Public BFF (`app`) | interno | HTTP/2 o HTTPS | Desde LB únicamente |
| `public-ingress` | Admin BFF (`app`) | interno | HTTP/2 o HTTPS | Desde LB; IP allowlist de admins |

### 3.2 BFF → Backends

| Origen | Destino | Puerto | Protocolo | Condición |
|---|---|---|---|---|
| Admin BFF | Admin Platform Backend | interno | gRPC + mTLS | Solo contratos definidos |
| Admin BFF | Public Backend | interno | gRPC + mTLS | Solo contratos definidos |
| Public BFF | Public Backend | interno | gRPC + mTLS | Solo contratos definidos |
| Public BFF | Admin Platform Backend | interno | gRPC + mTLS | Solo para operaciones autorizadas |

Los BFF no acceden directamente a PostgreSQL, Redis ni NATS.

### 3.3 Backends → Datos

| Origen | Destino | Puerto | Protocolo | Condición |
|---|---|---|---|---|
| Admin Platform Backend | PostgreSQL primario | 5432 | TCP + TLS | Solo credencial `platform_runtime` |
| Public Backend | PostgreSQL primario | 5432 | TCP + TLS | Credencial `*_runtime` del módulo |
| Public Backend | PostgreSQL réplica | 5432 | TCP + TLS | Solo queries elegibles; credencial readonly |
| Public Backend | Redis Cluster | 6379 | TCP + TLS | ACL por módulo; solo operaciones permitidas |
| Admin Platform Backend | Redis Cluster | 6379 | TCP + TLS | ACL restringida a PLATFORM |

### 3.4 Backends → Mensajería

| Origen | Destino | Puerto | Protocolo | Condición |
|---|---|---|---|---|
| Admin Platform Backend | NATS | 4222 | TCP + TLS | Cuenta NATS dedicada; subjects acotados |
| Public Backend | NATS | 4222 | TCP + TLS | Cuenta NATS dedicada; subjects acotados |
| Workers Outbox/Inbox | NATS JetStream | 4222 | TCP + TLS | Credencial worker; subjects propios |

### 3.5 Backends → Almacenamiento

| Origen | Destino | Protocolo | Condición |
|---|---|---|---|
| Public Backend | Object storage | HTTPS | Credencial por módulo; acceso a prefijo propio |
| Admin Platform Backend | Object storage | HTTPS | Credencial restringida a PLATFORM |

### 3.6 Backends → Proveedores externos

| Origen | Destino | Protocolo | Condición |
|---|---|---|---|
| Public Backend | PSP (pagos) | HTTPS | Egress allowlist de dominio; no loopback/privado |
| Public Backend | Proveedor email/SMS | HTTPS | Egress allowlist de dominio |
| Public Backend | Integraciones externas | HTTPS | Egress allowlist; anti-SSRF aplicado |

Egress no listado aquí está denegado por defecto.

### 3.7 Observabilidad (pull desde OTel Collector)

| Origen | Destino | Puerto | Protocolo | Condición |
|---|---|---|---|---|
| Todos los procesos | OTel Collector (`observability`) | 4317/4318 | gRPC/HTTP | Push de trazas y métricas |
| OTel Collector | Prometheus | interno | HTTP | Solo desde `observability` |
| Prometheus | Procesos (scrape) | métricas | HTTP | Solo desde `observability` |
| Grafana | Prometheus/Loki/Tempo | interno | HTTP | Solo desde `observability` |
| Equipo ops | Grafana | 443 | HTTPS | Solo desde `ops` / VPN |

### 3.8 Operaciones y administración

| Origen | Destino | Condición |
|---|---|---|
| Bastion/VPN (`ops`) | PostgreSQL (`data`) | Solo para mantenimiento; MFA + trazabilidad |
| Bastion/VPN (`ops`) | Redis (`data`) | Solo para mantenimiento; MFA + trazabilidad |
| Bastion/VPN (`ops`) | NATS (`messaging`) | Solo para mantenimiento; MFA + trazabilidad |
| CI/CD runners (`ops`) | Registro de imágenes | Push de imágenes firmadas |
| CI/CD runners (`ops`) | Cluster de despliegue | Solo desde pipeline aprobado; credencial temporaria |

---

## 4. Egress restringido por proceso

Cada proceso tiene una identidad de red y solo puede conectarse a los destinos de su columna.

| Proceso | Destinos permitidos |
|---|---|
| Admin BFF | LB entrada, Admin Platform Backend, Public Backend |
| Public BFF | LB entrada, Public Backend |
| Admin Platform Backend | PostgreSQL (platform), Redis (platform), NATS (platform), Object storage (platform), OTel Collector |
| Public Backend | PostgreSQL (módulos), Redis (módulos), NATS (módulos), Object storage (módulos), Proveedores externos allowlist, OTel Collector |
| Workers | NATS, PostgreSQL (módulo propio), OTel Collector |

Un proceso no puede conectarse a servicios de datos de otro proceso.

---

## 5. Flujos prohibidos

- BFF → PostgreSQL directo (cualquier schema).
- BFF → Redis directo.
- BFF → NATS directo.
- Proceso → PostgreSQL de otro proceso.
- Internet → PostgreSQL, Redis, NATS, métricas, administración (cualquier puerto directo).
- Proceso → URLs arbitrarias controladas por usuario sin validación anti-SSRF.
- Proceso → Metadatos cloud (169.254.169.254) o redes privadas desde URLs de usuario.

---

## 6. Estado de implementación

Diseño aprobado. No existen VPCs, security groups, firewalls ni reglas configuradas.
La implementación comienza junto con el despliegue de infraestructura de cada entorno.
