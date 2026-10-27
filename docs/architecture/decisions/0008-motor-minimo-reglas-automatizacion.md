# ADR-0008: Motor mínimo de reglas de automatización

- Estado: Aceptada (aprobada por el propietario el 2026-10-27). Todavía no está implementada: la implementación empieza con el bloque 5.1.
- Fecha: 2026-10-27
- Responsables: propietario del producto

> **En pocas palabras:** una regla es un dato, no código: un activador, unas condiciones y unas acciones elegidas de un catálogo cerrado y validadas al guardarlas. Sus versiones publicadas no cambian. Cada cambio de estado de una tarea y cada hallazgo nuevo del detector dejan un **evento** en una cola persistente, dentro de la misma transacción. Un job de Supabase Cron procesa la cola cada minuto y crea como máximo **una ejecución por regla y evento**. Qué reglas actúan y con qué versión se decide por el momento en que ocurrió el evento, no por cuándo se procesa. Después ejecuta sus acciones internas en SQL, con un máximo de 3 intentos en total, y registra el resultado. Una persona recibe como máximo **una notificación por evento** (y, como hoy, una por hallazgo), venga del detector o de cualquier regla.

## Contexto
- **Criterios 3 y 4 del MVP** (`requirements.md`): «configurar una regla segura y limitada» y que «la regla se ejecuta y su resultado queda trazado». Son los únicos criterios de aceptación que no cubre lo construido hasta la fase 4.
- **Requisitos:**
  - RF-022: activadores, condiciones y acciones permitidas.
  - RF-023: estado, resultado y errores de cada ejecución.
  - RF-024: sin efectos duplicados.
  - RF-025: reintentos limitados y sin ciclos.
  - RF-034: ejecuciones registradas.
  - `CLAUDE.md` §2: «sin acciones ni notificaciones duplicadas por un mismo evento».
  - `CLAUDE.md` §8: definiciones como datos validados; ejecución con estado, marcas de tiempo, versión, resultado y errores seguros; idempotencia; límites de reintentos; prevención de ciclos; versiones publicadas inmutables; evaluación en SQL dentro de una transacción.
- **Documentos de arquitectura:**
  - `overview.md` tiene un «Motor de automatización (diseño propuesto)».
  - ADR-0003 asigna la evaluación de reglas con acciones internas a SQL, y a Cron la tarea de llamar a funciones versionadas. Las acciones externas quedan fuera del MVP.
- **Lo que ya existe en `main` y condiciona el diseño:**
  - **Tareas:** los usuarios no pueden escribir en `tareas` directamente (`revoke` y `grant select`); todo cambio pasa por RPC y queda en `auditoria`.
  - **El detector** `privado.detectar_tareas_vencidas(ahora)` (Cron, cada minuto) bloquea cada organización `for share` y, en una sola consulta encadenada, hace tres cosas:
    - crea `hallazgos`, con `unique (organizacion_id, clave_deduplicacion)`;
    - escribe la auditoría como sistema;
    - crea `notificaciones`, con `hallazgo_id` **obligatorio** y `unique (hallazgo_id, destinatario_id)`, y FK compuesta con `membresias` y `hallazgos` con borrado en cascada.
  - **Notificaciones en el frontend:** solo se leen `id, titulo, mensaje, leida_en, creado_en`. `marcar_notificacion_leida` filtra por destinatario.
  - **Pruebas actuales de notificaciones:** cuentan filas e identificadores. No comprueban columnas ni su obligatoriedad.
  - **Versiones inmutables:** el patrón con borrador y publicada, protegido por triggers, ya está probado en `versiones_flujo` (ADR-0007).
  - **Otros:** errores propios `PTxyz`, FK compuestas por organización y Postgres 17 en local y en CI.
- **Matriz de permisos ya aprobada** (`permissions.md`, «Flujos, reglas y ejecuciones»):
  - ver reglas, ejecuciones y sus errores: los tres roles;
  - crear y editar borradores, publicar y activar o desactivar: propietario y administrador;
  - nadie modifica una versión publicada;
  - reintentar manualmente una ejecución fallida: propietario y administrador.
