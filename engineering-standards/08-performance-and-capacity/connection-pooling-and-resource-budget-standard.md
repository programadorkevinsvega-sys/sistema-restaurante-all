# Estándar de pooling y presupuesto de recursos

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Controlar conexiones, threads, memoria, sockets y concurrencia para evitar saturación de servicios y dependencias.

## Requisitos

- Definir propietario y alcance de cada pool.
- Calcular conexiones máximas agregadas considerando réplicas, procesos, workers, jobs y operaciones administrativas.
- Reservar capacidad para migraciones, monitoreo, failover y tareas de emergencia.
- Definir límites de espera, adquisición, vida útil, inactividad y conexiones máximas.
- Evitar crear pools sin límite por tenant o petición.
- Separar rutas de lectura y escritura solo si hay estrategia de consistencia y permisos adecuados.
- Limitar concurrencia de workers y proveedores externos.
- Medir saturación, espera, timeout, conexiones activas/inactivas y errores.
- Ajustar pools mediante pruebas representativas, no por valores arbitrarios.
- Evitar mantener conexiones/transacciones abiertas durante procesamiento CPU-bound o llamadas remotas largas.

## Presupuesto

El presupuesto debe incluir todos los procesos y réplicas, no solo el límite configurado en una instancia. El dimensionamiento debe considerar picos, failover y margen operativo.

## Verificación

Pruebas de carga, agotamiento, failover, picos, reconexión y comprobación de límites globales.
