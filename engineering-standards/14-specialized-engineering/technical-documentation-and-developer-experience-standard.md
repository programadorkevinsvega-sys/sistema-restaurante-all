# Estándar de documentación técnica y experiencia de desarrollo

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica a documentación de arquitectura, APIs, operación, contribución y onboarding.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.
- Mantener responsabilidades, límites de confianza y propiedad explícitos.
- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.
- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Mantener documentación cerca del artefacto responsable y definir dueño, audiencia, estado y fecha de revisión.
- Distinguir normativa, guía, tutorial, referencia, decisión, especificación y material histórico.
- Documentar quickstart reproducible, prerequisitos, configuración, pruebas y solución de problemas.
- Mantener diagramas como código o fuentes editables cuando sea viable; evitar diagramas obsoletos.
- Generar referencias API desde contratos cuando proceda y evitar duplicación manual divergente.
- Incluir ejemplos seguros, no usar secretos ni datos reales; marcar placeholders claramente.
- Probar enlaces, snippets y pasos críticos en CI o revisiones periódicas.
- Definir onboarding, estándares de contribución, ownership y proceso de actualización.
- Archivar o marcar contenido obsoleto sin borrarlo silenciosamente si conserva valor histórico.

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