- **Límite de Auth en CI:** el Supabase local de CI permite 30 registros o inicios de sesión cada 5 minutos (`auth.rate_limit.sign_in_sign_ups`). Hoy se usan 28: 25 registros de las pruebas de API (5 por módulo), 2 de las E2E y 1 inicio de sesión de `recorrido.spec.ts`.

## Opciones consideradas y recomendación

### 1. Momento de la evaluación
1. **Síncrona, dentro de la operación del usuario** (trigger o RPC).
   - Ventaja: efecto inmediato.
   - Inconvenientes: alarga la operación y un fallo de la regla podría revertirla. Los reintentos y la protección contra ciclos se complican, y contradice RNF-007.
2. **Cola persistente y procesamiento programado.**
   - El evento se escribe en la misma transacción que el cambio; un job lo procesa después.
   - Inconveniente: latencia de hasta 1 o 2 minutos.
   - Es lo que prevén ADR-0003 y RNF-007. **Recomendada.**
3. **Procesador en una Edge Function.**
   - Inconvenientes: pierde la transacción conjunta entre acción y registro y necesita la clave secreta. Solo se justifica con efectos externos, fuera del MVP.

### 2. Modelo de versiones
1. **Una tabla con número de versión** (`overview.md`).
   - Inconveniente: publicar obliga a copiar filas y la inmutabilidad depende de las columnas.
2. **Regla y versiones separadas, con borrador y publicada**, como los flujos.
   - Reutiliza un patrón probado. **Recomendada.**
   - Cambia lo escrito en `overview.md`, que se actualizará durante la implementación (tareas derivadas).

### 3. Validación de las definiciones `jsonb`
1. **`pg_jsonschema`.**
   - Ventaja: declarativo.
   - Inconvenientes: es una dependencia nueva que hay que verificar en local, en CI y en el plan; no da nuestros códigos `PTxyz` y no comprueba referencias dentro de la organización.
2. **Función propia en SQL sobre el catálogo cerrado.**
   - Comprueba claves exactas, tipos, valores de los enums, tamaños y referencias.
   - Da códigos propios y no añade dependencias. **Recomendada.**
3. **Tablas relacionales tipadas**, como los estados y las transiciones de ADR-0007.
   - Ventaja: lo valida la propia estructura.
   - Inconveniente: una tabla o muchas columnas opcionales por tipo.
   - Alternativa válida si se prefiere no usar `jsonb`.

Con cualquiera de las tres, la estructura se valida al guardar y las referencias se vuelven a comprobar al ejecutar.

### 4. Integración con el detector de vencimientos
1. **El detector emite un evento por cada hallazgo nuevo.**
   - En una migración nueva se reemplaza `privado.detectar_tareas_vencidas` (`create or replace`) con un paso más en la misma consulta encadenada: insertar en la cola un evento `tarea_vencida` por cada fila que devuelve la inserción de hallazgos.
   - Clave del evento: `tarea_vencida:<hallazgo_id>`, única.
   - El hallazgo ya está deduplicado, así que hay **un evento por vencimiento**, en la misma transacción que el hallazgo.
   - Hallazgos, notificaciones, auditoría, destinatarios y bloqueo **no cambian**. Las pruebas actuales del detector deben seguir pasando sin modificarlas. **Recomendada.**
   - La función se reemplaza, pero su resultado para los datos actuales es el mismo.
2. **Convertir el detector en la primera regla de cada organización.**
   - Ventaja: un único mecanismo.
   - Inconvenientes: cambia una funcionalidad ya validada y obliga a migrar datos. Se puede reconsiderar cuando el motor esté probado.
3. **Las reglas evalúan el vencimiento por su cuenta.** Habría dos detectores y duplicados. **Descartada.**

### 5. Notificaciones de las reglas
1. **Una tabla de notificaciones aparte.**
   - Inconveniente: duplica la bandeja, la RLS, `marcar_notificacion_leida`, la lectura del frontend y las pruebas.
2. **`hallazgo_id` opcional y un origen `accion_id`, deduplicando por acción y destinatario.**
   - Inconveniente: no cumple `CLAUDE.md` §2, porque dos reglas notificarían dos veces por el mismo evento.
