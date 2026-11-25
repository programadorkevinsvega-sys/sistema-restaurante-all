# Estándar de carga y procesamiento de archivos

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Tratar todo archivo, documento, imagen, archivo comprimido y contenido importado como entrada no confiable.

## Requisitos

- Aplicar límites de tamaño, cantidad, dimensiones, duración, profundidad y ratio de descompresión.
- Validar extensión, MIME declarado y firma/contenido real; ninguno por separado es suficiente.
- Generar nombres de almacenamiento controlados por servidor y evitar rutas suministradas por el usuario.
- Almacenar fuera del webroot o en almacenamiento privado con autorización de descarga.
- Aplicar permisos por tenant, propietario, clasificación y finalidad.
- Escanear malware y considerar sandbox/CDR para formatos de riesgo.
- Deshabilitar ejecución y renderizado activo no necesario.
- Evitar SSRF al descargar URLs o procesar referencias remotas.
- Proteger parsers, conversores, OCR y generadores de previews en entornos aislados y limitados.
- Mantener trazabilidad de hash, origen, estado de análisis y transformaciones cuando aplique.
- Definir retención, eliminación, cuarentena y acceso temporal.
- No confiar en el nombre original ni en metadata incrustada.

## Verificación

Pruebas de traversal, polyglots, MIME spoofing, ZIP bombs, archivos corruptos, malware de prueba, permisos cruzados y descarga expirada.
