# Plantilla de perfil de proyecto

**Estado:** plantilla

Completar antes de seleccionar estándares. No asumir que todos los campos aplican; justificar los no aplicables. Este perfil describe el contexto y permite evaluar disparadores; no sustituye el registro exhaustivo ni contiene estados de adopción.

## 1. Identidad y contexto
- Nombre/código del proyecto:
- Propietario de producto:
- Responsable técnico:
- Responsable de seguridad:
- Responsable de privacidad/legal:
- Fecha y versión del perfil:
- Tipo de sistema:
- Usuarios y actores:
- Mercados y jurisdicciones:

## 2. Criticidad y riesgo
- Impacto de indisponibilidad:
- Impacto de pérdida/corrupción de datos:
- Impacto financiero:
- Sensibilidad de datos:
- Requisitos regulatorios/contractuales:
- RTO/RPO objetivo:
- SLO/SLA:
- Riesgos de seguridad principales:
- Riesgos para personas, seguridad física o derechos:

## 3. Arquitectura y operación
- Estilo arquitectónico actual/propuesto:
- Lenguajes y runtimes:
- Procesos y servicios:
- Persistencia y ownership:
- Integraciones y proveedores:
- Mensajería:
- Despliegue y hosting:
- Regiones y residencia:
- Equipo y capacidad operativa:
- Presupuesto y restricciones:

## 4. Escala y rendimiento
- Usuarios activos esperados:
- Concurrencia:
- Volumen y crecimiento de datos:
- Perfil de lectura/escritura:
- Picos conocidos:
- Requisitos de latencia:
- Ventanas de mantenimiento:
- Requisitos de disponibilidad y continuidad:

## 5. Capacidades y superficies
- Web, móvil, escritorio, API, dispositivos/IoT:
- Pagos, identidad, notificaciones y terceros:
- Offline, sincronización y tiempo real:
- IA generativa, agentes o ML:
- Búsqueda, analítica, mapas/geoespacial:
- Accesibilidad, idiomas y mercados:
- Contenido, archivos y medios:
- Requisitos SEO o distribución:

## 6. Incertidumbres y límites
- Información desconocida:
- Supuestos pendientes de validar:
- Restricciones no negociables:
- Decisiones previas aprobadas:
- Dependencias y fechas:
- Capacidad para operar controles 24/7:

## 7. Evaluación de estándares (no seleccionar aquí)

La evaluación se realiza en el [registro de adopción](../PROJECT-STANDARDS-ADOPTION-REGISTER.md), usando el inventario completo. Para cada ID se registran dos dimensiones:

**Aplicabilidad:** Aplica / Condicional / No aplica.

**Estado de adopción:** Adoptado / Adoptado con adaptación / Aplazado / No aplicable / Rechazado / Pendiente de decisión / Brecha de biblioteca.

No utilizar Obligatorio, Condicional, No aplicable o Excepción como estados de adopción. Condicional pertenece únicamente a aplicabilidad. Excepción es un mecanismo de gobernanza, no un estado de adopción. Una excepción aprobada no borra aplicabilidad: debe registrarse según su decisión y enlazar el waiver.
