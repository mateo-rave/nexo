# Fase 5 — Motor mínimo de reglas de automatización

- Estado: **bloque 5.0 aprobado** por el propietario el 2026-10-27, con este plan y la [ADR-0008](../architecture/decisions/0008-motor-minimo-reglas-automatizacion.md) (aceptada). **La implementación del bloque 5.1 queda autorizada**; los bloques 5.2 y 5.3 siguen la regla de empezar solo tras aprobar el anterior. Todavía no hay código, migraciones ni pruebas de esta fase.
- Fecha: 2026-10-27
- Referencias: [ADR-0003](../architecture/decisions/0003-separacion-api-datos-sql-edge-functions.md), [ADR-0005](../architecture/decisions/0005-nombres-en-espanol.md), [ADR-0007](../architecture/decisions/0007-modelo-proyectos-tareas-estados-flujos.md), [ADR-0008](../architecture/decisions/0008-motor-minimo-reglas-automatizacion.md) (aceptada), [permisos](../security/permissions.md), [estrategia de pruebas](../qa/test-strategy.md), [alcance del MVP](../product/mvp-scope.md).

## Objetivo
Que una persona autorizada pueda configurar una regla limitada y segura, que la regla se ejecute cuando ocurra su evento y que su resultado quede trazado. Son los **criterios de aceptación 3 y 4 del MVP** (`requirements.md`) y el eslabón «regla → ejecución» del flujo crítico de `CLAUDE.md`, el único que falta después de las fases 1 a 4.

## Punto de partida (en `main`, `dd437f7`)
- **Tareas:** estados de un catálogo fijo y transiciones por flujo. Los usuarios no pueden escribir en `tareas` directamente: todo cambio pasa por RPC y se audita.
- **Detección de tareas vencidas** cada minuto: hallazgos deduplicados, notificaciones (con `hallazgo_id` obligatorio) al responsable o a propietarios y administradores, y auditoría como sistema.
- **Pruebas en CI:** 415 pgTAP, 49 de API y 2 E2E. Usan 28 de los 30 registros o inicios de sesión que permite el Supabase local cada 5 minutos.
- **Matriz de permisos** de reglas y ejecuciones ya aprobada en `permissions.md`.
- No existe ninguna tabla, función ni pantalla de reglas.

## Qué entra y qué no
**Entra** (según la ADR-0008, aceptada):
- Catálogo cerrado:
  - activadores `tarea_estado_cambiado` y `tarea_vencida`;
  - condiciones `estado_destino`, `proyecto` y `con_responsable`;
  - acción `notificar`, a `responsable` o a `propietarios_y_administradores`.
- Reglas con versiones `borrador` y `publicada` inmutables; activar y desactivar.
- Validación estricta de las definiciones `jsonb` con códigos de error propios.
- Cola persistente de eventos y procesamiento programado con Supabase Cron.
- Ejecuciones (`pendiente`, `exitosa`, `fallida`, `omitida`) y acciones con estado propio. Idempotencia por regla y evento, reintentos limitados y protección contra ciclos.
- Integración con el detector: emite un evento por hallazgo nuevo, sin cambiar su resultado.
- Notificaciones de reglas en la bandeja existente, como máximo una por evento y persona.
- Pantalla mínima para crear y publicar una regla y consultar sus ejecuciones.

**No entra.** Respecto a la primera versión del plan, el alcance se reduce o se precisa en estos puntos:
- **Reintento manual de una ejecución fallida:** la matriz lo permite, pero no es necesario para los criterios 3 y 4. Se pospone a un bloque posterior y la fila de la matriz se mantiene.
- **El estado `en_ejecucion`:** con el procesamiento en una sola transacción nunca se vería confirmado. Se añadirá cuando haya acciones externas (ADR-0008, apartado 6).
- **Acciones que generan eventos** (`crear_tarea_seguimiento`, `cambiar_estado`) y el activador `tarea_creada`, salvo que se aprueben.
- **Acciones con efectos externos** (correo, webhooks): ADR-0003 y `mvp-scope.md` los posponen.
- **Detección de inactividad** (RF-031), constructor visual, IA y sugerencias de reglas.
- **Historial de auditoría en pantalla, métricas y `docs/api/`:** pendientes del MVP con su propio bloque.
- **Retención de eventos y ejecuciones** (RNF-010): queda registrada como pendiente.

## Bloques de implementación
Cada bloque es una rama y un PR propios, con el CI en verde. Ninguno empieza sin aprobar el anterior.

