# ADR-0005: Contratos Protobuf y gRPC desde el inicio

- Estado: **Accepted**
- Historial: Proposed → Accepted
- Propuesto: 2026-11-24
- Aceptado: 2026-11-24
- Aprobación: propietario del producto, confirmada explícitamente en la conversación de arquitectura.

> **Nota de vigencia:** ADR-0007 sustituye parcialmente este ADR en lo relativo a la topología de procesos, los nombres de los procesos y el despliegue inicial de dos servicios. La decisión de definir Protobuf versionado desde el inicio y utilizar gRPC en las fronteras entre procesos permanece vigente. Los apartados siguientes conservan el registro histórico de la topología original `api-server`/BFF; sus referencias a dos procesos no describen la arquitectura vigente.

## Contexto

Definir Protobuf desde el inicio y usar gRPC en toda llamada no son la misma decisión. El estándar exige contratos Protobuf versionados y gRPC entre `api-server` y BFF. Para cumplir esa frontera, el BFF es un proceso independiente; los módulos internos alojados en `api-server` pueden invocarse mediante puertos locales.

## Decisión

1. Cada capacidad define desde el inicio contrato Protobuf versionado equivalente a su interfaz pública.
2. `api-server` es el proceso backend que aloja los módulos del monolito modular y expone los servicios gRPC.
3. El BFF es un proceso independiente; consume `api-server` mediante gRPC y expone HTTP/OpenAPI a los frontends.
4. El despliegue objetivo inicial usa dos servicios de aplicación en Docker Compose: `api-server` y `bff`.
5. gRPC entre `api-server` y BFF es obligatorio desde el inicio.
6. Módulos internos en el mismo proceso pueden usar traits/puertos locales y DTO propios, respetando el contrato público.
7. Al separar otro módulo como servicio, el adaptador gRPC implementa el mismo puerto y usa el Protobuf existente.
8. La llamada local no autoriza imports de implementaciones internas, exposición de entidades ni acceso a tablas ajenas.

## Consecuencias

Protobuf no se posterga hasta microservicios. El BFF se ejecuta en un proceso independiente de `api-server`; gRPC está presente en esa frontera desde el inicio. Solo se difiere el transporte gRPC para llamadas internas entre módulos que comparten el proceso backend. Contratos versionados y validados por CI cuando los controles estén implementados.

## Alternativas

Crear Protobuf solo al extraer servicio: rechazado. gRPC para toda llamada interna desde el día uno: no requerido. Llamadas locales sin contrato público equivalente: rechazado.

## Estado de implementación

Decisión aceptada. La separación de procesos `api-server`/BFF, los servicios gRPC backend/BFF y la generación Protobuf deben verificarse por separado; este ADR no afirma que el despliegue esté implementado.
