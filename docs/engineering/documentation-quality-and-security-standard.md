# Estándar de calidad, seguridad y mantenimiento documental

**Estado:** estándar documental aprobado y vigente en `main`, integrado mediante PR #8.  
**Ámbito:** todo el repositorio Restaurant OS: procesos backend, BFF, aplicaciones, módulos, crates, contratos, infraestructura, scripts y documentación transversal.  
**Jerarquía:** estándar especializado subordinado al [Estándar general de arquitectura](../architecture/engineering-standard.md), a la [Arquitectura de Restaurant OS](../architecture/restaurant-os-architecture.md), a los ADR aceptados y a los requisitos oficiales.

Este documento adapta prácticas de calidad documental de referencia a la arquitectura y al estado real de este repositorio. No importa ownership, topologías, productos, frameworks ni componentes de otros proyectos.

## 1. Objetivo y regla fundamental

La documentación es un artefacto de ingeniería. Debe ser precisa, coherente, verificable, reproducible, segura, comprensible y mantenible.

**La documentación describe la realidad comprobable del repositorio; nunca presenta una arquitectura futura, una propuesta o una intención como implementación terminada.**

Toda afirmación técnica debe estar respaldada por código, configuración, contratos, pruebas ejecutadas, scripts existentes, infraestructura verificable o decisiones aceptadas. Si no puede comprobarse, se omite o se etiqueta explícitamente como planificada, pendiente o no verificada.

## 2. Alcance y estructura documental

Este estándar se aplica a:
- README raíz y README de directorios/componentes.
- Los cuatro procesos independientes: Admin Platform Backend, Admin BFF, Public BFF y Public Backend.
- Los módulos y sus crates de implementación y contratos.
- Aplicaciones frontend y paquetes reutilizables existentes.
- Contratos HTTP/OpenAPI, gRPC/Protobuf y eventos.
- Workers, jobs y adaptadores.
- PostgreSQL, NATS, Redis, infraestructura, despliegue y observabilidad.
- Scripts, herramientas, configuración, ADR, requisitos y roadmap.

Cada componente debe tener documentación propia solo cuando ayude a entender su responsabilidad, límites, requisitos, configuración, ejecución, pruebas o integración. No crear README vacíos, repetidos o artificialmente extensos.

El README resume y enlaza fuentes normativas; no copia ADR, requisitos ni estándares completos. Cada decisión debe tener una fuente oficial única.

## 3. Exactitud y evidencia

Está prohibido:
- Inventar funcionalidades, endpoints, comandos, variables, dependencias, versiones o integraciones.
- Presentar ejemplos o pseudocódigo como implementación funcional.
- Declarar pruebas, compilaciones, CI, despliegues o infraestructura como exitosos/activos sin evidencia verificable.
- Declarar un componente IMPLEMENTED por tener solo carpetas, manifests, interfaces, contratos, mocks o tests no ejecutados.
- Confundir compilación con funcionamiento, pruebas locales con aceptación productiva o código existente con despliegue.
- Ocultar limitaciones, fallos, bloqueos o trabajo parcial para mejorar la presentación.

Antes de documentar comandos, variables o dependencias, inspeccionar el manifest, configuración, código y scripts que los consumen. No documentar comandos objetivo como si fueran utilizables.

Los ejemplos deben ser válidos para el stack y las versiones comprobadas. Si son ilustrativos, marcarlos como tales y no atribuirles comportamiento existente.

## 4. Coherencia con la arquitectura de Restaurant OS

Toda documentación debe respetar la topología de cuatro procesos independientes:
1. Admin Platform Backend: propietario de PLATFORM.
2. Admin BFF: proceso separado de composición y exposición HTTP.
3. Public BFF: proceso separado de composición y exposición HTTP.
4. Public Backend: propietario de los demás módulos canónicos.

Los BFF no son propietarios de dominios ni persistencia de negocio. Los módulos mantienen su ownership, contratos, schema, rol, migraciones e historial SQLx independientes conforme a los ADR aceptados. Los módulos no acceden directamente a tablas de otros módulos.

No sustituir esta arquitectura por la topología de CORE/BUSINESS/PLATFORM/PUBLIC de otro proyecto. No importar responsabilidades, nombres de productos, seis frontends, verticales, contratos o tecnologías ajenos.

La distribución y responsabilidades de módulos se consultan en [ADR-0008](../adr/0008-module-ownership-across-four-processes.md) y [requisitos.md](../../requisitos.md). Los límites de crates y dependencias se consultan en [ADR-0009](../adr/0009-crate-boundaries-and-dependencies.md). No redefinirlos desde un README.

