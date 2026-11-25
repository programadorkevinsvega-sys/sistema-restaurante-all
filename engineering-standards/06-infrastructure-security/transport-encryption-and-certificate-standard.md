# Estándar de cifrado de transporte y certificados

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Proteger confidencialidad, integridad y autenticidad de comunicaciones.

## Requisitos

- Usar TLS moderno soportado y deshabilitar protocolos/cifrados obsoletos.
- Validar cadena, nombre, propósito y vigencia de certificados; no desactivar verificación para resolver errores.
- Usar autenticación mutua cuando el riesgo y la arquitectura lo requieran.
- Proteger tráfico interno, replicación, administración, brokers, bases de datos y servicios externos.
- Gestionar emisión, almacenamiento, renovación, rotación y revocación.
- Automatizar renovación antes de expiración y alertar por fallos.
- Proteger claves privadas y evitar que aparezcan en logs o artefactos.
- Documentar terminación TLS, saltos de confianza y cifrado extremo a extremo cuando aplique.
- Evaluar cifrado en reposo por clasificación y modelo de amenazas; TLS no lo sustituye.

## Verificación

Escaneo TLS, pruebas de certificado inválido/expirado, rotación sin interrupción y validación de mTLS.
