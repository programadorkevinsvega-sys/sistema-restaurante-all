# Infrastructure

Definiciones y configuración de infraestructura para desarrollo, pruebas y despliegue. Incluye Docker, topología de los cuatro procesos, PostgreSQL, NATS Core/JetStream, Redis y observabilidad. Los archivos aquí describen infraestructura objetivo; no prueban que esté desplegada o activa.

Los cuatro backends se despliegan como servicios independientes. No colocar migraciones SQL de módulos aquí: cada módulo las mantiene bajo `backend/<backend>/modules/<modulo>/migrations/`. La carpeta raíz `migrations/` se conserva únicamente como ubicación histórica documentada.

## Documentos de diseño de infraestructura (subfase 0.7)

Los siguientes documentos están en `docs/infrastructure/` y son el diseño aprobado
antes de cualquier configuración real:

- [Modelo de red y matriz de flujos](../docs/infrastructure/network-model.md): zonas, flujos permitidos y prohibidos por proceso.
- [Política de secretos](../docs/infrastructure/secrets-policy.md): ciclo de vida, separación y reglas de uso de secretos.
- [Baseline de contenedores](../docs/infrastructure/container-baseline.md): controles mínimos por imagen y contenedor.
- [Política TLS/criptográfica](../docs/infrastructure/tls-crypto-policy.md): versiones, certificados, cifrado en reposo y gestión de claves.
- [Runbooks de rotación](../docs/infrastructure/rotation-runbooks.md): procedimientos de rotación programada y de emergencia.
