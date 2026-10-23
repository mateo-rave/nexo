# ADR-0004: Gestión de entornos, migraciones y pruebas

- Estado: Propuesta
- Fecha: 2026-10-23
- Responsables: propietario del producto

## Contexto
La máquina de desarrollo actual (Windows) no tiene Docker, Supabase CLI, Deno ni PostgreSQL instalados (inspección del 2026-10-23). El entorno local completo de Supabase (`supabase start`, `supabase test db` contra la base local) usa contenedores y requiere un runtime compatible con Docker. Se necesitan entornos separados, migraciones reproducibles y pruebas que no toquen producción.

## Opciones consideradas
1. **Local con Supabase CLI + Docker Desktop.** Paridad alta con la plataforma, pruebas rápidas y sin coste. Requiere instalar Docker Desktop (y en Windows, WSL 2) y recursos de máquina.
2. **Sin Docker local: proyecto Supabase de desarrollo en la nube + CI.** Desarrollo contra un proyecto remoto exclusivo de desarrollo; las pruebas completas se ejecutan en GitHub Actions, cuyos runners Linux incluyen Docker. Feedback más lento; riesgo de datos compartidos si el proyecto remoto no se limpia.
3. **Supabase Branching.** Entornos efímeros por rama. Depende del plan contratado; pendiente de verificar coste y disponibilidad.

## Decisión
- **Recomendada:** opción 1 para desarrollo local, más CI con la misma configuración.
- **Alternativa aceptada mientras no haya Docker:** opción 2. Ninguna prueba se declarará aprobada si no se ejecutó en alguno de estos entornos.
- Branching (opción 3) se reevaluará al elegir plan.

### Entornos
| Entorno | Qué es | Datos | Claves |
|---|---|---|---|
| Local | Supabase CLI (`supabase start`) con Docker. | `supabase/seed.sql` sintético. | Las que genera la CLI local; no son secretas de producción pero no se suben. |
| Desarrollo remoto | Proyecto Supabase dedicado. Opcional si existe entorno local. | Sintéticos; se puede reiniciar. | En `.env` local y en el gestor de secretos de la plataforma. |
| Pruebas / CI | Supabase CLI en GitHub Actions, base efímera por ejecución. | Creados por las propias pruebas. | Generadas en el job; nunca secretos de producción. |
| Producción | Proyecto Supabase separado + Vercel. | Reales. | Secretos solo en Supabase (Edge Function secrets) y Vercel; publicable en el frontend. |

Producción nunca se usa para pruebas ni para ejecutar `db reset`.

### Migraciones
- Todo cambio de esquema, política RLS, función, trigger, extensión y job de cron se versiona en `supabase/migrations/<timestamp>_<descripcion>.sql`.
- No se editan migraciones ya aplicadas en un entorno compartido; se crea una nueva.
- No se hacen cambios manuales en el dashboard de producción. Si se hace un cambio en desarrollo desde el dashboard, se captura como migración antes de continuar.
- Aplicación a producción solo con autorización explícita, tras pasar CI, con respaldo previo verificado.

### Datos de prueba
- `supabase/seed.sql` con datos sintéticos: al menos dos organizaciones, usuarios con cada rol, un usuario sin membresía, proyectos y tareas con fechas vencidas y no vencidas.
- Sin correos, nombres ni datos reales. Dominios de ejemplo (`example.com`).

### Pruebas
| Nivel | Herramienta | Requisito |
|---|---|---|
| Políticas RLS, funciones SQL, triggers | pgTAP mediante `supabase test db` (`supabase/tests/*.test.sql`). Posible uso de `supabase-test-helpers`. | Base local (Docker) o CI. Ejecutar contra un proyecto remoto solo si es de desarrollo; verificar soporte de la CLI antes de usarlo. |
| Edge Functions (lógica pura) | `deno test` sobre módulos sin dependencias de red. | Deno instalado (no requiere Docker). |
| Edge Functions (integración) | `supabase functions serve` + `deno test`, o despliegue a desarrollo. | Docker local, CI o proyecto de desarrollo. |
| Integración de API | Pruebas TypeScript con `supabase-js` y usuarios de prueba: Data API, RPC y Edge Functions, incluidos accesos cruzados. | Supabase local, CI o desarrollo. |
| Flujo completo | Playwright cuando el frontend de Stitch esté integrado. | Frontend en el repositorio. |
| Lint y formato | `deno fmt`, `deno lint`; `supabase db lint` para PL/pgSQL; Security/Performance Advisors. | Deno / CLI; Advisors desde el dashboard. |

Las versiones exactas de Supabase CLI, Deno y librerías se fijarán al instalarlas, verificando su compatibilidad.

## Consecuencias
- Hasta instalar Docker, el ciclo de pruebas de base de datos depende de CI o de un proyecto remoto de desarrollo.
- La carpeta del proyecto está dentro de OneDrive; la sincronización puede interferir con `node_modules`, caché de Deno y archivos temporales de la CLI. Se recomienda moverla fuera de OneDrive.
- Se reemplazan pytest, pytest-django, Ruff y Docker Compose propio como herramientas del MVP.

## Cómo se verificará
- `supabase db reset` (local o CI) aplica todas las migraciones y la semilla desde cero sin errores.
- CI ejecuta pgTAP, pruebas de Edge Functions y pruebas de API en cada cambio, y falla si alguna falla.
- Se documenta y ejecuta al menos una restauración de respaldo en un proyecto que no sea producción.
