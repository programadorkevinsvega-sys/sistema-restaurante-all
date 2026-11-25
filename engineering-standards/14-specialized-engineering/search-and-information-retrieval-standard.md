# Estándar de búsqueda y recuperación de información

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica a búsqueda textual, filtros, facetas, índices, ranking y recuperación semántica.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.
- Mantener responsabilidades, límites de confianza y propiedad explícitos.
- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.
- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Definir fuentes autoritativas, latencia de indexación, consistencia, retención y estrategia de reconstrucción.
- Aplicar autorización y tenant scoping antes de exponer resultados; el índice no debe ampliar permisos.
- Definir normalización, idioma, stemming, sinónimos, tokenización, typo tolerance y privacidad de consultas.
- Diseñar paginación estable, límites, filtros permitidos y prevención de consultas costosas.
- Gestionar datos personales y sensibles en índices, logs, snapshots y réplicas.
- Documentar ranking, relevancia, sesgos, resultados vacíos y explicación cuando sea importante.
- Mantener versionado de mappings/analyzers, reindexación blue-green y rollback.
- Probar relevancia con conjuntos representativos, autorización, borrado, frescura, carga y consultas adversariales.

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
