# Decisiones de arquitectura

Registra aquí las decisiones que afectan estructura, seguridad, dependencias, modelo de datos o despliegue. No registres cada detalle trivial.

Usa una numeración consecutiva (`0001-...md`) y la plantilla `ADR-TEMPLATE.md`.

Una decisión debe incluir contexto, opciones consideradas, decisión tomada, consecuencias, estado y fecha. Si una decisión cambia, crea una nueva ADR que sustituya a la anterior; no borres silenciosamente el historial.

## Índice
| ADR | Título | Estado |
|---|---|---|
| [0001](0001-supabase-como-plataforma-backend.md) | Supabase como plataforma de backend | Aceptada |
| [0002](0002-autenticacion-y-autorizacion-multiempresa.md) | Autenticación y autorización multiempresa | Aceptada |
| [0003](0003-separacion-api-datos-sql-edge-functions.md) | Separación entre Data API, SQL y Edge Functions | Propuesta |
| [0004](0004-entornos-migraciones-y-pruebas.md) | Gestión de entornos, migraciones y pruebas | Propuesta |

La ADR-0001 sustituye la preferencia inicial por Django/DRF/Celery/Redis que figuraba en `CLAUDE.md` (no existía una ADR previa).
