# Estándar de integración de pagos y controles financieros

**Versión:** 0.1.0 | **Estado:** Draft | **Aplicabilidad:** según perfil, amenazas y alcance del proyecto

## 1. Objetivo y alcance

Aplica a cobros, reembolsos, transferencias, métodos de pago, conciliación o datos financieros.

## 2. Principios

- Definir requisitos por resultados, riesgo y contexto; no por preferencia tecnológica.
- Mantener responsabilidades, límites de confianza y propiedad explícitos.
- Aplicar mínimo privilegio, privacidad, accesibilidad y seguridad desde el diseño cuando correspondan.
- Documentar decisiones, supuestos, dependencias y riesgos residuales.

## 3. Requisitos

- Evitar almacenar datos de tarjeta sensibles; evaluar alcance PCI DSS y usar tokenización/hosted fields/proveedor certificado cuando corresponda.
- Separar autorización, captura, anulación, reembolso, disputa y liquidación como estados/operaciones distintas.
- Diseñar idempotencia de comandos, claves únicas, control de concurrencia y resultado incierto por timeout.
- No marcar pago exitoso por redirección del navegador; verificar notificación autenticada y consultar proveedor cuando sea necesario.
- Conciliar operaciones internas con reportes/liquidaciones externas; detectar faltantes, duplicados y diferencias.
- Mantener ledger/auditoría inmutable según requisitos, precisión decimal, moneda, redondeo y trazabilidad.
- Aplicar segregación de funciones, límites, aprobación y antifraude proporcional al riesgo.
- Definir manejo de webhooks, reversos, chargebacks, cierres y contingencia del proveedor.
- No registrar PAN, CVV, credenciales ni payloads financieros sensibles en logs.
- Validar regulación, impuestos, jurisdicción y obligaciones contractuales con especialistas.

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

## 8. Amenazas y escenarios de fallo específicos

Evaluar doble cargo, reembolso duplicado, webhook falsificado/repetido/fuera de orden, timeout con resultado incierto, manipulación de importes/moneda, fraude, abuso de credenciales, conciliación incompleta, disputa, indisponibilidad del adquirente y exposición de datos de tarjeta. Los requisitos PCI y regulatorios se determinan por alcance, jurisdicción y contratos vigentes.

## 9. Pruebas de aceptación mínimas

- Repetir comandos de cobro/captura/reembolso y verificar idempotencia, unicidad y ausencia de doble efecto.
- Simular timeout antes y después de que el proveedor procese la operación; resolver estado incierto mediante consulta/conciliación.
- Validar firma/autenticidad, replay, duplicados, desorden y retraso de webhooks.
- Probar importes negativos, precisión, redondeo, moneda no soportada, límites y cambio de tipo de cambio.
- Conciliar ledger interno, operaciones del proveedor, settlement, fees, reversos y chargebacks; detectar faltantes y diferencias.
- Verificar segregación de funciones, límites de aprobación, auditoría y ausencia de datos prohibidos en logs.

## 10. Operación y evidencias

Conservar alcance PCI documentado cuando aplique, acuerdos del proveedor, matriz de estados financieros, ledger/auditoría, conciliaciones diarias o por ciclo, reportes de discrepancias, pruebas de recuperación, evidencias de aprobación y runbooks de incidentes.