# ADR-0004: Gestión de entornos, migraciones y pruebas

- Estado: Aceptada (provisional)
- Fecha: 2026-10-23 (propuesta y aceptación provisional)
- Responsables: propietario del producto

> **En pocas palabras:** por ahora no instalamos Docker. Trabajaremos con un proyecto de Supabase en la nube que sirve **solo para desarrollo** (un "laboratorio" donde se puede probar y romper sin afectar a clientes reales). Los cambios de la base de datos se escriben en archivos SQL numerados (migraciones) guardados en Git y se envían a ese proyecto con la CLI de Supabase. Producción será otro proyecto distinto, creado más adelante. El propietario ya creó la cuenta y el proyecto de desarrollo `nexo-dev`.

## Contexto
La máquina de desarrollo actual (Windows) no tiene Docker, Supabase CLI, Deno ni PostgreSQL instalados (inspección del 2026-10-23). El entorno local completo de Supabase (`supabase start`, `supabase test db` contra la base local) usa contenedores y requiere un runtime compatible con Docker. Se necesitan entornos separados, migraciones reproducibles y pruebas que no toquen producción.

## Opciones consideradas
1. **Local con Supabase CLI + Docker Desktop.** Paridad alta con la plataforma, pruebas rápidas y sin coste. Requiere instalar Docker Desktop (y en Windows, WSL 2) y recursos de máquina.
2. **Sin Docker local: proyecto Supabase de desarrollo en la nube + CI.** Desarrollo contra un proyecto remoto exclusivo de desarrollo; las pruebas completas se ejecutan en GitHub Actions, cuyos runners Linux incluyen Docker. Feedback más lento; riesgo de datos compartidos si el proyecto remoto no se limpia.
3. **Supabase Branching.** Entornos efímeros por rama. Depende del plan contratado; pendiente de verificar coste y disponibilidad.

## Decisión
- **Vigente:** opción 2. Proyecto Supabase en la nube **exclusivo para desarrollo**, sin Docker local (decisión del propietario, 2026-10-23).
- **CI:** el workflow de GitHub Actions (`.github/workflows/pruebas-base-datos.yml`) está preparado, pero todavía no se ha publicado ni ejecutado: falta crear el repositorio privado y configurar el remoto. Sus runners Linux sí incluyen Docker.
- **Futuro:** la opción 1 (Docker local) queda como mejora para cuando el ciclo de pruebas contra la nube resulte lento.
- **Branching:** la opción 3 se reevaluará al elegir plan.
- Ninguna prueba se declarará aprobada si no se ejecutó en alguno de estos entornos.

### Qué funciona sin Docker (comprobado con Supabase CLI 2.120.0 el 2026-10-23)
| Comando / acción | Uso | ¿Necesita Docker? |
|---|---|---|
| `supabase --version` | Comprueba la instalación. | No. **Verificado** (responde `2.120.0`). |
| `supabase init` | Crea `supabase/config.toml` y `supabase/.gitignore`. Las carpetas `migrations/` y `tests/` se crean al usarlas. | No. **Verificado.** |
| `supabase migration new <nombre>` | Crea un archivo de migración vacío con fecha. | No. **Verificado el 2026-10-24** (creó `20261024161000_esquema_base_organizaciones.sql`). |
| `supabase login` / `supabase link` | Conecta la CLI con el proyecto de desarrollo. | No. **Verificado el 2026-10-24:** el propietario los ejecutó en su terminal y `link` terminó con `Finished supabase link`. |
| `supabase db push --dry-run` / `db push` | Muestra y aplica las migraciones pendientes en el proyecto remoto (`--linked`). | No. **Verificado el 2026-10-24:** el simulacro y la aplicación de la primera migración en `nexo-dev` funcionaron sin Docker (`migration list --linked` la muestra como aplicada). |
| `supabase test db --linked` | Ejecutar pgTAP contra el proyecto enlazado. | **Sí. Verificado el 2026-10-24:** se conecta a `nexo-dev`, pero ejecuta `pg_prove` en un contenedor y falla con `DockerRunError` si no hay Docker ni Podman. No llegó a ejecutar ninguna prueba. |
| `supabase start`, `db reset` local, `functions serve` | Entorno local completo. | Sí; no se usarán por ahora. |

`supabase/config.toml` configura **solo el entorno local** (Docker). No cambia `nexo-dev` salvo que se ejecute `supabase config push`, que no se usará sin revisarlo antes.

### Cómo se ejecutarán las pruebas pgTAP sin Docker
Cada archivo de prueba:
- empieza con `begin;` y termina con `rollback;`, así no deja datos;
- crea la extensión pgTAP dentro de la propia prueba, para que la migración de producción no la incluya.

1. ~~Comprobar si `supabase test db --linked` funciona sin Docker.~~ Comprobado el 2026-10-24: **no funciona** (ver tabla anterior).
2. **Vía elegida: GitHub Actions** (propuesta del 2026-10-24, pendiente de la primera ejecución). El workflow `.github/workflows/pruebas-base-datos.yml` levanta en el servidor de GitHub un Supabase **local y desechable**, le aplica `supabase/migrations/` y ejecuta `supabase test db --local`. No toca `nexo-dev` ni usa credenciales. Detalle en `docs/operations/development-and-backups.md`.
3. Se descartó por ahora el SQL Editor: solo muestra el resultado de la última instrucción (`rollback`), así que habría que adaptar los archivos de prueba para ver los resultados de pgTAP.

### Reglas para el proyecto remoto de desarrollo
- Nunca guardar datos reales.
- Nunca ejecutar `supabase db reset --linked` ni comandos destructivos sin confirmar antes que el proyecto enlazado es el de desarrollo.
- No hacer cambios de esquema desde el dashboard. Si ocurre por error, se convierte en migración antes de seguir.
- La contraseña de la base de datos y las claves las gestiona el propietario: en un gestor de contraseñas y en `.env` local. Nunca se pegan en el chat ni en Git.

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

