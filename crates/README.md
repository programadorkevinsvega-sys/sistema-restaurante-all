# Crates compartidos y adaptadores

Esta carpeta se reserva para capacidades técnicas neutrales, contratos de transporte versionados y adaptadores reutilizables. No aloja módulos propietarios de negocio: esos viven bajo `backend/<backend>/modules/`. Un crate compartido no puede convertirse en propietario accidental de datos o reglas de negocio de otro módulo.

El catálogo propuesto, los límites entre contratos y transporte y las reglas de dependencias están descritos en [Diseño de crates y dependencias](../docs/architecture/crate-architecture.md) y ADR-0009. La propuesta sigue pendiente de aprobación; la presencia de estas carpetas no significa que existan crates Rust o dependencias implementadas.