Si se detecta una contradicción con una decisión aceptada, identificarla y resolverla en la fuente normativa correspondiente. Si exige cambiar arquitectura, preparar un ADR Proposed y esperar aprobación explícita; no elegir arbitrariamente una versión.

## 5. Seguridad documental

### 5.1 Información prohibida

No incluir en documentación, ejemplos, capturas, logs o artefactos versionados:
- Contraseñas, tokens, API keys, secretos JWT, claves privadas o credenciales SSH/TLS.
- Credenciales reales de PostgreSQL, Redis, NATS, cloud, Vault u otros proveedores.
- DSN/connection strings reales, cookies, refresh tokens o URLs firmadas temporales.
- Variables reales de producción, backups o dumps de bases de datos.
- Datos personales, financieros o privados de clientes, usuarios o tenants.
- IP, hostnames, rutas, topologías o detalles operativos privados que no sean necesarios para comprender la arquitectura.
- Información de incidentes no autorizada para publicación o cualquier dato que facilite acceso no autorizado.

Documentar tecnologías y arquitectura general sí está permitido. Los ejemplos deben usar placeholders inequívocos, dominios reservados para documentación o valores locales ficticios. No copiar archivos `.env` reales.

### 5.2 Variables de entorno

Solo documentar variables que el código/configuración realmente consuma. Para cada variable aplicable, indicar:
- Nombre exacto y componente consumidor.
- Finalidad.
- Si es obligatoria u opcional.
- Formato esperado.
- Valor predeterminado seguro, solo si existe.
- Si contiene un secreto o es configuración pública.

Un `.env.example` debe estar libre de secretos y sincronizado con el código. Nunca incluir secretos en ejemplos de frontend ni variables privadas en bundles públicos.

### 5.3 Exposición detectada

Si se encuentra un secreto:
1. No repetirlo en commits, comentarios, PR, ejemplos ni reportes.
2. Detener la publicación y tratarlo como posible exposición.
3. Informar el tipo de archivo/ubicación sin reproducir el valor.
4. Solicitar el procedimiento autorizado de revocación/rotación y respuesta a incidentes.
5. Considerar historial Git, artefactos, logs y copias; borrar el texto visible no revoca una credencial.

No intentar reescribir historial, revocar credenciales ni cambiar secretos sin autorización y procedimiento explícitos.

## 6. Clasificación documental

La clasificación depende de la sensibilidad y de los permisos reales del repositorio/ubicación:
- **Pública:** información expresamente aprobada para usuarios externos; descripción del producto, guías públicas y ejemplos seguros.
- **Interna:** ADR, arquitectura detallada, contratos internos, modelos, flujos técnicos y guías para colaboradores autorizados.
- **Restringida:** runbooks sensibles, recuperación, incidentes, accesos operativos, topologías privadas y configuraciones de infraestructura.

No asumir que un archivo es público o privado por su nombre. No guardar secretos en ninguna clasificación. No enlazar desde documentación pública a recursos privados inaccesibles para sus destinatarios. No trasladar procedimientos restringidos a README.

## 7. README raíz

El README raíz es el punto de entrada del repositorio y debe ofrecer una visión breve y honesta. Cuando se cree o actualice, incluir únicamente información aplicable y verificable:
1. Nombre y propósito del proyecto.
2. Estado real y alcance actual.
3. Arquitectura general y cuatro procesos.
4. Responsabilidades de backends/BFF y enlaces a su documentación.
5. Estructura del repositorio.
6. Tecnologías verificadas en manifests/configuración.
7. Requisitos, instalación, configuración, ejecución y pruebas solo si existen y se verificaron.
8. Seguridad, contribución y flujo Git/PR realmente configurado.
9. Enlaces a requisitos, arquitectura, ADR, reglas, roadmap y guías de componentes.
10. Licencia, organización, contacto o canal de vulnerabilidades solo si están definidos y autorizados.

No convertirlo en copia de los estándares. No inventar eslogan, promesas comerciales, licencia, contacto, badges, CI, cobertura o canales de seguridad. Los temas no aplicables o no verificables se omiten o se identifican como pendientes.

### 7.1 Elementos visuales y badges

Usar solo assets oficiales del repositorio con procedencia y autorización verificadas. Los diagramas deben reflejar los cuatro procesos y sus límites, diferenciar lo planificado de lo implementado y mantenerse junto al repositorio (por ejemplo Mermaid). Las capturas deben ser reales, autorizadas y no revelar datos sensibles. No crear maquetas para insinuar funcionalidades inexistentes ni incrustar imágenes de terceros sin licencia/autorización.

