# Backends y módulos

Esta carpeta organiza el código de los módulos por su backend propietario. Según ADR-0008, `admin-platform-backend/modules/` contiene únicamente PLATFORM y `public-backend/modules/` contiene los demás módulos de negocio canónicos. Los BFF no tienen módulos propietarios de negocio. No se debe duplicar un módulo ni cambiar su asignación sin un ADR aceptado.

Cada módulo es una unidad de ownership con implementación crate propia y schema PostgreSQL, rol, migraciones e historial SQLx exclusivos. Cada módulo tendrá desde el inicio un crate de implementación y un crate público `<modulo>-contracts`, con `src/` para las capas internas y `contracts/` para la API pública, conforme al diseño de ADR-0009. No existen tablas compartidas entre módulos.
