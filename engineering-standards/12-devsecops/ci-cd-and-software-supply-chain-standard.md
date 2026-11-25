# Estándar de CI/CD y cadena de suministro de software

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Producir artefactos reproducibles, verificables y desplegables sin exponer credenciales ni permitir alteraciones no autorizadas.

## Requisitos

- Los workflows deben tener permisos mínimos y tokens de alcance reducido.
- Separar validación de código no confiable de jobs privilegiados de publicación/despliegue.
- Fijar acciones y dependencias críticas a versiones inmutables o commits verificados cuando sea posible.
- Proteger secretos mediante entornos, aprobaciones y gestores dedicados.
- Construir artefactos una sola vez y promover el mismo artefacto entre entornos.
- Registrar commit, dependencias, builder, configuración, digest y procedencia.
- Mantener SBOM y escaneo de artefactos.
- Firmar artefactos y verificar firmas en despliegue cuando el ecosistema lo permita.
- Proteger releases, tags, paquetes y registros.
- Definir rollback o roll-forward y verificar health antes de completar despliegue.
- No desplegar automáticamente desde ramas o eventos que permitan ejecución de código no confiable con credenciales de producción.
- Mantener logs de auditoría de quién aprobó, construyó y desplegó.

## Reproducibilidad y supply chain

Preferir builds herméticos y dependencias fijadas. Registrar fuentes, hashes y licencias. Evitar scripts remotos no verificados durante build o runtime.

## Verificación

Pruebas de permisos, exposición de secretos, firma/verificación, provenance, despliegue progresivo y recuperación.
