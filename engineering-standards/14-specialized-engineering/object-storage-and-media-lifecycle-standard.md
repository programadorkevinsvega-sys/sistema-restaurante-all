# Estándar de almacenamiento de objetos y ciclo de vida de medios

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica a archivos, imágenes, audio, video, documentos, backups y objetos binarios.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.
- Mantener responsabilidades, límites de confianza y propiedad explícitos.
- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.
- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Separar metadatos de negocio del almacenamiento binario; definir propietario, clasificación, retención y referencia estable.
- Usar nombres/keys no confiables como datos; evitar traversal y sobrescritura accidental.
- Aplicar autorización por objeto, URLs firmadas de vida corta y alcance mínimo; no exponer buckets públicos por defecto.
- Validar tamaño, extensión, MIME real, firmas mágicas, malware y contenido activo; transformar/re-encodear formatos riesgosos.
- Definir cifrado, versionado, replicación, durabilidad, lifecycle, borrado y legal hold.
- Controlar uploads multipart, cuotas, checksum, reanudación y limpieza de cargas incompletas.
- Evitar servir contenido activo desde el mismo origen de la aplicación; aplicar headers y dominios aislados cuando proceda.
- Probar restauración, integridad, expiración de URLs, permisos, borrado y migración entre proveedores.

## 4. Antipatrones

- Adoptar herramientas sin requisitos ni evaluación de operación.
- Confiar en controles exclusivamente del cliente cuando el servidor debe hacer cumplir la regla.
- Registrar datos sensibles innecesarios o exponerlos en logs/telemetría.
- Ignorar fallos parciales, cambios de versión, límites de capacidad o dependencias externas.
- Considerar la existencia de documentación como prueba de implementación.

## 5. Verificación y evidencia

El proyecto DEBE definir pruebas automatizadas y controles manuales proporcionales al riesgo. Conservar resultados, configuración, responsables, excepciones y evidencias reproducibles. La conformidad se registra requisito por requisito en la matriz del proyecto.

## 6. Decisiones específicas

Las tecnologías, versiones, topologías, proveedores, umbrales y SLO se seleccionan en ADR o especificaciones del proyecto. No se heredan de ejemplos de esta biblioteca.

## 7. Revisión

Revisar ante cambios de alcance, amenazas, plataforma, proveedor, regulación, incidentes o evolución significativa del estándar.