3. **Ampliar `notificaciones` con dos columnas opcionales, `evento_id` y `accion_id`**, en una migración nueva. `hallazgo_id` deja de ser obligatorio y la restricción `unique (hallazgo_id, destinatario_id)` se mantiene. **Recomendada.**

**La restricción de origen.** Admite exactamente dos formas de notificación:

| Origen | `hallazgo_id` | `evento_id` | `accion_id` |
|---|---|---|---|
| Detector (como hoy) | obligatorio | vacío | vacío |
| Acción de una regla | el del evento si este procede de un hallazgo; vacío si no | obligatorio | obligatorio |

- La regla que la expresa: **`evento_id` y `accion_id` van juntos**, los dos llenos o los dos vacíos. Si están vacíos, `hallazgo_id` es obligatorio.
- Cualquier otra combinación se rechaza, por ejemplo una acción sin evento o una notificación sin ningún origen.
- Una notificación de una regla sobre `tarea_vencida` conserva **a la vez** `hallazgo_id`, `evento_id` y `accion_id`.

**Cómo se garantiza que el hallazgo corresponde al evento:**
- **El evento guarda su hallazgo.** El evento `tarea_vencida` guarda el hallazgo del que procede en una columna propia, `hallazgo_id`, con FK compuesta por organización. Una restricción del evento exige que `hallazgo_id` esté lleno si y solo si el tipo es `tarea_vencida`.
- **Un trigger revisa cada notificación antes de insertarla.** Si la notificación tiene `evento_id`, el trigger exige que:
  - su `hallazgo_id` sea exactamente el del evento, con comparación `is not distinct from`, que trata dos nulos como iguales y un nulo frente a un valor como distintos;
  - su `accion_id` pertenezca a una ejecución de ese mismo evento;
  - todo esté en la misma organización.
- **Qué impide el trigger.** Evita dos fallos:
  - que una notificación de una regla sobre un vencimiento omita el `hallazgo_id` y se salte así la deduplicación del detector;
  - que apunte a un hallazgo de otro evento.
- **Por qué un trigger y no solo una FK.** Las FK compuestas no se comprueban cuando una de sus columnas es nula, así que no bastan para exigir el `hallazgo_id`.
- **Quién escribe.** Solo escriben en `notificaciones` las funciones del sistema, porque `authenticated` no tiene permiso de escritura. Aun así, el trigger protege el dato aunque haya un error en ellas.

**Por qué no rompe nada:**
- Las filas existentes tienen `hallazgo_id` y `evento_id` y `accion_id` vacíos, así que cumplen la restricción nueva sin rellenar datos. El trigger solo actúa cuando hay `evento_id`.
- En Postgres las restricciones `unique` ignoran los valores nulos, así que una notificación no choca con la clave que no usa.
- No cambian la RLS, la RPC, la lectura del frontend ni las pruebas, que cuentan filas.

**Inserción cuando ya existe una notificación para ese destinatario:**
- La acción `notificar` calcula sus destinatarios entre los miembros actuales y los inserta con `on conflict do nothing`, sin columna de conflicto. Así cubre las dos restricciones `unique`:
  - **`(hallazgo_id, destinatario_id)`:** la persona ya recibió el aviso del detector o de otra regla para ese hallazgo;
  - **`(evento_id, destinatario_id)`:** otra regla ya la avisó por ese evento.
- **La notificación que ya existe no se modifica:** no cambian su origen, su texto ni su estado de lectura.
- **El destinatario queda omitido**, con el motivo `ya_notificado`, en el resultado de la acción. Se sabe comparando los destinatarios previstos con las filas que devolvió la inserción.
- **Sigue siendo un éxito:** la acción queda `completada` y no cuenta como fallo ni como reintento.
- **Orden garantizado.** El detector crea sus notificaciones y el evento en la misma consulta, y la regla se procesa en una transacción posterior. Por eso el aviso del detector siempre existe ya cuando la regla intenta avisar.
- **Quien dejó la organización** no recibe la notificación. La FK con `membresias` y el bloqueo `for share` de la organización lo impiden, y queda omitido con el motivo `ya_no_es_miembro`.

