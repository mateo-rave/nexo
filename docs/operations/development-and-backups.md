# Desarrollo, despliegue y respaldos

Estado: provisional. Escenario objetivo: Supabase (backend) + Vercel (frontend). No hay alojamiento contratado. Ver [ADR-0004](../architecture/decisions/0004-entornos-migraciones-y-pruebas.md).

## Requisitos del entorno
| Herramienta | Para qué | Estado en la máquina actual (2026-10-23) |
|---|---|---|
| Git | Control de versiones | Instalado |
| Supabase CLI | Migraciones, entorno local, pruebas pgTAP, tipos, despliegue de Edge Functions | Instalada con npm como dependencia del proyecto: 2.120.0 (`npm install` la restaura) |
| Docker Desktop (con WSL 2 en Windows) | `supabase start`, `db reset`, `test db` y `functions serve` locales | No instalado (no se usará por ahora) |
| Deno | Edge Functions, sus pruebas y pruebas de API | No instalado |
| Node.js | Ejecutar la Supabase CLI con `npx`; herramientas del frontend de Stitch | Instalado (v24) |
| Cuenta de Supabase | Proyectos de desarrollo y producción | Creada; proyecto `nexo-dev` creado por el propietario |
| Cuenta de Vercel | Despliegue del frontend | No configurada |
| GitHub | Repositorio remoto y CI | Cuenta creada (correo `noreply` configurado en el repositorio local). Repositorio privado `mateo-rave/nexo` creado y configurado como remoto `origin` (rama `main`); CI en GitHub Actions |

No presuponer que estas herramientas están disponibles: comprobarlas antes de cada tarea que las requiera. Las versiones se fijan al instalar, verificando compatibilidad.

> **Ubicación del proyecto:** `C:\dev\nexo`, fuera de OneDrive (decisión del 2026-10-23), para evitar conflictos de sincronización con `node_modules`, la caché de Deno y los archivos temporales de la CLI.

**Supabase CLI:** se instala dentro del proyecto con `npm install supabase --save-dev` y se ejecuta con `npx supabase <comando>`.

**Comandos interactivos:** `npx supabase login` abre el navegador y `npx supabase link` pide la contraseña de la base de datos. Los ejecuta **el propietario en su propia terminal**, para que la contraseña no pase por ningún chat ni registro.

## Desarrollo (flujo vigente: proyecto en la nube, sin Docker)
Decisión del 2026-10-23 (ADR-0004). La cuenta de Supabase y el proyecto `nexo-dev` ya existen, y el propietario lo enlazó con la CLI (`npx supabase link`, referencia `ixjupmbusvntlatgxmsi`; el vínculo local está en `supabase/.temp/`, que no se versiona).

**Lo hace el propietario, manualmente (pasos 1 y 2 hechos):**
1. Crear la cuenta de Supabase.
2. Crear un proyecto exclusivo para desarrollo, por ejemplo `nexo-dev`.
3. Guardar la contraseña de la base de datos en un gestor de contraseñas.
4. Copiar la URL y las claves al `.env` local, sin compartirlas en el chat ni en Git.

**Ciclo de trabajo, con la CLI instalada:**
1. `supabase migration new <nombre>` crea el archivo de la migración.
2. Se escribe el SQL en ese archivo y se revisa.
3. `supabase db push --dry-run` muestra lo que se aplicaría al proyecto de desarrollo.
4. `supabase db push` lo aplica.
5. Se ejecutan las pruebas pgTAP (método según ADR-0004).
6. Se revisa el Security Advisor del dashboard.
7. Se guarda en Git.

**Con Docker (futuro, opcional):** `supabase start`, `supabase db reset`, `supabase test db` y `supabase functions serve` en local.

Credenciales en `.env` local, nunca en Git. `.env.example` solo documenta nombres y valores ilustrativos.

