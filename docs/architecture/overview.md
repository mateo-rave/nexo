# Arquitectura propuesta de Nexo

Estado: **provisional**. Escenario objetivo: frontend propio en el repositorio (Vite, React, TypeScript y Tailwind CSS, ADR-0006) con despliegue previsto en Vercel; backend sobre Supabase. No hay alojamiento de frontend contratado ni configurado. Se revisará al elegir planes y despliegue.

Decisiones relacionadas:
- [ADR-0001](decisions/0001-supabase-como-plataforma-backend.md): Supabase como plataforma de backend.
- [ADR-0002](decisions/0002-autenticacion-y-autorizacion-multiempresa.md): autenticación y autorización multiempresa.
- [ADR-0003](decisions/0003-separacion-api-datos-sql-edge-functions.md): separación entre Data API, SQL y Edge Functions.
- [ADR-0004](decisions/0004-entornos-migraciones-y-pruebas.md): entornos, migraciones y pruebas.
- [ADR-0005](decisions/0005-nombres-en-espanol.md): nombres del código en español.
- [ADR-0006](decisions/0006-frontend-propio-con-react.md): frontend propio con React en el repositorio (sustituye a Stitch).
- [ADR-0007](decisions/0007-modelo-proyectos-tareas-estados-flujos.md): modelo de proyectos, tareas, estados y flujos.

> Historial: la versión anterior de este documento proponía un monolito modular con Django/DRF y Celery/Redis. Se sustituyó por la ADR-0001. Los principios de modularidad, límites claros y autorización en servidor se mantienen.

## Enfoque
Un único backend administrado (Supabase) con el esquema, las políticas y las funciones versionados en migraciones SQL, más un conjunto pequeño de Edge Functions. Sin microservicios. Sin una segunda API ni un segundo sistema de autenticación.

```text
 Navegador (frontend React, Vercel)
   │  clave publicable + JWT del usuario
   ├──► Supabase Auth ............ identidad, sesiones, JWT
   ├──► Data API (PostgREST) ..... CRUD simple ──┐
   ├──► RPC (funciones SQL) ...... operaciones atómicas ──┤
   └──► Edge Functions (Deno) .... secretos / efectos externos ──┤
                                                    ▼
                               PostgreSQL: tablas + RLS + restricciones
                               + triggers (auditoría, invariantes)
                               ▲
          Supabase Cron (pg_cron) ── llama funciones SQL de detección
                                     y procesamiento de ejecuciones
```

## Responsabilidades por componente

| Componente | Responsable de | Nunca |
|---|---|---|
| Frontend (React en el repositorio → Vercel) | Presentación; validación de formularios como ayuda de UX; recordar la organización mostrada; llamar a Auth, Data API, RPC y Edge Functions con el JWT del usuario. | Decidir permisos, aplicar reglas de negocio, contener claves secretas. Sustituir RLS o los controles de autorización del backend. Stack decidido: Vite, React, TypeScript y Tailwind CSS (ADR-0006). Implementación iniciada en `frontend/`: portada y panel de demostración con datos ficticios, todavía sin conexión al backend. |
| Supabase Auth | Registro, inicio de sesión, confirmación de correo, recuperación de contraseña, emisión y renovación de JWT. Redirecciones permitidas por entorno. | Guardar roles por organización (eso vive en `membresias`). |
| Data API (PostgREST) | Lecturas, listados paginados y filtrados, CRUD de una tabla protegido por RLS. | Operaciones de varias tablas o transiciones de estado. |
| Funciones SQL (RPC) | Crear organización + membresía propietario; gestionar miembros y roles; transiciones de estado de tareas; publicar versiones de flujos; evaluar reglas y aplicar acciones internas; detección de bloqueos. | Llamadas HTTP o uso de secretos de terceros. |
| Triggers | Auditoría de acciones críticas; `actualizado_en`; inmutabilidad de versiones publicadas; impedir cambios de `organizacion_id`; registrar eventos de dominio para el motor. | Lógica extensa difícil de rastrear. |
| RLS y permisos | Aislamiento por organización en cada tabla; permisos por rol y operación; `anon` sin acceso a datos de negocio. | Ser la única defensa: se combinan con restricciones y validación en RPC. |
| Edge Functions | Envío de correos y efectos externos; orquestación con timeouts y reintentos de red; endpoints con contrato propio; salud. | Duplicar CRUD o reglas ya aplicadas en SQL; usar la clave secreta sin comprobar membresía. |
| Tareas programadas (Supabase Cron) | Ejecutar periódicamente funciones SQL idempotentes (detección, reintentos pendientes). Invocar Edge Functions vía `pg_net` solo si hay efectos externos. | Contener lógica dentro del job. |
| Auditoría | Tabla `auditoria` de solo inserción, escrita por triggers/funciones; lectura por roles autorizados de la organización. | Ser editable o borrable por usuarios. |
| Notificaciones | Tabla `notificaciones` por destinatario, creadas por SQL con clave de deduplicación; el usuario solo lee y marca como leídas las suyas. Correo externo posterior vía Edge Function. | Enviarse dos veces por el mismo hallazgo. |
| Realtime | Fuera del MVP; candidato para notificaciones en vivo con canales privados autorizados. | Activarse sin una funcionalidad que lo necesite. |

