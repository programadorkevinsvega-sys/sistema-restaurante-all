# Estándar de segmentación de red y egress

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Limitar movimiento lateral, exposición accidental y acceso no autorizado entre componentes.

## Requisitos

- Clasificar redes y flujos por entorno, zona de confianza y función.
- Denegar tráfico por defecto y permitir solo flujos documentados.
- No exponer bases de datos, brokers, caches, administración, métricas ni control planes a Internet salvo justificación y controles reforzados.
- Separar plano de datos, administración, observabilidad y despliegue cuando sea viable.
- Restringir egress por proceso o workload; documentar destinos externos requeridos.
- Validar DNS y destinos de salida para reducir SSRF y exfiltración.
- Evitar credenciales compartidas como sustituto de segmentación.
- Proteger acceso administrativo con MFA, bastión o acceso privado equivalente y auditoría.
- Revisar reglas ante cambios de servicio y eliminar reglas temporales vencidas.

## Verificación

Escaneo de exposición, pruebas de conectividad permitida/denegada, revisión de egress y simulación de movimiento lateral.
