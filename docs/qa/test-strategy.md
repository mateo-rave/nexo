# Estrategia de QA y testing

Estado: adaptada a la arquitectura provisional con Supabase (ver [ADR-0004](../architecture/decisions/0004-entornos-migraciones-y-pruebas.md)).

## Objetivo
Probar reglas de negocio, políticas RLS, contratos de API, aislamiento multiempresa, integridad de datos y flujos críticos desde el comienzo.

## Pirámide de pruebas

### 1. Unitarias
Prueban unidades pequeñas sin infraestructura externa cuando sea posible.
- **SQL:** funciones puras (cálculo de vencimiento, evaluación de condiciones, validación de definiciones) con pgTAP.
- **Edge Functions:** módulos TypeScript sin red con `deno test`.

Usa mocks para dependencias externas (proveedor de correo); no los uses donde importe verificar consultas reales, restricciones o políticas.

### 2. Base de datos y módulo
Comprueban tablas, restricciones, triggers, políticas RLS y funciones RPC de un módulo contra un PostgreSQL de Supabase real (local o CI) con pgTAP. Cada módulo prueba entradas válidas, inválidas y permisos por rol.

### 3. Integración de API
Pruebas TypeScript con `supabase-js` que actúan como el frontend: inician sesión con usuarios de prueba y llaman a la Data API, RPC y Edge Functions. Demuestran que lo probado en SQL también se cumple a través de la API pública con la clave publicable. CI usa una base efímera; nunca datos locales ni producción.

### 4. E2E
Cuando exista el frontend propio (ADR-0006), Playwright probará los flujos principales desde la interfaz. Antes de eso, el recorrido completo se prueba con pruebas de integración de API.

## Pruebas de permisos (obligatorias)
Cada permiso de [docs/security/permissions.md](../security/permissions.md) necesita **dos** pruebas: una que demuestre que el rol autorizado **sí** puede hacerlo y otra que demuestre que un rol no autorizado **no** puede. Probar solo los rechazos no basta: una política que lo deniega todo también los pasaría.

Ejemplos de casos permitidos que deben pasar:
- `propietario_a`, `administrador_a` y `miembro_a` ven los proyectos y tareas de A.
- `administrador_a` crea un proyecto en A; `miembro_a` crea una tarea en A.
- `miembro_a` cambia el estado de una tarea de la que es responsable.
- `propietario_a` cambia el rol de `miembro_a` a `administrador`.
- Cada usuario ve y marca como leídas sus propias notificaciones.
- `administrador_a` consulta el historial de auditoría de A.

## Pruebas de aislamiento multiempresa (obligatorias)
Datos base: organizaciones A y B; usuarios `propietario_a`, `administrador_a`, `miembro_a`, `propietario_b`, `sin_membresia` y anónimo. Para **cada** tabla de negocio expuesta y **cada** RPC/Edge Function:

| Caso | Resultado esperado |
|---|---|
| `propietario_b` lista filas de A | Resultado vacío. |
| `propietario_b` lee una fila de A por ID | Sin filas. |
| `propietario_b` inserta una fila con `organizacion_id` de A | Error de RLS (`42501`) o rechazo de la RPC. |
| `propietario_b` inserta en B una fila hija que apunta a un padre de A (FK compuesta) | Error de restricción. |
| `propietario_b` actualiza una fila de A | 0 filas afectadas **y** la fila de A queda intacta (verificado como `propietario_a`). |
| `propietario_b` cambia el `organizacion_id` de su fila a A | Rechazado por trigger/política. |
| `propietario_b` borra una fila de A | 0 filas afectadas **y** la fila sigue existiendo. |
| `propietario_b` llama a una RPC/Edge Function con un ID de A (organización, proyecto, tarea, regla) | Error de autorización; sin efectos ni auditoría a nombre de A. |
| `propietario_b` ejecuta o publica una regla/flujo de A | Rechazado; sin ejecución creada. |
| `sin_membresia` hace cualquiera de lo anterior | Igual que `propietario_b`. |
| `anon` lee o escribe cualquier tabla de negocio | Error de permisos. |
| `miembro_a` ejecuta una acción reservada a `administrador`/`propietario` | Rechazado. |
| `administrador_a` asciende a alguien a `administrador` u `propietario` | Rechazado. |
| `miembro_a` lee notificaciones de otro usuario de A | Sin filas. |
| `miembro_a` lee el historial de auditoría | Sin filas o error de permisos. |
| Cualquier rol edita o borra un registro de auditoría | Rechazado. |
| `propietario_a` intenta quedarse sin propietario en A | Rechazado. |
| Membresía revocada | El usuario pierde acceso en la siguiente petición. |

