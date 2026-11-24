# Crates compartidos y adaptadores

Esta carpeta se reserva para capacidades técnicas neutrales y adaptadores reutilizables. No aloja módulos propietarios de negocio ni los contratos públicos Rust de cada módulo: esos viven bajo `backend/<backend>/modules/<modulo>/contracts/`. Un crate compartido no puede convertirse en propietario accidental de datos o reglas de negocio de otro módulo.

- `shared/`: utilidades técnicas neutrales.
- `contracts/events/`: esquemas de eventos versionados bajo ownership del módulo productor.
- `adapters/local/`: invocación local entre módulos que comparten proceso; implementa los mismos puertos que el adaptador gRPC.
- `adapters/grpc/`: transporte gRPC entre procesos.
- `adapters/messaging/`: NATS Core y JetStream.

Las fuentes Protobuf no viven aquí: su única ubicación es `contracts/protobuf/<backend>/<modulo>/v1/`.

El catálogo propuesto, los límites entre contratos y transporte y las reglas de dependencias están descritos en [Diseño de crates y dependencias](../docs/architecture/crate-architecture.md) y ADR-0009. La propuesta sigue pendiente de aprobación; la presencia de estas carpetas no significa que existan crates Rust o dependencias implementadas.
