# Modelo inicial de amenazas de Nexo

Estado: inicial, adaptado a la arquitectura provisional con Supabase ([ADR-0001](../architecture/decisions/0001-supabase-como-plataforma-backend.md), [ADR-0002](../architecture/decisions/0002-autenticacion-y-autorizacion-multiempresa.md)). Revisar al diseñar cada módulo y cada integración.

## Activos a proteger
- Credenciales, tokens, sesiones y claves de API de Supabase (especialmente claves secretas).
- Datos de organizaciones, proyectos, tareas y clientes.
- Definiciones de flujos y reglas.
- Historial de ejecuciones y auditoría.
- Archivos importados y exportados.
- Secretos de integraciones y webhooks.

## Actores y amenazas
- Usuario autenticado que manipula IDs para acceder a datos ajenos (BOLA/IDOR), llamando directamente a la Data API sin pasar por la interfaz.
- Usuario con rol limitado que intenta ejecutar acciones administrativas.
- Cliente anónimo que abusa de endpoints de autenticación.
- Archivo malformado o excesivamente grande que consume recursos.
- Regla de automatización que se repite, entra en ciclo o ejecuta acciones duplicadas.
- Secreto filtrado en Git, logs, respuestas de error o en el bundle del frontend.
- Evento/webhook falso, repetido o alterado.
- Dependencia externa comprometida o no disponible.

### Amenazas específicas de Supabase
- **Tabla expuesta sin RLS:** cualquier usuario con la clave publicable lee o escribe toda la tabla.
- **Política demasiado amplia:** `using (true)`, falta de `with check` en `insert`/`update`, o política para `anon` en datos de negocio.
- **Clave secreta en el cliente:** `sb_secret_...` (o `service_role` heredada) en Vercel como variable pública o en código del frontend; omite RLS por completo.
- **Edge Function con clave secreta** que no verifica membresía: convierte un endpoint en un bypass de RLS.
- **`security definer` sin `search_path` fijo** o sin comprobar membresía: escalada de privilegios.
- **Vistas que omiten RLS** por ejecutarse con permisos del propietario.
- **Autorización basada en `user_metadata`**, que el usuario puede modificar.
- **Claims desactualizados** si en el futuro se ponen roles en el JWT.
- **Cambio de `organizacion_id`** en un `update` para mover una fila a otra organización.
- **Relaciones cruzadas:** tarea de la organización B apuntando a proyecto de A.
- **Jobs de cron** que crean filas sin `organizacion_id` correcto o duplican efectos.
- **Realtime / Storage** habilitados sin políticas cuando se usen.
- **Cambios manuales en el dashboard** de producción no versionados que desactivan una política.
- **Mensajes de error de PostgREST** que exponen nombres de restricciones o detalles internos.

## Controles iniciales
- Autorización en base de datos y servidor para cada recurso: RLS en todas las tablas expuestas, restricciones (FK compuestas, `not null`), triggers de invariantes y validación en RPC.
- Funciones auxiliares de autorización en un esquema no expuesto, `security definer` con `search_path = ''`.
- `anon` sin permisos sobre datos de negocio.
- Vistas con `security_invoker = true`.
- Clave publicable en el frontend; claves secretas solo en secretos de Edge Functions o herramientas de servidor; búsqueda automática de secretos en CI.
- Edge Functions con el JWT del usuario por defecto; uso justificado y auditado de la clave secreta.
- Pruebas negativas de aislamiento entre organizaciones (pgTAP y API).
- Contraseñas y sesiones gestionadas por Supabase Auth; confirmación de correo; MFA a evaluar.
- Rate limiting: límites de Supabase Auth configurados por entorno; CAPTCHA a evaluar. La Data API no tiene límites por usuario equivalentes: riesgo a evaluar antes de producción.
- Validación estricta de payloads (`check`, tipos, validación de `jsonb`) y archivos.
- Consultas parametrizadas: supabase-js/PostgREST en el cliente; nunca concatenar entrada del usuario en SQL dinámico (`format()` con `%I`/`%L` si fuera imprescindible).
- Idempotencia, límites de intentos, timeouts y detección de ciclos en automatizaciones.
- Verificación de firma/secretos en webhooks cuando se implementen.
- Logs sin secretos y con IDs de correlación en Edge Functions.
- CORS explícito en Edge Functions; Site URL y redirecciones restringidas en Auth; HTTPS (proporcionado por Supabase y Vercel).
- Todos los cambios de seguridad versionados en migraciones; revisar Security Advisor antes de cada despliegue.
- Copias de seguridad con prueba de restauración.