Comprobaciones globales:
- Ninguna tabla de esquemas expuestos tiene RLS deshabilitado.
- Las vistas expuestas usan `security_invoker`.
- Las funciones `security definer` fijan `search_path`.
- Ninguna clave secreta aparece en el bundle del frontend ni en el repositorio (búsqueda automática en CI). **Implementada en parte:** el job `frontend` del workflow falla si el bundle contiene `sb_secret_` o `service_role`. Sigue pendiente la búsqueda en el repositorio; el workflow solo filtra además las claves de su propio registro (salida de `supabase start`).

## Pruebas del motor de automatización
- Una regla válida se ejecuta y queda una ejecución `exitosa` con versión de regla, timestamps y resultado.
- Una definición con condición o acción no permitida se rechaza al guardar.
- Una versión publicada no puede modificarse.
- El mismo evento procesado dos veces produce una sola ejecución y un solo efecto.
- La detección programada ejecutada dos veces seguidas no duplica hallazgos ni notificaciones.
- Dos procesos concurrentes no toman la misma ejecución pendiente.
- Un fallo transitorio se reintenta hasta el límite y termina `fallida` con error seguro.
- Si una acción falla, la ejecución no queda `exitosa` y no persisten efectos parciales.
- Una acción externa queda `programada` hasta que la Edge Function la confirma.
- Una cadena de reglas que se dispararían mutuamente se detiene en la profundidad máxima.
- Proveedor externo caído: la acción queda `fallida`/reintentable, no `completada`.

## Flujos críticos
- Registrar usuario y crear organización (con membresía propietario atómica).
- Crear proyecto y tarea con responsable y fecha límite.
- Definir y publicar una regla permitida.
- Procesar el evento sin duplicar sus efectos.
- Detectar un bloqueo y crear notificación.
- Consultar la ejecución y la auditoría.
- Intentar leer, modificar, borrar o ejecutar acciones sobre otra organización y recibir denegación.

## Casos negativos obligatorios
- Sin autenticación.
- JWT caducado o manipulado.
- Rol insuficiente.
- Identificador de recurso manipulado.
- Acceso cruzado entre organizaciones.
- Campos ausentes o inválidos.
- Evento repetido.
- Reintento tras fallo.
- Acción no permitida.
- Ciclo de automatización detectado o limitado.
- Dependencia externa caída.

## Herramientas
| Uso | Herramienta | Requiere |
|---|---|---|
| SQL, RLS, triggers, RPC | pgTAP vía `supabase test db` (`supabase/tests/`); opcional `supabase-test-helpers`. | Supabase local (Docker) o CI. |
| Edge Functions | `deno test`. | Deno; integración además Supabase local/CI/desarrollo. |
| Integración de API | `deno test` + `supabase-js` (un solo runtime con las Edge Functions), en `pruebas/api/`. Decidido el 2026-10-24: Deno 2.9.8 y `npm:@supabase/supabase-js@2.118.0`. | Supabase local de CI. |
| E2E | Playwright. | Frontend en el repositorio (ADR-0006). |
| Lint/formato | `deno fmt`, `deno lint`, `supabase db lint`, Security/Performance Advisors. | Deno, Supabase CLI. |
| CI | GitHub Actions con Supabase CLI (los runners Linux incluyen Docker). | Repositorio en GitHub. |

Las versiones se fijarán al instalar cada herramienta, verificando compatibilidad.

### Sin Docker local (situación vigente)
- Las pruebas pgTAP se ejecutan en CI (ver abajo). Las de integración de API también, contra el mismo Supabase local y desechable de CI; no se conectan a `nexo-dev` ni a producción (decisión del 2026-10-24, ver "Pruebas de integración de API").
- Las pruebas pgTAP se envuelven en `begin; ... rollback;` para no dejar datos.
- `supabase test db --linked` necesita Docker (comprobado el 2026-10-24). Por eso las pruebas pgTAP se ejecutan en GitHub Actions contra un Supabase local y desechable creado a partir de las migraciones (`.github/workflows/pruebas-base-datos.yml`, ver ADR-0004), y el resultado se anota indicando dónde se ejecutó.
- Las pruebas unitarias de Edge Functions solo necesitan Deno.

