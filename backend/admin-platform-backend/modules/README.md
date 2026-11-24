# Módulos de Admin Platform Backend

Este backend contiene únicamente el módulo propietario `PLATFORM`, ubicado en `platform/`. PLATFORM mantiene la propiedad del ciclo de vida SaaS: tenants, planes, suscripciones y límites.

Cada módulo conserva schema, rol, migraciones e historial SQLx exclusivos. La identidad de usuarios y membresías pertenece a IDENTITY en Public Backend; PLATFORM consume sus contratos cuando lo necesita y no duplica sus tablas.