# Módulos internos de Admin BFF

Este directorio no contiene módulos propietarios de dominios de negocio. Si se organiza código aquí, se limita a capacidades internas de composición, transporte o presentación del BFF.

No crear schemas PostgreSQL, tablas de negocio, migraciones de dominio ni historiales SQLx de módulos propietarios en Admin BFF. Los datos y reglas autoritativos permanecen en Admin Platform Backend (PLATFORM) o Public Backend (los demás dominios).