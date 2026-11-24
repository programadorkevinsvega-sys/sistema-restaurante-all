# Packages

Esta carpeta contiene bibliotecas reutilizables por las aplicaciones frontend.
Los paquetes deben ser pequeños, tener responsabilidades claras y no convertirse
en la fuente de verdad de las reglas del backend.

## Contenido

- [`ui/`](./ui/): componentes visuales compartidos y elementos del sistema de
  diseño.
- [`shared-types/`](./shared-types/): tipos de API usados por los clientes;
  preferir generarlos desde contratos publicados para evitar divergencias.
- [`permissions/`](./permissions/): utilidades de interfaz para presentar u
  ocultar acciones según permisos. La autorización efectiva siempre se valida
  en el backend.
- [`validation/`](./validation/): validaciones reutilizables para formularios y
  experiencia de usuario. El servidor debe validar de nuevo toda entrada.
- [`utilities/`](./utilities/): funciones genéricas que no pertenecen a un
  dominio ni dependen de una aplicación concreta.

## Límites

- No incluir acceso a base de datos ni lógica de dominio autoritativa.
- No duplicar manualmente los contratos entre backend y frontend.
- Evitar dependencias entre paquetes que formen ciclos.
- Mantener las dependencias de interfaz separadas de los crates Rust.
