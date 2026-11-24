# Contracts

Esta carpeta contiene contratos versionados que cruzan límites de módulos o servicios.

- events/: esquemas de eventos versionados.
- proto/: contratos Protobuf versionados para APIs gRPC.
- OpenAPI es la fuente de verdad para las superficies HTTP y debe mantenerse en su ubicación versionada de contratos HTTP definida por el proyecto.

Protobuf existe desde el inicio aunque una llamada interna se ejecute localmente. Los contratos gRPC entre backends y BFF son obligatorios desde el inicio; solo se difiere gRPC para llamadas entre módulos internos del mismo proceso.

Los tipos y stubs derivados se generan desde sus contratos fuente y no se editan a mano. CI debe regenerar y fallar si hay diferencias. Ver [Arquitectura](../../docs/architecture/restaurant-os-architecture.md), [Reglas de implementación](../../docs/engineering/implementation-rules.md) y [ADRs](../../docs/adr/README.md).

No incluir reglas de negocio, adaptadores, SQL ni tipos duplicados manualmente.