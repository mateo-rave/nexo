# ADR-0007: Modelo de proyectos, tareas, estados y flujos

- Estado: Aceptada
- Fecha: 2026-10-24 (decisiones aprobadas por el propietario)
- Responsables: propietario del producto

> **En pocas palabras:** las tareas usan un catálogo fijo de cinco estados. Cada proyecto sigue una versión publicada de un flujo de su organización, que decide qué transiciones están permitidas; toda organización tiene un flujo predeterminado. Cada organización tiene una zona horaria (`America/Bogota` por defecto) y una tarea vence cuando `ahora >= límite`. Los bloqueos manuales, los motivos de espera y «en riesgo» no forman parte del MVP.

## Contexto
- RF-012 y RF-013 piden tareas con estado y transiciones validadas en el backend; RF-020 y RF-021, flujos básicos con versiones publicadas. `mvp-scope.md` limita el flujo del MVP a «estados y transiciones permitidas de un proceso».
- RF-030 pide detectar tareas vencidas «según la hora y las reglas configuradas».
- Ningún documento definía los estados de una tarea, la relación entre flujo, proyecto y tarea, ni la zona horaria con la que se calcula un vencimiento.
- El panel de demostración del frontend (ADR-0006) usa cuatro estados y muestra conceptos sin respaldo en los requisitos: bloqueos manuales, motivos de espera, tareas «en riesgo» y siguientes pasos sugeridos. Son datos ficticios marcados como ilustrativos.
- Hoy existen las tablas `perfiles`, `organizaciones`, `membresias` y `auditoria` (migraciones 1 y 2, aplicadas en `nexo-dev`). Proyectos, tareas y flujos no existen todavía.

## Opciones consideradas
### Estados de las tareas
1. **Estados y transiciones fijos para todas las organizaciones.** Lo más simple, pero los flujos quedarían sin contenido y el MVP los incluye (CLAUDE.md, sección 2).
2. **Estados libres por flujo.** Máxima flexibilidad, pero la detección y las métricas no sabrían qué significa «terminada», y habría que validar texto libre.
3. **Catálogo fijo de estados y transiciones configurables por flujo.** La base de datos rechaza cualquier estado desconocido, la detección y las métricas funcionan igual en todas las organizaciones y los flujos tienen contenido real. **Elegida.**

### Relación entre proyectos, tareas y flujos
1. **Un flujo por organización.** Sencillo, pero no permite procesos distintos por proyecto.
2. **Un flujo por tarea.** Flexible, pero complejo de validar y de mostrar.
3. **Cada proyecto usa una versión publicada y sus tareas la heredan.** Un concepto claro, compatible con las FK compuestas y con la inmutabilidad de las versiones. **Elegida.**

### Zona horaria
1. **Todo en UTC y cada navegador en su hora local.** Un mismo vencimiento significaría cosas distintas para cada persona.
2. **Una zona horaria por organización.** Todo el equipo, la detección y las métricas usan la misma referencia. **Elegida.**
3. **Una zona horaria por usuario.** Excesiva para el MVP y sin un significado único del vencimiento.

## Decisión

### 1. Estados y transiciones
- **Catálogo** (tipo enumerado): `pendiente`, `en_curso`, `en_revision`, `completada` y `cancelada`. `completada` y `cancelada` son **terminales**: nunca vencen y no cuentan como trabajo abierto. `en_revision` es un estado de avance, no un proceso de aprobación (RF-035 sigue fuera del MVP).
- **Cada versión de flujo** elige qué estados del catálogo usa, un estado inicial no terminal, al menos un estado terminal y sus transiciones (solo entre estados de esa versión; ninguna de un estado a sí mismo).
- **Flujo predeterminado:**

  | Desde | Hacia |
  |---|---|
  | `pendiente` | `en_curso`, `cancelada` |
  | `en_curso` | `en_revision`, `cancelada` |
  | `en_revision` | `en_curso`, `completada`, `cancelada` |
  | `completada` | `en_curso` (reabrir) |
  | `cancelada` | ninguna |

  Estado inicial: `pendiente`.
- **Permisos:** todas las transiciones siguen la regla vigente de `docs/security/permissions.md` («Cambiar estado (solo transiciones permitidas)»): `propietario` y `administrador`, y `miembro` si es responsable o creador de la tarea. No hay excepciones por transición: cancelar y reabrir siguen la misma regla. El flujo solo decide si una transición existe.
- **Validación:** el estado cambia mediante una función RPC que comprueba el permiso, valida la transición y registra la auditoría en una sola transacción. Un trigger rechaza además cualquier cambio de estado que no siga una transición permitida, llegue por donde llegue. Ambos usan la misma función interna del esquema `privado`, para no duplicar la regla.

