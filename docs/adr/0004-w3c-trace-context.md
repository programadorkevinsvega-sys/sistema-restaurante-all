# ADR-0004: W3C Trace Context en todos los contratos

- Estado: **Accepted**
- Historial: Proposed → Accepted
- Propuesto: 2026-11-24
- Aceptado: 2026-11-24
- Aprobación: propietario del producto, confirmada explícitamente en la conversación de arquitectura.

## Contexto

La observabilidad distribuida requiere conservar trazas entre HTTP, gRPC, módulos, eventos y workers. Un trace_id ad hoc no garantiza interoperabilidad.

## Decisión

1. Adoptar W3C Trace Context.
2. traceparent es portador canónico; tracestate se propaga cuando aplique.
3. trace_id es el identificador contenido en el componente trace-id de traceparent; no se modifica al continuar el mismo flujo.
4. HTTP usa headers W3C; gRPC usa metadata; eventos incluyen traceparent y tracestate opcional en su envelope versionado.
5. Outbox, Inbox y workers conservan el contexto.
6. Mantener diferenciados trace_id, span_id, request_id, correlation_id, causation_id y event_id.
7. El contexto es diagnóstico; no sustituye tenant, actor, autorización ni idempotencia.

## Consecuencias

Contratos y eventos deben propagar contexto; OpenTelemetry extrae/injecta W3C. Pruebas cubren propagación, continuidad, privacidad y contexto ausente/malformado.

## Alternativas

Trace ID propio sin W3C: rechazado por falta de interoperabilidad. Crear nueva traza sin vínculo en cada worker: rechazado porque rompe continuidad.

## Estado de implementación

Decisión aceptada; no afirma que OpenTelemetry o la propagación estén desplegados.
