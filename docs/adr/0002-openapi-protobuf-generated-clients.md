# ADR-0002: OpenAPI, Protobuf y código generado

- Estado: **Accepted**
- Historial: Proposed → Accepted
- Propuesto: 2026-11-24
- Aceptado: 2026-11-24
- Aprobación: propietario del producto, confirmada explícitamente en la conversación de arquitectura.

## Contexto

Los frontends deben evolucionar independientemente sin duplicar contratos del backend. Se requieren fuentes de verdad explícitas y detección automática de divergencias.

## Decisión

1. OpenAPI es fuente de verdad para superficies HTTP.
2. Protobuf versionado es fuente de verdad para APIs gRPC.
3. OpenAPI genera tipos y clientes HTTP consumidos por frontends y BFF.
4. Protobuf genera stubs y tipos gRPC para backends y BFF.
5. Código generado es artefacto: no se edita a mano; se cambia fuente y se regenera.
6. CI ejecuta generadores con versiones fijadas y falla si el resultado difiere del código generado versionado.
7. CI valida lint y compatibilidad; Protobuf usa controles equivalentes a buf lint y buf breaking.
8. Frontends independientes; reglas de negocio y autorización efectiva permanecen en backend.

## Consecuencias

Contratos fuente versionados y responsables; herramientas fijadas; cambios incompatibles requieren nueva versión y convivencia; PR de contrato incluye artefactos generados o falla CI.

## Alternativas

DTO duplicados a mano: rechazados por divergencia. Generar HTTP desde Protobuf o gRPC desde OpenAPI: rechazado porque cada formato es fuente de su transporte.

## Estado de implementación

Decisión aceptada. Generadores y checks no se consideran activos hasta configurarse y ejecutarse con evidencia.
