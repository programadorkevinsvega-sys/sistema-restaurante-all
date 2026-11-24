# Adapters

Esta carpeta contiene adaptadores Rust que conectan los puertos de aplicación
con transportes, brokers u otras tecnologías. Un adaptador traduce entre un
contrato y su implementación técnica; no decide las reglas del dominio.

## Contenido

- [`grpc/`](./grpc/): clientes y servidores gRPC para módulos extraídos como
  servicios. En el monolito modular, la comunicación interna debe preferir
  contratos locales; gRPC no es obligatorio entre módulos.
- [`messaging/`](./messaging/): integración con brokers y transporte de
  mensajes, incluyendo publicación o consumo de eventos.
- [`local/`](./local/): integraciones en el mismo proceso o implementaciones
  sustitutas para pruebas, cuando sean necesarias.

## Límites

- Las reglas y los casos de uso pertenecen a los módulos de dominio.
- La persistencia específica de un dominio permanece junto a ese dominio; no
  centralizar todos los repositorios en esta carpeta.
- Los adaptadores implementan puertos definidos por la aplicación y traducen
  errores y datos explícitamente.
- No guardar aquí secretos, configuración de despliegue ni migraciones SQL.

Si `local/` se usa para configuración del entorno local y no para adaptadores
en proceso, esa configuración corresponde a [`infrastructure/docker/`](../../infrastructure/docker/).
