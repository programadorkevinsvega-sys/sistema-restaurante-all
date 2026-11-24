# Módulos

Cada subdirectorio de este nivel representa un módulo/crate con responsabilidad y propiedad de datos propias. Su estructura interna sigue domain, application, infrastructure y contracts. Cada módulo mantiene schema, rol, directorio de migraciones e historial SQLx exclusivos. No crear tablas compartidas, FKs, joins ni consultas directas entre módulos.

Los módulos concretos se incorporan según la asignación de dominios aprobada; este directorio no asigna dominios por inferencia.
