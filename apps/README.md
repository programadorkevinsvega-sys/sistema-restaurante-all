# Aplicaciones

Contiene los cuatro procesos backend independientes y las aplicaciones frontend. Cada proceso tiene su propio punto de entrada; Admin Platform Backend aloja PLATFORM, Public Backend aloja los demás módulos de negocio y los BFF son procesos separados de composición sin propiedad de dominios de negocio. Las aplicaciones frontend consumen HTTP/OpenAPI a través del BFF que les corresponde y no contienen reglas autoritativas de negocio.

La presencia de estas carpetas define la estructura objetivo, no demuestra que los binarios o frontends estén implementados.
