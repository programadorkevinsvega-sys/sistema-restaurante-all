# Aplicaciones

Contiene los cuatro procesos backend independientes y las aplicaciones frontend. Cada backend tiene su propio punto de entrada en `src/main.rs`; los BFF son procesos separados de sus backends. Las aplicaciones frontend consumen HTTP/OpenAPI a través del BFF que les corresponde y no contienen reglas autoritativas de negocio.

La presencia de estas carpetas define la estructura objetivo, no demuestra que los binarios o frontends estén implementados.