## Pruebas de base de datos en GitHub Actions
Con la CLI 2.120.0, `supabase test db` necesita Docker incluso con `--linked` (ADR-0004). Como no instalamos Docker en el ordenador de desarrollo, las pruebas pgTAP se ejecutan en GitHub, cuyos servidores Ubuntu ya traen Docker.

**Workflow:** `.github/workflows/pruebas-base-datos.yml`, job `pgtap`. Se ejecuta en cada *pull request*, en cada *push* a `main` y a mano desde la pestaña Actions (`workflow_dispatch`).

**Qué hace, paso a paso:**
1. `actions/checkout` descarga el repositorio (sin dejar guardado el token de GitHub).
2. `actions/setup-node` prepara Node.js 24.
3. `npm ci` instala la CLI exactamente en la versión de `package-lock.json`.
4. `npx supabase --version` deja constancia de la versión usada.
5. `npx supabase start` crea un Supabase local y vacío **dentro del servidor de GitHub** y le aplica `supabase/migrations/` en orden. Su salida va a un archivo temporal del runner, porque incluye las claves de ese Supabase local: si va bien solo se muestran las líneas `Applying migration ...`, y si falla, un diagnóstico saneado.
6. `npx supabase test db --local` ejecuta los archivos de `supabase/tests/` con pgTAP.
7. `denoland/setup-deno` instala Deno 2.9.8, y `deno check --frozen` descarga `supabase-js`, comprueba sus hashes contra `pruebas/api/deno.lock` y comprueba los tipos.
8. `deno test` ejecuta las pruebas de integración de API de `pruebas/api/` contra el mismo Supabase local, con solo la URL local y la clave publicable local (ver `docs/qa/test-strategy.md`).

Al terminar, GitHub destruye el servidor y la base de datos con él.

**Lo que no hace:** no usa `--linked`, `db push`, `db reset` contra un proyecto remoto, `SUPABASE_ACCESS_TOKEN`, la contraseña de `nexo-dev` ni ningún otro secreto. Sus permisos son solo de lectura del repositorio (`contents: read`).

**Cómo leer el resultado:** en el registro del paso "Ejecutar las pruebas pgTAP":
- **Éxito:** cada archivo termina en `.. ok` y al final aparecen `All tests successful.`, `Files=11, Tests=199` y `Result: PASS`. El job se marca en verde.
- **Fallo:** el archivo afectado muestra `not ok N - <descripción de la comprobación>`, junto con lo esperado y lo obtenido. Al final aparece `Result: FAIL`. El job se marca en rojo.
- Si un archivo ejecuta menos comprobaciones de las que declara su `plan()`, pg_prove también lo marca como fallo.

**Última validación registrada:** ejecución `40134690914`, commit `46b4b629ef914bbe38b79e875b31b88c18eea250`, en el Supabase local y desechable de GitHub Actions: pgTAP `Files=11, Tests=199`, `Result: PASS`; API `ok | 40 passed | 0 failed`. Es la primera ejecución de las pruebas de API; ninguna prueba se ejecutó contra `nexo-dev`.

**Validación anterior, posterior a la aplicación en `nexo-dev`:** ejecución `40132365624` del 2026-10-24 (`push`, commit `681d0215555298fb9e6d388d81329a1e786d21d8`, solo documentación, posterior a la aplicación en `nexo-dev`): se aplicaron las dos migraciones y los once archivos dieron `ok`, `All tests successful.`, `Files=11, Tests=199`, `Result: PASS`. Como todas, se ejecutó contra la base desechable de CI, no contra `nexo-dev`.

