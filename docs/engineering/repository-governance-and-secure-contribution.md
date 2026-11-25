# Gobernanza del repositorio y contribución segura

**Estado:** política aprobada para un proyecto con un único mantenedor; enforcement de GitHub sujeto a la configuración efectiva documentada en `github-protection-setup.md`.
**Ámbito:** repositorio Restaurant OS, ramas, Pull Requests, revisiones, dependencias, GitHub Actions, secretos y cadena de suministro.
**Autoridad:** subordinada a ADR-0020 y ADR-0024, a los requisitos y a los estándares vigentes.

Esta política define el comportamiento esperado. Una regla escrita, un archivo CODEOWNERS o un workflow no demuestran por sí solos que GitHub esté aplicando una protección. El estado efectivo se registra en [configuración de protección de main](./github-protection-setup.md).

## 1. Flujo de ramas

Las ramas de trabajo se crean desde la versión actualizada de `main` y se integran mediante Pull Request. No se trabaja directamente sobre `main`.

Prefijos permitidos:

| Prefijo | Uso |
|---|---|
| `feat/` | capacidad nueva |
| `fix/` | corrección |
| `docs/` | documentación |
| `security/` | controles o correcciones de seguridad |
| `refactor/` | reestructuración sin cambio funcional intencional |
| `test/` | pruebas |
| `chore/` | mantenimiento y tooling |
| `release/` | preparación de una versión |

Usar nombres breves, descriptivos, en minúsculas y kebab-case; por ejemplo `docs/phase-0.2-secure-repository-governance`. No incluir nombres de clientes, datos personales, secretos ni información sensible en nombres de ramas.

Las ramas de trabajo deben ser de vida corta. Antes de abrir o actualizar un PR, sincronizar con `main` mediante el procedimiento del repositorio y resolver conflictos sin sobrescribir trabajo ajeno. No hacer force-push a ramas protegidas. El force-push en ramas de trabajo solo se permite cuando no perjudica a otros colaboradores y el PR conserva trazabilidad.

## 2. Commits y Pull Requests

### Commits

Usar Conventional Commits:

`<tipo>(<ámbito opcional>): <descripción imperativa breve>`

Tipos habituales: `feat`, `fix`, `docs`, `security`, `refactor`, `test`, `build`, `ci`, `chore` y `revert`. Añadir `BREAKING CHANGE:` en el cuerpo o footer cuando corresponda. Un commit debe representar un cambio coherente; evitar commits de ruido, secretos, archivos generados manualmente o artefactos locales.

### Pull Requests

Cada PR debe:

- Tener un objetivo acotado y una descripción del problema, solución y alcance.
- Indicar archivos/áreas afectadas, ADR y requisitos relacionados.
- Describir riesgos, compatibilidad, migración y rollback cuando apliquen.
- Enumerar validaciones ejecutadas con resultado y evidencia; distinguir expresamente las no ejecutadas.
- Identificar riesgos residuales, bloqueos y trabajo diferido.
- Incluir documentación y changelog cuando corresponda.
- No mezclar refactors ajenos ni cambios fuera del alcance aprobado.

El proyecto opera actualmente con un único mantenedor y no dispone de una segunda persona que pueda revisar o aprobar PRs. Por tanto, el flujo vigente exige PR, CI obligatorio, revisión propia estructurada antes de fusionar y evidencia verificable; no exige una aprobación humana independiente imposible de obtener. El autor no registra una aprobación ficticia ni presenta una revisión propia como independiente. CODEOWNERS identifica ownership de rutas, pero no debe convertirse en un bloqueo imposible mientras exista un único mantenedor. Cuando se incorporen colaboradores autorizados, se activarán las aprobaciones independientes y la revisión de Code Owners para las rutas sensibles.

Cambios sensibles incluyen, como mínimo: autenticación/autorización, aislamiento multi-tenant, validación de entradas, pagos/datos financieros, criptografía, secretos, archivos, infraestructura, dependencias críticas, workflows, permisos CI/CD, CODEOWNERS, Rulesets y políticas de seguridad.

No se deben configurar checks obligatorios por nombre supuesto. Solo se hacen obligatorios checks existentes, estables, asociados al PR y observados en ejecuciones exitosas.

## 3. Versionado y changelog

Cuando el proyecto publique artefactos/versiones, usar Semantic Versioning (MAJOR.MINOR.PATCH) para versiones del producto y artefactos que sigan ese esquema:

