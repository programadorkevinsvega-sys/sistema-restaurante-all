# Contracts

Esta carpeta contiene los contratos versionados que cruzan los límites de
módulos o servicios. Su objetivo es permitir que productores y consumidores
intercambien datos sin compartir implementaciones internas.

## Contenido

- [`events/`](./events/): esquemas de eventos publicados entre módulos,
  procesos o servicios.
- [`proto/`](./proto/): definiciones Protocol Buffers para las APIs gRPC.

Los contratos deben tener nombres y versiones explícitos, documentar su
compatibilidad y evitar exponer detalles internos de persistencia.

## No incluir

- Reglas de negocio, casos de uso o entidades de dominio.
- Implementaciones de clientes gRPC, brokers o adaptadores.
- Modelos de tablas o consultas SQL.
- Tipos duplicados que puedan generarse desde estos contratos.

Las interfaces internas de una capacidad deben permanecer junto al módulo que
las define. Esta carpeta se reserva para formatos y APIs que realmente cruzan
un límite.
