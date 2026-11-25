# Estándar de caché distribuida

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Reducir latencia y carga de origen sin convertir la caché en fuente de verdad accidental.

## Requisitos

- Definir para cada dato cacheado propietario, fuente autoritativa, tolerancia a obsolescencia y estrategia de invalidación.
- Aplicar cache-aside u otro patrón explícito; no cachear indiscriminadamente cada consulta.
- Usar claves determinísticas, versionadas y con ámbito de tenant, identidad, permisos, idioma, moneda y filtros cuando afecten el resultado.
- No incluir datos sensibles por defecto; cifrar o evitar cachear cuando el riesgo lo exija.
- Establecer TTL finito, jitter, límites de tamaño y política de expulsión.
- Evitar cache stampede mediante single-flight, locks acotados, stale-while-revalidate o técnicas equivalentes.
- La invalidación debe ser confiable y resistente a duplicados y eventos fuera de orden.
- Prevenir stale refill cuando una lectura antigua termine después de una invalidación.
- Las operaciones críticas de autorización, pagos, saldos y disponibilidad no deben depender de una copia obsoleta salvo política explícita.
- La caída de caché debe tener fallback seguro y limitado; no provocar avalancha sobre el origen.
- Definir aislamiento, ACL, TLS, rotación y monitoreo.

## Verificación

Pruebas de invalidación, expiración, concurrencia, stampede, cache poisoning, aislamiento entre usuarios/tenants y caída del clúster.
