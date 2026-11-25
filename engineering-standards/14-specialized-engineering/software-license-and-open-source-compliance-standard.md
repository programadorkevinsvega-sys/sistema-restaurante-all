# Estándar de licencias de software y cumplimiento open source

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica a dependencias, código, modelos, fuentes, imágenes, datasets y artefactos de terceros.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.

- Mantener responsabilidades, límites de confianza y propiedad explícitos.

- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.

- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Inventariar dependencias directas/transitivas y sus licencias; generar SBOM cuando corresponda.

- Revisar compatibilidad de licencias con distribución, modificación, SaaS, uso comercial y obligaciones de atribución.

- Prohibir incorporar componentes sin licencia clara o con restricciones incompatibles sin aprobación legal.

- Registrar avisos, copyright, NOTICE, modificaciones y fuentes exigidas.

- Revisar licencias de modelos, datasets, fuentes tipográficas, imágenes, SDK y contenido.

- Definir proceso de aprobación, excepción, reemplazo y respuesta ante cambios de licencia.

- Escanear dependencias y artefactos de forma automatizada; conservar evidencia por release.

- No interpretar el uso público de un repositorio como permiso ilimitado.

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

## 8. Riesgos específicos y controles de distribución

Evaluar obligaciones copyleft, atribución, redistribución de binarios, modificaciones, linking, SaaS/network use, patentes, marcas, fuentes de datos, derechos de imagen, modelos y restricciones territoriales. No resolver interpretaciones legales complejas mediante inferencia del agente.

## 9. Pruebas de aceptación mínimas

- Generar inventario/SBOM por artefacto distribuible y reconciliarlo con lockfiles.

- Bloquear releases con componentes sin licencia identificada o política de aprobación incumplida.

- Verificar avisos, NOTICE, atribuciones, fuentes y ofertas de código cuando la licencia lo exija.

- Probar detección de dependencia nueva/transitiva y cambio de licencia o versión.

- Verificar procedencia y términos de datasets, modelos, fuentes, imágenes, SDK y contenido incorporado.

- Registrar revisión legal para licencias incompatibles, ambiguas o de alto impacto.

## 10. Operación y evidencias

Conservar SBOM por release, reportes de escaneo, decisiones de aprobación, notices publicados, excepciones, procedencia de componentes y revisión legal documentada.
