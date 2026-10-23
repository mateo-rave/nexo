# ADR-0004: Gestión de entornos, migraciones y pruebas

- Estado: Aceptada (provisional)
- Fecha: 2026-10-23 (propuesta y aceptación provisional)
- Responsables: propietario del producto

> **En pocas palabras:** por ahora no instalamos Docker. Trabajaremos con un proyecto de Supabase en la nube que sirve **solo para desarrollo** (un "laboratorio" donde se puede probar y romper sin afectar a clientes reales). Los cambios de la base de datos se escriben en archivos SQL numerados (migraciones) guardados en Git y se envían a ese proyecto con la CLI de Supabase. Producción será otro proyecto distinto, creado más adelante. Ni las cuentas ni el proyecto existen todavía: los creará el propietario.

## Contexto
La máquina de desarrollo actual (Windows) no tiene Docker, Supabase CLI, Deno ni PostgreSQL instalados (inspección del 2026-10-23). El entorno local completo de Supabase (`supabase start`, `supabase test db` contra la base local) usa contenedores y requiere un runtime compatible con Docker. Se necesitan entornos separados, migraciones reproducibles y pruebas que no toquen producción.

## Opciones consideradas
1. **Local con Supabase CLI + Docker Desktop.** Paridad alta con la plataforma, pruebas rápidas y sin coste. Requiere instalar Docker Desktop (y en Windows, WSL 2) y recursos de máquina.
2. **Sin Docker local: proyecto Supabase de desarrollo en la nube + CI.** Desarrollo contra un proyecto remoto exclusivo de desarrollo; las pruebas completas se ejecutan en GitHub Actions, cuyos runners Linux incluyen Docker. Feedback más lento; riesgo de datos compartidos si el proyecto remoto no se limpia.
3. **Supabase Branching.** Entornos efímeros por rama. Depende del plan contratado; pendiente de verificar coste y disponibilidad.

## Decisión
- **Vigente:** opción 2. Proyecto Supabase en la nube **exclusivo para desarrollo**, sin Docker local (decisión del propietario, 2026-10-23).
- **CI:** se añadirá cuando exista la cuenta de GitHub; sus runners Linux sí incluyen Docker.
- **Futuro:** la opción 1 (Docker local) queda como mejora para cuando el ciclo de pruebas contra la nube resulte lento.
- **Branching:** la opción 3 se reevaluará al elegir plan.
- Ninguna prueba se declarará aprobada si no se ejecutó en alguno de estos entornos.

### Qué funciona sin Docker (a confirmar al instalar la CLI)
| Comando / acción | Uso | ¿Necesita Docker? |
|---|---|---|
| `supabase init` | Crea la carpeta `supabase/` en el repositorio. | Según la documentación, no. |
| `supabase migration new <nombre>` | Crea un archivo de migración vacío con fecha. | No (solo crea un archivo). |
| `supabase login` / `supabase link` | Conecta la CLI con el proyecto de desarrollo. | Según la documentación, no. |
| `supabase db push --dry-run` / `db push` | Muestra y aplica las migraciones pendientes en el proyecto remoto. | Según la documentación, no. |
| `supabase test db` contra el proyecto remoto | Ejecutar pgTAP. | **No verificado.** La documentación lo describe para la base local. |
| `supabase start`, `db reset` local, `functions serve` | Entorno local completo. | Sí; no se usarán por ahora. |

### Cómo se ejecutarán las pruebas pgTAP sin Docker
1. Primero se comprobará si la versión instalada de la CLI permite ejecutar `supabase test db` contra el proyecto enlazado sin Docker.
2. Si no lo permite, cada archivo de prueba se ejecutará en el **SQL Editor del proyecto de desarrollo**. Cada archivo:
   - empieza con `begin;` y termina con `rollback;`, así no deja datos;
   - crea la extensión pgTAP dentro de la propia prueba, para que la migración de producción no la incluya.
3. Cuando exista GitHub, CI ejecutará `supabase test db` con Docker de forma automática.

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
- Hasta instalar Docker, las pruebas de base de datos dependen del proyecto remoto de desarrollo y, más adelante, de CI.
- El ciclo de prueba es más lento que en local: cada cambio se sube por red.
- El proyecto remoto es compartido. Si dos personas trabajan a la vez, sus datos de prueba pueden mezclarse. Por eso las pruebas crean sus propios datos y los deshacen con `rollback`.
- La Supabase CLI sigue siendo necesaria. Su instalación es una dependencia que se aprobará en su momento, eligiendo el método según lo disponible: binario, gestor de paquetes o `npx` con Node.js.
- La carpeta del proyecto está dentro de OneDrive; la sincronización puede interferir con `node_modules`, caché de Deno y archivos temporales de la CLI. Se recomienda moverla fuera de OneDrive.
- Se reemplazan pytest, pytest-django, Ruff y Docker Compose propio como herramientas del MVP.

## Cómo se verificará
- `supabase db push --dry-run` muestra exactamente las migraciones esperadas antes de aplicarlas al proyecto de desarrollo.
- Cuando exista CI: `supabase db reset` aplica todas las migraciones y la semilla desde cero sin errores.
- CI ejecuta pgTAP, pruebas de Edge Functions y pruebas de API en cada cambio, y falla si alguna falla.
- Se documenta y ejecuta al menos una restauración de respaldo en un proyecto que no sea producción.
