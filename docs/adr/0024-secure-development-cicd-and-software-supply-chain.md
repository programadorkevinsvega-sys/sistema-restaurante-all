# ADR-0024: Desarrollo seguro, CI/CD y cadena de suministro de software

- Estado: **Proposed**
- Fecha: 2026-11-25
- Ámbito: repositorios, revisión, dependencias, workflows, construcción, artefactos, publicación y despliegue.
- Complementa: ADR-0009, ADR-0015, ADR-0020 y ADR-0023.
- Aprobación: pendiente de aprobación explícita.

## Contexto

Dependencias transitivas, acciones de CI, imágenes base, herramientas, credenciales de pipeline y artefactos pueden introducir vulnerabilidades o código malicioso. Un workflow con permisos excesivos puede convertir una contribución no confiable en acceso a secretos o producción. Se requiere trazabilidad desde commit hasta despliegue.

## Decisión propuesta

### 1. Repositorios y ramas

- Proteger main y ramas críticas mediante Rulesets/branch protection realmente configurados.
- Exigir PR, impedir force-push/borrado de ramas protegidas y exigir checks relevantes.
- Exigir revisión humana para cambios de seguridad, workflows, infraestructura, dependencias y políticas.
- CODEOWNERS se combina con reglas de revisión obligatoria; el archivo por sí solo no impone enforcement.
- Proteger cuentas con escritura/administración mediante MFA.
- Separar permisos de lectura, escritura, administración y despliegue.
- Registrar excepciones, cambios de emergencia y bypasses.
- Aprobación de agente no sustituye revisión humana requerida.

### 2. Workflows y CI

- Permisos mínimos por workflow/job; tokens limitados y de corta duración.
- No conceder write global si el job solo requiere lectura.
- Fijar acciones de terceros a SHA completo verificable cuando sea compatible.
- Revisar acciones, imágenes y herramientas antes de incorporarlas.
- Separar validación de contribuciones no confiables de publicación/despliegue privilegiados.
- No ejecutar código de forks/PR no confiables con secretos privilegiados.
- Evitar interpolar datos no confiables en shell.
- Limitar permisos de runners, filesystem, red y persistencia entre jobs; preferir runners efímeros/aislados para trabajos de riesgo.
- No exponer secretos en logs, argumentos, outputs, cachés ni artefactos.
- Proteger environments productivos con aprobaciones y restricciones de rama/actor.

### 3. Análisis automatizado

Integrar progresivamente SAST, SCA, secret scanning, escaneo de imágenes/OS packages, IaC scanning cuando exista infraestructura como código, DAST controlado, fuzz testing de parsers/validadores/contratos, verificación de licencias, SBOM y análisis de procedencia/firmas. Las herramientas no garantizan seguridad absoluta. Hallazgos requieren triage y no deben ignorarse ni bloquearse indiscriminadamente.

### 4. Política de dependencias

Mantener lockfiles; revisar cambios transitivos; preferir paquetes mantenidos y con licencia compatible; evitar dependencias abandonadas, duplicadas o innecesarias; registrar origen/versión/licencia/justificación de dependencias sensibles; priorizar CVE explotables; revisar actualizaciones mayores; restringir registries; revisar typosquatting, scripts de instalación y comportamiento de build; separar dependencias de producción, desarrollo y CI.

### 5. SBOM, procedencia y artefactos

- Generar SBOM utilizable por artefacto/release.
- Relacionar commit, workflow, dependencias, imagen, artefacto y release.
- Producir procedencia verificable del build.
- Firmar artefactos y verificar firma/procedencia antes de despliegue cuando sea viable.
- Promover artefactos inmutables: el contenido probado es el que llega a producción.
- Evitar reconstruir contenido diferente entre staging y producción.
- Mantener inventario de versiones desplegadas y capacidad de identificar componentes afectados por CVE.
- Proteger repositorios de artefactos y limitar publicación/promoción.

### 6. Ambientes y credenciales

Separar desarrollo, pruebas, staging y producción. Usar secretos distintos. No copiar datos productivos sin autorización y anonimización. Workflows de prueba no reciben credenciales de producción. Despliegues productivos usan identidad temporal y autorización del environment. Rollback usa artefactos verificados ya construidos.

### 7. Gestión de vulnerabilidades

Cada hallazgo registra severidad, activo, versión, exposición, explotabilidad, propietario, plazo y evidencia de cierre. Definir objetivos de tratamiento por severidad antes de producción. Vulnerabilidades explotadas activamente y secretos expuestos se tratan como incidentes. Aceptación temporal de riesgo requiere responsable, mitigación y expiración. Mantener proceso zero-day, divulgación responsable y reescaneo tras corregir.

### 8. Revisión y gates

Pruebas funcionales y de seguridad pueden ser checks separados. Cambios de auth, autorización, validación, archivos, pagos, datos multi-tenant, criptografía y workflows requieren pruebas negativas. La aprobación del PR y la aceptación de ADR son actos distintos. CI verde no equivale a revisión completa ni autorización de despliegue.

## Alternativas consideradas

Revisión solo manual y escáneres como única garantía se rechazan. Acciones sin SHA fijado, secretos de producción en PRs y reconstrucción distinta entre entornos se rechazan. Bloquear todos los hallazgos sin triage se rechaza.

## Consecuencias

Mejora trazabilidad y reduce riesgo de dependencias/workflows/artefactos comprometidos. Añade tiempo de CI, herramientas, falsos positivos, SBOM y disciplina de actualización.

## Límites

No selecciona herramientas, runners, registries, formato SBOM concreto ni plataforma de despliegue. No configura Rulesets/workflows ni fija SLAs numéricos.

## Plan futuro

Auditar permisos; definir matriz por workflow/environment; integrar escaneo; establecer SBOM/procedencia; firmar/verificar artefactos; aplicar gates; definir proceso de vulnerabilidades; probar workflow comprometido y secreto expuesto.

## Estado de implementación

Proposed. No modifica workflows, reglas GitHub, dependencias, lockfiles, runners, secretos ni despliegues.
