# ADR-0006: AI como capacidad transversal sin schema propio en esta etapa

- Estado: **Accepted**
- Historial: Proposed → Accepted
- Propuesto: 2026-11-24
- Aceptado: 2026-11-24
- Aprobación: propietario del producto, confirmada explícitamente en la conversación de arquitectura.

## Contexto

AI aporta capacidades transversales a distintos dominios, pero actualmente no existe un caso aprobado que justifique un módulo propietario, persistencia centralizada ni un schema PostgreSQL independiente. Asignarle un schema o tablas por anticipado crearía ownership y migraciones sin una responsabilidad de datos concreta.

## Decisión

1. AI es una capacidad transversal accesible por un puerto/contrato; no es un dominio propietario ni un módulo independiente en esta etapa.
2. AI no tiene schema PostgreSQL, tablas ni migraciones propios por ahora.
3. Cada módulo conserva la propiedad y persistencia de los datos de sus propios procesos y funcionalidades. AI accede a esos datos mediante contratos y herramientas autorizadas; no consulta ni modifica directamente schemas ajenos.
4. Si un módulo necesita persistir resultados, contexto o referencias para su proceso, los guarda bajo su propio ownership y aplica sus reglas de tenant, autorización, auditoría y retención.
5. No se crean por anticipado tablas centrales de conversaciones, configuración de modelos o consumo de IA.
6. Si aparece una necesidad concreta de persistencia compartida —por ejemplo, conversaciones, configuración centralizada o medición de consumo por tenant—, se propone un ADR nuevo que defina el módulo propietario, sus responsabilidades, schema, límites y contratos antes de implementarlo.
7. AI debe respetar los mismos permisos, alcance de tenant/sucursal y auditoría exigidos a las acciones humanas y a los módulos que expongan herramientas.

## Consecuencias

- No existe un schema `ai` en la arquitectura actual.
- No deben añadirse migraciones ni tablas AI en esta etapa.
- Los módulos conservan sus datos y responsabilidades; AI no absorbe ni duplica datos de SALES, INVENTORY, FINANCE, ANALYTICS u otros dominios.
- Una futura plataforma AI con persistencia propia requerirá una decisión arquitectónica separada y aprobada.

## Alternativas

- Crear un schema AI desde el inicio para conversaciones, configuración y uso: rechazado por falta de un caso de persistencia aprobado.
- Permitir que AI consulte o escriba directamente en schemas de otros módulos: rechazado por violar ownership y límites de dominio.

## Estado de implementación

Decisión arquitectónica aceptada. No demuestra que exista un puerto AI, proveedores de modelos, herramientas, almacenamiento ni infraestructura implementados.
