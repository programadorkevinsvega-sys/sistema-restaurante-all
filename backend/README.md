# Backends y módulos

Esta carpeta organiza el código de los módulos por su backend propietario. Según ADR-0008, `admin-platform-backend/modules/` contiene únicamente PLATFORM y `public-backend/modules/` contiene los demás módulos de negocio canónicos. Los BFF no tienen módulos propietarios de negocio. No se debe duplicar un módulo ni cambiar su asignación sin un ADR aceptado.

Cada módulo es una unidad de ownership con implementación crate propia y schema PostgreSQL, rol, migraciones e historial SQLx exclusivos. La separación de un crate público `<modulo>-contracts` y los límites de dependencia están desarrollados como propuesta en [ADR-0009](../docs/adr/0009-crate-boundaries-and-dependencies.md) y [Diseño de crates y dependencias](../docs/architecture/crate-architecture.md); siguen pendientes de aprobación. No existen tablas compartidas entre módulos.
