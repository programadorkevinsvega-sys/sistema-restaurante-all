# Estándar de machine learning y MLOps

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica a modelos predictivos, clasificación, ranking, entrenamiento y despliegue de modelos.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.
- Mantener responsabilidades, límites de confianza y propiedad explícitos.
- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.
- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Definir problema, población, métrica de éxito, baseline, restricciones y daños potenciales.
- Gobernar datasets: procedencia, consentimiento/base legal, calidad, linaje, versiones, sesgos y retención.
- Separar entrenamiento, validación, prueba y producción; evitar leakage y contaminación temporal.
- Versionar código, datos, features, parámetros, artefactos y entorno para reproducibilidad.
- Evaluar desempeño por segmentos, robustez, fairness pertinente, calibración y límites conocidos.
- Controlar registro, aprobación, despliegue gradual, rollback y compatibilidad de features.
- Monitorear drift de datos/concepto, calidad, latencia, costos y degradación; definir reentrenamiento controlado.
- Proteger endpoints y artefactos; evitar extracción, poisoning y acceso no autorizado.
- Mantener supervisión humana y mecanismo de apelación cuando la decisión afecte derechos o acceso.

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