## Reglas del motor de automatización
No ejecutar código, SQL, shell ni expresiones libres aportadas por usuarios. Las reglas se expresan con un esquema limitado, validado y versionado, con catálogo cerrado de condiciones y acciones. El SQL que evalúa reglas es código del proyecto en migraciones; nunca se construye a partir de texto del usuario. Las acciones de efectos externos deben ser explícitas, autorizadas y auditables.

## SQL, XSS y validación
No crear un sanitizador global indiscriminado. Usa consultas parametrizadas, validación con restricciones y tipos, escape contextual al renderizar en el frontend y políticas de contenido cuando corresponda. La validación de entrada no sustituye la autorización.

## RLS de PostgreSQL
Decisión: RLS es el mecanismo principal de aislamiento (ADR-0002). Requisitos:
- Documentar cada política junto a su migración.
- Políticas por operación y por rol.
- Probar con roles `authenticated` y `anon` simulando JWT, nunca solo con roles con bypass.
- Las funciones de sistema (cron) que operan sin usuario deben propagar el `organizacion_id` del recurso de origen y tener pruebas propias.

RLS no es la única defensa: se combina con restricciones, triggers y validación en RPC y Edge Functions.

## Revisión del Security Advisor de `nexo-dev` (2026-10-24)
Comando: `npx supabase db advisors --linked --type security --level info` (CLI 2.120.0), tras aplicar la migración `20261024161000_esquema_base_organizaciones.sql`. Resultado: **3 avisos `WARN`, ninguno `ERROR` y ninguno `INFO`**. No se modificaron funciones, permisos, políticas ni triggers a raíz de esta revisión.

| # | Aviso | Objeto | Decisión provisional |
|---|---|---|---|
| 1 | `anon_security_definer_function_executable` (0028) | `public.rls_auto_enable()` | Se conserva; aviso registrado. |
| 2 | `authenticated_security_definer_function_executable` (0029) | `public.crear_organizacion(p_nombre text)` | Intencional; aviso aceptado. |
| 3 | `authenticated_security_definer_function_executable` (0029) | `public.rls_auto_enable()` | Se conserva; aviso registrado. |

### Avisos 1 y 3: `public.rls_auto_enable()`
- **Qué es:** la función y el event trigger `ensure_rls` del RLS automático de `nexo-dev`, que no están en las migraciones del repositorio (ver ADR-0004, "RLS automático de `nexo-dev`").
  - La función existe, devuelve `event_trigger`, no recibe argumentos y su definición coincide con la revisada antes del primer `db push`.
  - **Su procedencia y quién la gestiona no están confirmadas.**
- **Prueba controlada:** una única petición `POST /rest/v1/rpc/rls_auto_enable`, sin sesión, con la clave pública y cuerpo `{}`.
  - Resultado: **HTTP 400**, código PostgreSQL `0A000`, mensaje `cannot display a value of type event_trigger`.
  - La llamada RPC fue **rechazada** y la respuesta **no fue 2xx**.
- **Lo que no se demostró:**
  - El punto exacto en que PostgreSQL rechazó la operación.
  - Que el cuerpo de la función no llegara a ejecutarse. Es lo más probable, porque no apareció el error propio de `pg_event_trigger_ddl_commands()` fuera de un event trigger, pero no es concluyente.
  - Que el comportamiento se mantenga en futuras versiones de Supabase o PostgREST.
- **Decisión provisional:** conservar la función y el event trigger, registrar los avisos y **no cambiar sus permisos** hasta tener motivos y evidencia adicionales. El permiso `execute` de `anon` y `authenticated` sigue concedido.

