# Registro de adopción de estándares del proyecto

**Plantilla:** copiar a la documentación del proyecto consumidor. No editar el catálogo compartido para registrar decisiones particulares.

## 1. Identificación
| Campo | Valor |
|---|---|
| Proyecto | [nombre] |
| Propietario | [responsable] |
| Responsable técnico | [responsable] |
| Versión de biblioteca | [semver + commit/tag] |
| Versión de inventario | [versión + commit/tag] |
| Fecha de evaluación | [AAAA-MM-DD] |
| Próxima revisión | [AAAA-MM-DD] |
| Perfil de riesgo | [base/elevado/crítico/distribuido/mixto] |
| Estado del registro | [borrador/en revisión/aprobado] |

## 2. Resumen ejecutivo
- Propósito y alcance:
- Usuarios y actores:
- Dominios:
- Interfaces:
- Modelo de despliegue:
- Jurisdicciones:
- Tipos y sensibilidad de datos:
- Criticidad y objetivos de recuperación:
- Restricciones y presupuesto:
- Supuestos desconocidos:

## 3. Registro exhaustivo obligatorio

**No construir esta tabla a mano desde memoria.** Copiar todas las filas STD-* y TOP-* de [STANDARDS-COVERAGE-AND-TOPIC-REGISTER.md](./STANDARDS-COVERAGE-AND-TOPIC-REGISTER.md). Debe existir una fila por cada ID, sin omisiones, duplicados ni IDs inventados. La versión 0.3.0 del inventario contiene 67 estándares documentales y 91 temas: 158 elementos que requieren evaluación. Si cambia el inventario, usar el conteo de la versión fijada.

| ID | Elemento | Versión | Aplicabilidad | Disparador/evidencia | Estado de adopción | Justificación/impacto | Responsable | ADR/acción/evidencia | Fecha objetivo/revisión |
|---|---|---|---|---|---|---|---|---|---|
| [copiar cada ID] | | | Aplica / Condicional / No aplica | | [estado permitido] | | | | |

**Estados de adopción:** Adoptado, Adoptado con adaptación, Aplazado, No aplicable, Rechazado, Pendiente de decisión, Brecha de biblioteca.

Reglas:
- No aplicable requiere aplicabilidad No aplica, justificación verificable y disparador de reevaluación.
- Condicional exige describir disparador, evidencia y resultado.
- Aplazado exige responsable, fecha objetivo, riesgo temporal y control compensatorio.
- Rechazado requiere decisión expresa del propietario, motivo, consecuencias y mitigación.
- Pendiente identifica quién decide, fecha límite y trabajo bloqueado.
- Brecha identifica tema, insuficiencia, investigación/estándar faltante, responsable y fecha.
- No dejar celdas vacías ni utilizar N/A sin explicación.
- Aplicabilidad y estado de adopción son columnas obligatorias e independientes.

## 4. Decisiones pendientes
| Decisión | Por qué importa | Opciones | Impacto de esperar | Quién decide | Fecha límite |
|---|---|---|---|---|---|

## 5. Aplazamientos y riesgos temporales
| ID estándar/tema | Riesgo aceptado | Control compensatorio | Responsable | Fecha objetivo | Condición de escalamiento |
|---|---|---|---|---|---|

## 6. No aplicabilidad y rechazos
Para cada caso registrar alcance analizado, criterio, evidencia, motivo, consecuencias, riesgo residual, disparador de reevaluación y propietario que acepta la decisión.

## 7. Brechas de biblioteca
| ID TOP | Tema | Necesidad | Documento/controles faltantes | Investigación/acción | Responsable | Fecha |
|---|---|---|---|---|---|---|

## 8. Trazabilidad de conformidad
| Requisito | ID estándar/tema y versión | Componente | Control implementado | Prueba | Evidencia | Resultado |
|---|---|---|---|---|---|---|

## 9. Excepciones
Referenciar el registro formal de excepciones con alcance, aprobación, compensaciones, fecha de expiración y plan de cierre. No duplicar ni ocultar excepciones.

## 10. Aprobaciones
| Rol | Nombre | Decisión | Fecha | Referencia |
|---|---|---|---|---|
| Propietario del producto | | | | |
| Responsable de arquitectura | | | | |
| Seguridad/privacidad, si aplica | | | | |
| Operaciones, si aplica | | | | |

## 11. Historial
| Versión | Fecha | Cambio | Autor |
|---|---|---|---|
| 0.1 | | Creación | |
| 0.2 | | Inventario exhaustivo e IDs estables; separación de dimensiones | |