**Validación previa a la aplicación en `nexo-dev`:** ejecución `40129717008` del 2026-10-24 (`push`, commit `f15b3726b37c7518f62de508780055f264bf24a8`, solo documentación).
- `npx supabase start` aplicó `20261024161000_esquema_base_organizaciones.sql` y `20261024194726_gestion_miembros.sql`, y `npx supabase test db --local` ejecutó los once archivos, todos con `ok`.
- Resumen: `All tests successful.`, `Files=11, Tests=199`, `Result: PASS`.
- Avisos sin efecto en el resultado: límites de descarga (`toomanyrequests`) de `public.ecr.aws`, que la CLI resolvió descargando de `ghcr.io`.
- Se ejecutaron contra la base local y desechable de CI, no contra `nexo-dev`. En ese momento la migración 2 aún estaba pendiente en `nexo-dev` (según `migration list --linked` y `db push --dry-run --linked`); se aplicó después (ver "Aplicación de la migración 2 en `nexo-dev`").
- La ejecución `40130589952` (commit `af374f669664385bd8493da134ae64cda0965f4d`, solo documentación), inmediatamente anterior a la aplicación, dio el mismo resultado: `All tests successful.`, `Files=11, Tests=199`, `Result: PASS`.

**Validación anterior de la migración 2:** ejecución `40128981309` del 2026-10-24 (`push`, commit `2c21c0ebda80a7cf5675516c318e5c2fd31d7ec9`), con el mismo resultado: `All tests successful.`, `Files=11, Tests=199`, `Result: PASS`.
- La ejecución anterior con la migración 2, `40128592605` (commit `9447e8f`), **falló**: un error de intercalación (*collation*) en una comprobación de `agregar_miembro.test.sql` detuvo ese archivo (`Files=11, Tests=170`, `Result: FAIL`). Se corrigió la prueba, no la migración.

**Validación de la migración 1:** ejecución `40117625548` del 2026-10-24 (`workflow_dispatch`, commit `e16163f2632c295c495ebd287e3eca0a582759dd`).
- `npx supabase start` aplicó `20261024161000_esquema_base_organizaciones.sql` y `npx supabase test db --local` ejecutó los seis archivos, todos con `ok`.
- Resumen: `All tests successful.`, `Files=6, Tests=101`, `Result: PASS`.
- Avisos sin efecto en el resultado:
  - `no files matched pattern: supabase/seed.sql`;
  - límites de descarga (`toomanyrequests`) de `public.ecr.aws`, que la CLI resolvió descargando de `ghcr.io`.
- La ejecución por *push* `40115395090` (mismo commit) figura como `success`, pero sin registros ni pasos accesibles. **No se usa como evidencia.**
- Estas pruebas se ejecutan contra la base local y desechable, no contra `nexo-dev`.

**Comprobación en `nexo-dev` del registro con Supabase Auth (V3, 2026-10-24):**
- Se creó desde el Dashboard el usuario sintético `prueba-v3@example.com`, con "Auto Confirm User".
- Una consulta de solo lectura (`npx supabase db query --linked`) confirmó su perfil, con `nombre_visible = 'Usuario'` y 0 membresías.
- Tras borrarlo desde el Dashboard, otra consulta de solo lectura confirmó 0 cuentas, 0 perfiles y 0 membresías residuales.
- **Límites:** no cubre el envío de `nombre_visible` desde el frontend y no valida la aplicación completa.
- El Security Advisor de la base de datos ya se revisó (2026-10-24, ver `docs/security/threat-model.md`). La configuración de Auth se revisó desde el Dashboard el mismo día y se subió a mano el mínimo de contraseña de 6 a 8 caracteres (detalle y asuntos previos a un lanzamiento público en `docs/security/threat-model.md`).

**Aplicación de la migración 2 en `nexo-dev` (2026-10-24, 20:41 UTC):**
- **Sin respaldo verificado** de `nexo-dev` (opción A aceptada por el propietario). La reversión manual está en "Reversión manual de la migración 2"; no se ha ejecutado.
- **Antes de aplicar:**
  - repositorio sincronizado en `af374f6`, sin cambios locales, con CI `40130589952` en verde;
  - `projects list`: `nexo-dev`, referencia `ixjupmbusvntlatgxmsi`, `ACTIVE_HEALTHY`, `linked: true`;
  - `migration list --linked`: `20261024161000` aplicada; `20261024194726` solo en local;
  - `db push --dry-run --linked`: única migración pendiente `20261024194726_gestion_miembros.sql`.