Los badges son opcionales. Solo se admiten si su fuente es real, accesible y vigente. No agregar badges de CI, cobertura, licencia, seguridad, versión o estado sin evidencia reproducible. Retirar los que dejen de ser exactos.

## 8. README de componentes

Adaptar la estructura al propósito del componente. Cuando aplique, documentar:
- Identificación: nombre, tipo, responsabilidad y ubicación.
- Descripción: qué es, qué problema resuelve y qué no es responsable de hacer.
- Capacidades: estados de implementación con evidencia.
- Arquitectura: ownership, límites, dependencias autorizadas, contratos e integraciones.
- Tecnologías y versiones verificadas.
- Requisitos previos.
- Instalación y configuración seguras.
- Comandos reales de ejecución.
- Pruebas y controles de calidad existentes.
- Estructura de directorios que realmente existe.
- Documentación relacionada y seguridad.

No exigir secciones vacías. No documentar directorios futuros como existentes. Los BFF se describen como composición/transporte y no como propietarios de reglas de negocio o acceso directo a PostgreSQL de negocio.

## 9. Estados de implementación

Usar estos estados inequívocos cuando se informe el estado de una capacidad:
- `IMPLEMENTED`: implementada y verificada con evidencia adecuada.
- `PARTIALLY_IMPLEMENTED`: existe una implementación incompleta.
- `IN_PROGRESS`: está en desarrollo.
- `PLANNED`: planificada, no implementada.
- `NOT_AVAILABLE`: no está disponible.
- `DEPRECATED`: obsoleta o en retirada.
- `BLOCKED`: bloqueada por dependencia o decisión pendiente.

Los estados se asignan a capacidades concretas, no indiscriminadamente a todo un componente. Una carpeta, interfaz, contrato, mock o test no ejecutado no demuestra por sí solo IMPLEMENTED. No usar porcentajes sin metodología objetiva ni confundir estado de desarrollo con estado de producción.

## 10. Comandos, ejemplos y enlaces

Todo comando documentado debe existir, corresponder al entorno descrito y tener finalidad clara. Verificarlo cuando sea posible. Debe señalar requisitos y efectos relevantes. Los comandos destructivos requieren advertencia explícita y prerrequisitos.

Los ejemplos de código deben ser válidos, seguros y compatibles con las APIs/versiones comprobadas. No usar credenciales reales ni pseudocódigo presentado como código ejecutable.

Los enlaces deben:
- Preferir rutas relativas dentro del repositorio.
- Apuntar a archivos/rutas existentes.
- Evitar enlaces temporales, privados o dependientes de ramas efímeras.
- Mantenerse actualizados cuando se muevan documentos.
- Evitar duplicar documentos para corregir referencias.

## 11. Sincronización y fuente de verdad

Actualizar la documentación afectada cuando cambien responsabilidades, capacidades, contratos, endpoints, configuración, variables, dependencias, comandos, requisitos, pruebas, arquitectura, integraciones o procedimientos.

Fuentes principales:
- Arquitectura y decisiones: estándar de arquitectura, arquitectura de Restaurant OS y ADR aceptados.
- Ownership y requisitos: `requisitos.md`.
- Fases y entregables: `ROADMAP.md`.
- HTTP/gRPC/eventos: contratos fuente correspondientes.
- Implementación y operación: reglas vigentes y documentación del componente.
- Gobernanza GitHub: [guía de protección de main](./github-protection-setup.md).

El README enlaza la fuente normativa; no la reemplaza. Los documentos bajo `rules/` están marcados como históricos/superseded y no se deben reactivar ni duplicar sus reglas. Las correcciones se realizan en las fuentes vigentes.

## 12. Validación documental y CI

Toda modificación documental debe revisar, según el alcance:
- Sintaxis y formato Markdown.
- Jerarquía de encabezados y estructura.
- Enlaces y rutas internas.
- Referencias a scripts, manifests y componentes.
- Coherencia con ADR, ownership y requisitos.
- Comandos, variables y versiones citados.
- Exposición accidental de secretos o datos sensibles.

La automatización puede incorporar validadores Markdown, enlaces/rutas, detección de secretos y comprobaciones de coherencia con manifests/configuración. Las reglas de detección deben contemplar falsos positivos; las excepciones deben estar justificadas, acotadas y nunca contener secretos reales.

### 12.1 CI selectivo

