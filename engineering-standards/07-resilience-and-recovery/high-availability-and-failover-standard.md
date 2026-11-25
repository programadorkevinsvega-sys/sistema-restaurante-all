# Estándar de alta disponibilidad y failover

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Diseñar servicios que toleren fallos de componentes y recuperen capacidad dentro de objetivos definidos.

## Requisitos

- Definir SLI, SLO, presupuesto de error y alcance del servicio.
- Identificar dependencias críticas, dominios de fallo y puntos únicos de falla.
- Separar redundancia de proceso, zona, región, almacenamiento y plano de control según riesgo.
- Definir mecanismo de elección de líder, quórum y fencing cuando exista escritor único o coordinación distribuida.
- Evitar split-brain y escritores concurrentes no autorizados.
- Definir failover automático o manual, criterios, límites y autoridad.
- Diseñar clientes para reconexión, DNS/endpoints estables, drenaje y recuperación.
- Evaluar consistencia, lag, pérdida potencial de datos y comportamiento de lecturas durante failover.
- No declarar alta disponibilidad por tener réplicas sin probar cambio de rol y recuperación.
- Ejecutar pruebas de caos controladas y ejercicios operativos.
- Documentar degradación aceptable cuando una dependencia pierde capacidad.

## Dimensionamiento

Número de réplicas, quorum, RPO, RTO, latencia y capacidad deben derivarse del análisis de impacto, costo y pruebas; no existen valores universales.

## Verificación

Pruebas de caída de nodo, partición de red, pérdida de zona, failover, fencing, recuperación y consistencia posterior.