| Bloque | Contenido | Pruebas |
|---|---|---|
| **5.0** (este) | Plan y ADR-0008. Solo documentación. **Aprobado el 2026-10-27.** | Revisión del propietario. |
| **5.1 — Definición de reglas** | Migración nueva:<br>• `reglas_automatizacion`, `periodos_activacion_regla` y `versiones_regla` (con `publicada_en`);<br>• triggers de inmutabilidad de las versiones publicadas y de los periodos, y de prohibición de borrado de los periodos;<br>• índice único parcial de periodo abierto y `check` de fechas;<br>• función de validación del catálogo;<br>• RPC para crear la regla, guardar el borrador, publicar, activar (abre un periodo) y pausar (lo cierra);<br>• RLS, permisos y auditoría.<br>Nombres en el glosario de ADR-0005. Subida de `sign_in_sign_ups` en `supabase/config.toml`, anotada en `test-strategy.md`. | pgTAP y API |
| **5.2 — Eventos y ejecución** | Migración nueva:<br>• `eventos_automatizacion` (con `hallazgo_id` en los vencimientos), `ejecuciones_automatizacion` y `acciones_automatizacion`;<br>• trigger de evento en `tareas`;<br>• reemplazo de `privado.detectar_tareas_vencidas` para que emita el evento;<br>• ampliación de `notificaciones` (`evento_id`, `accion_id`, restricción de origen, trigger de correspondencia con el evento y `unique (evento_id, destinatario_id)`);<br>• función de procesamiento y job de Cron `procesar_automatizaciones`. | pgTAP y API |
| **5.3 — Pantalla y recorrido** | Sección del espacio:<br>• listar reglas;<br>• crear una regla con el catálogo, sin texto libre salvo el nombre;<br>• publicar y activar;<br>• ver las ejecuciones con su estado, sus acciones, sus destinatarios omitidos y sus errores seguros.<br>La pantalla avisa de que la regla actúa en el siguiente procesamiento y de que pausarla no cancela los eventos ya ocurridos. | E2E y revisión visual |

## Pruebas necesarias
Siguen `test-strategy.md`, con el caso permitido y el denegado para cada fila de la matriz.

**Base de datos (pgTAP):**
- **Validación:** se acepta cada combinación válida del catálogo y se rechazan, cada uno con su código propio:
  - un activador, una condición o una acción desconocidos;
  - una clave de más o de menos;
  - un tipo incorrecto;
  - un estado fuera del catálogo;
  - `estado_destino` con `tarea_vencida`;
  - un proyecto de otra organización;
  - una definición por encima de los límites.
- **Inmutabilidad:** una versión publicada no se modifica ni se borra; solo puede haber un borrador por regla.
- **Permisos:**
  - propietario y administrador crean, publican y activan;
  - un miembro no puede;
  - todos los miembros leen las reglas y las ejecuciones de su organización.
  - Nadie lee la cola de eventos.
- **Aislamiento:** con la tabla completa de `test-strategy.md`, para cada tabla nueva y cada RPC. No se crea ninguna ejecución a nombre de otra organización.
- **Semántica temporal** (cada caso de la tabla del apartado 7 de la ADR-0008, procesando la cola con tiempo controlado):
  - un evento anterior a la primera activación no ejecuta la regla, aunque esté activa al procesarlo;
  - un evento ocurrido durante una pausa no la ejecuta, aunque se reactive antes de procesarlo;
  - un evento ocurrido con la regla activa la ejecuta, aunque se pause antes de procesarlo;
  - un evento usa la última versión publicada antes de él, aunque se publique otra antes de procesarlo;
  - activar, pausar y reactivar dejan periodos que no se solapan y como máximo uno abierto;
  - no se puede activar una regla sin versión publicada;
  - **el resultado es el mismo procesando el evento un minuto o una hora después.**
- **Periodos de activación** (con el caso permitido y el denegado):
  - activar inserta un periodo abierto; activar una regla que ya está activa se rechaza y no crea un segundo periodo;
  - el índice único parcial rechaza un segundo periodo abierto aunque se intente insertar fuera de la RPC (como propietario de las tablas, en la prueba);
  - pausar cierra el periodo abierto una sola vez; pausar una regla que no está activa se rechaza;
  - un periodo cerrado no admite ningún `update`: ni volver a cambiar `desactivada_en`, ni reabrirlo, ni cambiar `activada_en`, `regla_id` u `organizacion_id`;
  - un periodo abierto no admite ningún cambio salvo su cierre;
  - ningún periodo se puede borrar ni truncar;
  - una fecha de cierre anterior a la de apertura se rechaza;
  - una reactivación no puede empezar antes del fin del periodo anterior;
  - `authenticated` y `anon` no pueden escribir en la tabla; un miembro no puede activar ni pausar.
