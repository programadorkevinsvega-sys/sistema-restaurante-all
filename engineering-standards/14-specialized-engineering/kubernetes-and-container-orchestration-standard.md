# Estándar de Kubernetes y orquestación de contenedores

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica solo cuando Kubernetes u otro orquestador se justifica por requisitos operativos.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.
- Mantener responsabilidades, límites de confianza y propiedad explícitos.
- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.
- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Documentar por qué orquestación supera alternativas más simples y asignar equipo responsable del plano de control.
- Separar namespaces/entornos y aplicar RBAC, NetworkPolicies, Pod Security y admission policies.
- Ejecutar workloads sin root, filesystem de solo lectura cuando sea posible, capabilities mínimas y seccomp.
- Definir requests/limits, probes correctas, disruption budgets, afinidad y topología anti-fallo.
- Gestionar secretos mediante mecanismos externos/rotación; no incrustarlos en imágenes o manifests.
- Fijar imágenes por digest, escanear y verificar firmas/procedencia.
- Gestionar ingress/egress, TLS, service accounts y permisos de cloud.
- Probar upgrades, rollback, autoscaling, node failure, pérdida de zona y recuperación de volúmenes.
- Definir política de versiones soportadas, parches, backups del estado y runbooks del clúster.

## 4. Antipatrones

- Adoptar herramientas sin requisitos ni evaluación de operación.
- Confiar en controles exclusivamente del cliente cuando el servidor debe hacer cumplir la regla.
- Registrar datos sensibles innecesarios o exponerlos en logs/telemetría.
- Ignorar fallos parciales, cambios de versión, límites de capacidad o dependencias externas.
- Considerar la existencia de documentación como prueba de implementación.

## 5. Verificación y evidencia

El proyecto DEBE definir pruebas automatizadas y controles manuales proporcionales al riesgo. Conservar resultados, configuración, responsables, excepciones y evidencias reproducibles. La conformidad se registra requisito por requisito en la matriz del proyecto.

## 6. Decisiones específicas

Las tecnologías, versiones, topologías, proveedores, umbrales y SLO se seleccionan en ADR o especificaciones del proyecto. No se heredan de ejemplos de esta biblioteca.

## 7. Revisión

Revisar ante cambios de alcance, amenazas, plataforma, proveedor, regulación, incidentes o evolución significativa del estándar.
