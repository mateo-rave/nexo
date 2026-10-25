# ADR-0003: Separación entre Data API, SQL y Edge Functions

- Estado: Aceptada (provisional)
- Fecha: 2026-10-23 (propuesta y aceptación provisional)
- Responsables: propietario del producto

> **En pocas palabras:** el frontend solo muestra y pide cosas; las reglas importantes viven en la base de datos (tablas protegidas, funciones SQL y triggers); las Edge Functions se reservan para lo que necesite secretos o servicios externos, que en el MVP casi no existe. "Provisional" significa que se aplica desde ya, pero se revisará con la experiencia real de las primeras funciones SQL y del frontend propio (ADR-0006, que sustituye la referencia original al código de Stitch).

## Contexto
Con Supabase, la lógica puede vivir en cuatro lugares: el frontend, la Data API (PostgREST sobre tablas con RLS), funciones SQL/triggers y Edge Functions (TypeScript/Deno). Sin un criterio explícito la lógica se dispersa, se duplica o termina en React, donde cualquier usuario puede saltársela.

## Opciones consideradas
1. **Todo en Edge Functions** (la Data API solo para lecturas). Un único lenguaje para la lógica; pero las operaciones atómicas de varias tablas necesitan transacciones que el cliente supabase-js no ofrece, se pierde la cercanía a los datos y cada operación añade un salto de red.
2. **Todo en SQL.** Transaccional y cercano a los datos; pero SQL/PL/pgSQL no es adecuado para llamadas externas, secretos, manejo de reintentos con red ni para lógica compleja de orquestación.
3. **Reparto por criterio** de seguridad, transaccionalidad, rendimiento y mantenibilidad.

## Decisión
Opción 3, con estas reglas:

| Capa | Usar para | No usar para |
|---|---|---|
| Frontend | Presentación, validación de formularios solo como ayuda de UX, llamadas a Auth, Data API, RPC y Edge Functions con el JWT del usuario. | Permisos, reglas de negocio, cálculos que el servidor deba confiar, claves secretas. |
| Data API (PostgREST) | Lecturas y CRUD de una sola tabla cuando RLS y restricciones bastan (listar proyectos, editar descripción de tarea). Paginación con rangos y filtros. | Operaciones de varias tablas que deban ser atómicas o con reglas de transición. |
| Funciones SQL (RPC) | Operaciones atómicas de varias escrituras; transiciones de estado; publicar versión de flujo; crear organización + propietario; cambiar roles; evaluación de reglas cuyas acciones son escrituras internas; detección de bloqueos basada en conjuntos de filas. | Llamadas HTTP salientes, uso de secretos de terceros, lógica larga con espera de red. |
| Triggers | Invariantes que deben cumplirse siempre: auditoría, `actualizado_en`, inmutabilidad de versiones publicadas, bloqueo de cambio de `organizacion_id`, registro de eventos de dominio. | Efectos externos o lógica de negocio extensa difícil de seguir. |
| Edge Functions | Operaciones que requieren secretos o efectos externos (correo, webhooks futuros); orquestación con timeouts y reintentos de red; endpoints específicos con contrato propio; endpoint de salud. | CRUD que la Data API ya cubre; duplicar reglas que ya validó SQL. |
| Cron (pg_cron) | Disparar periódicamente funciones SQL de detección y de procesamiento de ejecuciones pendientes; invocar una Edge Function vía `pg_net` solo cuando haya efectos externos. | Contener lógica: el job solo llama a una función versionada en migraciones. |
| Realtime | Fuera del MVP. Candidato futuro: notificaciones en vivo, con canales privados y autorización. | — |

### Justificación aplicada al motor de automatización
- **Evaluación de reglas y acciones internas en SQL.** En el MVP las acciones permitidas (crear tarea, crear notificación, cambiar estado, crear hallazgo) son escrituras en la misma base de datos. Ejecutarlas en una transacción SQL junto con el registro de la ejecución garantiza que no quede una acción aplicada sin su registro ni un registro "exitoso" sin su acción. La idempotencia se impone con restricciones `unique`, que solo la base de datos garantiza bajo concurrencia.
- **Acciones con efectos externos en Edge Functions (posterior al MVP).** Las integraciones externas quedaron fuera del MVP; este diseño se documenta para que el modelo de datos no lo impida más adelante. Si una regla debe enviar un correo, la transacción SQL registra la acción como `programada`; una Edge Function la procesa, aplica timeout y reintentos limitados y la marca como `completada` o `fallida`. Así se diferencia acción programada de acción completada.
- **Detección de bloqueos en SQL.** Detectar tareas vencidas o sin actividad es una consulta sobre conjuntos de filas; hacerlo en SQL evita transferir datos y permite insertar hallazgos con `on conflict do nothing` sobre una clave de deduplicación.

### Convenciones
- Funciones expuestas como RPC en el esquema `public` (o un esquema de API dedicado, pendiente); funciones internas en `privado`, no expuesto.
- Las funciones RPC son `security invoker` por defecto. `security definer` solo cuando se justifique, con `set search_path = ''`, comprobación explícita de membresía/rol y prueba asociada.
- Errores de RPC con códigos propios (`raise exception using errcode = ...`) y mensajes seguros; no devolver nombres de restricciones ni SQL al cliente.
- Las Edge Functions devuelven errores con forma `{ "error": { "code", "message", "request_id" } }`.

## Consecuencias
- La lógica de negocio crítica queda en SQL versionado en migraciones, con pruebas pgTAP. Requiere disciplina de revisión de PL/pgSQL.
- Las Edge Functions quedan pequeñas y enfocadas, más fáciles de probar con `deno test`.
- El contrato de API para el frontend (ADR-0006; originalmente pensado para Stitch) se compone de: tablas/vistas expuestas, funciones RPC y endpoints de Edge Functions. Debe documentarse en `docs/api/` (pendiente).

## Cómo se verificará
- Revisión de cada nueva operación contra la tabla anterior antes de implementarla.
- Pruebas que demuestran atomicidad: si una acción falla, ni la acción ni un estado `exitosa` persisten.
- Pruebas de idempotencia: ejecutar dos veces la misma detección o el mismo evento no duplica hallazgos ni notificaciones.
