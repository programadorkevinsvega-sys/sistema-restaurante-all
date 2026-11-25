# Protección efectiva de `main` y configuración de GitHub

**Estado observado:** 2026-11-25 — Ruleset `protect-main` configurado y verificado. PR de prueba #33 ejecutado con CI pasando y mergeado a `main`. Aprobación independiente pendiente de segundo colaborador (repositorio de un solo propietario en esta etapa).
**Objetivo:** aplicar la política de [gobernanza y contribución segura](./repository-governance-and-secure-contribution.md) mediante controles reales de GitHub.

## 1. Estado comprobado

| Control | Estado observado | Evidencia |
|---|---|---|
| Rulesets de ramas | ✅ Configurado | Ruleset `protect-main` activo; target `main` |
| Protección clásica de `main` | ✅ Activa vía Ruleset | Ruleset con enforcement `Active` aplicado a `main` |
| Pull Request obligatorio | ✅ Activo | Verificado en PR #33: merge bloqueado sin PR |
| Revisión de Code Owners obligatoria | ⚠️ Configurada; pendiente segundo colaborador | CODEOWNERS presente; regla activa en Ruleset; repositorio tiene un solo propietario activo — se requiere segundo colaborador humano para enforcement efectivo |
| Checks obligatorios | ✅ Activo | `Markdown and secret validation` requerido y verificado en PR #33 |
| CODEOWNERS | ✅ Presente en raíz | Archivo `/CODEOWNERS`; rutas sensibles cubiertas |
| Workflow documental | ✅ Presente y funcionando | `.github/workflows/documentation-security.yml`; CI pasó en PR #33 |
| Force push bloqueado | ✅ Activo | Configurado en Ruleset `protect-main` |
| Restricción de borrado | ✅ Activo | Configurado en Ruleset `protect-main` |

PR de prueba utilizado para verificación: [#33](https://github.com/programadorkevinsvega-sys/sistema-restaurante-all/pull/33) — mergeado a `main` el 2026-11-25. El check `Markdown and secret validation` detectó y bloqueó correctamente una línea en blanco extra (MD047), confirmando que el fallo bloquea el merge. Corregido y mergeado tras pasar CI.

**Riesgo residual:** la aprobación independiente de Code Owner no puede satisfacerse con un único colaborador. Acción pendiente: incorporar un segundo responsable humano autorizado y reactivar `Required approvals: 1` y `Require review from Code Owners` en el Ruleset. Responsable: `@programadorkevinsvega-sys`. Sin fecha límite fija en esta etapa; debe resolverse antes de incorporar colaboradores con escritura.

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

**Criterio de cierre:** Ruleset activo y aplicado a `main`; checks reales obligatorios probados con PR de prueba; permisos revisados; evidencia almacenada. ✅ Satisfecho con riesgo residual documentado (aprobación independiente pendiente de segundo colaborador). La subfase 0.2 se considera cerrada con ese riesgo registrado y con responsable asignado.

## 7. Relación documental

- [Política de gobernanza y contribución segura](./repository-governance-and-secure-contribution.md)
- [ADR-0024 — Desarrollo seguro, CI/CD y cadena de suministro](../adr/0024-secure-development-cicd-and-software-supply-chain.md)
- [Estándar de calidad, seguridad y mantenimiento documental](./documentation-quality-and-security-standard.md)
- [Reglas de implementación y operación](./implementation-rules.md)
