# Configuración objetivo de protección de `main` en GitHub

**Estado:** guía de configuración pendiente de aplicar/verificar. Este documento no demuestra que existan Rulesets, branch protection ni revisiones obligatorias activas.

## Objetivo

Proteger `main` para que los cambios entren mediante Pull Request y las revisiones definidas por el repositorio se apliquen realmente. `CODEOWNERS` identifica quién debe revisar determinadas rutas, pero por sí solo no obliga a solicitar ni aprobar una revisión.

## Pasos de configuración

1. Abrir el repositorio en GitHub y entrar en **Settings → Rules → Rulesets** (o **Settings → Branches** si se utiliza la configuración clásica).
2. Crear un ruleset para ramas y seleccionar `main` como rama objetivo. Si se usa branch protection clásica, crear una regla cuyo patrón sea `main`.
3. Activar **Require a pull request before merging**.
4. Definir el número de aprobaciones requerido por la política del proyecto. Si la política exige aprobación independiente, configurar al menos una aprobación de otra persona con permiso de revisión.
5. Activar **Require review from Code Owners** para que las rutas cubiertas por `CODEOWNERS` requieran revisión de sus responsables.
6. Evaluar y activar **Dismiss stale pull request approvals when new commits are pushed** para que cambios posteriores a una aprobación vuelvan a revisarse.
7. Activar **Require conversation resolution** para que los hilos de revisión pendientes se resuelvan antes de integrar.
8. Activar **Block force pushes** y **Restrict deletions** para proteger la rama principal.
9. Configurar **Require status checks to pass** únicamente cuando existan workflows/checks reales, estables y observados en ejecuciones del repositorio. No inventar nombres de checks ni marcar como activos controles que todavía no existen.
10. Guardar el ruleset/regla y verificarlo con una PR de prueba o consultando la configuración efectiva de GitHub.

## CODEOWNERS

El archivo `CODEOWNERS` en la raíz asigna actualmente `docs/architecture/`, `docs/adr/`, `docs/engineering/`, `docs/security/` y los documentos normativos raíz (README, PROMPT_MAESTRO, ROADMAP y requisitos) a `@programadorkevinsvega-sys`. Mantener estas asignaciones o actualizarlas con responsables reales cuando cambie la propiedad documental.

- Mantener el archivo `CODEOWNERS` en una ubicación reconocida por GitHub (`.github/CODEOWNERS`, `CODEOWNERS` en la raíz o `docs/CODEOWNERS`).
- Declarar responsables reales y rutas que deban revisar.
- Verificar que los responsables tengan permisos suficientes para revisar.
- La obligatoriedad se obtiene al activar **Require review from Code Owners** en Rulesets/branch protection; la mera existencia del archivo no basta.

## Estado y evidencia

Hasta que la configuración se aplique y se verifique:

- La revisión mediante PR es el procedimiento documental esperado.
- CODEOWNERS puede identificar responsables, pero no se afirma que sus revisiones sean obligatorias.
- No se afirma que `main` esté protegida.
- No se afirma que CI o status checks estén activos sin workflows y ejecuciones verificables.

La lectura de la configuración efectiva de protección de ramas no está disponible para esta integración de GitHub. Por tanto, no se afirma que el ruleset o branch protection esté activo. Registrar en el repositorio la fecha de configuración, las opciones activadas y evidencia de verificación cuando un administrador complete el proceso.
