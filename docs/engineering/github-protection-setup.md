# Protección efectiva de `main` y configuración de GitHub

**Estado observado:** 2026-11-25 — `main` no está protegida. La API de ramas devuelve `protected: false`; la consulta de Rulesets no devuelve reglas configuradas. CODEOWNERS existe, pero no hay evidencia de enforcement obligatorio.
**Objetivo:** aplicar la política de [gobernanza y contribución segura](./repository-governance-and-secure-contribution.md) mediante controles reales de GitHub.

## 1. Estado comprobado

| Control | Estado observado | Evidencia |
|---|---|---|
| Rulesets de ramas | No configurados | La lista de Rulesets del repositorio devolvió `[]` |
| Protección clásica de `main` | No activa | Objeto de rama `main`: `protected: false` |
| Pull Request obligatorio | No verificado/activo | No existe protección de rama activa |
| Revisión de Code Owners obligatoria | No activa | CODEOWNERS existe; no hay Ruleset/branch protection que lo exija |
| Checks obligatorios | No configurados | No hay protección de rama que los exija |
| CODEOWNERS | Presente en raíz | Archivo `/CODEOWNERS` |
| Workflow documental | Presente | `.github/workflows/documentation-security.yml` |

La lectura del endpoint clásico de detalle de protección no está permitida para esta integración; sin embargo, el objeto de la rama confirma `protected: false`. No afirmar que una regla está activa hasta comprobar la configuración efectiva y su enforcement.

## 2. Ruleset requerido para `main`

Crear en **Settings → Rules → Rulesets → New branch ruleset** un ruleset con estos valores:

- Nombre: `protect-main`.
- Enforcement status: **Active** (no Evaluate).
- Target branches: incluir exactamente `main`.
- Bypass list: vacía; no conceder bypass permanente a administradores, apps o equipos.
- Require a pull request before merging: activado.
- Required approvals: al menos **1 aprobación humana independiente**.
- Require review from Code Owners: activado.
- Dismiss stale pull request approvals when new commits are pushed: activado.
- Require conversation resolution: activado.
- Block force pushes: activado.
- Restrict deletions: activado.
- Require status checks to pass: activar únicamente checks existentes, estables y observados en PRs; no inventar nombres.
- Require branches to be up to date: habilitar si el check requerido y el flujo de integración lo soportan de forma estable.

La aprobación debe proceder de alguien distinto del autor. Si el autor es el único Code Owner o no existe otro revisor con permisos suficientes, el PR no puede satisfacer la regla; incorporar un segundo responsable humano autorizado antes de exigir una aprobación que nadie pueda emitir. No sustituir esa revisión por autoaprobación.

No activar reglas de firma de commits, linear history, merge queue u otras restricciones adicionales sin validar su compatibilidad con el flujo acordado y el estado real del repositorio.

## 3. CODEOWNERS

El archivo raíz `/CODEOWNERS` es una ubicación reconocida por GitHub. Mantener responsables reales para:
- `.github/` y workflows.
- `docs/adr/`, `docs/architecture/`, `docs/engineering/` y `docs/security/`.
- `scripts/` e `infrastructure/`.
- Archivos normativos raíz y el propio `CODEOWNERS`.

CODEOWNERS solo identifica responsables. La obligación de revisión nace al activar **Require review from Code Owners** en el Ruleset. Después de configurar, comprobar que GitHub solicita la revisión en PRs que modifican cada ruta sensible.

## 4. Checks y CI

El workflow documental actual es `.github/workflows/documentation-security.yml`. Declara `contents: read`, fija checkout por SHA y ejecuta validación Markdown, enlaces locales y Gitleaks. Su existencia no equivale a un check obligatorio ni prueba que todas las ejecuciones hayan pasado.

Antes de agregar un check al Ruleset:
1. Abrir un PR de prueba que active el workflow.
2. Confirmar el nombre exacto del check reportado por GitHub.
3. Confirmar ejecuciones correctas y fallidas, y que el fallo bloquea el merge.
4. Confirmar que el check se ejecuta para los cambios que debe cubrir.
5. Configurar ese nombre exacto como requerido y probar nuevamente.

No hay workflow de despliegue que deba recibir permisos privilegiados en el estado actual. Cuando se introduzca, separar validación de PR y despliegue; usar permisos mínimos por job, environments protegidos, aprobaciones y credenciales temporales. Nunca exponer secretos de producción a código de PR/fork no confiable.

## 5. Permisos de colaboradores y despliegue

En **Settings → Collaborators and teams**, revisar cada usuario/equipo y asignar el rol mínimo. Registrar quién puede leer, escribir, mantener y administrar. El permiso de repositorio no concede por sí solo acceso a secretos productivos: los environments y credenciales deben mantenerse separados.

Antes de producción:
- Proteger cuentas con escritura/administración mediante MFA.
- Revisar acceso y revocación de colaboradores.
- Configurar environments independientes y aprobaciones de despliegue.
- Preferir GitHub App/OIDC y tokens de corta duración.
- Verificar que workflows de validación no tengan acceso a secretos de despliegue.

## 6. Verificación y evidencia

Tras aplicar la configuración:
- Registrar fecha, actor administrador, ID/nombre del Ruleset y ramas objetivo.
- Guardar captura o exportación de sus reglas sin incluir secretos.
- Consultar la configuración efectiva de `main` y confirmar que aparece protegida.
- Abrir PR de prueba para verificar PR obligatorio, aprobación independiente, CODEOWNERS, checks, resolución de conversaciones y bloqueo de force-push/borrado.
- Registrar resultados, links a PR y ejecuciones de Actions.
- Verificar que no existe bypass permanente no autorizado.

**Criterio de cierre:** Ruleset activo y aplicado a `main`; CODEOWNERS exigido; checks reales obligatorios y probados; permisos revisados; evidencia almacenada. Hasta entonces, la subfase 0.2 permanece bloqueada en su puerta de avance, aunque la política y los archivos del repositorio estén preparados.

## 7. Relación documental

- [Política de gobernanza y contribución segura](./repository-governance-and-secure-contribution.md)
- [ADR-0024 — Desarrollo seguro, CI/CD y cadena de suministro](../adr/0024-secure-development-cicd-and-software-supply-chain.md)
- [Estándar de calidad, seguridad y mantenimiento documental](./documentation-quality-and-security-standard.md)
- [Reglas de implementación y operación](./implementation-rules.md)
