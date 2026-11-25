# Estándar de internacionalización y localización

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica cuando usuarios, datos, monedas, idiomas o jurisdicciones trascienden una única convención regional.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.

- Mantener responsabilidades, límites de confianza y propiedad explícitos.

- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.

- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Separar textos traducibles de código y mantener catálogos de mensajes con claves estables y contexto.

- Usar Unicode y formatos regionales para fechas, horas, números, direcciones, nombres, unidades y monedas.

- No asumir formatos, género, orden de nombres, calendario, separadores ni códigos postales universales.

- Gestionar zonas horarias con identificadores IANA; almacenar instantes inequívocos y distinguir fecha civil de timestamp.

- Manejar pluralización, género gramatical, texto dinámico, expansión y direccionalidad RTL.

- Definir moneda y precisión; no usar float binario para importes financieros.

- Traducir contenido legal y transaccional con revisión competente; registrar versión y jurisdicción.

- Probar locales representativos, formatos extremos, cambios DST, texto largo y fallback de traducciones.

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

## Riesgos y escenarios de fallo específicos

Evaluar ambigüedad de fecha/hora, transición DST, doble conversión de zona, pérdida de precisión monetaria, traducción legal incorrecta, pluralización errónea, truncamiento, RTL mal renderizado y datos regionales interpretados con locale incorrecto.

## Pruebas de aceptación mínimas

- Probar fechas civiles, instantes UTC, zonas IANA y cambios DST (hora inexistente/repetida).

- Verificar números, moneda, redondeo, unidades, calendarios, nombres y direcciones en locales objetivo.

- Probar plurales, género gramatical, texto largo, expansión, fallback y RTL.

- Confirmar que reglas de negocio usan valores normalizados y no dependen del formato de presentación.

- Revisar por persona competente traducciones legales, financieras y de seguridad antes de publicar.

## Operación y evidencias

Conservar matriz de locales, fuentes de traducción, glosario, revisiones, pruebas automatizadas por locale, versión de contenido legal y plan de actualización.