- MAJOR: incompatibilidad pública deliberada.
- MINOR: capacidad compatible.
- PATCH: corrección compatible.

Las APIs HTTP y los paquetes Protobuf conservan su versionado de contrato propio; no inferir que una versión del producto cambia automáticamente la versión de todos los contratos. Una ruptura de contrato requiere revisión de compatibilidad y estrategia de transición conforme a ADR-0002/ADR-0005/ADR-0007.

Mantener `CHANGELOG.md` con secciones `Unreleased`, `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed` y `Security`, siguiendo Keep a Changelog. Registrar cambios relevantes para usuarios, operadores, integradores y despliegues; no copiar cada commit. Al publicar, mover el contenido correspondiente a una versión fechada y asociarlo al tag/artefacto exacto. No crear versiones ni declarar releases mientras no exista proceso de publicación aprobado.

## 4. Revisión de dependencias y vulnerabilidades

Antes de incorporar o actualizar una dependencia:

1. Justificar la necesidad y comprobar si la capacidad ya existe en el stack.
2. Verificar origen, mantenedor, actividad, licencia, historial de vulnerabilidades y riesgo de typosquatting/supply-chain.
3. Revisar dependencias transitivas, scripts de instalación/build y permisos requeridos.
4. Preferir versiones mantenidas y fijadas de forma reproducible; conservar lockfiles cuando el ecosistema los utilice.
5. Separar dependencias de producción, desarrollo, CI y tooling.
6. Evitar dependencias abandonadas, duplicadas, excesivas o sin justificación.
7. Revisar el diff completo y ejecutar las pruebas/escáneres disponibles.

Los avisos de seguridad deben triagiarse considerando severidad, explotabilidad, exposición real, alcance, disponibilidad de mitigación y si existe explotación activa. Cada hallazgo debe registrar identificador (CVE/GHSA u otro), paquete/versión afectada, activo, severidad, responsable, decisión, mitigación, fecha objetivo y evidencia de cierre.

No se inventan plazos universales de remediación en esta fase. Antes de producción se aprobarán objetivos de tratamiento por severidad y exposición. Una vulnerabilidad crítica explotada, una credencial expuesta o un riesgo alto sin mitigación bloquea la integración o publicación, salvo excepción de emergencia documentada y temporal. Las excepciones no eliminan la obligación de corregir y revalidar.

Automatización de actualizaciones (por ejemplo Dependabot) se habilitará cuando se incorporen manifests/ecosistemas y exista una política de agrupación, revisión y CI adecuada. Su ausencia actual no se describe como automatización activa.

## 5. GitHub Actions y CI/CD

- Declarar `permissions` explícitos al nivel mínimo necesario; preferir permisos de solo lectura y elevarlos únicamente en el job que los requiera.
- No usar `write-all` ni tokens personales de larga duración en workflows.
- Separar validación de PR/código no confiable de publicación, firma y despliegue privilegiados.
- Los workflows de PR/forks no reciben secretos de producción ni credenciales de despliegue.
- Despliegues usan environments protegidos, aprobaciones humanas, restricciones de rama y credenciales de corta duración/federadas cuando estén disponibles.
- Fijar acciones de terceros a SHA completo revisado; actualizar esos SHA mediante PR.
- Fijar imágenes de contenedor por digest cuando se usen en pipelines privilegiados; los tags versionados por sí solos no garantizan inmutabilidad.
- No interpolar entradas no confiables directamente en comandos shell; transferirlas mediante variables de entorno y validar.
- Limitar concurrencia, duración, red, filesystem y permisos del runner; preferir runners efímeros/aislados para tareas privilegiadas.
- No compartir workspace, credenciales o artefactos modificables entre jobs de distinto nivel de confianza.
- No publicar artefactos ni desplegar desde el mismo job que ejecuta código no confiable.
- Mantener logs y artefactos libres de secretos y datos personales.
- Los checks obligatorios se definen solo después de verificar el nombre real del check y su estabilidad.

Todo workflow privilegiado debe someterse a una revisión propia específica de seguridad, permisos, acciones, dependencias y rutas de ejecución mientras exista un único mantenedor. Antes de habilitar despliegues productivos o cambios de alto impacto, se recomienda revisión externa especializada cuando no exista una segunda persona interna.

## 6. Permisos y separación de funciones