**Borrados:**
- **Tarea:** su hallazgo y sus notificaciones se borran en cascada, como hoy.
- **Evento:** las FK de `evento_id` y `accion_id` se definirán en 5.2. Como no se borran eventos ni acciones mientras no haya una política de retención, no hay riesgo inmediato.

### 6. Estados de una ejecución
1. **Cinco estados** (`pendiente`, `en_ejecucion`, `exitosa`, `fallida`, `omitida`, como en `overview.md`).
   - `en_ejecucion` solo tiene sentido si una ejecución dura más de una transacción, por ejemplo si la procesa una Edge Function.
2. **Cuatro estados: `pendiente`, `exitosa`, `fallida` y `omitida`.**
   - Cada ejecución se procesa de principio a fin dentro de la transacción del job, con su propio punto de recuperación.
   - Si el job se interrumpe, todo se deshace y la ejecución sigue `pendiente`.
   - `en_ejecucion` nunca se vería confirmado, así que no se añade un estado que no puede observarse. **Recomendada.**
   - Se añadiría cuando existan acciones externas. Este cambio respecto a `overview.md` se justifica por esa razón.

**Qué significa cada estado final:**
| Estado | Cuándo |
|---|---|
| `pendiente` | Aún no se ha intentado, o falló un intento con un error transitorio y quedan intentos (`intentos < 3`). Si es así, `proximo_intento_en` indica cuándo se hará el siguiente. |
| `exitosa` | Todas sus acciones quedaron `completada`, aunque no hubiera nadie a quien avisar porque todos estaban ya notificados. |
| `omitida` | No correspondía actuar: <br>• las condiciones no se cumplen;<br>• la tarea ya no existe;<br>• el hallazgo ya estaba resuelto;<br>• se superó la profundidad máxima o la regla ya está en la cadena de origen.<br>Se guarda el código del motivo. Pausar la regla después del evento **no** omite la ejecución (apartado 7). |
| `fallida` | Debía actuar y no pudo: <br>• un error que no es transitorio, en cualquier intento;<br>• un error transitorio en el tercer intento, es decir, sin intentos restantes.<br>Se guardan un código y un mensaje seguros, sin SQL ni nombres de restricciones, y el número de intentos realizados. |

Las acciones mantienen su propio estado (`programada`, `completada`, `fallida`). Así se distingue una acción programada de una completada (`CLAUDE.md` §8).

### 7. Semántica temporal: qué reglas y qué versión aplican a un evento
**Principio:** la elegibilidad de una regla y la versión aplicada se deciden **solo por el momento en que ocurrió el evento** (`ocurrido_en`). La hora a la que el job procesa la cola no influye: procesar un evento con un minuto o con una hora de retraso da el mismo resultado.

**El momento del evento:**
- en un cambio de estado, el de la transacción que cambió la tarea;
- en un vencimiento, el de la detección (`detectado_en` del hallazgo), porque el evento es la creación del hallazgo.

Los periodos son semiabiertos: incluyen su inicio y excluyen su fin.

**Opciones consideradas para el modelo:**
1. **Un campo `activa` y la fecha de la última activación (`activada_en`) en la regla**, como proponía la versión anterior.
   - **No basta.** No permite saber si la regla estaba activa en un instante del pasado:
     - una regla activada a las 10:00, pausada a las 11:00 y reactivada a las 12:00 solo guarda «12:00»;
     - un evento de las 10:30 procesado a las 12:05 se descartaría por error.
   - Además, comprobar si «sigue activa al procesarlo» hace depender el resultado de la hora de procesamiento. **Descartada.**
2. **Reconstruir los periodos a partir de la auditoría.**
   - Inconveniente: la auditoría es un registro para personas y no una fuente de datos para el motor, y no tiene una restricción que impida periodos solapados. **Descartada.**
3. **Cambio mínimo de modelo:** una tabla nueva, `periodos_activacion_regla`*, con `organizacion_id`, `regla_id`, `activada_en` y `desactivada_en` (vacío mientras siga activa).
   - La regla deja de guardar `activa` y `activada_en`: «está activa» significa «tiene un periodo abierto», y así no hay dos fuentes que puedan contradecirse.
   - **Recomendada.**
   - Para las versiones basta lo ya previsto: `publicada_en` en cada versión, que nunca cambia porque la versión publicada es inmutable.

