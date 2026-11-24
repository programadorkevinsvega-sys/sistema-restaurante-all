# Adapters

Esta carpeta contiene adaptadores técnicos que conectan puertos de aplicación con transportes, brokers y otras tecnologías. Un adaptador traduce entre contrato e implementación; no decide reglas del dominio.

- grpc/: clientes y servidores gRPC. Son obligatorios desde el inicio en las fronteras backend ↔ BFF y se usan entre servicios separados. No son obligatorios para llamadas entre módulos internos que comparten proceso.
- messaging/: integración con brokers y transporte de eventos.
- local/: adaptadores en proceso o sustitutos de prueba cuando correspondan.

Los módulos internos usan puertos/traits y contratos públicos; nunca implementaciones internas ajenas. La comunicación local no elimina el contrato Protobuf versionado equivalente.

No guardar aquí secretos, migraciones ni configuración de despliegue. Ver [Arquitectura](../../docs/architecture/restaurant-os-architecture.md) y [Reglas de implementación](../../docs/engineering/implementation-rules.md).