# Crates compartidos y adaptadores

Solo contiene capacidades técnicas reutilizables y contratos/adaptadores transversales. No aloja módulos propietarios de negocio: esos viven bajo `backend/<backend>/modules/`. Un crate compartido no puede convertirse en propietario accidental de datos o reglas de negocio de otro módulo.
