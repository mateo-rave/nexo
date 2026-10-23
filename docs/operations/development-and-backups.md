# Desarrollo, despliegue y respaldos

Estado: provisional. Escenario objetivo: Supabase (backend) + Vercel (frontend). No hay alojamiento contratado. Ver [ADR-0004](../architecture/decisions/0004-entornos-migraciones-y-pruebas.md).

## Requisitos del entorno
| Herramienta | Para qué | Estado en la máquina actual (2026-10-23) |
|---|---|---|
| Git | Control de versiones | Instalado |
| Supabase CLI | Migraciones, entorno local, pruebas pgTAP, tipos, despliegue de Edge Functions | No instalado |
| Docker Desktop (con WSL 2 en Windows) | `supabase start`, `db reset`, `test db` y `functions serve` locales | No instalado |
| Deno | Edge Functions, sus pruebas y pruebas de API | No instalado |
| Node.js | Posible instalación de la CLI con `npx`; herramientas del frontend de Stitch | No verificado |
| Cuenta de Supabase | Proyectos de desarrollo y producción | No configurada |
| Cuenta de Vercel | Despliegue del frontend | No configurada |
| GitHub | Repositorio y CI | Repositorio aún no inicializado |

No presuponer que estas herramientas están disponibles: comprobarlas antes de cada tarea que las requiera. Las versiones se fijan al instalar, verificando compatibilidad.

> La carpeta del proyecto está dentro de OneDrive. Se recomienda moverla fuera (p. ej. `C:\dev\nexo`) para evitar conflictos de sincronización con `node_modules`, la caché de Deno y archivos temporales de la CLI.

## Desarrollo local
**Con Docker (recomendado):**
1. `supabase start` levanta PostgreSQL, Auth, Data API y demás servicios.
2. `supabase db reset` aplica migraciones y `supabase/seed.sql`.
3. `supabase test db` ejecuta pgTAP.
4. `supabase functions serve` sirve Edge Functions localmente.

**Sin Docker:**
- Usar un proyecto Supabase dedicado a desarrollo; aplicar migraciones con la CLI enlazada a ese proyecto.
- Ejecutar las pruebas en CI.
- Verificar qué comandos de la CLI funcionan sin Docker antes de documentarlos como flujo oficial.

Credenciales en `.env` local, nunca en Git. `.env.example` solo documenta nombres y valores ilustrativos.

## Entornos
- **Local:** Supabase CLI, datos sintéticos, claves locales generadas por la CLI.
- **Desarrollo remoto:** proyecto Supabase separado, datos sintéticos, reiniciable.
- **Pruebas/CI:** GitHub Actions con base efímera por ejecución; sin secretos de producción.
- **Producción:**
  - proyecto Supabase propio;
  - secretos en Edge Function secrets y variables de Vercel (solo URL y clave publicable expuestas al cliente);
  - confirmación de correo activa;
  - Site URL y redirecciones restringidas;
  - logs sin información sensible.

### Variables de entorno
| Variable | Dónde | Pública |
|---|---|---|
| URL del proyecto Supabase | Frontend, pruebas, Edge Functions | Sí |
| Clave publicable (`sb_publishable_...`) | Frontend, pruebas | Sí (protegida por RLS) |
| Clave secreta (`sb_secret_...`) | Solo Edge Functions / herramientas de servidor / CI de pruebas | **No** |
| Cadena de conexión a PostgreSQL | CLI, respaldos, herramientas de administración | **No** |
| Credenciales del proveedor de correo | Secrets de Edge Functions | **No** |
| Orígenes permitidos para CORS de Edge Functions | Secrets de Edge Functions | Sí |

El prefijo de las variables públicas del frontend (`VITE_`, `NEXT_PUBLIC_`, etc.) depende del framework que genere Stitch; no se fija hasta inspeccionarlo. Las Edge Functions reciben automáticamente algunas variables de Supabase; verificar cuáles en la documentación vigente al implementarlas.

## Migraciones
- Ubicación: `supabase/migrations/`.
- Una migración por cambio coherente; incluye tablas, políticas, funciones, triggers, extensiones y jobs de cron.
- No editar migraciones aplicadas en entornos compartidos.
- No hacer cambios manuales en producción desde el dashboard.
- Orden de despliegue: CI verde → respaldo verificado → migración en producción con autorización explícita → verificación posterior.

## Respaldos
- La disponibilidad, frecuencia y retención de los backups administrados de Supabase, y de PITR, dependen del plan. Verificarlo al contratar; no asumirlo.
- Independientemente del plan, mantener un respaldo lógico propio (`pg_dump` del esquema y los datos, incluido el esquema `auth` cuando corresponda) cifrado y fuera del proyecto.
- Supabase Storage, si se usa, se respalda por separado: los backups de base de datos no incluyen los objetos.
- El plan operativo debe definir frecuencia, retención, cifrado, ubicación, responsables y objetivos de recuperación (RPO/RTO).
- Un respaldo no se considera verificado hasta restaurarlo en un proyecto que no sea producción y comprobar la integridad: recuento de filas por tabla, políticas RLS activas y una prueba de aislamiento.

No ejecutar scripts destructivos, `db reset` ni restauraciones sobre producción sin autorización explícita y un plan de recuperación.

## Despliegue
- **Backend:** migraciones con Supabase CLI y despliegue de Edge Functions desde CI o manualmente con autorización.
- **Frontend:** Vercel, previews por rama apuntando al proyecto de desarrollo; producción apuntando al proyecto de producción.
- **Comprobaciones de salud:** Edge Function `health` (pendiente) y estado de Supabase.
- **Reversión:** las migraciones no se revierten automáticamente; cada migración de riesgo debe documentar su reversión manual. El frontend se revierte desde Vercel.
- **Verificación posterior:** prueba de humo del flujo crítico con un usuario de prueba y revisión del Security Advisor.