- **Idempotencia:**
  - procesar la cola dos veces da una sola ejecución por regla y evento;
  - publicar una versión nueva no vuelve a ejecutar un evento ya procesado;
  - la detección ejecutada dos veces da un solo evento por hallazgo.
- **Notificaciones:**
  - **restricción de origen:** se aceptan la forma del detector (solo `hallazgo_id`) y la de una acción (`evento_id` y `accion_id`, con o sin `hallazgo_id`), y se rechaza cualquier otra combinación;
  - **trigger de correspondencia:** se rechaza una notificación de una acción cuyo `hallazgo_id` no sea el de su evento (incluido omitirlo en un evento `tarea_vencida`) o cuya acción pertenezca a otro evento;
  - dos reglas que avisan a la misma persona por el mismo evento le crean una sola notificación;
  - una regla `tarea_vencida` no avisa de nuevo a quien ya recibió el aviso del detector, y la notificación que ya existía no cambia;
  - los destinatarios omitidos quedan anotados en la acción con su motivo (`ya_notificado`, `ya_no_es_miembro`), y la acción y la ejecución terminan como éxito.
- **Compatibilidad:**
  - las pruebas actuales del detector y de las notificaciones pasan **sin modificarlas**;
  - las notificaciones existentes siguen siendo válidas con la restricción nueva.
- **Estados:**
  - `exitosa` solo si todas las acciones quedan `completada`;
  - `omitida`, con su código, en cada motivo de la ADR-0008;
  - `fallida`, sin efectos parciales, ante un error que no es transitorio, en el intento en que ocurra.
- **Reintentos** (3 intentos totales, incluido el primero), provocando un fallo transitorio de bloqueo (`lock_timeout`):
  - tras el intento 1, la ejecución sigue `pendiente`, con `intentos = 1` y el siguiente intento a 1 minuto;
  - no se intenta de nuevo antes de esa espera;
  - tras el intento 2, sigue `pendiente`, con `intentos = 2` y el siguiente intento a 5 minutos;
  - tras el intento 3, queda `fallida`, con `intentos = 3`, un error seguro y sin un cuarto intento;
  - un fallo transitorio seguido de un éxito deja la ejecución `exitosa`, con el número de intentos realizados.
- **Concurrencia:** dos procesadores simultáneos no toman la misma ejecución (`skip locked`).
- **Ciclos:** se omite una ejecución que supera la profundidad máxima o repite la regla en su cadena de origen, con eventos de origen preparados en la prueba.
- **Revalidación:** si la tarea se borró, el proyecto se archivó o un destinatario salió de la organización, el resultado es el que define la ADR-0008, sin errores que filtren datos.

**API (`supabase-js`, `pruebas/api/`):** las mismas comprobaciones de permisos y aislamiento a través de la API pública con la clave publicable, más los códigos de error de las RPC nuevas. Habrá un módulo nuevo con sus 5 usuarios, posible gracias a la subida del límite de registros.

**E2E (Playwright):**
1. El propietario crea, publica y activa una regla: activador `tarea_estado_cambiado`, condición `estado_destino` = En revisión, acción `notificar` a `propietarios_y_administradores`.
2. Pasa una tarea a En revisión.
3. Tras el siguiente procesamiento programado, ve la ejecución `exitosa` y la notificación en su bandeja.

## Criterios verificables para dar la fase por terminada
La fase termina cuando los PR de los bloques 5.1, 5.2 y 5.3 están fusionados en `main`, con el CI en verde y, en ese CI:
1. Existen y pasan las pruebas pgTAP y de API de todos los puntos de «Pruebas necesarias».
2. Pasa la E2E descrita, contra el Supabase local, sin datos simulados.
3. Las 415 pruebas pgTAP, las 49 de API y las 2 E2E existentes pasan sin modificarlas, y los recuentos totales aumentan.
4. En particular, están probados con tiempo controlado:
   - todos los casos de la tabla de semántica temporal (apartado 7 de la ADR-0008);
   - el ciclo de vida de los periodos de activación: un periodo cerrado no cambia, no se borra y no puede haber dos abiertos a la vez;
   - la secuencia de los 3 intentos (1 minuto, 5 minutos, `fallida` sin un cuarto intento);
   - la restricción y el trigger de correspondencia de las notificaciones.
5. Ninguna tabla nueva expuesta tiene RLS deshabilitado. Las funciones `security definer` nuevas fijan `search_path`. El bundle no contiene claves secretas.
6. La documentación coincide con lo construido:
   - la ADR-0008 aceptada;
   - el glosario de ADR-0005;
   - `overview.md` y `test-strategy.md` actualizados.
7. Las migraciones se aplican a `nexo-dev` solo con autorización expresa del propietario. No es una condición para cerrar la fase.

