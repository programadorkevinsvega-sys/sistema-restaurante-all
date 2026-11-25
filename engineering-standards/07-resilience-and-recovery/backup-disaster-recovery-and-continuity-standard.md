# Estándar de backup, recuperación ante desastres y continuidad

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Asegurar que datos y servicios puedan recuperarse de corrupción, error humano, ransomware, pérdida de infraestructura o desastre regional.

## Requisitos

- Clasificar sistemas y datos por criticidad y definir RPO/RTO aprobados por negocio.
- Definir backups completos e incrementales, logs transaccionales o mecanismos equivalentes según tecnología.
- Cifrar backups en tránsito y reposo y separar credenciales de backup de las credenciales de producción.
- Mantener copias aisladas, inmutables o protegidas contra borrado malicioso cuando el riesgo lo justifique.
- Documentar retención, ubicación, jurisdicción, acceso y eliminación.
- Verificar integridad de backup y ejecutar restauraciones periódicas.
- Probar recuperación completa, recuperación puntual y consistencia de dependencias.
- Definir orden de recuperación, responsables, comunicación y criterios de retorno.
- No considerar una réplica de alta disponibilidad como sustituto de backup.
- Incluir secretos, configuraciones, certificados, artefactos y dependencias necesarias para reconstruir el servicio.
- Proteger el entorno de recuperación contra contaminación desde producción comprometida.

## Continuidad

Mantener runbooks, contactos, dependencias, inventario, procedimientos alternativos y ejercicios tabletop. Registrar resultados, tiempos reales y acciones correctivas.

## Verificación

Restore test con evidencia, simulacro de desastre, validación de RPO/RTO y pruebas de integridad funcional.
