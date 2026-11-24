# Backends y módulos

Esta carpeta organiza el código de los módulos por su backend propietario. Según ADR-0008, `admin-platform-backend/modules/` contiene únicamente PLATFORM y `public-backend/modules/` contiene los demás módulos de negocio canónicos. Los BFF no tienen módulos propietarios de negocio. No se debe duplicar un módulo ni cambiar su asignación sin un ADR aceptado.

Cada módulo es un crate independiente y mantiene sus propias capas, schema PostgreSQL, rol, migraciones e historial SQLx. No existen tablas compartidas entre módulos.