### Precauciones al escribir migraciones (desde la migración de esquema base, 2026-10-24)
- **Permisos por defecto de tablas y secuencias:** la primera migración retira a `anon` y `authenticated` los permisos automáticos sobre tablas y secuencias nuevas de `public`. Cada tabla nueva nace sin acceso y su migración debe conceder explícitamente solo lo necesario (`grant select`, `grant update (columna)`...).
- **Permisos por defecto de funciones:** PostgreSQL concede `execute` a `PUBLIC` (todos los roles, incluido `anon`) en cada función nueva, en cualquier esquema, y no se puede retirar por esquema. Por eso **cada función nueva** debe incluir `revoke execute on function ... from public, anon;` y después conceder `execute` solo a quien corresponda. La prueba `rls_activado.test.sql` comprueba que `anon` no pueda ejecutar ninguna función invocable de `public` ni de `privado`; excluye solo las que devuelven `trigger` o `event_trigger`, que no se pueden llamar directamente.
- **Nivel de aislamiento:** las protecciones que comparan filas de la misma tabla, como "siempre un propietario", suponen el aislamiento `read committed`, que es el que usa la Data API. Se protegen con un bloqueo de fila (`for no key update`) sobre la organización: tras esperar, cada consulta ve lo confirmado por la otra transacción. Con `repeatable read` o `serializable`, la consulta seguiría viendo la foto inicial y dos cambios simultáneos podrían no detectarse. Si alguna vez se usa otro nivel, hay que revisar estas protecciones.
- **RLS automático de `nexo-dev` (configuración fuera del repositorio):** al revisar `nexo-dev` antes del primer `db push` (2026-10-24) apareció la función `public.rls_auto_enable()` y el event trigger `ensure_rls`. No están en ninguna migración; probablemente los creó Supabase al crear el proyecto, con la opción de activar RLS automáticamente. Activan RLS en cada tabla nueva de `public`. Reglas:
  - **No dependemos de ellos.** Otro proyecto (producción, CI, local) puede no tenerlos. Cada migración activa RLS explícitamente (`alter table ... enable row level security`) y define sus políticas y permisos. La prueba `rls_activado.test.sql` lo comprueba en cualquier entorno.
  - **No se modifican ni se borran** desde nuestras migraciones: los gestiona Supabase.
  - **`rls_auto_enable()` conserva `execute` para `PUBLIC`.** No es invocable directamente (devuelve `event_trigger`). Por eso la prueba de funciones ejecutables por `anon` excluye las funciones que devuelven `trigger` o `event_trigger`: se ejecutan mediante su trigger y no son funciones RPC ordinarias invocables directamente.
  - Al crear el proyecto de producción, decidir y documentar si se activa la misma opción.
- **Orden de bloqueos (para la migración de gestión de miembros y siguientes):** una función que modifique la organización y sus membresías en la misma transacción debe bloquear **primero la organización** (`select ... for no key update`) y después las membresías. El trigger `exigir_propietario` sigue ese orden; si una función lo invierte, dos operaciones simultáneas pueden quedarse esperando la una a la otra (*deadlock*), y PostgreSQL cancelaría una de ellas.

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

Las versiones exactas de Supabase CLI, Deno y librerías se fijarán al instalarlas, verificando su compatibilidad. La de Supabase CLI queda en `package.json`.

## Consecuencias
- Sin Docker local, las pruebas de base de datos se ejecutan en CI: el workflow de GitHub Actions está preparado, pero todavía no se ha ejecutado (falta publicar el repositorio).
- El ciclo de prueba es más lento que en local: cada cambio se sube por red.
- El proyecto remoto es compartido. Si dos personas trabajan a la vez, sus datos de prueba pueden mezclarse. Por eso las pruebas crean sus propios datos y los deshacen con `rollback`.
- **Instalación de la Supabase CLI (decidido el 2026-10-23):** como dependencia de desarrollo del proyecto con npm (`npm install supabase --save-dev`) y uso mediante `npx supabase ...`. Requiere Node.js 20 o superior; la máquina tiene Node.js 24.
  - Ventaja: la versión queda fijada en `package.json` y `package-lock.json`, así que el equipo y CI usan la misma.
  - Se descartaron Scoop (instalación global, versión no registrada en el proyecto) y `npx` sin instalar (descarga cada vez, versión variable).
  - **Instalada el 2026-10-23: versión 2.120.0, fijada exacta.** Se eligió la última versión estable con más de dos semanas publicada (6 de octubre); la 2.122.0 salió el mismo día de la instalación. Para actualizar, cambiar la versión en `package.json`, reinstalar y repetir las comprobaciones de la tabla anterior.
- **Ubicación del proyecto (decidido el 2026-10-23):** se mueve de OneDrive a `C:\dev\nexo`. La sincronización de OneDrive interfiere con `node_modules`, la caché de Deno y los archivos temporales de la CLI. La copia en la nube la dará GitHub cuando exista la cuenta.
- Se reemplazan pytest, pytest-django, Ruff y Docker Compose propio como herramientas del MVP.

## Cómo se verificará
- `supabase db push --dry-run` muestra exactamente las migraciones esperadas antes de aplicarlas al proyecto de desarrollo.
- Cuando exista CI: `supabase db reset` aplica todas las migraciones y la semilla desde cero sin errores.
- CI ejecuta pgTAP, pruebas de Edge Functions y pruebas de API en cada cambio, y falla si alguna falla.
- Se documenta y ejecuta al menos una restauración de respaldo en un proyecto que no sea producción.