El detalle y la justificación del reparto están en la ADR-0003.

## Módulos lógicos
Se mantienen como límites de responsabilidad, ahora expresados como grupos de tablas, funciones y migraciones (no como apps de Django):

- `cuentas`: perfil de usuario vinculado a `auth.users`.
- `organizaciones`: organizaciones, membresías, roles.
- `proyectos`: proyectos.
- `tareas`: tareas, asignación, estados, fechas límite.
- `flujos`: definiciones y versiones publicadas inmutables.
- `automatizacion`: reglas, eventos, ejecuciones, acciones.
- `monitoreo`: hallazgos de bloqueo y métricas básicas.
- `notificaciones`: notificaciones internas.
- `auditoria`: historial de acciones.
- `integraciones`: futuro; conectores y webhooks.

Crea las tablas de un módulo cuando exista una primera necesidad implementable y probada. Un módulo no escribe directamente en tablas internas de otro: usa sus funciones.

Esquemas de PostgreSQL:
- `public`: tablas y funciones RPC que el frontend puede usar (todas con RLS).
- `privado`: funciones auxiliares de autorización y lógica interna; no expuesto por la Data API.
- Nombres de esquema adicionales (p. ej. un esquema `api` dedicado) quedan pendientes.

## Multiempresa
- Cada tabla de negocio tiene `organizacion_id not null`.
- Las tablas hijas usan clave foránea compuesta `(organizacion_id, padre_id)` para que la base de datos impida relaciones entre organizaciones.
- RLS habilitado en todas las tablas expuestas; políticas por operación basadas en `membresias` y `auth.uid()`. Cada migración lo activa explícitamente: el RLS automático que tiene `nexo-dev` (`rls_auto_enable`, fuera del repositorio) no se considera una protección. Detalle en ADR-0004.
- Un `organizacion_id` enviado por el cliente nunca es prueba de autorización: se valida contra la membresía.
- Las funciones de sistema (cron) operan sobre todas las organizaciones, pero cada fila que crean hereda el `organizacion_id` del recurso que la originó.

Detalle en ADR-0002. Roles (`propietario`, `administrador`, `miembro`) y matriz de permisos en [docs/security/permissions.md](../security/permissions.md).