- **Aplicación:** `npx supabase db push --linked` (CLI 2.120.0), entre 20:41:15 y 20:41:20 UTC. Salida: `Applying migration 20261024194726_gestion_miembros.sql...`, `Finished supabase db push.`, código de salida 0. Sin seeds ni roles. No se ejecutó ningún otro SQL ni se tocó el historial de migraciones.
- **Después de aplicar:**
  - `migration list --linked`: ambas migraciones en local y remoto;
  - `db push --dry-run --linked`: `Remote database is up to date.`;
  - una consulta de solo lectura a `pg_proc` (`npx supabase db query --linked`) confirmó las seis funciones con `search_path` vacío:

| Función | `security definer` | Volatilidad | `execute` para `anon` | `execute` para `authenticated` |
|---|---|---|---|---|
| `privado.exigir_read_committed()` | no | `volatile` | no | no |
| `privado.buscar_usuario_confirmado(text)` | sí | `stable` | no | no |
| `public.agregar_miembro(uuid, text, rol_membresia)` | sí | `volatile` | no | sí |
| `public.cambiar_rol_miembro(uuid, uuid, rol_membresia)` | sí | `volatile` | no | sí |
| `public.quitar_miembro(uuid, uuid)` | sí | `volatile` | no | sí |
| `public.salir_de_organizacion(uuid)` | sí | `volatile` | no | sí |

- **Security Advisor** (`npx supabase db advisors --linked --type security --level info`), antes y después:
  - **antes:** 3 `WARN`, los ya documentados en `docs/security/threat-model.md` (0028 y 0029 de `public.rls_auto_enable()`, 0029 de `public.crear_organizacion`);
  - **después:** 7 `WARN`, ningún `ERROR` ni `INFO`. Siguen los mismos 3, más 4 nuevos `authenticated_security_definer_function_executable` (0029), uno por cada RPC: `agregar_miembro`, `cambiar_rol_miembro`, `quitar_miembro` y `salir_de_organizacion`;
  - los 4 nuevos eran esperados: las RPC son `security definer` y ejecutables por `authenticated` por diseño (ver migración 2 y `docs/security/permissions.md`). No se modificó nada para silenciarlos.
- **Límites:** las RPC no se han llamado en `nexo-dev`; su comportamiento solo está probado con pgTAP en la base desechable de CI. No se ha hecho ninguna prueba de API con `supabase-js`.

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

> **Precaución con `npx supabase projects api-keys`:** el 2026-10-24, con la CLI 2.120.0 y **sin `--reveal`**, la salida de este comando incluyó la clave heredada `service_role` completa. Apareció en una salida local, no se mostró ni se guardó y no se publicó intencionalmente en GitHub. No hay indicios de que esté comprometida.
> - No volver a ejecutar ese comando con la salida completa visible en pantalla ni guardada en registros.
> - Para consultar claves, preferir el Dashboard, o una consulta que filtre explícitamente los valores secretos antes de mostrar nada.
> - No copiar claves secretas (`sb_secret_...`, `service_role`) a archivos versionados, prompts, registros compartidos ni capturas de pantalla.
> - `service_role` tiene privilegios elevados y **elude RLS**: quien la tenga puede leer y modificar los datos de todas las organizaciones.
> - Cualquier rotación o desactivación de esta clave debe planificarse después de comprobar qué depende de ella.

## Migraciones
- Ubicación: `supabase/migrations/`.
- Una migración por cambio coherente; incluye tablas, políticas, funciones, triggers, extensiones y jobs de cron.
- No editar migraciones aplicadas en entornos compartidos.
- No hacer cambios manuales en producción desde el dashboard.
- Orden de despliegue: CI verde → respaldo verificado → migración en producción con autorización explícita → verificación posterior.