### Pruebas de integración de API (`pruebas/api/`)
Decisión del 2026-10-24: Deno + `supabase-js` contra el Supabase local y desechable del workflow `.github/workflows/pruebas-base-datos.yml`, en el mismo job y después de las pruebas pgTAP.
- **Versiones fijadas:**
  - Deno `2.9.8`, instalado en CI con `denoland/setup-deno` fijado por SHA (`22d081ff2d3a40755e97629de92e3bcbfa7cf2ed`, `v2.0.5`);
  - `npm:@supabase/supabase-js@2.118.0` en `pruebas/api/deno.json`;
  - hashes de todas sus dependencias en `pruebas/api/deno.lock`, congelado: CI falla si no coinciden.
- **Archivos:**
  - uno por RPC: `agregar_miembro.test.ts`, `cambiar_rol_miembro.test.ts`, `quitar_miembro.test.ts` y `salir_de_organizacion.test.ts`;
  - `auxiliares.ts` con los clientes, los usuarios de prueba, el escenario y las comprobaciones comunes.
- **Datos:** cada archivo registra una vez a `propietario_a`, `administrador_a`, `miembro_a`, `propietario_b` y `sin_membresia`.
  - Los correos son sintéticos (`@example.com`) y únicos en cada ejecución.
  - Cada prueba crea sus propias organizaciones A y B con las RPC, así que las pruebas no dependen unas de otras.
- **Errores:** se comprueban por separado el estado HTTP, leído del `Response` real con un `fetch` propio que se pasa al cliente, y el cuerpo: SQLSTATE en `code`, mensaje en `message` y código propio de Nexo en `details`.
- **Rechazos:** después de cada operación rechazada se vuelve a leer, por la Data API, el estado de membresías y auditoría de las organizaciones afectadas, y se comprueba que no cambió.
- **Credenciales:**
  - de `supabase status` solo se extraen la URL local y la clave publicable local;
  - Deno se ejecuta con un entorno vacío más esas dos variables, `--allow-env` limitado a ellas y `--allow-net` limitado al servidor local de la API;
  - `auxiliares.ts` se niega a continuar si la URL no es `127.0.0.1` o `localhost`, o si la clave no es publicable (`sb_publishable_...`);
  - no se usa `service_role` ni ninguna clave secreta.
- **Límite de registros:** el Supabase local limita a 30 los registros e inicios de sesión cada 5 minutos por IP (`auth.rate_limit.sign_in_sign_ups`). Hoy se registran como mucho 20 usuarios por ejecución.
- **Primera ejecución (2026-10-24):** ejecución `40134690914`, commit `46b4b629ef914bbe38b79e875b31b88c18eea250`, en el Supabase local y desechable de GitHub Actions: pgTAP `Files=11, Tests=199`, `Result: PASS`; API `ok | 40 passed | 0 failed`.
- **Lo que no cubren:** las pruebas contra `nexo-dev` (solo se ejecutan en el Supabase local de CI), las operaciones simultáneas y el rechazo de `repeatable read`, que no se puede elegir desde la Data API. Siguen cubiertos solo por pgTAP y el razonamiento de ADR-0004.

## Reglas de calidad
- No afirmar que pasó una prueba si no fue ejecutada; indicar dónde se ejecutó.
- No desactivar una prueba que falla solo para dejar CI verde sin investigar la causa.
- Un "0 filas afectadas" no basta para probar una denegación de escritura: verificar que la fila objetivo sigue intacta.
- Los cálculos (vencimiento, inactividad) se verifican con datos de referencia y tiempo controlado.
- Fixtures pequeños y sintéticos; sin datos personales reales.
- Probar permisos en SQL (pgTAP) **y** a través de la API.
- Informar pruebas pasadas, fallidas y no ejecutadas por separado.

## Umbral inicial
Primero cobertura de caminos críticos y riesgos de seguridad: toda tabla expuesta debe tener su archivo de pruebas RLS antes de considerarse terminada. Un porcentaje de cobertura por sí solo no demuestra calidad; la meta cuantitativa se decidirá después.
