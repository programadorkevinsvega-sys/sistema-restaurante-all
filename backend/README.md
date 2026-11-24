# Backends y módulos

Esta carpeta organiza el código de los módulos por su backend propietario. Los cuatro procesos tienen conjuntos de módulos independientes. La asignación concreta de cada dominio debe respetar la matriz de responsabilidades de `requisitos.md` y los ADR aceptados; no se debe duplicar un módulo ni inventar una asignación para llenar carpetas.

Cada módulo es un crate independiente y mantiene sus propias capas, schema PostgreSQL, rol, migraciones e historial SQLx. No existen tablas compartidas entre módulos.
