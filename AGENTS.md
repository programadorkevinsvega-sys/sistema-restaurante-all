# Instrucciones para agentes

Antes de proponer o modificar arquitectura, leer en este orden:

1. [Estándar general](docs/architecture/engineering-standard.md)
2. [Arquitectura de Restaurant OS](docs/architecture/restaurant-os-architecture.md)
3. [Reglas de implementación](docs/engineering/implementation-rules.md)
4. [Estándar de calidad, seguridad y mantenimiento documental](docs/engineering/documentation-quality-and-security-standard.md)
5. [ADRs aceptados y propuestos aplicables](docs/adr/README.md)
6. [Seguridad de contraseñas y autenticación](docs/security/password-and-authentication.md), cuando la tarea afecte IDENTITY o autenticación
7. [Requisitos](requisitos.md) y [Roadmap](ROADMAP.md)
8. [Configuración de protección de main en GitHub](docs/engineering/github-protection-setup.md)

Al crear o modificar documentación, cumplir además el [Estándar de calidad, seguridad y mantenimiento documental](docs/engineering/documentation-quality-and-security-standard.md). Respetar precedencia: el estándar general es obligatorio; la arquitectura de Restaurant OS puede especializarlo o endurecerlo, nunca debilitarlo; las reglas de implementación están subordinadas. No resolver contradicciones por inferencia: proponer ADR y esperar aprobación explícita.

Un agente puede analizar y proponer, pero no aprobar decisiones de producto, aceptar ADRs, fusionar PRs, desplegar ni ejecutar acciones irreversibles sin autorización explícita. No afirmar que una regla está implementada o verificada sin evidencia. Los cambios de documentación arquitectónica se integran mediante PR a main. CODEOWNERS identifica responsables, pero la revisión de code owners solo es obligatoria si un Ruleset o branch protection de GitHub activa expresamente ese requisito. Consultar [Configuración de protección de main](docs/engineering/github-protection-setup.md); no afirmar que está activa sin verificarla.

## Flujo de trabajo obligatorio por subfase

1. **Crear la rama en GitHub primero** — nunca crear una rama solo en local. Crear la rama desde el repositorio remoto y traerla a local: `git checkout -b <rama> origin/main && git push -u origin <rama>`.
2. **Implementar en local sobre esa rama** — hacer todos los cambios de código y documentación de la subfase completa.
3. **Documentación y código van juntos** — nunca cerrar una subfase y actualizar la documentación después. Todo `.md`, checklist, índice y referencia cruzada afectado se actualiza en el mismo commit o PR.
4. **Push y PR** — subir los cambios y abrir el PR hacia `main`.
5. **CI verde antes de fusionar** — esperar que todos los checks pasen en verde. Si el CI falla, corregir en la misma rama antes de cualquier otra acción.
6. **Fusionar a main** — una vez CI verde, mergear el PR.
7. **Sincronizar local** — después del merge, actualizar local: `git checkout main && git pull origin main`.
8. **Solo entonces continuar** — no iniciar la siguiente subfase hasta que local esté sincronizado con `main` del repositorio.
