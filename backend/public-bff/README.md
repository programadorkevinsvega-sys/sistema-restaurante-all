# Public BFF

Proceso/binario independiente que compone y expone por HTTP/OpenAPI las APIs necesarias para las interfaces públicas y operativas.

No es propietario de dominios de negocio, schemas PostgreSQL ni tablas de negocio. Las operaciones se dirigen mediante contratos a los módulos propietarios de Public Backend. No duplica reglas de negocio ni persistencia.