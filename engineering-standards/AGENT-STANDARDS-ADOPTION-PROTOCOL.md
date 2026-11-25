# Protocolo obligatorio de consulta y adopción de estándares para agentes

**Versión:** 0.2.0 | **Estado:** Draft | **Audiencia:** agentes de IA, asistentes de ingeniería y automatizaciones

## 1. Propósito

Impedir que un agente comience a diseñar o implementar un sistema sin descubrir, presentar y registrar los estándares relevantes de la biblioteca. El agente debe actuar como facilitador de decisiones, no como propietario silencioso de las decisiones del producto.

## 2. Regla de entrada obligatoria

Antes de proponer arquitectura definitiva, crear código funcional, generar infraestructura, modificar esquemas o iniciar implementación, el agente DEBE:

1. Identificar la versión de biblioteca disponible.
2. Leer el catálogo maestro y el protocolo.
3. Recorrer todos los índices de áreas y sus estándares.
4. Revisar el perfil del proyecto y las decisiones ya tomadas.
5. Construir una lista de temas aplicables, condicionales y brechas.
6. Presentar al propietario las decisiones necesarias.
7. Registrar el resultado en el registro de adopción.
8. Confirmar qué estándares se adoptan y cuáles requieren investigación o ADR.

La consulta no debe convertirse en un interrogatorio interminable: agrupar temas relacionados, explicar consecuencias y preguntar por bloques comprensibles. Sin embargo, no se permite omitir una familia del catálogo por conveniencia.

## 3. No asumir ni inventar decisiones

El agente NO DEBE:
- asumir que una tecnología se adopta porque aparece en un ejemplo;
- convertir una recomendación en requisito obligatorio sin aprobación;
- declarar no aplicable un estándar sin fundamento;
- interpretar silencio como consentimiento;
- inventar restricciones, presupuesto, escala, jurisdicción o SLO;
- cambiar decisiones previas aceptadas sin proceso formal;
- empezar implementación de una decisión arquitectónica material que siga pendiente;
- confundir un ADR aprobado con una capacidad ya implementada;
- presentar una brecha documental como si estuviera cubierta.

El agente DEBE identificar conflictos entre decisiones existentes, estándares y requisitos; explicar precedencia documental y solicitar resolución cuando no exista regla suficiente.

## 4. Descubrimiento del proyecto

Como mínimo, recopilar o confirmar:
- propósito, usuarios, actores y procesos críticos;
- tipo de producto y dominios funcionales;
- interfaces: web, móvil, API, escritorio, dispositivos o integraciones;
- modelo de despliegue y operación;
- exposición pública, límites de confianza y dependencias externas;
- clases de datos, sensibilidad, propiedad, residencia y retención;
- países, jurisdicciones y obligaciones aplicables;
- criticidad, impacto de indisponibilidad y pérdida/corrupción de datos;
- concurrencia, volumen, crecimiento, latencia y disponibilidad esperados;
- conectividad, offline, tiempo real y requisitos de sincronización;
- tecnologías existentes, experiencia del equipo y restricciones de plataforma;
- presupuesto, plazo, equipo operativo y tolerancia a complejidad;
- objetivos de recuperación, soporte y ciclo de vida.

Si un dato no se conoce, registrarlo como desconocido y explicar qué decisión depende de él.

## 5. Recorrido de catálogo

El agente debe presentar las familias del [catálogo maestro](./MASTER-STANDARDS-CATALOG.md) en su totalidad. Para cada estándar:
- explicar en lenguaje claro qué riesgo o necesidad cubre;
- indicar escenarios en los que aplica;
- señalar costo, complejidad y dependencias;
- mostrar alternativas cuando existan;
- proponer una clasificación preliminar razonada;
- pedir confirmación cuando implique una decisión de producto, costo, riesgo, privacidad o arquitectura.

Para catálogos extensos se puede realizar el recorrido por etapas, pero el registro debe mostrar todas las filas y estados. La interfaz conversacional puede agrupar preguntas, no borrar elementos.

## 6. Clasificación de cada estándar

Usar solo los estados definidos en el catálogo:
- Adoptado.
- Adoptado con adaptación.
- Aplazado.
- No aplicable.
- Rechazado.
- Pendiente de decisión.
- Brecha de biblioteca.

Toda clasificación debe incluir motivo, responsable, versión, fecha, evidencia o acción requerida. Aplazado exige fecha objetivo, mitigación y riesgo temporal. No aplicable exige condición de reevaluación. Rechazado exige decisión explícita y análisis de consecuencias.

## 7. Preguntas al propietario

El agente debe preguntar, según el contexto:
- ¿Este control o capacidad es necesario para el alcance y nivel de riesgo?
- ¿Qué nivel de protección/disponibilidad/consistencia se necesita?
- ¿Qué alternativa prefiere el propietario, considerando costos y operación?
- ¿Qué restricciones o proveedores ya están comprometidos?
- ¿Se acepta el riesgo residual de aplazar o rechazar el estándar?

No preguntar repetidamente decisiones ya registradas. Mostrar la decisión previa y pedir confirmación solo si cambió el contexto o hay contradicción.

## 8. Decisiones y artefactos

Después de la selección, el agente debe producir:
- perfil del proyecto;
- registro de adopción completo;
- matriz de conformidad;
- lista de brechas de biblioteca;
- ADR para decisiones técnicas materiales;
- mapa de requisitos, responsables, tareas, pruebas y evidencias;
- lista de decisiones bloqueantes y supuestos explícitos.

El agente no debe crear un ADR para cada requisito trivial. Los ADR registran decisiones con alternativas y consecuencias; los requisitos se gestionan en especificaciones y matrices.

## 9. Puertas antes de implementación

No comenzar la implementación de una capacidad cuando:
- su requisito de seguridad o privacidad crítico está sin resolver;
- existe contradicción arquitectónica sin decisión;
- la tecnología elegida no está aprobada;
- faltan criterios de aceptación verificables;
- se desconoce un requisito legal material para el tratamiento previsto;
- hay un riesgo crítico sin dueño ni mitigación.

El agente puede avanzar en investigación, prototipos aislados o documentación no comprometida si delimita claramente el alcance y no simula una aprobación.

## 10. Durante la construcción

Para cada estándar adoptado:
- vincular requisitos a componentes y tareas;
- añadir pruebas automatizadas o controles manuales apropiados;
- conservar evidencia y resultados;
- revisar desviaciones y excepciones;
- actualizar el registro cuando cambie el alcance;
- no marcar como conforme solo porque existe código o documentación.

## 11. Reevaluación obligatoria

Reabrir el análisis cuando cambien dominios, datos, jurisdicción, exposición, arquitectura, proveedor, volumen, criticidad, conectividad, amenazas, regulación o modelo de operación; también después de incidentes relevantes.

## 12. Salida mínima del agente

Antes de implementar, presentar un resumen que incluya:
1. alcance y perfil;
2. estándares adoptados;
3. estándares adaptados;
4. aplazados y riesgos temporales;
5. no aplicables/rechazados y razones;
6. pendientes que bloquean;
7. brechas de biblioteca;
8. ADR requeridos;
9. pruebas y evidencias esperadas.

## 13. Regla final

**Ningún estándar puede desaparecer del análisis sin un estado y una razón.** La decisión final corresponde al propietario del proyecto, dentro de las obligaciones legales, contractuales y de seguridad que no puedan ser dispensadas por preferencia.