Aplicar mínimo privilegio y conceder acceso por necesidad:

- **Lectura:** consulta de código, issues y documentación; no implica capacidad de escritura.
- **Escritura:** contribución mediante ramas y PR; no implica administración de repositorio ni despliegue productivo.
- **Mantenimiento:** gestión operativa acotada del repositorio; no implica acceso automático a secretos/producción.
- **Administración:** cambios de configuración, Rulesets, permisos, secretos y políticas; reservado a responsables designados.
- **Despliegue:** identidad específica por environment, separada de permisos generales del repositorio.

Revisar accesos al incorporar/salir colaboradores y periódicamente antes de producción. Proteger cuentas con escritura/administración mediante MFA. Preferir GitHub App/OIDC y tokens de corta duración a PATs. No reutilizar credenciales entre entornos. La identidad que puede modificar Rulesets no debe recibir acceso de producción salvo necesidad justificada.

La matriz de permisos efectiva debe documentar sujeto/rol, repositorio/environment, acciones permitidas, aprobador, fecha de concesión y revisión/revocación.

## 7. Secretos y datos sensibles

Nunca versionar secretos, tokens, certificados privados, DSN reales, credenciales, cookies, refresh tokens, claves de firma ni datos productivos. Usar placeholders ficticios en ejemplos. Los secretos se almacenan en el gestor aprobado o en GitHub Secrets/Environments según su alcance, con acceso mínimo, rotación y revocación.

No pasar secretos por argumentos, logs, outputs, cachés o artefactos. No exponer secretos a workflows que ejecuten código de contribuciones no confiables. Los secretos de desarrollo, pruebas, staging y producción son independientes.

Ante sospecha de exposición: detener la publicación, no copiar el valor a comentarios/PR, identificar el tipo y ubicación sin reproducirlo, solicitar rotación/revocación por el responsable y tratarlo como incidente. Eliminar el texto del último commit no revoca el secreto ni sanea historial, logs o artefactos.

## 8. Excepciones, bypasses y cambios de emergencia

No se conceden bypasses permanentes ni se debilitan Rulesets para acelerar entregas. Una excepción requiere:

- incidente o necesidad concreta y alcance limitado;
- responsable solicitante; si existe otra persona autorizada, aprobador distinto; en el modelo de único mantenedor, revisión propia documentada y controles compensatorios;
- motivo, riesgo, controles compensatorios y rutas/commits afectados;
- duración/expiración explícita;
- registro en issue/PR privado o restringido según sensibilidad;
- revisión posterior, restauración de controles y evidencia.

Los cambios de emergencia deben conservar trazabilidad y someterse a revisión posterior tan pronto como sea posible. No registrar secretos ni detalles explotables en issues públicos. La excepción no autoriza omitir rotación de credenciales expuestas ni controles legales/privacidad.

## 9. Checklist de PR seguro

- [ ] Rama y commits siguen las convenciones.
- [ ] Alcance acotado y vinculado a requisitos/ADR.
- [ ] No hay secretos, datos personales ni artefactos locales.
- [ ] Dependencias nuevas/actualizadas están justificadas y revisadas.
- [ ] Workflows y permisos tienen mínimo privilegio.
- [ ] Contratos, ownership y documentación permanecen coherentes.
- [ ] Pruebas/checks aplicables ejecutados; resultados y límites declarados.
- [ ] Revisión propia estructurada completada y registrada por el único mantenedor.
- [ ] CI obligatorio completado; no se simula una aprobación independiente.
- [ ] Si hay colaboradores autorizados disponibles, Code Owners y revisores especializados participaron cuando aplica.
- [ ] Riesgos/excepciones tienen responsable y vencimiento.
- [ ] Changelog actualizado cuando corresponde.

## 10. Estado de aplicación

La política de contribución y este checklist describen el estándar que debe seguir el equipo. La aplicación técnica depende de Rulesets/branch protection, permisos, CODEOWNERS y workflows configurados en GitHub. El estado efectivo se mantiene en [github-protection-setup.md](./github-protection-setup.md).

**La subfase 0.2 solo puede cerrarse cuando las protecciones reales de `main`, los checks obligatorios, la política de permisos y el flujo de revisión propio estén alineados y probados. La revisión independiente no es requisito mientras el proyecto tenga un único mantenedor; se convierte en requisito al incorporar un segundo colaborador autorizado y actualizar el Ruleset.**
