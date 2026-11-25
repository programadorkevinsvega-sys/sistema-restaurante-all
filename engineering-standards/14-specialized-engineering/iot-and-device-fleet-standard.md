# Estándar de IoT y gestión de flotas de dispositivos

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica a sensores, terminales, equipos conectados, firmware y dispositivos gestionados.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.

- Mantener responsabilidades, límites de confianza y propiedad explícitos.

- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.

- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Asignar identidad criptográfica única por dispositivo y ciclo de provisión/revocación.

- Evitar secretos compartidos globales; proteger almacenamiento seguro y arranque cuando la plataforma lo permita.

- Firmar firmware y actualizaciones; validar integridad, rollback seguro y recuperación ante actualización fallida.

- Definir inventario, propietario, estado, versión, soporte y fin de vida del dispositivo.

- Segmentar red, limitar egress, autenticar telemetría y controlar comandos remotos.

- Diseñar para conectividad intermitente, almacenamiento limitado, relojes inexactos y sincronización eventual.

- Minimizar telemetría, proteger ubicación y datos personales, y definir retención.

- Probar pérdida/robo, clonación, downgrade, firmware corrupto, revocación y actualización masiva.

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

## Amenazas y escenarios de fallo específicos

Evaluar clonación de identidad, extracción de claves, firmware downgrade, cadena de suministro comprometida, dispositivo perdido, comandos remotos abusivos, reloj manipulado, conectividad intermitente y actualización masiva fallida.

## Pruebas de aceptación mínimas

- Probar provisión, rotación y revocación individual de identidad de dispositivo.

- Rechazar firmware sin firma, alterado, downgrade no autorizado y versiones fuera de política.

- Simular pérdida de conectividad durante actualización y recuperación segura.

- Verificar aislamiento de telemetría/comandos por dispositivo y límites de frecuencia.

- Ensayar inventario, cuarentena, revocación y respuesta a dispositivo robado/comprometido.

- Medir comportamiento ante flota parcial, relojes incorrectos y almacenamiento agotado.

## Operación y evidencias

Conservar inventario de dispositivos/firmware, cadena de firma, historial de provisión/revocación, estado de parches, métricas de flota y runbooks de cuarentena/recuperación.