### Aviso 2: `public.crear_organizacion(p_nombre text)`
- **Decisión:** el acceso de `authenticated` es **intencional**. Es la única vía para crear una organización junto con su membresía `propietario`, en una sola transacción. Los usuarios no tienen permiso de `insert` en `organizaciones`, `membresias` ni `auditoria`.
  - La función comprueba `auth.uid()`, valida el nombre y genera el `id` en el servidor.
  - `anon` no puede ejecutarla: el Advisor no la marca para `anon`, y lo comprueba `rls_activado.test.sql`.
- **Evidencia:** las 101 comprobaciones pgTAP pasaron en CI, incluidas las de `crear_organizacion.test.sql`. Eso no elimina todos los riesgos posibles.
- **Situación conocida:**
  - Los inicios de sesión anónimos están **desactivados** en `nexo-dev`, según comprobó el propietario.
  - El registro normal de cuentas está **habilitado**. Se confirmó después, en la revisión de Auth desde el Dashboard (ver la sección siguiente).
  - **No existe un límite de organizaciones por usuario.** Los límites de uso y la prevención de creación abusiva son una cuestión de diseño pendiente, no una corrección implementada.

### Alcance de esta revisión
El Advisor comprueba patrones de configuración, no la lógica de las políticas (por ejemplo, el aislamiento entre organizaciones, que cubren las pruebas pgTAP). La salida de la CLI no incluyó avisos sobre la configuración de Auth; esa revisión se hizo aparte, desde el Dashboard (ver la sección siguiente). Que solo aparezcan estos tres avisos **no significa que no existan otros riesgos**.

## Revisión de la configuración de Auth de `nexo-dev` (Dashboard, 2026-10-24)
El propietario revisó las opciones de autenticación en el Dashboard de Supabase. Es una revisión distinta del Security Advisor de la base de datos (sección anterior) y no cambia sus tres avisos.

| Opción | Estado observado |
|---|---|
| Permitir registros normales | Habilitado |
| Vinculación manual de identidades | Desactivada |
| Inicios de sesión anónimos | Desactivados |
| Confirmación de correo electrónico | Habilitada |
| Protección CAPTCHA | Desactivada |
| Protección contra contraseñas filtradas | Desactivada |
| Longitud mínima de contraseña | **Cambiada de 6 a 8 caracteres** durante la revisión |
| Requisitos adicionales de caracteres | **No verificado:** la opción no aparecía en la pantalla revisada |

- Este es el único cambio de configuración: el mínimo de contraseña. Se hizo a mano en el Dashboard de `nexo-dev` y no está en ninguna migración.
- La revisión de configuración de Auth desde el Dashboard queda **realizada**. **No significa que la seguridad de Nexo esté terminada.**
- **Antes de un lanzamiento público** hay que evaluar:
  - la protección CAPTCHA;
  - la protección contra contraseñas filtradas;
  - los requisitos adicionales de caracteres de las contraseñas, que no pudieron verificarse.

## Riesgos residuales y asuntos pendientes
- Antes de un lanzamiento público: evaluar CAPTCHA, la protección contra contraseñas filtradas y los requisitos adicionales de caracteres de las contraseñas (ver "Revisión de la configuración de Auth de `nexo-dev`").
- `crear_organizacion` sin límite de organizaciones por usuario: decidir límites de uso y prevención de creación abusiva (ver "Revisión del Security Advisor de `nexo-dev`").
- Permiso `execute` de `anon` y `authenticated` sobre `public.rls_auto_enable()`, configuración externa al repositorio: confirmar su procedencia y gestión antes de decidir si se retira.
- Confirmar cómo gestionará la sesión el frontend de Stitch (cliente puro o renderizado en servidor).
- Rate limiting de la Data API frente a abuso por usuarios autenticados.
- Definir retención y eliminación de datos (incluido `auth.users` y auditoría).
- Revisar obligaciones legales aplicables en los mercados de operación y región de alojamiento del proyecto Supabase.
- Seleccionar planes y observabilidad.
- Definir límites de tamaño, duración y consumo para las automatizaciones.
- Dependencia del proveedor (lock-in) y plan de salida.