### 2. Proyectos, tareas y flujos
- **Jerarquía:** organización → flujos (`definiciones_flujo`) → versiones (`versiones_flujo`, `borrador` → `publicada`) → estados y transiciones de cada versión.
- **Los flujos se guardan en tablas, no en `jsonb`:** estados y transiciones son filas con restricciones y claves foráneas. El `jsonb` validado contra un catálogo cerrado queda para las reglas de automatización (RF-022).
- **FK compuestas (ADR-0002):** el proyecto apunta a una versión **publicada** de su misma organización, `(organizacion_id, version_flujo_id)`; la tarea apunta a su proyecto, `(organizacion_id, proyecto_id)`.
- **Inmutabilidad:** un trigger impide modificar una versión publicada y sus estados y transiciones (CLAUDE.md, sección 8).
- **Flujo predeterminado:** toda organización tiene uno publicado. Lo crea una función del módulo `flujos`, en `privado`, a la que llama `crear_organizacion`; el módulo de organizaciones no escribe directamente en las tablas de flujos (CLAUDE.md, sección 6). Las organizaciones existentes lo reciben con un relleno en la misma migración.
- **Versión de un proyecto:** el proyecto conserva la versión con la que se creó. En el MVP no se cambia: **un flujo nuevo o modificado solo se aplica a proyectos nuevos.**
- **Estado del proyecto:** `activo` o `archivado` (la matriz permite archivar), independiente de los flujos.
- **Escrituras:** las tareas se crean, editan, asignan, cambian de estado y eliminan solo mediante RPC, porque la matriz concede permisos distintos por columna y por condición (un `miembro` puede asignar responsable en cualquier tarea, pero editar el título solo en las suyas) y cada cambio debe quedar en la auditoría. La lectura usa la Data API con RLS, filtros y paginación (RF-041). La vía de escritura de los proyectos queda pendiente para el plan de la fase 2, aplicando los criterios de la ADR-0003.
- **Responsable:** debe ser miembro de la misma organización. FK compuesta `(organizacion_id, responsable_id)` hacia la clave primaria `(organizacion_id, usuario_id)` de `membresias`.

### 3. Fecha límite y zona horaria
- **Organización:** nueva columna `zona_horaria`, con `America/Bogota` por defecto. Un trigger la valida contra `pg_timezone_names` (un `check` no puede consultar tablas). La editan `propietario` y `administrador` («Editar nombre y datos de la organización») solo mediante una RPC; la Data API no recibe permiso de `update` sobre esa columna.
- **Tarea:** dos columnas, y la distinción entre fecha con hora y sin hora sale de cuál tiene valor:

  | Columna | Contenido | Es la fuente de verdad cuando… |
  |---|---|---|
  | `fecha_limite` (`date`, nula si no aplica) | El día elegido, **solo si se eligió sin hora**. | la tarea no tiene hora. |
  | `vence_en` (`timestamptz`, nula si no hay fecha límite) | El instante, exclusivo, a partir del cual la tarea está vencida. | la tarea tiene hora explícita; en las demás es un valor derivado. |

  Restricción: si hay `fecha_limite`, hay `vence_en`.
- **Cómo se calcula** (en la base de datos, no en el frontend; CLAUDE.md, sección 3). La RPC recibe el día y, si la hay, la hora local elegidos:
  - **Sin hora:** guarda el día; un trigger calcula `vence_en` como las 00:00 del día siguiente en la zona de la organización e ignora cualquier valor enviado.
  - **Con hora:** convierte el día y la hora con la zona de la organización y guarda solo el instante.
- **Cambio de zona horaria:** la RPC que la cambia, en una sola transacción, recalcula `vence_en` de las **tareas abiertas con `fecha_limite`** (sin hora), conserva los instantes de las tareas con hora explícita y de las tareas cerradas, y registra la auditoría.
- **Invariante:** en una tarea abierta sin hora, `vence_en` siempre está calculado con la zona actual de su organización. El trigger lo recalcula en cada escritura de la tarea, incluida la reapertura (de `completada` a `en_curso`).
- **Vencimiento:** una tarea está vencida si `ahora >= vence_en` y su estado no es terminal. Sin `vence_en` no vence nunca. La función de detección recibe el instante «ahora» como parámetro (en producción, la hora de la base de datos), para poder probarla con tiempo controlado.
- **Visualización:** sin hora se muestra el día elegido («vence el viernes»), nunca «sábado 00:00»; con hora, `vence_en` en la zona de la organización, indicando siempre la zona.
- **Deduplicación de hallazgos** (principio para la fase de detección): la clave usa la fecha límite tal como la eligió el usuario (el día si no tiene hora; el instante si la tiene), nunca el instante recalculado. Un cambio de zona no duplica un hallazgo; un cambio de fecha límite sí puede generar uno nuevo.

### 4. Salida de un miembro
- Al borrarse una membresía (con `quitar_miembro`, `salir_de_organizacion` o al eliminarse la cuenta), las tareas en las que esa persona era responsable quedan **sin responsable**: la FK vacía solo `responsable_id` (`on delete set null (responsable_id)`, disponible desde PostgreSQL 15).
- Esa acción automática ejecuta los triggers de fila de `tareas`. El trigger de auditoría la registra como **acción del sistema** (actor vacío) cuando la membresía del responsable anterior ya no existe; una reasignación hecha por una persona registra a su autor.
- Las RPC de la migración 2 no se modifican: el efecto sobre las tareas lo produce la FK.

