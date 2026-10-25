# Nexo

Nexo es un SaaS multiempresa en construcción para pequeños negocios de servicios. Su objetivo es centralizar y coordinar solicitudes, proyectos, tareas y responsables; detectar bloqueos; y automatizar tareas repetitivas con reglas explícitas, controladas y auditables.

El público inicial (pequeñas agencias digitales y equipos de servicios) es una hipótesis: la validación comercial está pendiente. Visión, requisitos y alcance del MVP en [`docs/product/`](docs/product/).

## Estado actual

- **Backend (Supabase), en construcción:**
  - **Hecho y probado:** esquema base, autenticación con Supabase Auth, organizaciones y membresías (crear organizaciones; agregar, cambiar de rol, quitar y salir de miembros), con RLS y auditoría. Son las dos migraciones de [`supabase/migrations/`](supabase/migrations/), aplicadas en el proyecto de desarrollo.
  - **Pendiente:** las funcionalidades de negocio: proyectos, tareas, flujos de trabajo y automatizaciones.
- **Frontend, en construcción:** aplicación propia en [`frontend/`](frontend/), con Vite, React, TypeScript y Tailwind CSS ([ADR-0006](docs/architecture/decisions/0006-frontend-propio-con-react.md)). Hoy tiene la portada y un panel de demostración con **datos ficticios**: todavía no está conectado al backend y el CI aún no lo compila ni lo comprueba. El despliegue previsto es Vercel, todavía sin configurar.
- **Pruebas:** pgTAP para la base de datos y pruebas de integración de la API con Deno y `supabase-js`. Se ejecutan en GitHub Actions contra un Supabase local y desechable.

El detalle del avance está en el plan de la fase 1: [`docs/plans/`](docs/plans/).

## Estructura del repositorio

| Ruta | Contenido |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Reglas permanentes del proyecto: alcance, arquitectura, identidad visual, seguridad, pruebas y convenciones de nombres. |
| [`docs/`](docs/) | Producto (`product/`), arquitectura y decisiones ADR (`architecture/`), planes por fase (`plans/`), estrategia de pruebas (`qa/`), seguridad y permisos (`security/`) y operaciones (`operations/`). |
| [`frontend/`](frontend/) | Aplicación web (Vite, React, TypeScript y Tailwind CSS) con su propio `package.json` y `package-lock.json`. Scripts: `dev`, `build`, `typecheck`, `lint` y `preview`. |
| [`supabase/`](supabase/) | Configuración local de Supabase (`config.toml`), migraciones SQL (`migrations/`) y pruebas pgTAP (`tests/`). |
| [`pruebas/api/`](pruebas/api/) | Pruebas de integración de la API con Deno y `supabase-js` (`deno.json` y `deno.lock` con versiones fijadas). |
| [`.github/workflows/`](.github/workflows/) | CI: `pruebas-base-datos.yml` levanta un Supabase local, aplica las migraciones y ejecuta las pruebas pgTAP y de API. |
| `package.json` | Fija la versión de la CLI de Supabase usada en el proyecto. |
| `.env.example` | Nombres de variables de entorno con valores de ejemplo, sin secretos reales. |

## Preparar el entorno

Requisitos y detalles en [`docs/operations/development-and-backups.md`](docs/operations/development-and-backups.md).

1. Instalar Node.js (versión 20 o superior, según `package.json`).
2. Instalar la CLI de Supabase en la versión fijada: `npm ci`. Se usa con `npx supabase <comando>`.
3. Las pruebas pgTAP y de API se ejecutan en GitHub Actions. Ejecutarlas en local con `npx supabase start` requiere Docker.
4. Para trabajar con el proyecto remoto de desarrollo, el propietario ejecuta `npx supabase login` y `npx supabase link` en su propia terminal. Las contraseñas y claves no se comparten ni se guardan en Git.

No subas archivos `.env` ni claves secretas al repositorio: `.env.example` es solo una plantilla.

## Documentación clave

- Arquitectura: [`docs/architecture/overview.md`](docs/architecture/overview.md) y decisiones en [`docs/architecture/decisions/`](docs/architecture/decisions/) (ADR-0001 a ADR-0007).
- Pruebas: [`docs/qa/test-strategy.md`](docs/qa/test-strategy.md).
- Seguridad: [`docs/security/threat-model.md`](docs/security/threat-model.md) y [`docs/security/permissions.md`](docs/security/permissions.md).
