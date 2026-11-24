# Contratos HTTP OpenAPI

Este directorio es la fuente de verdad versionada para las superficies HTTP de Restaurant OS.

- Organizar los documentos por backend/capacidad y versión, por ejemplo: openapi/<backend>/<capacidad>/v1/openapi.yaml.
- OpenAPI genera los tipos y clientes HTTP consumidos por los frontends y BFF.
- No editar manualmente los artefactos generados; cambiar el contrato fuente y regenerar.
- Fijar generador y versión cuando se incorpore tooling.
- CI valida OpenAPI, genera artefactos desde cero y falla si los artefactos versionados difieren.
- No declarar CI ni generación activa hasta que existan workflows, herramientas y evidencia de ejecución.

Ver [ADR-0002](../../../docs/adr/0002-openapi-protobuf-generated-clients.md) y [reglas de implementación](../../../docs/engineering/implementation-rules.md).
