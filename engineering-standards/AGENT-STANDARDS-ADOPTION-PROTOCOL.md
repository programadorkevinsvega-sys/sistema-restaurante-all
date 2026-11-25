# Protocolo obligatorio de consulta y adopción de estándares para agentes

**Versión:** 0.3.0 | **Estado:** Draft | **Audiencia:** agentes de IA, asistentes de ingeniería y automatizaciones

## 1. Propósito
Impedir que un agente comience a diseñar o implementar un sistema sin descubrir, presentar y registrar los estándares relevantes de la biblioteca. El agente facilita decisiones; no es propietario silencioso de las decisiones del producto.

## 2. Puerta de entrada obligatoria

Antes de proponer arquitectura definitiva, crear código funcional, generar infraestructura, modificar esquemas o iniciar implementación, el agente DEBE:
1. Identificar versión, tag/commit y fecha de la biblioteca.
2. Leer README, catálogo, este protocolo, gobernanza e [inventario exhaustivo](./STANDARDS-COVERAGE-AND-TOPIC-REGISTER.md).
3. Recorrer todos los documentos normativos y temas de descubrimiento enumerados en el inventario fijado. La versión 0.3.0 contiene 66 documentos normativos y 92 temas (158 elementos); otras versiones deben usar el conteo real.
4. Leer completos los documentos aplicables y relacionados con el perfil, no limitarse a títulos o resúmenes.
5. Revisar perfil del proyecto, decisiones aceptadas, requisitos, restricciones y riesgos ya documentados.
6. Crear una fila por cada ID STD-* y TOP-*, sin omisiones ni duplicados.
7. Separar aplicabilidad de estado de adopción y presentar al propietario las decisiones materiales.
8. Registrar respuesta, responsable, razón, evidencia, fecha y ADR/acción relacionada.
9. Identificar brechas documentales y proponer investigación o nuevos estándares.
10. Confirmar qué decisiones bloquean diseño o implementación.

La consulta puede agrupar preguntas, pero no puede agrupar ni borrar filas del registro. No se permite muestreo de familias.

## 3. No asumir ni inventar decisiones

El agente NO DEBE asumir tecnologías por ejemplos, convertir recomendaciones en requisitos sin aprobación, declarar no aplicabilidad sin fundamento, interpretar silencio como consentimiento, inventar restricciones, cambiar decisiones aceptadas sin proceso, iniciar implementación material pendiente, confundir ADR aprobado con capacidad implementada, presentar brechas como cubiertas ni declarar conformidad por existir documentación/código/configuración.

El agente DEBE identificar conflictos entre decisiones, estándares y requisitos; explicar precedencia y solicitar resolución.

## 4. Descubrimiento del proyecto

Confirmar propósito, usuarios, dominios, interfaces, despliegue, exposición, límites de confianza, dependencias, clases de datos, sensibilidad, propiedad, residencia, retención, jurisdicciones, criticidad, impactos, concurrencia, volumen, latencia, disponibilidad, conectividad, offline, tiempo real, tecnologías, capacidades del equipo, presupuesto, plazo, RTO/RPO, soporte y ciclo de vida.

Si un dato se desconoce, registrarlo como desconocido y explicar qué decisiones dependen de él. La falta de información no equivale a No aplica.

## 5. Recorrido e inventario

Presentar todas las familias A–J y todas las filas del inventario. Por cada estándar y tema:
- explicar riesgo/necesidad, alcance y disparadores;
- indicar requisitos y escenarios de aplicación;
- señalar costos, complejidad, dependencias y alternativas;
- verificar si existe cobertura dedicada o solo transversal/parcial;
- proponer clasificación preliminar con fundamento;
- pedir confirmación en decisiones materiales de producto, costo, riesgo, privacidad o arquitectura.

El inventario es la lista de control canónica. Cada ID debe tener fila individual aunque el propietario responda por bloques.

## 6. Clasificación en dos dimensiones

**Aplicabilidad:** Aplica, Condicional o No aplica. Condicional exige disparador y evidencia. No aplica exige justificación y disparador de reevaluación.

**Estado de adopción:** Adoptado, Adoptado con adaptación, Aplazado, No aplicable, Rechazado, Pendiente de decisión o Brecha de biblioteca.

No aplicable como estado solo es válido cuando aplicabilidad = No aplica. Rechazado se usa cuando aplica y el propietario decide no adoptarlo. Aplazado requiere fecha objetivo, responsable, riesgo temporal y controles compensatorios. Brecha requiere acción de investigación/documentación.

Cada fila incluye ID, versión, aplicabilidad, estado, justificación, responsable, fecha, evidencia/ADR y revisión siguiente. No se aceptan vacíos, omitidos ni valores por defecto.

## 7. Preguntas al propietario

Preguntar según contexto sobre necesidad y riesgo, nivel de protección/disponibilidad/consistencia, alternativas y costos, restricciones/proveedores y aceptación de riesgo residual. Mostrar decisiones previas; no repetir salvo cambio o contradicción. El silencio nunca es aprobación.

## 8. Artefactos requeridos

Producir perfil, registro completo con todos los IDs, matriz de conformidad requisito-control-prueba-evidencia, lista de brechas con owner y fecha, ADR para decisiones materiales, mapa de requisitos/responsables/tareas/pruebas/evidencias y lista de decisiones bloqueantes/supuestos/riesgos. No crear ADR para cada requisito trivial.

## 9. Puertas antes de implementación

No iniciar implementación de una capacidad cuando su requisito crítico de seguridad/privacidad no esté resuelto, exista contradicción arquitectónica sin decisión, tecnología material no aprobada, falten criterios verificables, se desconozca requisito legal material o exista riesgo crítico sin dueño/mitigación. Se permite investigación o prototipos aislados si se delimitan y no simulan aprobación.

## 10. Durante construcción y operación

Vincular cada requisito adoptado a componente/tarea, control, prueba y evidencia. Conservar resultados reproducibles; revisar excepciones, expiraciones y desviaciones; actualizar registro ante cambios. Verificar en diseño, CI, preproducción, producción y operación según riesgo. No marcar conforme solo por intención.

## 11. Reevaluación obligatoria

Reabrir análisis ante cambios de dominio, datos, jurisdicción, exposición, arquitectura, proveedor, volumen, criticidad, conectividad, amenazas, regulación, equipo, operación o incidentes. Comparar versiones del inventario y procesar cada ID nuevo, modificado o retirado.

## 12. Salida mínima antes de implementar

Presentar alcance/perfil; inventario y cobertura revisados; adoptados; adaptados; aplazados y riesgos; no aplicables/rechazados con razones; pendientes bloqueantes; brechas; ADR; controles, pruebas y evidencias.

## 13. Regla final

**Ningún estándar ni tema puede desaparecer del análisis sin ID, aplicabilidad, estado y razón.** La decisión corresponde al propietario dentro de obligaciones legales, contractuales y de seguridad no dispensables.