## Motor de automatización
Decidido en la [ADR-0008](decisions/0008-motor-minimo-reglas-automatizacion.md) y escrito en las migraciones `20261027120000_reglas_automatizacion.sql` y `20261027130000_ejecucion_automatizaciones.sql`, pendientes de validar en CI. La ADR-0008 sustituye el diseño propuesto que figuraba aquí; las diferencias principales se indican.
- **Definiciones:** `reglas_automatizacion` y `versiones_regla` separadas (`borrador` → `publicada`, como los flujos), con activador, condiciones y acciones en `jsonb` validados al guardar por una función propia en SQL contra un catálogo cerrado, con códigos de error propios (no se usa `pg_jsonschema`). Una versión publicada es inmutable (trigger).
- **Catálogo del MVP:** activadores `tarea_estado_cambiado` y `tarea_vencida`; condiciones `estado_destino`, `proyecto` y `con_responsable`; acción `notificar`. `tarea_creada`, «tiempo sin actividad», `crear_tarea_seguimiento`, `cambiar_estado` y `crear_hallazgo` quedan fuera por ahora.
- **Activación:** `periodos_activacion_regla` guarda cada periodo en que la regla estuvo activa. Qué reglas actúan sobre un evento y con qué versión se decide por el momento del evento (`ocurrido_en`), no por la hora de procesamiento.
- **Eventos:** cola persistente `eventos_automatizacion`, escrita en la misma transacción que el cambio: un trigger sobre el cambio de estado de una tarea y el detector de vencimientos (un evento por hallazgo nuevo). No se expone a los usuarios.
- **Ejecuciones:** `ejecuciones_automatizacion` con `estado` (`pendiente`, `exitosa`, `fallida`, `omitida`; `en_ejecucion` se añadirá con las acciones externas), `regla_id`, `version_regla_id`, `evento_id`, `intentos`, `max_intentos`, marcas de tiempo, `codigo_error` y mensaje seguro.
- **Acciones:** `acciones_automatizacion` con estado propio (`programada`, `completada`, `fallida`), para distinguir acción programada de acción completada.
- **Idempotencia:** `unique (regla_id, evento_id)` en las ejecuciones (por regla y evento, no por versión), clave única de cada evento y, en las notificaciones, una por hallazgo y destinatario y una por evento y destinatario; inserciones con `on conflict do nothing`.
- **Concurrencia:** los eventos y las ejecuciones pendientes se toman con `for update skip locked`.
- **Reintentos:** solo para fallos transitorios; 3 intentos en total, incluido el primero, con esperas de 1 y 5 minutos.
- **Timeouts:** un `lock_timeout` por transacción, cuyo vencimiento cuenta como fallo transitorio, y lotes limitados. No se fija `statement_timeout` dentro de la función (no limitaría la sentencia en curso). Timeout explícito en las llamadas externas de Edge Functions cuando existan.
- **Ciclos:** los eventos causados por una acción llevan `ejecucion_origen_id` y profundidad; se omite la ejecución si se supera la profundidad máxima (3) o si la regla ya está en su cadena de origen.
- **Resultado:** una ejecución solo es `exitosa` si todas sus acciones se completaron en la misma transacción; si algo falla no persisten efectos parciales.

## API para el frontend
El contrato consumible por el frontend se compone de:
1. Tablas y vistas expuestas por la Data API.
2. Funciones RPC.
3. Endpoints de Edge Functions.

Documentación:
- Tipos TypeScript generados del esquema con la CLI de Supabase.
- `docs/api/` (pendiente) con cada operación, permisos requeridos, ejemplos de petición/respuesta y códigos de error.
- OpenAPI escrita para los endpoints de Edge Functions. El uso del OpenAPI que genera PostgREST queda pendiente de verificar.

Errores:
- RPC: códigos de error propios y mensajes seguros; sin nombres de restricciones ni SQL.
- Edge Functions: `{ "error": { "code", "message", "request_id" } }`.

Paginación con rangos (`limit`/`offset` o `Range`) y filtros explícitos en listados crecientes.

CORS:
- La Data API y Auth son servicios de Supabase; su protección real es el JWT + RLS, no el origen.
- En Edge Functions, CORS se configura explícitamente con los dominios de Vercel autorizados por entorno.
- En Auth se restringen la Site URL y las URLs de redirección.

## Entornos
Local (Supabase CLI + Docker), desarrollo remoto, pruebas/CI y producción, con proyectos Supabase separados. Detalle en ADR-0004 y en `docs/operations/development-and-backups.md`.

## Decisiones pendientes
- Framework del frontend y gestión de la sesión: **resuelto** por ADR-0006 (SPA con Vite y React; sesión en el cliente con `supabase-js`). Queda pendiente decidir la política de seguridad de contenido (CSP).
- Planes de Supabase y Vercel; disponibilidad de backups, PITR y Branching según plan.
- Invitación de miembros: flujo y caducidad. La matriz de roles ya está definida en `docs/security/permissions.md`.
- Validación de esquemas `jsonb` de reglas: función propia vs `pg_jsonschema`. Los flujos no usan `jsonb`: sus estados y transiciones se guardan en tablas (ADR-0007).
- Métricas concretas del MVP (RF-037).
- Posterior al MVP: proveedor de correo, modelo de aprobaciones especializadas, Realtime.
- Esquema dedicado para la API vs `public`.
- Almacenamiento de archivos (Supabase Storage) y sus políticas, si se necesita.
- Observabilidad: logs de Supabase, IDs de correlación en Edge Functions, servicio externo opcional.
