# Estándar de accesibilidad y diseño inclusivo

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica a interfaces web, móviles, documentos y experiencias digitales; el nivel legal se determina por jurisdicción y contrato.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.
- Mantener responsabilidades, límites de confianza y propiedad explícitos.
- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.
- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Adoptar una versión y nivel de referencia explícitos de WCAG u otra norma aplicable; no declarar conformidad sin evaluación.
- Navegación completa por teclado, orden de foco lógico, foco visible, ausencia de trampas y enlaces descriptivos.
- Semántica correcta, nombres accesibles, roles/estados, estructura de encabezados y alternativas textuales.
- Contraste, zoom/reflow, tamaño de objetivos, movimiento reducido y no depender solo del color/sonido.
- Formularios con instrucciones, etiquetas, errores anunciables y recuperación.
- Compatibilidad con lectores de pantalla, ampliadores y tecnologías de asistencia.
- Multimedia con subtítulos/transcripciones y controles accesibles cuando aplique.
- Pruebas automáticas complementadas con revisión manual y pruebas con usuarios diversos; herramientas automáticas no bastan.
- Documentar excepciones, barreras conocidas, mitigación y plan de remediación.

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

## 8. Riesgos y escenarios de fallo específicos
Evaluar exclusión por discapacidad visual, auditiva, motora, cognitiva o neurológica; barreras en autenticación/pago; pérdida de foco; contenido dinámico no anunciado; contraste insuficiente; dependencia de gestos; movimiento dañino y documentos descargables inaccesibles.

## 9. Pruebas de aceptación mínimas
- Seleccionar versión y nivel de WCAG aplicable y mapear criterios pertinentes por flujo.
- Completar tareas críticas solo con teclado, sin trampas y con foco visible/lógico.
- Probar lectores de pantalla y tecnologías de asistencia en plataformas representativas.
- Verificar zoom/reflow, contraste, objetivos táctiles, movimiento reducido, subtítulos y transcripciones.
- Probar formularios, errores, autenticación, recuperación y mensajes dinámicos anunciables.
- Combinar escáner automatizado, inspección manual y pruebas con usuarios; documentar límites y barreras residuales.

## 10. Operación y evidencias
Conservar matriz de criterios, versión normativa, reportes automáticos/manuales, sesiones de prueba, issues de barreras, excepciones aprobadas y evidencia de remediación.