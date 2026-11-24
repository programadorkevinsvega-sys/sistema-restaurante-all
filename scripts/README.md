# Scripts

Herramientas reproducibles de desarrollo, validación, generación de contratos y operaciones locales. Los scripts no deben duplicar reglas de arquitectura ni ejecutar migraciones de producción automáticamente. Documentar propósito, entradas, efectos y requisitos de cada script.

## Validación documental

- `scripts/docs/check_markdown_links.py`: comprueba enlaces locales y fragmentos de encabezados en los archivos Markdown modificados entre dos referencias Git.
- Ejecución local: `python scripts/docs/check_markdown_links.py --base-ref origin/main --head-ref HEAD`.
- La validación de estilo se ejecuta mediante `markdownlint-cli2` desde el workflow `.github/workflows/documentation-security.yml`.
- El escaneo de secretos usa Gitleaks sobre los commits del rango analizado. La validación del workflow no sustituye la revisión de secretos ya presentes en el historial anterior.
