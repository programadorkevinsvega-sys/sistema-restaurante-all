# Baseline de contenedores

**Estado:** diseño aprobado — subfase 0.7
**Versión:** 1.0
**Fecha:** 2026-11-25
**Fase:** 0.7
**Autoridad:** ADR-0023
**Documentos relacionados:**

- [Modelo de red](./network-model.md)
- [Política de secretos](./secrets-policy.md)

---

## 1. Propósito

Define los controles mínimos que debe satisfacer cada imagen y contenedor de los cuatro
procesos antes de ejecutarse en cualquier entorno. No selecciona orquestador, runtime
de contenedores ni plataforma de despliegue.

---

## 2. Imagen base

| Control | Regla |
|---|---|
| Base mínima | Imagen mínima (distroless, alpine o equivalente); sin herramientas innecesarias |
| Usuario | No-root; UID/GID no-privilegiado definido explícitamente en el Dockerfile |
| Fijación | Imagen base fijada por digest en pipelines privilegiados; no solo por tag |
| Escaneo | Escaneo de vulnerabilidades en cada build y antes de desplegar; fallo bloqueante para críticas/altas no mitigadas |
| Secretos | Sin secretos, credenciales, DSNs ni claves en capas de imagen |
| Build args | Sin secretos en `ARG` ni `ENV` de build; usar bind mounts o secrets de BuildKit |
| Tamaño | Minimizar capas; no incluir compiladores, herramientas de desarrollo ni artefactos de build en la imagen final |

---

## 3. Ejecución del contenedor

| Control | Regla |
|---|---|
| `privileged` | Prohibido salvo justificación documentada y aprobada |
| `--user` | Siempre no-root; coincide con el UID definido en la imagen |
| Capabilities | Retirar todas (`--cap-drop ALL`); añadir solo las estrictamente necesarias |
| Filesystem | Read-only (`--read-only`) cuando sea viable; tmpfs para directorios temporales necesarios |
| `seccomp` | Perfil restrictivo (default Docker/Kubernetes o perfil personalizado); sin `unconfined` en producción |
| AppArmor/SELinux | Perfil restrictivo cuando el host lo soporte |
| `no-new-privileges` | Activado; el proceso no puede escalar privilegios |
| Namespace de red | Aislado por proceso; sin `--network host` salvo necesidad justificada |
| PID namespace | Aislado; sin `--pid host` |

---

## 4. Límites de recursos

Cada contenedor define límites; no se ejecuta sin ellos en producción ni staging.

| Recurso | Regla |
|---|---|
| CPU | `limits.cpu` definido; no ilimitado |
| Memoria | `limits.memory` definido; no ilimitado |
| Procesos/threads | `pids_limit` configurado; no ilimitado |
| Descriptores de archivo | `ulimit nofile` acotado |
| Almacenamiento temporal | `--tmpfs` con tamaño máximo; sin escritura irrestricta en `/tmp` |

Los valores concretos se dimensionan por proceso antes de producción con métricas de carga real.

---

## 5. Secretos en tiempo de ejecución

- Secretos inyectados en runtime mediante variables de entorno desde el gestor de secretos
  o como archivos montados en memoria (tmpfs); nunca en capas de imagen.
- No exponer secretos en variables de entorno de build.
- No logear variables de entorno completas al arrancar.
- El proceso lee el secreto una vez al iniciar o lo consulta al gestor en cada uso crítico.

---

## 6. Health checks y ciclo de vida

| Control | Regla |
|---|---|
| Liveness probe | Definido; fallo reinicia el contenedor |
| Readiness probe | Definido; fallo retira el pod del balanceo antes de reiniciar |
| Startup probe | Definido para procesos con arranque lento |
| Graceful shutdown | El proceso maneja `SIGTERM`; completa requests en curso antes de terminar |
| Timeout de shutdown | Definido; no terminar abruptamente sin tiempo de gracia |

---

## 7. Build y CI/CD

| Control | Regla |
|---|---|
| Dockerfile | Revisado como parte de code review; cambios sensibles requieren revisión de seguridad |
| Acciones de terceros en CI | Fijadas a SHA completo revisado |
| Imágenes de terceros en pipeline | Fijadas por digest cuando se usan en pasos privilegiados |
| Firma de imágenes | Evaluar firma (cosign o equivalente) antes de producción |
| Separación | Jobs de validación de PR no tienen acceso a secretos de producción ni a registros privilegiados |
| Registro | Imágenes publicadas en registro privado; no en registro público salvo decisión explícita |

---

## 8. Checklist por proceso antes de desplegar

- [ ] Imagen base fijada por digest.
- [ ] Sin secretos en capas de imagen.
- [ ] Usuario no-root definido.
- [ ] Escaneo de vulnerabilidades pasado; sin críticas/altas sin mitigar.
- [ ] `privileged: false`.
- [ ] `cap-drop ALL` con solo las capabilities necesarias.
- [ ] `read-only` filesystem o justificación documentada.
- [ ] `no-new-privileges: true`.
- [ ] Límites de CPU, memoria y pids definidos.
- [ ] Health checks (liveness, readiness, startup) definidos.
- [ ] Graceful shutdown implementado.
- [ ] Variables de entorno sin secretos en texto plano.

---

## 9. Estado de implementación

Baseline aprobado. No existen Dockerfiles, imágenes, configuraciones de orquestador
ni pipelines de build implementados. La implementación comienza con la preparación
de infraestructura en cada entorno.
