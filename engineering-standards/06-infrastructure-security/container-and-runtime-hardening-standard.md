# Estándar de endurecimiento de contenedores y runtime

**Versión:** 0.1.0 | **Estado:** Draft

## Objetivo

Reducir la superficie de ataque del sistema operativo, las imágenes, los contenedores y los procesos en ejecución.

## Requisitos

- Ejecutar procesos con usuario no privilegiado y filesystem de solo lectura cuando sea viable.
- Eliminar capabilities innecesarias, evitar modo privileged y limitar namespaces.
- Definir CPU, memoria, procesos, descriptores y límites de almacenamiento.
- Usar imágenes mínimas, reproducibles, mantenidas y escaneadas.
- Fijar imágenes por digest en despliegues de producción cuando sea apropiado.
- No incluir secretos ni herramientas de desarrollo innecesarias en imágenes finales.
- Aplicar seccomp, AppArmor/SELinux o controles equivalentes según plataforma.
- Separar build y runtime, y evitar descargar dependencias no verificadas durante el arranque.
- Mantener health checks que reflejen capacidad real sin filtrar información sensible.
- Definir shutdown ordenado, drenaje de conexiones y manejo de señales.

## Verificación

Escaneo de imágenes, pruebas de privilegios, filesystem, límites, comportamiento de shutdown y ejecución como usuario no root.
