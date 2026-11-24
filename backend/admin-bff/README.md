# Admin BFF

Proceso/binario independiente que compone y expone por HTTP/OpenAPI las APIs necesarias para las interfaces administrativas.

No es propietario de dominios de negocio, schemas PostgreSQL ni tablas de negocio. Las operaciones sobre dominios empresariales se dirigen mediante contratos al módulo propietario de Public Backend; las capacidades de plataforma se consultan en Admin Platform Backend. No duplica reglas de negocio ni persistencia.