**Ciclo de vida de un periodo (opción 3):**
| Operación | Qué hace con el periodo | Cuándo se rechaza |
|---|---|---|
| **Activar** la regla | **Inserta** un periodo nuevo con `activada_en` = momento de la activación y `desactivada_en` vacío. | La regla ya tiene un periodo abierto, no tiene ninguna versión publicada o `activada_en` sería anterior al fin del último periodo cerrado. |
| **Pausar** la regla | **Actualiza una sola vez** el periodo abierto: cambia `desactivada_en` de vacío al momento de la pausa. Es el único cambio que admite un periodo en toda su vida. | La regla no tiene ningún periodo abierto. |
| **Reactivar** la regla | Es una activación más: inserta un periodo nuevo. El anterior, ya cerrado, no se reabre ni se modifica. | Igual que activar. |
| Cualquier otro cambio | No existe ninguna operación autorizada que modifique un periodo cerrado, cambie `activada_en`, `regla_id` u `organizacion_id`, o elimine un periodo. | Siempre. |

**Cómo se garantiza** (defensa en capas, como en el resto del esquema):
1. **Operaciones autorizadas.** `authenticated` y `anon` solo pueden leer la tabla (`grant select` con RLS para los miembros). Solo escriben las dos RPC `security definer`, activar y pausar, que:
   - comprueban el rol (propietario o administrador) con `auth.uid()`;
   - bloquean la fila de la regla `for update`, de modo que dos activaciones o pausas de la misma regla se hacen una detrás de otra;
   - aplican las comprobaciones de la tabla anterior con códigos de error propios.
2. **Como máximo un periodo abierto.** Un índice único parcial sobre `regla_id` limitado a las filas con `desactivada_en` vacío lo impide en la propia base de datos. Esto vale incluso si dos peticiones llegaran a la vez, aunque la RPC ya bloquea la regla.
3. **Coherencia de las fechas.** Una restricción `check` exige que `desactivada_en` esté vacío o no sea anterior a `activada_en`.
   - Un periodo que se abre y se cierra en el mismo instante es vacío: como los periodos son semiabiertos, no contiene ningún evento.
   - La RPC de activar exige que el periodo nuevo no empiece antes del fin del último periodo cerrado, así que los periodos de una regla nunca se solapan.
   - No se usa una restricción de exclusión sobre rangos, porque necesitaría la extensión `btree_gist`, una dependencia nueva. Con el bloqueo de la regla y el índice parcial es suficiente.
4. **Inmutabilidad del periodo cerrado.** Un trigger `before update` solo admite una transición: `desactivada_en` pasa de vacío a un valor y las demás columnas no cambian. Cualquier otro `update` se rechaza, incluido el de un periodo ya cerrado.
5. **Sin borrados.** Unos triggers `before delete` y `before truncate` rechazan siempre la operación, como ya ocurre con `auditoria`. La FK hacia `reglas_automatizacion` es `on delete restrict`, y las reglas no se eliminan en esta fase.

**Relación con la selección de versión.** El motor nunca modifica el pasado: un periodo cerrado y una versión publicada son inmutables, y lo único que cambia es el cierre de un periodo abierto. Cerrar un periodo solo cambia la elegibilidad de los eventos **posteriores** a la pausa, que ya estaban fuera porque aún no habían ocurrido.

En consecuencia, la decisión sobre un evento ya ocurrido (si la regla actúa y con qué versión) es siempre la misma, aunque el evento se procese tarde o más de una vez.

**Regla de elegibilidad (opción 3).** Una regla actúa sobre un evento si y solo si:
1. tiene un periodo de activación que contiene el instante del evento (`activada_en <= ocurrido_en` y, si existe, `ocurrido_en < desactivada_en`);
2. tiene al menos una versión con `publicada_en <= ocurrido_en`.

La versión aplicada es la de mayor número entre ellas y queda registrada en la ejecución. Activar una regla exige que tenga una versión publicada, así que dentro de un periodo siempre hay alguna. Las reglas no se eliminan en esta fase, así que la historia de periodos y versiones nunca se pierde.

