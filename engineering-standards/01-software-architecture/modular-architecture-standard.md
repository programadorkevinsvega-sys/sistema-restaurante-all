# Estándar de arquitectura modular

**Versión:** 0.1.0 | **Estado:** Draft  
**Aplicabilidad:** sistemas con dominios o capacidades que requieren evolución independiente.

## Objetivo

Evitar acoplamiento accidental y mantener límites explícitos entre capacidades del sistema, incluso cuando se desplieguen inicialmente en un solo proceso.

## Principios

- Alta cohesión dentro de cada módulo y bajo acoplamiento entre módulos.
- Un módulo tiene una responsabilidad principal y un propietario técnico/funcional identificable.
- La implementación interna no constituye una API pública.
- Las dependencias deben apuntar a contratos estables y permitidos.
- Las decisiones de separación física se basan en necesidades verificables, no en el número de carpetas.

## Requisitos

- Cada módulo DEBE declarar propósito, responsabilidades, datos que posee, contratos expuestos y dependencias permitidas.
- Un módulo NO DEBE leer o escribir directamente la persistencia privada de otro módulo.
- Las dependencias entre módulos deben pasar por contratos explícitos.
- No se deben crear ciclos de dependencias.
- Los tipos de dominio no deben trasladarse a paquetes compartidos genéricos solo para evitar definir contratos.
- Las utilidades compartidas deben ser técnicas, neutrales y sin reglas de negocio.
- Las operaciones internas deben conservar la frontera de autorización y validación.
- Los cambios de contrato deben gestionarse con compatibilidad y pruebas.

## Monolito modular y servicios distribuidos

Un monolito modular puede ser la opción preferida cuando el equipo, carga y operación no justifican distribución. Los límites internos deben diseñarse para que la extracción futura sea posible, pero no se debe anticipar complejidad distribuida sin necesidad.

La extracción a un servicio separado exige evaluar latencia, disponibilidad, consistencia, despliegue, seguridad, observabilidad, costo y ownership operacional.

## Antipatrones

- Módulos que comparten tablas o modelos internos.
- Dependencias circulares.
- Un módulo común que acumula reglas de todos los dominios.
- Separar servicios sin ownership ni motivo operacional.
- Confundir separación de carpetas con aislamiento real.

## Verificación

- Grafo de dependencias sin ciclos.
- Pruebas arquitectónicas que bloqueen imports prohibidos.
- Contratos públicos identificables.
- Persistencia privada no accesible desde módulos consumidores.
- ADR para cambios de límites o extracción física.