## Decisiones aprobadas (2026-10-27)
### Antes de la primera migración (bloque 5.1)
Determinan las tablas, las RPC y las pruebas de 5.1. Aprobadas:

| # | Decisión | Decisión aprobada |
|---|---|---|
| A1 | Catálogo exacto y forma `jsonb` de cada condición y acción | El de la ADR-0008: dos activadores, tres condiciones y la acción `notificar`, con sus límites. |
| A2 | Modelo de versiones | Regla y versiones separadas, con borrador y publicada; un solo borrador por regla. |
| A3 | Método de validación | Función propia en SQL, con códigos de error propios. |
| A4 | Semántica temporal | La elegibilidad y la versión se deciden por el momento del evento. Tabla nueva `periodos_activacion_regla`, en lugar de `activa` y `activada_en`, más `publicada_en` en las versiones.<br>• Activar inserta un periodo y pausar actualiza `desactivada_en` una sola vez.<br>• Cerrado, el periodo es inmutable y no se elimina.<br>• Como máximo uno abierto por regla.<br>• Lo garantizan las RPC con la regla bloqueada, el índice único parcial, el `check` de fechas y los triggers `before update`, `before delete` y `before truncate` (ADR-0008, apartado 7). Una regla actúa sobre un evento si un periodo lo contiene y tiene una versión publicada antes de él. Pausar no cancela los eventos ya ocurridos. |
| A5 | Auditoría de la gestión de reglas | Una fila por creación, borrador guardado, publicación, activación y pausa. El motor no se basa en la auditoría. |
| A6 | Límite de registros de Auth en CI | Subir `sign_in_sign_ups` en `supabase/config.toml` (por ejemplo a 100), solo para local y CI, anotarlo en `test-strategy.md` y no aplicarlo nunca al proyecto remoto sin revisarlo. |
| A7 | Reintento manual | Posponerlo. No forma parte de 5.1 ni de 5.2. |

### Antes del bloque 5.2
Aprobadas con la ADR-0008; solo afectan a 5.2:

| # | Decisión | Decisión aprobada |
|---|---|---|
| B1 | Integración con el detector | El detector emite un evento por hallazgo nuevo dentro de su consulta, con clave `tarea_vencida:<hallazgo_id>`. Su comportamiento no cambia. |
| B2 | Notificaciones | `evento_id` y `accion_id` opcionales y siempre juntos; sin ellos, `hallazgo_id` es obligatorio. El evento guarda su `hallazgo_id`, y un trigger exige que coincida con el de la notificación y que la acción sea de ese evento. Las notificaciones de reglas sobre vencimientos llevan los tres. Se inserta con `on conflict do nothing`: la notificación existente no cambia y el destinatario queda omitido como `ya_notificado`. |
| B3 | Estados de la ejecución | Cuatro: `pendiente`, `exitosa`, `fallida` y `omitida`, con los motivos de la ADR-0008. |
| B4 | Idempotencia | `unique (regla_id, evento_id)` y la clave única del evento. |
| B5 | Valores de los límites | `max_intentos` = 3 intentos totales, incluido el primero; esperas de al menos 1 minuto antes del segundo y 5 minutos antes del tercero; profundidad máxima 3; `lock_timeout` por ejecución; el lote y el `statement_timeout`, los que se midan en 5.2. |
| B6 | Auditoría de las ejecuciones | Una fila con actor «sistema» al terminar cada ejecución, que recoge su resultado e intentos. |
| B7 | Tarea borrada | `on delete set null (tarea_id)` en los eventos, que conservan su instantánea. Las ejecuciones pendientes de esa tarea quedan `omitida`. |

### Pospuestas (no bloquean la fase 5)
- Retención de eventos y ejecuciones (RNF-010).
- Activador `tarea_creada` y acciones que generen eventos.
- Reintento manual.
- El estado `en_ejecucion` y las acciones externas.

## Riesgos
- **Validación propia incompleta:** cada rechazo del catálogo tendrá su prueba explícita.
- **Crecimiento de la cola:** lotes limitados, índice sobre los eventos sin procesar y retención pendiente.
- **Tiempo límite del lote:** un `statement_timeout` general deshace el lote sin contar el intento. Se mitiga con lotes pequeños y un `lock_timeout` por ejecución.
- **Cambios en lo existente** (`notificaciones` y el detector): se hacen con migraciones nuevas, y las pruebas actuales deben pasar sin modificarlas.
- **`supabase/config.toml`:** el cambio del límite no debe llegar nunca al proyecto remoto sin revisión.
- **Latencia percibida:** la pantalla debe decir que la regla actúa en el siguiente procesamiento.
