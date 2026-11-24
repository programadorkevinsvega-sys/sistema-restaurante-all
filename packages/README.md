# Packages

Bibliotecas reutilizables para aplicaciones frontend.

- ui/: componentes visuales y sistema de diseño.
- shared-types/: tipos y clientes HTTP generados desde OpenAPI y tipos/stubs gRPC derivados de Protobuf cuando aplique. No editar código generado manualmente.
- permissions/: utilidades de interfaz; la autorización efectiva siempre se valida en backend.
- validation/: validaciones de experiencia de usuario; el servidor valida de nuevo toda entrada.
- utilities/: funciones genéricas.

Los frontends son aplicaciones independientes que consumen contratos versionados. CI debe regenerar los artefactos y fallar si difieren de los contratos fuente. Ver [ADR-0002](../docs/adr/0002-openapi-protobuf-generated-clients.md) y [Reglas de implementación](../docs/engineering/implementation-rules.md).