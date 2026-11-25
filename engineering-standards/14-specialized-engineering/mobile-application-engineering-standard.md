# Estándar de ingeniería de aplicaciones móviles

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica a clientes nativos, multiplataforma o híbridos en dispositivos móviles.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.
- Mantener responsabilidades, límites de confianza y propiedad explícitos.
- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.
- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Definir plataformas, versiones mínimas, ciclo de soporte y estrategia de actualización.
- Aplicar almacenamiento seguro del sistema operativo para credenciales; evitar secretos embebidos y almacenamiento plano de tokens.
- Solicitar permisos en contexto, con minimización, explicación y manejo de denegación/revocación.
- Proteger deep links, universal links, intents, IPC y superficies expuestas.
- Usar TLS con validación normal de certificados; no desactivar validación para resolver errores.
- Gestionar ciclo de vida, procesos terminados, restauración de estado, batería y conectividad variable.
- Definir telemetría respetuosa de privacidad, crash reporting y redacción de datos.
- Probar dispositivos, tamaños, densidades, versiones, accesibilidad, actualización y distribución segura.
- Revisar almacenamiento local, backups del dispositivo, capturas de pantalla y datos sensibles según amenaza.

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
