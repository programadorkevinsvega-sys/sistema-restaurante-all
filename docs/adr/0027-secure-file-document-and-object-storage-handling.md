# ADR-0027: Seguridad de archivos, documentos y almacenamiento de objetos

- Estado: **Accepted**
- Fecha: 2026-11-25
- Ámbito: cargas, procesamiento, almacenamiento, previsualización, descarga, exportación y eliminación de archivos/documentos.
- Complementa: ADR-0001, ADR-0008, ADR-0014, ADR-0015, ADR-0018 y ADR-0020 a ADR-0026.
- Aprobación: aprobada explícitamente por el propietario del producto el 2026-11-25.

## Contexto

Restaurant OS manejará imágenes, documentos comerciales, soportes de pago, facturas, documentos fiscales, importaciones/exportaciones y adjuntos. Un archivo puede contener malware, explotar parsers, consumir recursos, filtrar metadatos o quedar accesible para otro tenant. Extensión y Content-Type no prueban el formato real; UUID/URL opaca tampoco autorizan descarga.

## Decisión

### 1. Archivos no confiables

Todo archivo recibido se considera hostil hasta validar formato, estructura y política de uso. Extensión y MIME declarados son señales, no evidencia suficiente. Inspeccionar contenido con detección apropiada; mantener allowlist por caso de uso; rechazar archivos corruptos, ambiguos, truncados o no soportados. No ejecutar archivos recibidos ni servir contenido activo por defecto.

### 2. Límites de carga y consumo

Definir límites por endpoint, tipo y tenant para tamaño individual/total, cantidad, dimensiones/píxeles, duración/resolución/códec si aplica, páginas/objetos/profundidad de archivos comprimidos, tiempo de procesamiento, memoria/CPU, cuota de almacenamiento y ritmo de carga. Dimensionar según necesidades reales. Rechazar temprano y evitar reservar recursos ilimitados.

### 3. Nombres y almacenamiento

- Generar nombres/identificadores internos en servidor; nunca usar nombre/ruta del cliente como ruta física.
- Canonicalizar rutas y prevenir traversal, symlinks y colisiones.
- Almacenar fuera de webroot y en ubicación no ejecutable.
- Separar buckets/espacios y permisos por entorno/finalidad.
- No exponer credenciales de almacenamiento al navegador.
- Ownership y autorización pertenecen al módulo responsable del caso de uso.
- No crear schema/tabla global de archivos para sustituir ownership; metadata pertenece al módulo propietario.
- Checksum/hash y versión pueden apoyar integridad, pero no sustituyen autorización.

### 4. Cuarentena y procesamiento aislado

Los archivos pueden permanecer en cuarentena hasta controles requeridos. Usar antivirus/sandbox cuando riesgo/capacidad lo justifiquen. Procesar imágenes, PDFs, documentos y comprimidos en procesos aislados, sin privilegios, filesystem limitado, egress restringido y límites de recursos. Mantener parsers actualizados. Rechazar/aislar bombas de descompresión, archivos recursivos, polyglots, contenido activo y estructuras malformadas. Escáner no es garantía absoluta; combinar allowlist, límites y aislamiento.

### 5. Metadatos y contenido sensible

Eliminar EXIF/geolocalización cuando no sean necesarios. No registrar contenido ni nombres originales sensibles en logs. Documentos fiscales/legales requieren integridad, autenticidad, acceso y retención del dominio. No modificar silenciosamente documentos probatorios; conservar original/evidencia conforme a reglas del módulo. Clasificar sensibilidad, minimizar duplicados y temporales. No enviar a proveedores/IA sin finalidad, autorización, contrato y evaluación de privacidad.

### 6. Descargas y previsualizaciones

Cada descarga, preview, conversión y exportación se autoriza en backend propietario. Comprobar tenant, propietario, relación, permiso y estado. UUID/ruta/URL firmada no son autorización. URLs firmadas, si se usan, serán breves, acotadas y revocables/invalidadas cuando sea viable. Evitar contenido activo no confiable en el mismo origen. Configurar Content-Disposition, Content-Type, nosniff y caché. Derivados/miniaturas conservan vínculo de autorización con original. Enlaces compartidos requieren alcance, destinatario/propósito y expiración; no hay enlaces públicos permanentes por defecto.

### 7. Aislamiento multi-tenant

Tenant se resuelve desde contexto autenticado validado, nunca de path/metadata no verificada. Cada operación comprueba pertenencia y autorización. Workers verifican contexto, identidad y propósito. Credenciales de almacenamiento limitadas a objetos/buckets necesarios. Comprometer un procesador no debe dar acceso a todos los tenants. Accesos excepcionales se auditan conforme ADR-0021/0026.

### 8. Integridad, versiones y ciclo de vida

Definir cuándo un archivo es inmutable/reemplazable. Documentos fiscales/legales/probatorios conservan versiones o evidencia de integridad según dominio/ley. Sustituciones, eliminaciones y transformaciones críticas registran actor, momento, motivo y resultado. Temporales, miniaturas, conversiones y exportaciones heredan clasificación/retención salvo regla justificada. Eliminar derivados, cachés y URLs según ADR-0018; aplicar legal hold. Baja de tenant respeta ADR-0014 y no elimina automáticamente datos de clientes/documentos que deban conservarse.

### 9. Cifrado y disponibilidad

Almacenamiento privado cuando sea posible; cifrado en tránsito/en reposo según clasificación y ADR-0023; credenciales separadas para lectura, escritura, administración y backup; versionado/protección contra borrado y backups según criticidad. Probar restauración e integridad. Replicación/versionado no sustituyen backup. Observar capacidad, fallos, latencia, cuarentena, escaneos y accesos anómalos.

### 10. Pruebas de aceptación

Probar MIME/extensión falsos, corruptos, traversal, symlinks, archivos comprimidos expansivos, polyglots, scripts, SVG/HTML activo, documentos malformados, malware de prueba, cargas excesivas, descargas cruzadas entre tenants, URLs expiradas, revocación, restauración, eliminación y legal hold.

## Alternativas consideradas

Confiar en extensión/MIME; guardar en webroot; usar nombre original como ruta; publicar objetos y ocultar URL; procesar dentro del proceso principal con permisos amplios; conservar todo indefinidamente: rechazados.

## Consecuencias

Reduce malware, traversal, abuso de recursos, exposición cruzada y pérdida de integridad. Cuarentena/escaneo/procesamiento aislado añaden latencia y costo; formatos permitidos requieren mantenimiento.

## Límites

No selecciona proveedor de object storage, antivirus, sandbox o parser. No define tablas, rutas API, cuotas numéricas ni plazos legales. No modifica SQL/migraciones ni implementa almacenamiento.

## Plan futuro

Inventariar casos de uso/owners; definir formatos y límites; seleccionar almacenamiento/credenciales; diseñar cuarentena y procesamiento aislado; implementar autorización de carga/descarga; integrar retención/legal hold/auditoría; probar malware, aislamiento y recuperación.

## Estado de implementación

Accepted. La decisión está aprobada; no implementa cargas, almacenamiento, escaneo, cuarentena, parsers, URLs firmadas, tablas ni infraestructura.