Una modificación exclusivamente documental debería ejecutar validaciones documentales y de seguridad aplicables, sin ejecutar innecesariamente toda la batería de compilación/test de Rust o frontend. Si el cambio también afecta código, contratos, scripts o workflows, ejecutar las validaciones correspondientes a esas áreas.

La selección debe basarse en rutas/alcance verificables y no permitir omitir controles por etiquetar incorrectamente un cambio.

**Estado actual:** este estándar define los controles deseados, pero no demuestra que exista un workflow documental, escáner de secretos o validador de enlaces. No se deben declarar activos hasta que estén implementados y sus ejecuciones sean verificables. La incorporación o modificación de workflows/scripts de CI requiere alcance y autorización explícitos; no forma parte de este documento por sí sola.

## 13. Revisión de documentación en Pull Requests

Todo PR que modifique arquitectura, capacidades, contratos, configuración, dependencias, comandos, pruebas o procedimientos debe revisar la documentación afectada.

La descripción del PR debe permitir conocer:
- Qué documentación cambió y por qué.
- Qué código, configuración, contrato o decisión respalda cada afirmación.
- Qué se verificó y con qué evidencia.
- Qué permanece planificado, pendiente, bloqueado o no verificado.
- Qué validaciones se ejecutaron y cuáles no.

No declarar que CODEOWNERS exige revisión sin Ruleset/branch protection efectivo. No afirmar CI obligatorio sin workflow/checks configurados y verificados. La guía de protección de main documenta el estado objetivo y no prueba por sí misma que esté activo.

## 14. Procedimiento obligatorio para agentes

Antes de modificar documentación:
1. Leer completo el documento que se va a cambiar.
2. Inspeccionar el componente, código y estructura existente.
3. Revisar manifests, configuración, scripts y pruebas relacionados.
4. Revisar contratos, requisitos y ADR relevantes.
5. Seguir enlaces a fuentes normativas y detectar contradicciones.
6. Identificar datos sensibles y clasificación documental.
7. Definir el alcance exacto y los archivos afectados.

Después de modificar:
1. Revisar el diff completo.
2. Validar Markdown, enlaces y rutas con herramientas disponibles.
3. Verificar comandos, variables y afirmaciones contra fuentes reales.
4. Revisar secretos/datos sensibles.
5. Comprobar ownership y coherencia arquitectónica.
6. Ejecutar validaciones documentales disponibles.
7. Reportar cambios, evidencia, limitaciones y verificaciones no ejecutadas.

No inventar validaciones ni declarar éxito sin ejecutarlas. No borrar información correcta, advertencias o limitaciones sin justificación. No realizar actualizaciones cosméticas masivas que oculten cambios funcionales.

## 15. Definition of Done documental

Una modificación documental está terminada cuando cumple todos los criterios aplicables:
- [ ] Describe el estado real y distingue implementación de planificación.
- [ ] Respeta la arquitectura, ownership y ADR aceptados.
- [ ] No inventa capacidades, comandos, variables, versiones o resultados.
- [ ] No expone secretos, datos personales ni detalles restringidos.
- [ ] Los enlaces y rutas existen.
- [ ] Los comandos/configuración citados fueron contrastados.
- [ ] No duplica fuentes normativas ni reactiva documentos históricos.
- [ ] Se ejecutaron las validaciones disponibles y se reportaron las no ejecutadas.
- [ ] El PR explica el cambio, su evidencia y los pendientes.

La documentación general se considera coherente cuando los índices y referencias cruzadas apuntan a las fuentes vigentes y no existen contradicciones conocidas sin registrar.

## 16. Relación con otros estándares

Este documento complementa, pero no sustituye:
- [Estándar general de arquitectura](../architecture/engineering-standard.md).
- [Arquitectura de Restaurant OS](../architecture/restaurant-os-architecture.md).
- [Reglas de implementación](./implementation-rules.md).
- [ADRs](../adr/README.md).
- [Requisitos](../../requisitos.md).
- [Roadmap](../../ROADMAP.md).
- [Gobernanza de GitHub](./github-protection-setup.md).

Ante conflictos, aplicar la precedencia documental oficial. Una modificación de arquitectura requiere ADR y aprobación explícita; una regla documental no puede modificar ownership, límites de módulos ni contratos.

## 17. Regla final

**Realidad verificable → documentación coherente → validación disponible → revisión por PR → mantenimiento sincronizado.**

Un README profesional no promete lo que todavía no existe: explica con claridad qué existe, qué responsabilidad tiene, cómo se utiliza cuando hay instrucciones verificadas y cuáles son sus límites.