**Casos:**
| Situación | Resultado |
|---|---|
| El evento ocurre antes de la primera activación | La regla no actúa, aunque esté activa cuando se procesa la cola. |
| El evento ocurre con la regla activa | Actúa con la última versión publicada antes del evento. |
| Se publica una versión nueva después del evento y antes de procesarlo | Se usa la versión anterior, la vigente cuando ocurrió el evento. |
| El evento ocurre con la regla pausada | No actúa, aunque se reactive antes de procesar la cola. |
| Se pausa la regla después del evento y antes de procesarlo | **Actúa**, porque estaba activa cuando ocurrió el evento. Pausar solo afecta a los eventos posteriores. |
| Se reactiva tras una pausa | Abre un periodo nuevo. Los eventos de la pausa no se recuperan. |
| Activación y evento casi simultáneos | Decide la comparación de las marcas de tiempo guardadas, así que el resultado es determinista aunque no coincida con el orden de confirmación de las transacciones. Se acepta en el MVP. |

**Consecuencia que hay que comunicar:** pausar una regla no cancela los eventos que ya ocurrieron mientras estaba activa. Como mucho, esos eventos se procesan en los siguientes minutos. La pantalla de 5.3 debe decirlo. Cancelar lo pendiente sería una función nueva y no entra en esta fase.

### 8. Idempotencia
- **Evento:** `unique (organizacion_id, clave_evento)`.
  - `tarea_vencida:<hallazgo_id>`, para el detector.
  - El propio identificador del evento, para los cambios de estado, porque cada cambio es un evento distinto y el trigger se dispara una sola vez por cambio.
- **Ejecución:** `unique (regla_id, evento_id)`. Es **por regla y evento, no por versión**: aunque se publique una versión nueva, el mismo evento no puede volver a ejecutar la misma regla. Corrige la propuesta anterior, que decía «versión + evento».
- **Notificación:** por hallazgo y destinatario (ya existe) y por evento y destinatario (nueva).
- Todas las inserciones usan `on conflict do nothing`, así que procesar la cola dos veces no duplica nada.

### 9. Reintentos y tiempo límite
- **Qué se reintenta:** solo los errores transitorios, es decir, bloqueo no disponible, fallo de serialización y bloqueo mutuo. Los errores de datos fallan de inmediato.
- **Límite:** `max_intentos` = 3 cuenta **los intentos totales, incluido el primero**. `intentos` empieza en 0 y sube en cada intento realizado. La secuencia completa:

| Intento | Cuándo | Si termina con un error transitorio |
|---|---|---|
| 1 | En el primer procesamiento de la ejecución | Sigue `pendiente`, con `intentos = 1` y `proximo_intento_en` a 1 minuto |
| 2 | Al menos 1 minuto después del primero | Sigue `pendiente`, con `intentos = 2` y `proximo_intento_en` a 5 minutos |
| 3 | Al menos 5 minutos después del segundo | Queda `fallida`, con `intentos = 3` |

- No hay espera antes del primer intento.
- Las esperas son mínimas: el intento se hace en el primer procesamiento del job posterior a `proximo_intento_en`.
- Un error no transitorio deja la ejecución `fallida` en el intento en que ocurra, sin agotar los demás.
- **Tiempos:**
  - cada ejecución fija un `lock_timeout` corto, para que una espera de bloqueo se convierta en un error transitorio que se puede capturar y contar;
  - el job procesa un lote limitado con un `statement_timeout` general.
- **Riesgo conocido:** si se agota el `statement_timeout` general, se deshace todo el lote sin contar el intento, y una ejecución problemática podría repetirse. Con la acción `notificar` (unas pocas inserciones) el riesgo es bajo, y se mitiga con lotes pequeños y el `lock_timeout` por ejecución.
- **Solapamiento:** según la documentación de pg_cron, no se ejecutan a la vez dos instancias del mismo job; hay que verificarlo en 5.2. Aun así, las ejecuciones se toman con `for update skip locked`.
- **Reintento manual:** la matriz lo permite, pero no es necesario para los criterios 3 y 4. **Recomendación:** posponerlo a un bloque posterior. La fila de la matriz se mantiene.

