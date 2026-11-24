# Arquitectura

Fuentes normativas:

1. [Estándar general](./engineering-standard.md): reglas base para cualquier proyecto.
2. [Arquitectura de Restaurant OS](./restaurant-os-architecture.md): especialización del producto.
3. [Reglas de implementación](../engineering/implementation-rules.md): desarrollo, pruebas y mantenimiento.
4. [ADRs](../adr/README.md): decisiones y desviaciones aprobadas.

Precedencia: el estándar es el mínimo; Restaurant OS puede especializarlo o endurecerlo, nunca debilitarlo. Las reglas de implementación no contradicen los anteriores. Toda desviación requiere ADR aceptado por el propietario del producto.

Los documentos históricos sustituidos se conservan con estado `superseded`, fecha de sustitución y enlace a su fuente vigente. Las ideas de `futuro.md` son propuestas, no decisiones aprobadas.

La topología objetivo de Restaurant OS consta de cuatro procesos/binarios independientes: Admin Platform Backend, Admin BFF, Public BFF y Public Backend. Cada proceso contiene sus propios módulos. Entre procesos se utilizan gRPC para solicitudes/respuestas, NATS Core para señales efímeras y NATS JetStream para eventos durables, según corresponda. Los módulos dentro de un mismo backend conservan el patrón modular descrito en el estándar general.

Para configurar la exigencia efectiva de revisión por propietarios de código en GitHub, seguir [Configuración de protección de main](../engineering/github-protection-setup.md). `CODEOWNERS` por sí solo no obliga a solicitar ni aprobar revisiones.
