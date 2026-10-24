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
| GitHub | Repositorio remoto y CI | Cuenta creada (correo `noreply` configurado en el repositorio local). Falta crear el repositorio privado y configurar el remoto |

No presuponer que estas herramientas están disponibles: comprobarlas antes de cada tarea que las requiera. Las versiones se fijan al instalar, verificando compatibilidad.

> **Ubicación del proyecto:** `C:\dev\nexo`, fuera de OneDrive (decisión del 2026-10-23), para evitar conflictos de sincronización con `node_modules`, la caché de Deno y los archivos temporales de la CLI.

**Supabase CLI:** se instala dentro del proyecto con `npm install supabase --save-dev` y se ejecuta con `npx supabase <comando>`.

**Comandos interactivos:** `npx supabase login` abre el navegador y `npx supabase link` pide la contraseña de la base de datos. Los ejecuta **el propietario en su propia terminal**, para que la contraseña no pase por ningún chat ni registro.

## Desarrollo (flujo vigente: proyecto en la nube, sin Docker)
Decisión del 2026-10-23 (ADR-0004). La cuenta de Supabase y el proyecto `nexo-dev` ya existen; falta enlazarlo con la CLI.

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
5. `npx supabase start` crea un Supabase local y vacío **dentro del servidor de GitHub** y le aplica `supabase/migrations/` en orden.
6. `npx supabase test db --local` ejecuta los archivos de `supabase/tests/` con pgTAP.

Al terminar, GitHub destruye el servidor y la base de datos con él.

**Lo que no hace:** no usa `--linked`, `db push`, `db reset` contra un proyecto remoto, `SUPABASE_ACCESS_TOKEN`, la contraseña de `nexo-dev` ni ningún otro secreto. Sus permisos son solo de lectura del repositorio (`contents: read`).

**Cómo leer el resultado:** en el registro del paso "Ejecutar las pruebas pgTAP":
- **Éxito:** cada archivo termina en `.. ok` y al final aparecen `All tests successful.`, `Files=6, Tests=101` y `Result: PASS`. El job se marca en verde.
- **Fallo:** el archivo afectado muestra `not ok N - <descripción de la comprobación>`, junto con lo esperado y lo obtenido. Al final aparece `Result: FAIL`. El job se marca en rojo.
- Si un archivo ejecuta menos comprobaciones de las que declara su `plan()`, pg_prove también lo marca como fallo.

**Última validación registrada:** ejecución `40117625548` del 2026-10-24 (`workflow_dispatch`, commit `e16163f2632c295c495ebd287e3eca0a582759dd`).
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