### 10. Ciclos
- Los eventos causados por una acción llevan `ejecucion_origen_id` y `profundidad + 1`.
- Se omite la ejecución si se supera la profundidad máxima (3) o si la misma regla ya figura en su cadena de origen.
- Con el catálogo recomendado, `notificar` no genera eventos y no puede haber ciclos. Las columnas y la comprobación se incluyen igualmente, para no cambiar el modelo al añadir acciones que sí los generen.

### 11. Límite de registros de Auth en las pruebas de CI
1. **Subir `sign_in_sign_ups` en `supabase/config.toml`**, por ejemplo a 100.
   - Solo afecta al Supabase local y de CI.
   - Cambio mínimo y sin tocar las pruebas existentes. **Recomendada.**
   - Condición: no aplicar nunca ese archivo al proyecto remoto (`supabase config push`) sin revisarlo, y anotarlo en `test-strategy.md`.
2. **Compartir los usuarios entre módulos de prueba.**
   - Inconveniente: cada módulo de `deno test` registra los suyos; compartirlos obliga a reestructurar las pruebas existentes y los acopla.
3. **Crear los usuarios con la API de administración.**
   - Inconvenientes: las pruebas usarían la clave secreta y dejarían de actuar como el frontend. Además, el inicio de sesión posterior también cuenta para el límite.
4. **Meter las pruebas de reglas en un módulo existente.**
   - Inconveniente: acopla funcionalidades distintas.

## Decisión
Se aceptan las opciones recomendadas en cada apartado, con este **catálogo inicial cerrado**:

| Tipo | Valores | Notas |
|---|---|---|
| Activadores | `tarea_estado_cambiado`, `tarea_vencida` | El primero lo emite un trigger sobre `tareas` cuando cambia `estado`; cubre todas las RPC, porque no hay escritura directa. El segundo lo emite el detector. `tarea_creada` queda fuera hasta que se pida. |
| Condiciones (todas deben cumplirse; sin «o» ni expresiones) | `estado_destino` (lista del catálogo de estados; solo con `tarea_estado_cambiado`), `proyecto` (un proyecto de la organización), `con_responsable` (sí o no) | «Tiempo sin actividad» (RF-031) queda fuera porque su detección no existe. |
| Acciones (solo internas) | `notificar`, con destinatarios `responsable` o `propietarios_y_administradores` | Es la acción de menor riesgo y no genera eventos. Quedan fuera `crear_tarea_seguimiento`, `cambiar_estado` y `crear_hallazgo`; este último porque el detector ya lo hace. |

**Límites:** como máximo 5 condiciones y 3 acciones por versión, y un solo borrador por regla. El nombre de la regla tiene una longitud máxima. Los textos de las notificaciones se generan en el servidor, a partir de datos conocidos y del nombre de la regla.

### Modelo de datos propuesto
Los nombres del glosario de ADR-0005 se reutilizan. Los marcados con * son nuevos y se añadirán al glosario en el bloque 5.1, antes de usarlos.

