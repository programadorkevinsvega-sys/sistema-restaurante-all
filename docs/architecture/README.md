# Arquitectura

Fuentes normativas:

1. [Estándar general](./engineering-standard.md): reglas base para cualquier proyecto.
2. [Arquitectura de Restaurant OS](./restaurant-os-architecture.md): especialización del producto.
3. [Reglas de implementación](../engineering/implementation-rules.md): desarrollo, pruebas y mantenimiento.
4. [ADRs](../adr/README.md): decisiones y desviaciones aprobadas.

Precedencia: el estándar es el mínimo; Restaurant OS puede especializarlo o endurecerlo, nunca debilitarlo. Las reglas de implementación no contradicen los anteriores. Toda desviación requiere ADR aceptado por el propietario del producto.

Los documentos históricos sustituidos se conservan con estado `superseded`, fecha de sustitución y enlace a su fuente vigente. Las ideas de `futuro.md` son propuestas, no decisiones aprobadas.

La topología objetivo de Restaurant OS separa `api-server` (backend modular/gRPC) y `bff` (HTTP/OpenAPI para frontends) en dos procesos. Los módulos internos de `api-server` no se convierten por ello en microservicios.

Para configurar la exigencia efectiva de revisión por propietarios de código en GitHub, seguir [Configuración de protección de main](../engineering/github-protection-setup.md). `CODEOWNERS` por sí solo no obliga a solicitar ni aprobar revisiones.