### 5. Conceptos de la demostración
- **Bloqueo manual y motivos de espera:** fuera del MVP. Si se incorporan, serán una señal independiente del estado, no un estado del flujo; este modelo no lo impide.
- **«En riesgo»:** fuera de las decisiones aprobadas hasta validar su utilidad. Puede calcularse con `vence_en` y el estado sin columnas nuevas; si entra, se decidirá en la fase de métricas (RF-037).
- **Siguiente paso sugerido:** fuera del MVP (las sugerencias están pospuestas).
- Mientras el panel de demostración no esté conectado al backend, estos conceptos siguen marcados como ilustrativos. Al conectarlo, se retiran o se mantienen claramente identificados como ficticios.

## Consecuencias
- **Migraciones (ADR-0004):** no se editan las migraciones 1 y 2.
  - Una migración nueva del módulo `flujos` crea el tipo de estado, las tablas de flujos (con RLS, permisos explícitos y `revoke execute ... from public, anon` en cada función), los triggers de inmutabilidad, la función del flujo predeterminado con su relleno, la columna `zona_horaria`, su validación, la RPC que la cambia y el reemplazo de `crear_organizacion`.
  - Proyectos y tareas van en la migración siguiente (fase 2).
- **Contrato de `crear_organizacion`:** conserva su firma exacta (`p_nombre text`), así que se reemplaza con `create or replace` y mantiene sus permisos y pruebas. Como devuelve la fila completa (`returns public.organizaciones`), su respuesta y la de la Data API incluirán `zona_horaria`: cambio aditivo que debe documentarse en la API.
- **Orden de bloqueos (amplía ADR-0004):** organización → membresías → tareas. Una RPC de tareas no debe bloquear membresías después de bloquear una tarea, para no producir un bloqueo mutuo con `quitar_miembro`.
- **Nombres:** el tipo de estado, las tablas de estados y transiciones de cada versión, las columnas (`zona_horaria`, `fecha_limite`, `vence_en`, `responsable_id`), las RPC y las acciones de auditoría nuevas se añaden al glosario de ADR-0005 antes de usarlos.
- **Ventajas:** detección y métricas uniformes; flujos con contenido real sin validar `jsonb`; la base de datos impide relaciones entre organizaciones y transiciones fuera del flujo; el modelo admite añadir después señales de bloqueo, inactividad (RF-031) y etiquetas propias de estado.
- **Compromisos:**
  - las organizaciones no pueden crear estados propios;
  - un flujo nuevo solo se aplica a proyectos nuevos;
  - hay más RPC que mantener;
  - un `miembro` responsable puede cancelar o reabrir sus tareas aunque no pueda eliminarlas (queda auditado);
  - una organización de otra zona verá vencimientos en hora de Bogotá hasta cambiar la suya (el frontend debería pedir confirmarla al crearla).
- **Riesgos:** varias superficies nuevas de aislamiento; una zona mal configurada adelanta o retrasa vencimientos; las pruebas de API de tareas necesitarán más usuarios de prueba que el límite actual del Supabase local de CI (30 registros o inicios de sesión cada 5 minutos).
- **Pendiente de verificar antes de la migración:** la versión de PostgreSQL de `nexo-dev`. Si fuera anterior a la 15, `responsable_id` se vaciaría con un trigger en lugar de la FK, sin cambiar el resto de esta decisión.

## Cómo se verificará
Pruebas pgTAP y de integración de API, en CI:
- Una transición no permitida por el flujo se rechaza, por RPC y por escritura directa; una permitida funciona para cada rol que la matriz autoriza y se rechaza para los demás, con auditoría solo en los casos permitidos.
- `cancelada` no tiene salida; `completada → en_curso` funciona y recalcula `vence_en` si la tarea no tiene hora.
- Una versión publicada y sus estados y transiciones no pueden modificarse.
- Un proyecto no puede apuntar a una versión de otra organización ni a un borrador; una tarea no puede apuntar a un proyecto de otra organización.
- Toda organización, nueva o existente, tiene un flujo predeterminado publicado; `crear_organizacion` sigue pasando sus pruebas actuales.
- Una tarea sin hora recibe `vence_en` igual a las 00:00 del día siguiente en la zona de su organización.
- Al cambiar la zona se recalculan solo las tareas abiertas sin hora; las tareas con hora y las cerradas conservan su instante.
- El límite exclusivo funciona en el instante exacto (`ahora = vence_en` ya está vencida), con tiempo controlado y con una zona que tenga cambio de horario.
- Una zona horaria no válida se rechaza.
- Al salir o ser quitado un miembro, sus tareas quedan sin responsable y la auditoría lo registra como acción del sistema.