### Reversión manual de la migración 2 (`20261024194726_gestion_miembros.sql`)
Preparada el 2026-10-24 para aplicar la migración 2 en `nexo-dev` sin respaldo. **No existe ningún respaldo verificado de `nexo-dev`**: no consta qué ofrece su plan y nunca se ha hecho un `pg_dump` propio. Se acepta porque es un proyecto de desarrollo, con datos sintéticos, y la migración solo añade funciones. **No se ha ejecutado nunca.** Ejecutarla requiere autorización explícita.

**Qué crea la migración** (según sus `create function`):
- `privado.exigir_read_committed()`
- `privado.buscar_usuario_confirmado(text)`
- `public.agregar_miembro(uuid, text, public.rol_membresia)`
- `public.cambiar_rol_miembro(uuid, uuid, public.rol_membresia)`
- `public.quitar_miembro(uuid, uuid)`
- `public.salir_de_organizacion(uuid)`

Además, ajusta sus permisos con `revoke` y `grant`. No crea tablas, tipos, políticas, triggers ni esquemas, y no modifica datos al aplicarse.

**Orden:** primero las cuatro RPC públicas y después las dos funciones auxiliares, porque las RPC llaman a esas funciones:
- las cuatro llaman a `privado.exigir_read_committed()`;
- `agregar_miembro` llama también a `privado.buscar_usuario_confirmado(text)`.

PostgreSQL no registra las llamadas dentro de un cuerpo PL/pgSQL como dependencias, así que no impondría este orden por sí mismo. Se sigue igualmente para que nunca exista una RPC que llame a una función ya borrada. Todo va en una sola transacción: o se borra todo o nada.

```sql
begin;
drop function public.agregar_miembro(uuid, text, public.rol_membresia);
drop function public.cambiar_rol_miembro(uuid, uuid, public.rol_membresia);
drop function public.quitar_miembro(uuid, uuid);
drop function public.salir_de_organizacion(uuid);
drop function privado.buscar_usuario_confirmado(text);
drop function privado.exigir_read_committed();
commit;
```

Sin `if exists` ni `cascade`, a propósito:
- si una función falta o tiene otra firma, el script falla y no borra nada;
- si algún objeto posterior depende de estas funciones, PostgreSQL se niega a borrarlas en vez de arrastrarlo.

Al borrar cada función desaparecen también sus permisos `execute`.

**Qué queda intacto:** todo lo que creó la migración 1, que la migración 2 no modifica:
- el esquema `privado` y el tipo `public.rol_membresia`;
- las tablas `perfiles`, `organizaciones`, `membresias` y `auditoria`, con sus índices, políticas RLS y triggers;
- las funciones `privado.es_miembro`, `privado.tiene_rol`, `privado.tiene_organizacion_en_comun`, las funciones de los triggers y `public.crear_organizacion`.

**Lo que no deshace:**
- **Datos:** las membresías que se hayan añadido, cambiado o quitado con estas RPC, y sus filas de `auditoria`, permanecen. La auditoría es inmutable por diseño (trigger `auditoria_impedir_cambios`).
- **Historial de migraciones:** borrar las funciones a mano no actualiza `supabase_migrations.schema_migrations`. La versión `20261024194726` seguiría figurando como aplicada en `migration list --linked`, y `db push` no volvería a aplicarla. Tras una reversión, el historial debe tratarse explícitamente, con su propia autorización, por ejemplo con `npx supabase migration repair 20261024194726 --status reverted --linked`, que escribe en esa tabla remota. También hay que decidir qué hacer con el archivo local de la migración.

**Comprobación tras una reversión (solo lectura):**
- las seis funciones ya no existen en `pg_proc`;
- las tablas, políticas y funciones de la migración 1 siguen presentes.

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
- **Comprobaciones de salud:** Edge Function `salud` (pendiente) y estado de Supabase.
- **Reversión:** las migraciones no se revierten automáticamente; cada migración de riesgo debe documentar su reversión manual. El frontend se revierte desde Vercel.
- **Verificación posterior:** prueba de humo del flujo crítico con un usuario de prueba y revisión del Security Advisor.