| Tabla | Columnas principales |
|---|---|
| `reglas_automatizacion` | `organizacion_id`, `nombre`, `creado_por`. Sin `activa` ni `activada_en`: si está activa lo dicen sus periodos. |
| `periodos_activacion_regla`* | `regla_id`, `activada_en`, `desactivada_en` (vacío mientras siga activa).<br>• Se inserta al activar y se actualiza una sola vez al pausar.<br>• Cerrado, es inmutable; nunca se elimina (triggers `before update`, `before delete` y `before truncate`).<br>• Índice único parcial: como máximo un periodo abierto por regla.<br>• `check` de fechas.<br>• FK `on delete restrict` hacia la regla. |
| `versiones_regla`* | `regla_id`, `numero`, `estado` (`borrador`, `publicada`), `activador`, `condiciones` (`jsonb`), `acciones` (`jsonb`), `publicada_en`. Las publicadas son inmutables (trigger), incluido `publicada_en`. |
| `eventos_automatizacion`* | `tipo`; `tarea_id` (al borrar la tarea pasa a nulo, `on delete set null (tarea_id)`, para conservar el rastro); `hallazgo_id` (lleno si y solo si el tipo es `tarea_vencida`); `clave_evento`*; `datos` (instantánea del cambio); `ocurrido_en`; `ejecucion_origen_id`; `profundidad`*; `procesado_en`*. No se expone a `authenticated`. |
| `ejecuciones_automatizacion` | `regla_id`, `version_regla`, `evento_id`, `estado` (`pendiente`, `exitosa`, `fallida`, `omitida`), `intentos` (de 0 a 3), `max_intentos` (3, intentos totales incluido el primero), `proximo_intento_en`*, `iniciada_en`, `terminada_en`, `codigo_error`, `mensaje_error`, `resultado`. Con `unique (regla_id, evento_id)`. |
| `acciones_automatizacion` | `ejecucion_id`, `orden`, `tipo`, `estado` (`programada`, `completada`, `fallida`), `resultado` (destinatarios notificados y omitidos, con su motivo) |
| `notificaciones` (ampliada) | Más `evento_id`* y `accion_id`*, opcionales. Restricción de origen (apartado 5); trigger de correspondencia con el evento; `unique (evento_id, destinatario_id)`. |

Todas llevan `organizacion_id` con FK compuestas y triggers que impiden cambiarlo.

### Permisos, RLS y auditoría
- Se aplica la matriz vigente sin cambiarla.
- **Lectura con RLS** para los miembros: reglas, versiones, ejecuciones y acciones.
- **Escritura solo mediante RPC** `security definer` con `search_path` fijo, que comprueban el rol con `auth.uid()`:
  - crear la regla;
  - guardar el borrador;
  - publicar;
  - activar (abre un periodo de activación) o pausar (cierra el periodo abierto).
- Quien no es miembro recibe el mismo error que si el recurso no existiera. `anon` no tiene acceso.
- **Auditoría:**
  - creación, borrador guardado, publicación, activación y pausa de reglas. La auditoría es un registro para personas: el motor se basa en los periodos de activación, no en ella.
  - una fila con actor «sistema» al terminar cada ejecución, que recoge su resultado y los intentos, como exige `permissions.md`.

## Consecuencias
- **Positivas:**
  - cumple los criterios 3 y 4 del MVP con una acción de bajo riesgo;
  - el detector conserva su comportamiento y sus pruebas;
  - el modelo admite más adelante acciones que generan eventos y acciones externas (ADR-0003) sin rediseñarlo.
- **Compromisos:**
  - **latencia:** una regla actúa uno o dos minutos después del evento;
  - **mantenimiento:** se añaden un segundo job de Cron y una cola que crecerá, cuya retención (RNF-010) queda pendiente;
  - **cambios en lo existente:** `notificaciones` se amplía y `privado.detectar_tareas_vencidas` se reemplaza, siempre con migraciones nuevas;
  - **cambios en la documentación:** se aparta de `overview.md` en el modelo de versiones y en los estados.
- **Riesgos:**
  - la validación propia debe probarse caso por caso;
  - un `statement_timeout` del lote completo no cuenta como intento;
  - cambiar `supabase/config.toml` exige no aplicarlo nunca al proyecto remoto sin revisarlo.
- **Tareas derivadas** (se harán durante la implementación):
  - añadir los nombres al glosario de ADR-0005;
  - actualizar `overview.md` (modelo de versiones y estados) y `test-strategy.md` (límite de registros y pruebas del motor);
  - `permissions.md` no cambia.

## Cómo se verificará
Con pruebas en CI contra el Supabase local y desechable, según los criterios de [`docs/plans/fase-5-reglas-automatizacion.md`](../../plans/fase-5-reglas-automatizacion.md):
- **pgTAP:** validación, inmutabilidad, RLS, idempotencia, reintentos, ciclos, concurrencia e integración con el detector;
- **API:** pruebas con `supabase-js`;
- **E2E:** una prueba con Playwright;
- **lo que ya existe:** las 415 pruebas pgTAP, las 49 de API y las 2 E2E siguen pasando **sin modificarlas**.
