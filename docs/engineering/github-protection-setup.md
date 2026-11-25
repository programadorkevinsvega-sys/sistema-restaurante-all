# Protección efectiva de `main` y configuración de GitHub

**Estado observado:** 2026-11-25 — Ruleset `protect-main` (ID `28057956`) activo sobre `main`, sin bypass actors. Requiere 0 aprobaciones, mantiene activada la revisión de Code Owners, exige el check `Markdown and secret validation` y bloquea borrado y force-push. El único mantenedor listado es el propietario del repositorio. La política del proyecto es solo-maintainer; por ello, la revisión independiente no es un requisito operativo hasta incorporar otra persona autorizada. La regla `require_code_owner_review: true` debe desactivarse para alinear la configuración con ese modelo; esta modificación administrativa no se ha aplicado desde la integración disponible.
**Objetivo:** aplicar la política de [gobernanza y contribución segura](./repository-governance-and-secure-contribution.md) mediante controles reales de GitHub.

## 1. Estado comprobado

| Control | Estado observado | Evidencia |
|---|---|---|
| Rulesets de ramas | ✅ Configurado | Ruleset `protect-main` activo; target `main` |
| Protección clásica de `main` | ✅ Activa vía Ruleset | Ruleset con enforcement `Active` aplicado a `main` |
| Pull Request obligatorio | ✅ Activo | Verificado en PR #33: merge bloqueado sin PR |
| Revisión de Code Owners | ⚠️ Desalineada con el modelo solo-maintainer | API del Ruleset: `require_code_owner_review: true`; hay un solo mantenedor. Debe desactivarse mientras no exista un segundo colaborador autorizado |
| Checks obligatorios | ✅ Activo | `Markdown and secret validation` requerido en Ruleset y ejecución `success` en PR #45 y en el commit de merge a `main` |
| CODEOWNERS | ✅ Presente en raíz | Archivo `/CODEOWNERS`; rutas sensibles cubiertas |
| Workflow documental | ✅ Presente y funcionando | `.github/workflows/documentation-security.yml`; CI pasó en PR #33, PR #45 y commit de merge de PR #45 |
| Force push bloqueado | ✅ Activo | Configurado en Ruleset `protect-main` |
| Restricción de borrado | ✅ Activo | Configurado en Ruleset `protect-main` |

Evidencia reciente: [PR #45](https://github.com/programadorkevinsvega-sys/sistema-restaurante-all/pull/45) terminó con sus dos ejecuciones `Markdown and secret validation` en `success`; tras el merge squash, el mismo check también terminó en `success` sobre el commit `e24593f5c02ec4c2264e7c2919a57160b5ca4f37` de `main`. La prueba histórica [PR #33](https://github.com/programadorkevinsvega-sys/sistema-restaurante-all/pull/33) documenta además un fallo MD047 que bloqueó el flujo y fue corregido antes de fusionar.

**Riesgo/configuración pendiente:** la API confirma `required_approving_review_count: 0`, `require_code_owner_review: true`, `required_review_thread_resolution: true`, `dismiss_stale_reviews_on_push: true`, `required_status_checks.strict_required_status_checks_policy: true`, un check requerido (`Markdown and secret validation`), `deletion`, `non_fast_forward` y `bypass_actors: []`. Para el modelo actual de único mantenedor, cambiar `require_code_owner_review` a `false`; mantener 0 aprobaciones, PR obligatorio, resolución de conversaciones, check obligatorio, bloqueo de borrado/force-push y bypass vacío. Esta edición del Ruleset requiere permisos administrativos y no se pudo ejecutar mediante las acciones GitHub disponibles en esta sesión. No se afirma que esté aplicada.

## 2. Ruleset requerido para `main`

Crear en **Settings → Rules → Rulesets → New branch ruleset** un ruleset con estos valores:

- Nombre: `protect-main`.
- Enforcement status: **Active** (no Evaluate).
- Target branches: incluir exactamente `main`.
- Bypass list: vacía; no conceder bypass permanente a administradores, apps o equipos.
- Require a pull request before merging: activado.
- Required approvals: **0** mientras exista un único mantenedor; cambiar a **1** cuando haya un segundo colaborador autorizado.
- Require review from Code Owners: **desactivado mientras exista un único mantenedor**. Activarlo cuando haya al menos un segundo Code Owner autorizado capaz de revisar y aprobar.
- Dismiss stale pull request approvals when new commits are pushed: activado cuando aplique.
- Require conversation resolution: activado.
- Block force pushes: activado.
- Restrict deletions: activado.
- Require status checks to pass: activar únicamente checks existentes, estables y observados en PRs; no inventar nombres.
- Require branches to be up to date: habilitar si el check requerido y el flujo de integración lo soportan de forma estable.

**Cuando se incorpore un segundo colaborador autorizado:** actualizar el Ruleset a `Required approvals: 1` y activar `Require review from Code Owners` para las rutas pertinentes antes de que realice su primer PR.

No activar reglas de firma de commits, linear history, merge queue u otras restricciones adicionales sin validar su compatibilidad con el flujo acordado y el estado real del repositorio.

## 3. CODEOWNERS

El archivo raíz `/CODEOWNERS` es una ubicación reconocida por GitHub. Mantener responsables reales para:

- `.github/` y workflows.
- `docs/adr/`, `docs/architecture/`, `docs/engineering/` y `docs/security/`.
- `scripts/` e `infrastructure/`.
- Archivos normativos raíz y el propio `CODEOWNERS`.

CODEOWNERS identifica ownership, pero no debe utilizarse como bloqueo de aprobación independiente en el modelo solo-maintainer. Mantener el archivo con responsables reales. Cuando exista un segundo Code Owner autorizado, activar **Require review from Code Owners** y comprobar que GitHub solicita la revisión en PRs que modifican cada ruta sensible.

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
- Abrir PR de prueba para verificar PR obligatorio, checks, resolución de conversaciones y bloqueo de force-push/borrado.
- Registrar resultados, links a PR y ejecuciones de Actions.
- Verificar que no existe bypass permanente no autorizado.

**Criterio de cierre:** Ruleset activo y alineado con el modelo solo-maintainer (0 aprobaciones y revisión de Code Owners desactivada mientras no exista segundo revisor); checks reales obligatorios probados; PR obligatorio, resolución de conversaciones, bloqueo de force-push/borrado y bypass vacío verificados; permisos revisados; evidencia almacenada. **Estado actual: parcialmente satisfecho; subfase 0.2 aún no cerrada** porque `require_code_owner_review` continúa en `true` y requiere ajuste administrativo.

## 7. Relación documental

- [Política de gobernanza y contribución segura](./repository-governance-and-secure-contribution.md)
- [ADR-0024 — Desarrollo seguro, CI/CD y cadena de suministro](../adr/0024-secure-development-cicd-and-software-supply-chain.md)
- [Estándar de calidad, seguridad y mantenimiento documental](./documentation-quality-and-security-standard.md)
- [Reglas de implementación y operación](./implementation-rules.md)
