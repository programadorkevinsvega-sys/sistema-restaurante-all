# ADR-0005: Contratos Protobuf y gRPC desde el inicio

- Estado: **Accepted**
- Historial: Proposed → Accepted
- Propuesto: 2026-11-24
- Aceptado: 2026-11-24
- Aprobación: propietario del producto, confirmada explícitamente en la conversación de arquitectura.

## Contexto

Definir Protobuf desde el inicio y usar gRPC en toda llamada no son la misma decisión. El estándar exige contratos Protobuf versionados y gRPC entre backends y BFF; módulos en el mismo proceso pueden invocarse mediante puertos locales.

## Decisión

1. Cada capacidad define desde el inicio contrato Protobuf versionado equivalente a su interfaz pública.
2. gRPC entre backends y BFF es obligatorio desde el inicio.
3. Módulos internos en el mismo proceso pueden usar traits/puertos locales y DTO propios, respetando el contrato público.
4. Al separar un módulo, el adaptador gRPC implementa el mismo puerto y usa el Protobuf existente.
5. La llamada local no autoriza imports de implementaciones internas, exposición de entidades ni acceso a tablas ajenas.

## Consecuencias

Protobuf no se posterga hasta microservicios. gRPC está presente en frontera backend ↔ BFF desde el inicio. Solo se difiere el transporte gRPC para llamadas internas del mismo proceso. Contratos versionados y validados por CI.

## Alternativas

Crear Protobuf solo al extraer servicio: rechazado. gRPC para toda llamada interna desde el día uno: no requerido. Llamadas locales sin contrato público equivalente: rechazado.

## Estado de implementación

Decisión aceptada. Servicios gRPC backend/BFF y generación Protobuf deben verificarse por separado.
