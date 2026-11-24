# Infrastructure

Definiciones y configuración de infraestructura para desarrollo, pruebas y despliegue. Incluye Docker, topología de los cuatro procesos, PostgreSQL, NATS Core/JetStream, Redis y observabilidad. Los archivos aquí describen infraestructura objetivo; no prueban que esté desplegada o activa.

Los cuatro backends se despliegan como servicios independientes. No colocar migraciones SQL de módulos aquí: cada módulo las mantiene bajo `backend/<backend>/modules/<modulo>/migrations/`. La carpeta raíz `migrations/` se conserva únicamente como ubicación histórica documentada.
