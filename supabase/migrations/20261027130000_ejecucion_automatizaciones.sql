-- =============================================================================
-- Migración: eventos y ejecución de reglas de automatización (fase 5,
-- bloque 5.2)
-- Decisión: ADR-0008 · Plan: docs/plans/fase-5-reglas-automatizacion.md
-- Permisos: docs/security/permissions.md · Nombres: ADR-0005
-- Multiempresa: ADR-0002 · Reparto de capas: ADR-0003 · Bloqueos: ADR-0004
--
-- Contenido:
--   1. Tipos: estado_ejecucion y estado_accion.
--   2. Tablas: eventos_automatizacion (cola persistente, no expuesta),
--      ejecuciones_automatizacion y acciones_automatizacion.
--   3. Notificaciones: evento_id y accion_id opcionales, restricción de
--      origen, una por evento y destinatario, y trigger de correspondencia.
--   4. Emisión de eventos: trigger sobre el cambio de estado de una tarea y
--      evento tarea_vencida desde el detector (privado.detectar_tareas_vencidas
--      se reemplaza; hallazgos, notificaciones y auditoría no cambian).
--   5. Procesamiento: reparto por momento del evento, ejecución con su propio
--      punto de recuperación, 3 intentos en total, ciclos y auditoría.
--   6. Comprobación programada con Supabase Cron.
--   7. RLS y permisos.
--
-- Semántica temporal (ADR-0008, apartado 7): qué reglas actúan y con qué
-- versión se decide por ocurrido_en, nunca por la hora de procesamiento. El
-- reparto solo toma eventos con al menos 10 segundos de antigüedad: así ya
-- son visibles las transacciones que empezaron antes (una activación o una
-- publicación todavía sin confirmar) y el resultado no depende del momento
-- en que pasa el job.
-- No se fija statement_timeout dentro de la función: un SET dentro de una
-- función no limita la sentencia ya en curso. Acotan el tiempo el lote
-- limitado y un lock_timeout por transacción, cuyo vencimiento se trata como
-- fallo transitorio.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Tipos
-- en_ejecucion no existe: cada ejecución se procesa de principio a fin dentro
-- de la transacción del job y ese estado nunca se vería confirmado (ADR-0008,
-- apartado 6).
-- -----------------------------------------------------------------------------
create type public.estado_ejecucion as enum ('pendiente', 'exitosa', 'fallida', 'omitida');

create type public.estado_accion as enum ('programada', 'completada', 'fallida');


-- -----------------------------------------------------------------------------
-- 2. Tablas
-- -----------------------------------------------------------------------------

-- 2.1 Cola persistente de lo que ocurrió. Se escribe en la misma transacción
-- que el cambio que la origina. Si la tarea o el hallazgo se borran, el
-- evento se conserva con su instantánea (datos) y la referencia queda vacía.
-- La regla "hallazgo_id lleno si y solo si es tarea_vencida" se exige al
-- crear el evento (trigger de la sección 4.1): un check estricto rompería el
-- borrado de una tarea, que vacía primero el hallazgo y después la tarea.
create table public.eventos_automatizacion (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references public.organizaciones (id) on delete cascade,
  tipo public.tipo_evento_automatizacion not null,
  tarea_id uuid,
  hallazgo_id uuid,
  clave_evento text not null,
  datos jsonb not null,
  ocurrido_en timestamptz not null,
  ejecucion_origen_id uuid,
  profundidad integer not null default 0,
  procesado_en timestamptz,
  -- Fallos del reparto de este evento (sección 5.7): tras 3 se descarta con
  -- codigo_error = reparto_fallido, para que un evento envenenado no se
  -- reintente en cada pasada.
  intentos_reparto integer not null default 0,
  codigo_error text,
  creado_en timestamptz not null default now(),
  foreign key (organizacion_id, tarea_id)
    references public.tareas (organizacion_id, id) on delete set null (tarea_id),
  foreign key (organizacion_id, hallazgo_id)
    references public.hallazgos (organizacion_id, id) on delete set null (hallazgo_id),
  constraint eventos_automatizacion_datos_validos check (jsonb_typeof(datos) = 'object'),
  constraint eventos_automatizacion_profundidad_valida check (profundidad >= 0),
  constraint eventos_automatizacion_intentos_reparto_validos check (intentos_reparto between 0 and 3),
  constraint eventos_automatizacion_hallazgo_solo_en_vencimientos
    check (tipo = 'tarea_vencida' or hallazgo_id is null),
  unique (organizacion_id, clave_evento),
  unique (organizacion_id, id)
);

create index eventos_automatizacion_sin_procesar_indice
  on public.eventos_automatizacion (ocurrido_en)
  where procesado_en is null;

-- 2.2 Una ejecución por regla y evento (idempotencia, ADR-0008, apartado 8).
-- intentos cuenta los intentos realizados; max_intentos (3) es el total,
-- incluido el primero (apartado 9).
create table public.ejecuciones_automatizacion (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  regla_id uuid not null,
  version_regla_id uuid not null,
  evento_id uuid not null,
  estado public.estado_ejecucion not null default 'pendiente',
  intentos integer not null default 0,
  max_intentos integer not null default 3,
  proximo_intento_en timestamptz not null,
  iniciada_en timestamptz,
  terminada_en timestamptz,
  codigo_error text,
  mensaje_error text,
  resultado jsonb not null default '{}'::jsonb,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  foreign key (organizacion_id, regla_id)
    references public.reglas_automatizacion (organizacion_id, id),
  foreign key (organizacion_id, version_regla_id)
    references public.versiones_regla (organizacion_id, id),
  -- La versión es de la misma regla.
  foreign key (regla_id, version_regla_id)
    references public.versiones_regla (regla_id, id),
  foreign key (organizacion_id, evento_id)
    references public.eventos_automatizacion (organizacion_id, id),
  constraint ejecuciones_automatizacion_max_intentos_valido check (max_intentos between 1 and 10),
  constraint ejecuciones_automatizacion_intentos_validos check (intentos between 0 and max_intentos),
  constraint ejecuciones_automatizacion_terminada_coherente
    check ((estado = 'pendiente') = (terminada_en is null)),
  constraint ejecuciones_automatizacion_exitosa_sin_error
    check (estado <> 'exitosa' or codigo_error is null),
  constraint ejecuciones_automatizacion_resultado_valido check (jsonb_typeof(resultado) = 'object'),
  unique (regla_id, evento_id),
  unique (organizacion_id, id)
);

create index ejecuciones_automatizacion_pendientes_indice
  on public.ejecuciones_automatizacion (proximo_intento_en)
  where estado = 'pendiente';

create index ejecuciones_automatizacion_organizacion_indice
  on public.ejecuciones_automatizacion (organizacion_id, creado_en desc);

-- El evento causado por una acción apunta a la ejecución que lo causó
-- (ciclos, ADR-0008, apartado 10).
alter table public.eventos_automatizacion
  add foreign key (organizacion_id, ejecucion_origen_id)
    references public.ejecuciones_automatizacion (organizacion_id, id);

-- 2.3 Cada acción de una ejecución, con su propio estado: así se distingue
-- una acción programada de una completada (CLAUDE.md, sección 8).
create table public.acciones_automatizacion (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  ejecucion_id uuid not null,
  orden integer not null,
  tipo text not null,
  estado public.estado_accion not null default 'programada',
  resultado jsonb not null default '{}'::jsonb,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  foreign key (organizacion_id, ejecucion_id)
    references public.ejecuciones_automatizacion (organizacion_id, id),
  constraint acciones_automatizacion_orden_valido check (orden between 1 and 3),
  constraint acciones_automatizacion_tipo_valido check (tipo in ('notificar')),
  constraint acciones_automatizacion_resultado_valido check (jsonb_typeof(resultado) = 'object'),
  unique (ejecucion_id, orden),
  unique (organizacion_id, id)
);

create trigger ejecuciones_automatizacion_asignar_actualizado_en
  before update on public.ejecuciones_automatizacion
  for each row execute function privado.asignar_actualizado_en();

create trigger acciones_automatizacion_asignar_actualizado_en
  before update on public.acciones_automatizacion
  for each row execute function privado.asignar_actualizado_en();

create trigger eventos_automatizacion_impedir_cambio_organizacion_id
  before update on public.eventos_automatizacion
  for each row execute function privado.impedir_cambio_organizacion_id();

create trigger ejecuciones_automatizacion_impedir_cambio_organizacion_id
  before update on public.ejecuciones_automatizacion
  for each row execute function privado.impedir_cambio_organizacion_id();

create trigger acciones_automatizacion_impedir_cambio_organizacion_id
  before update on public.acciones_automatizacion
  for each row execute function privado.impedir_cambio_organizacion_id();


-- -----------------------------------------------------------------------------
-- 3. Notificaciones de las reglas (ADR-0008, apartado 5)
-- Dos formas válidas:
--   detector (como hoy): solo hallazgo_id;
--   acción de una regla: evento_id y accion_id, y además el hallazgo_id del
--   evento si procede de un vencimiento.
-- Las filas existentes (solo hallazgo_id) ya cumplen la restricción. Las
-- restricciones unique ignoran los nulos: una persona recibe como máximo una
-- notificación por hallazgo (ya existía) y una por evento (nueva).
-- -----------------------------------------------------------------------------
alter table public.notificaciones
  alter column hallazgo_id drop not null,
  add column evento_id uuid,
  add column accion_id uuid,
  add constraint notificaciones_origen_valido check (
    (evento_id is null and accion_id is null and hallazgo_id is not null)
    or (evento_id is not null and accion_id is not null)
  ),
  add foreign key (organizacion_id, evento_id)
    references public.eventos_automatizacion (organizacion_id, id),
  add foreign key (organizacion_id, accion_id)
    references public.acciones_automatizacion (organizacion_id, id),
  add constraint notificaciones_evento_destinatario_unico unique (evento_id, destinatario_id);

-- Correspondencia con el evento: el hallazgo de la notificación es exactamente
-- el del evento (is not distinct from: un vacío frente a un valor no
-- coincide) y la acción pertenece a una ejecución de ese evento. Una clave
-- foránea compuesta no basta: no se comprueba si una de sus columnas es nula,
-- y permitiría omitir el hallazgo y saltarse la deduplicación del detector.
create function privado.validar_origen_notificacion()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_organizacion_id uuid;
  v_hallazgo_id uuid;
begin
  if new.evento_id is null then
    return new;
  end if;

  select e.organizacion_id, e.hallazgo_id into v_organizacion_id, v_hallazgo_id
  from public.eventos_automatizacion e
  where e.id = new.evento_id;

  if not found
     or v_organizacion_id is distinct from new.organizacion_id
     or new.hallazgo_id is distinct from v_hallazgo_id then
    raise exception using
      errcode = 'PT400',
      message = 'La notificación no corresponde a su evento.',
      detail = 'origen_notificacion_invalido';
  end if;

  if not exists (
    select 1
    from public.acciones_automatizacion a
    join public.ejecuciones_automatizacion x
      on x.organizacion_id = a.organizacion_id
     and x.id = a.ejecucion_id
    where a.id = new.accion_id
      and a.organizacion_id = new.organizacion_id
      and x.evento_id = new.evento_id
  ) then
    raise exception using
      errcode = 'PT400',
      message = 'La notificación no corresponde a su evento.',
      detail = 'origen_notificacion_invalido';
  end if;

  return new;
end;
$$;

create trigger notificaciones_validar_origen
  before insert or update of organizacion_id, hallazgo_id, evento_id, accion_id on public.notificaciones
  for each row execute function privado.validar_origen_notificacion();


-- -----------------------------------------------------------------------------
-- 4. Emisión de eventos
-- -----------------------------------------------------------------------------

-- 4.1 Al crear un evento: tarea obligatoria, y hallazgo obligatorio en los
-- vencimientos (la restricción de la tabla impide que lo tengan los demás).
create function privado.validar_evento_automatizacion()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.tarea_id is null then
    raise exception using
      errcode = 'PT400',
      message = 'Un evento debe indicar su tarea.', detail = 'evento_sin_tarea';
  end if;
  if new.tipo = 'tarea_vencida' and new.hallazgo_id is null then
    raise exception using
      errcode = 'PT400',
      message = 'Un evento de vencimiento debe indicar su hallazgo.', detail = 'evento_sin_hallazgo';
  end if;
  return new;
end;
$$;

create trigger eventos_automatizacion_validar
  before insert on public.eventos_automatizacion
  for each row execute function privado.validar_evento_automatizacion();

-- 4.2 Cambio de estado de una tarea. Los usuarios no escriben en tareas
-- directamente (solo mediante RPC), así que el trigger cubre todos los cambios
-- de estado. Si el cambio lo causa una acción de una regla, el motor fija el
-- parámetro de sesión nexo.ejecucion_origen_id (solo en su transacción) y el
-- evento hereda el origen y la profundidad + 1. Con el catálogo actual ninguna
-- acción cambia tareas: el mecanismo queda preparado (ADR-0008, apartado 10).
-- security definer (justificado): el evento debe escribirse sea cual sea el
-- rol que cambia la tarea, y authenticated no escribe en la cola.
create function privado.emitir_evento_estado_tarea()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
  v_texto text := current_setting('nexo.ejecucion_origen_id', true);
  v_origen_id uuid;
  v_profundidad integer := 0;
begin
  if v_texto ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    select x.id, e.profundidad + 1 into v_origen_id, v_profundidad
    from public.ejecuciones_automatizacion x
    join public.eventos_automatizacion e
      on e.organizacion_id = x.organizacion_id
     and e.id = x.evento_id
    where x.id = v_texto::uuid
      and x.organizacion_id = new.organizacion_id;

    if v_origen_id is null then
      v_profundidad := 0;
    end if;
  end if;

  insert into public.eventos_automatizacion (
    id, organizacion_id, tipo, tarea_id, clave_evento, datos, ocurrido_en,
    ejecucion_origen_id, profundidad
  )
  values (
    v_id, new.organizacion_id, 'tarea_estado_cambiado', new.id,
    'tarea_estado_cambiado:' || v_id::text,
    jsonb_build_object(
      'titulo', new.titulo,
      'estado_anterior', old.estado,
      'estado_nuevo', new.estado,
      'proyecto_id', new.proyecto_id,
      'responsable_id', new.responsable_id
    ),
    clock_timestamp(),
    v_origen_id,
    v_profundidad
  );

  return null;
end;
$$;

create trigger tareas_emitir_evento_estado
  after update of estado on public.tareas
  for each row
  when (old.estado is distinct from new.estado)
  execute function privado.emitir_evento_estado_tarea();

-- 4.3 Detector de vencimientos: se reemplaza para que, en la misma consulta
-- que crea cada hallazgo nuevo, anuncie un evento tarea_vencida (clave
-- tarea_vencida:<hallazgo_id>, ocurrido_en = detectado_en). Hallazgos,
-- notificaciones, destinatarios, auditoría y bloqueos son los de la migración
-- 20261025200000; solo se añade proyecto_id a la consulta de vencidas (para
-- la instantánea del evento) y el paso "eventos".
create or replace function privado.detectar_tareas_vencidas(p_ahora timestamptz)
returns integer
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_organizacion_id uuid;
  v_nuevos integer;
  v_total integer := 0;
begin
  if p_ahora is null then
    raise exception using errcode = 'PT400',
      message = 'Debes indicar el instante de la comprobación.', detail = 'ahora_invalido';
  end if;

  for v_organizacion_id in
    select distinct t.organizacion_id
    from public.tareas t
    where t.vence_en <= p_ahora
      and t.estado not in ('completada', 'cancelada')
    order by t.organizacion_id
  loop
    perform 1 from public.organizaciones o where o.id = v_organizacion_id for share;

    with vencidas as (
      select t.id, t.organizacion_id, t.proyecto_id, t.titulo, t.estado, t.responsable_id,
             t.fecha_limite, t.vence_en, o.zona_horaria
      from public.tareas t
      join public.organizaciones o on o.id = t.organizacion_id
      join public.proyectos p on p.organizacion_id = t.organizacion_id and p.id = t.proyecto_id
      where t.organizacion_id = v_organizacion_id
        and p.archivado_en is null
        and t.vence_en <= p_ahora
        and privado.tarea_vencida(t.vence_en, t.estado, p_ahora)
    ),
    nuevos as (
      insert into public.hallazgos (
        organizacion_id, tarea_id, tipo, prioridad, clave_deduplicacion, evidencia, detectado_en
      )
      select
        v.organizacion_id, v.id, 'tarea_vencida', 'alta',
        privado.clave_hallazgo_vencimiento(v.id, v.fecha_limite, v.vence_en),
        jsonb_build_object(
          'titulo', v.titulo,
          'estado', v.estado,
          'fecha_limite', v.fecha_limite,
          'vence_en', v.vence_en,
          'zona_horaria', v.zona_horaria,
          'comprobado_en', p_ahora
        ),
        p_ahora
      from vencidas v
      on conflict (organizacion_id, clave_deduplicacion) do nothing
      returning id, organizacion_id, tarea_id
    ),
    auditados as (
      insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
      select n.organizacion_id, null, 'hallazgo.creado', 'hallazgo', n.id,
             jsonb_build_object('tipo', 'tarea_vencida', 'tarea_id', n.tarea_id)
      from nuevos n
      returning 1
    ),
    notificadas as (
      insert into public.notificaciones (organizacion_id, destinatario_id, hallazgo_id, titulo, mensaje)
      select n.organizacion_id, m.usuario_id, n.id, 'Tarea vencida',
             format('La tarea «%s» superó su fecha límite.', v.titulo)
      from nuevos n
      join vencidas v on v.id = n.tarea_id
      join public.membresias m
        on m.organizacion_id = n.organizacion_id
       and (m.usuario_id = v.responsable_id
            or (v.responsable_id is null and m.rol in ('propietario', 'administrador')))
      on conflict (hallazgo_id, destinatario_id) do nothing
      returning 1
    ),
    eventos as (
      insert into public.eventos_automatizacion (
        organizacion_id, tipo, tarea_id, hallazgo_id, clave_evento, datos, ocurrido_en
      )
      select
        n.organizacion_id, 'tarea_vencida', n.tarea_id, n.id,
        'tarea_vencida:' || n.id::text,
        jsonb_build_object(
          'titulo', v.titulo,
          'estado', v.estado,
          'proyecto_id', v.proyecto_id,
          'responsable_id', v.responsable_id,
          'fecha_limite', v.fecha_limite,
          'vence_en', v.vence_en
        ),
        p_ahora
      from nuevos n
      join vencidas v on v.id = n.tarea_id
      on conflict (organizacion_id, clave_evento) do nothing
      returning 1
    )
    select count(*) into v_nuevos from nuevos;

    v_total := v_total + v_nuevos;
  end loop;

  return v_total;
end;
$$;


-- -----------------------------------------------------------------------------
-- 5. Procesamiento
-- No son RPC: las ejecuta el job programado (sección 6) y nadie más puede
-- llamarlas desde la API (sección 7). Reciben "ahora" como parámetro para
-- poder probarlas con tiempo controlado; el job les pasa now().
-- -----------------------------------------------------------------------------

-- 5.1 Textos.
create function privado.etiqueta_estado_tarea(p_estado text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_estado
    when 'pendiente' then 'Pendiente'
    when 'en_curso' then 'En curso'
    when 'en_revision' then 'En revisión'
    when 'completada' then 'Completada'
    when 'cancelada' then 'Cancelada'
    else p_estado
  end;
$$;

create function privado.mensaje_resultado_automatizacion(p_codigo text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_codigo
    when 'condiciones_no_cumplidas' then 'El evento no cumple las condiciones de la regla.'
    when 'tarea_no_disponible' then 'La tarea ya no existe.'
    when 'hallazgo_resuelto' then 'El hallazgo ya estaba resuelto.'
    when 'profundidad_maxima' then 'Se superó la profundidad máxima de automatizaciones encadenadas.'
    when 'ciclo_detectado' then 'La regla ya forma parte de la cadena que causó el evento.'
    when 'fallo_transitorio' then 'Fallo temporal; se volverá a intentar.'
    when 'reintentos_agotados' then 'No se pudo completar tras agotar los intentos.'
    when 'error_registro' then 'No se pudo registrar el resultado de la ejecución.'
    when 'reparto_fallido' then 'No se pudo repartir el evento a sus reglas.'
    else 'No se pudo completar la ejecución.'
  end;
$$;

-- 5.2 ¿Se cumplen las condiciones? Se evalúan sobre la instantánea del evento
-- (datos), así el resultado no depende de cambios posteriores en la tarea.
-- Las condiciones ya están validadas (migración 20261027120000): los uuid
-- tienen formato correcto.
create function privado.condiciones_cumplidas(p_condiciones jsonb, p_datos jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(bool_and(
    case c.valor ->> 'tipo'
      when 'estado_destino' then
        p_datos ? 'estado_nuevo' and (c.valor -> 'estados') @> jsonb_build_array(p_datos -> 'estado_nuevo')
      when 'proyecto' then
        (p_datos ->> 'proyecto_id') is not null
        and (p_datos ->> 'proyecto_id')::uuid = (c.valor ->> 'proyecto_id')::uuid
      when 'con_responsable' then
        ((p_datos ->> 'responsable_id') is not null) = (c.valor ->> 'valor')::boolean
      else false
    end
  ), true)
  from jsonb_array_elements(p_condiciones) c (valor);
$$;

-- 5.3 Motivo para no actuar, o null si la regla debe actuar (ADR-0008,
-- apartado 6).
create function privado.motivo_omision_automatizacion(
  p_ejecucion public.ejecuciones_automatizacion,
  p_evento public.eventos_automatizacion,
  p_version public.versiones_regla
)
returns text
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_evento.tarea_id is null then
    return 'tarea_no_disponible';
  end if;

  if p_evento.tipo = 'tarea_vencida' then
    if p_evento.hallazgo_id is null then
      return 'tarea_no_disponible';
    end if;
    if exists (
      select 1
      from public.hallazgos h
      where h.organizacion_id = p_evento.organizacion_id
        and h.id = p_evento.hallazgo_id
        and h.resuelto_en is not null
    ) then
      return 'hallazgo_resuelto';
    end if;
  end if;

  if p_evento.profundidad > 3 then
    return 'profundidad_maxima';
  end if;

  -- La regla ya figura en la cadena de ejecuciones que causó el evento. UNION
  -- (no UNION ALL) detiene la recursión si la cadena se repite.
  if p_evento.ejecucion_origen_id is not null and exists (
    with recursive cadena (ejecucion_id) as (
      select p_evento.ejecucion_origen_id
      union
      select e.ejecucion_origen_id
      from cadena c
      join public.ejecuciones_automatizacion x on x.id = c.ejecucion_id
      join public.eventos_automatizacion e
        on e.organizacion_id = x.organizacion_id
       and e.id = x.evento_id
      where e.ejecucion_origen_id is not null
    )
    select 1
    from cadena c
    join public.ejecuciones_automatizacion x on x.id = c.ejecucion_id
    where x.regla_id = p_ejecucion.regla_id
  ) then
    return 'ciclo_detectado';
  end if;

  if not privado.condiciones_cumplidas(p_version.condiciones, p_evento.datos) then
    return 'condiciones_no_cumplidas';
  end if;

  return null;
end;
$$;

-- 5.4 Acción notificar. Destinatarios entre los miembros actuales (la
-- organización está bloqueada "for share"). Se inserta con on conflict do
-- nothing sin columna de conflicto: cubre a la vez una notificación previa
-- del mismo hallazgo (detector u otra regla) y una del mismo evento (otra
-- regla). La notificación existente no cambia y el destinatario queda omitido
-- como ya_notificado; la acción se completa igualmente.
create function privado.ejecutar_accion_notificar(
  p_accion_id uuid,
  p_evento public.eventos_automatizacion,
  p_regla public.reglas_automatizacion,
  p_accion jsonb
)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_previstos uuid[];
  v_notificados uuid[];
  v_responsable_id uuid;
  v_mensaje text;
begin
  if p_accion ->> 'destinatarios' = 'responsable' then
    select t.responsable_id into v_responsable_id
    from public.tareas t
    where t.organizacion_id = p_evento.organizacion_id
      and t.id = p_evento.tarea_id;

    v_previstos := case when v_responsable_id is null then '{}'::uuid[] else array[v_responsable_id] end;
  else
    select coalesce(array_agg(m.usuario_id order by m.usuario_id), '{}'::uuid[]) into v_previstos
    from public.membresias m
    where m.organizacion_id = p_evento.organizacion_id
      and m.rol in ('propietario', 'administrador');
  end if;

  if p_evento.tipo = 'tarea_vencida' then
    v_mensaje := format('La tarea «%s» superó su fecha límite.', p_evento.datos ->> 'titulo');
  else
    v_mensaje := format(
      'La tarea «%s» pasó a %s.',
      p_evento.datos ->> 'titulo',
      privado.etiqueta_estado_tarea(p_evento.datos ->> 'estado_nuevo')
    );
  end if;

  with insertadas as (
    insert into public.notificaciones (
      organizacion_id, destinatario_id, hallazgo_id, evento_id, accion_id, titulo, mensaje
    )
    select
      p_evento.organizacion_id, d.usuario_id, p_evento.hallazgo_id, p_evento.id, p_accion_id,
      format('Regla «%s»', p_regla.nombre), v_mensaje
    from unnest(v_previstos) d (usuario_id)
    on conflict do nothing
    returning destinatario_id
  )
  select coalesce(array_agg(i.destinatario_id), '{}'::uuid[]) into v_notificados
  from insertadas i;

  update public.acciones_automatizacion a
  set estado = 'completada',
      resultado = jsonb_build_object(
        'notificados', to_jsonb(v_notificados),
        'omitidos', (
          select coalesce(jsonb_agg(jsonb_build_object('destinatario_id', d.usuario_id, 'motivo', 'ya_notificado')), '[]'::jsonb)
          from unnest(v_previstos) d (usuario_id)
          where not (d.usuario_id = any (v_notificados))
        )
      )
  where a.id = p_accion_id;
end;
$$;

-- 5.5 Un intento de una ejecución pendiente (ya bloqueada por quien llama).
-- El intento se cuenta antes del subbloque, así que queda contado aunque el
-- subbloque se deshaga. El subbloque es un punto de recuperación: si algo
-- falla, no persiste ningún efecto parcial (ni notificaciones ni acciones
-- completadas).
-- 3 intentos en total: tras un fallo transitorio en el intento 1 se espera
-- 1 minuto; en el 2, 5 minutos; en el 3, la ejecución queda fallida. Un error
-- que no es transitorio la deja fallida en el intento en que ocurre.
create function privado.ejecutar_automatizacion(p_ejecucion_id uuid, p_ahora timestamptz)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_ejecucion public.ejecuciones_automatizacion;
  v_evento public.eventos_automatizacion;
  v_version public.versiones_regla;
  v_regla public.reglas_automatizacion;
  v_motivo text;
  v_accion jsonb;
  v_orden integer;
  v_accion_id uuid;
  v_codigo text;
begin
  select * into v_ejecucion from public.ejecuciones_automatizacion x where x.id = p_ejecucion_id;
  select * into v_evento from public.eventos_automatizacion e where e.id = v_ejecucion.evento_id;
  select * into v_version from public.versiones_regla v where v.id = v_ejecucion.version_regla_id;
  select * into v_regla from public.reglas_automatizacion r where r.id = v_ejecucion.regla_id;

  update public.ejecuciones_automatizacion x
  set intentos = x.intentos + 1,
      iniciada_en = coalesce(x.iniciada_en, p_ahora)
  where x.id = p_ejecucion_id
  returning * into v_ejecucion;

  begin
    -- Igual que el detector: espera a que termine una salida de miembro en
    -- curso y lee el estado confirmado, así no notifica a quien ya salió.
    -- Dentro del subbloque, una espera agotada (lock_timeout) es un fallo
    -- transitorio que ya está contado.
    perform 1 from public.organizaciones o where o.id = v_ejecucion.organizacion_id for share;

    v_motivo := privado.motivo_omision_automatizacion(v_ejecucion, v_evento, v_version);

    if v_motivo is not null then
      update public.ejecuciones_automatizacion x
      set estado = 'omitida',
          terminada_en = p_ahora,
          codigo_error = v_motivo,
          mensaje_error = privado.mensaje_resultado_automatizacion(v_motivo),
          resultado = jsonb_build_object('motivo', v_motivo)
      where x.id = p_ejecucion_id;
    else
      v_orden := 0;
      for v_accion in
        select a.valor
        from jsonb_array_elements(v_version.acciones) with ordinality a (valor, posicion)
        order by a.posicion
      loop
        v_orden := v_orden + 1;

        insert into public.acciones_automatizacion (organizacion_id, ejecucion_id, orden, tipo)
        values (v_ejecucion.organizacion_id, p_ejecucion_id, v_orden, v_accion ->> 'tipo')
        on conflict (ejecucion_id, orden) do nothing;

        select a.id into v_accion_id
        from public.acciones_automatizacion a
        where a.ejecucion_id = p_ejecucion_id
          and a.orden = v_orden;

        -- El catálogo solo tiene la acción notificar (ADR-0008).
        perform privado.ejecutar_accion_notificar(v_accion_id, v_evento, v_regla, v_accion);
      end loop;

      update public.ejecuciones_automatizacion x
      set estado = 'exitosa',
          terminada_en = p_ahora,
          codigo_error = null,
          mensaje_error = null,
          resultado = jsonb_build_object('acciones', v_orden)
      where x.id = p_ejecucion_id;
    end if;
  exception
    when lock_not_available or serialization_failure or deadlock_detected then
      if v_ejecucion.intentos >= v_ejecucion.max_intentos then
        v_codigo := 'reintentos_agotados';
      else
        update public.ejecuciones_automatizacion x
        set proximo_intento_en = p_ahora + case v_ejecucion.intentos
              when 1 then interval '1 minute'
              else interval '5 minutes'
            end,
            codigo_error = 'fallo_transitorio',
            mensaje_error = privado.mensaje_resultado_automatizacion('fallo_transitorio')
        where x.id = p_ejecucion_id;
      end if;
    when others then
      v_codigo := 'error_interno';
  end;

  -- Fallo definitivo: la ejecución queda fallida y sus acciones también (el
  -- subbloque deshizo las que se hubieran empezado).
  if v_codigo is not null then
    update public.ejecuciones_automatizacion x
    set estado = 'fallida',
        terminada_en = p_ahora,
        codigo_error = v_codigo,
        mensaje_error = privado.mensaje_resultado_automatizacion(v_codigo),
        resultado = jsonb_build_object('motivo', v_codigo)
    where x.id = p_ejecucion_id;

    insert into public.acciones_automatizacion (organizacion_id, ejecucion_id, orden, tipo, estado)
    select v_ejecucion.organizacion_id, p_ejecucion_id, a.posicion::integer, a.valor ->> 'tipo', 'fallida'
    from jsonb_array_elements(v_version.acciones) with ordinality a (valor, posicion)
    on conflict (ejecucion_id, orden) do update set estado = 'fallida';
  end if;

  -- Auditoría (actor "sistema") al terminar la ejecución.
  select * into v_ejecucion from public.ejecuciones_automatizacion x where x.id = p_ejecucion_id;

  if v_ejecucion.estado <> 'pendiente' then
    insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
    values (
      v_ejecucion.organizacion_id, null, 'ejecucion.terminada', 'ejecucion', p_ejecucion_id,
      jsonb_build_object(
        'regla_id', v_ejecucion.regla_id,
        'version_regla_id', v_ejecucion.version_regla_id,
        'evento_id', v_ejecucion.evento_id,
        'estado', v_ejecucion.estado,
        'intentos', v_ejecucion.intentos,
        'codigo', v_ejecucion.codigo_error
      )
    );
  end if;
end;
$$;

-- 5.6 Registro de un fallo ocurrido fuera del subbloque de la ejecución (por
-- ejemplo, al escribir su auditoría o al marcarla como fallida). Quien llama
-- ya deshizo todo lo de ese intento, también sus efectos: la ejecución nunca
-- queda exitosa sin su registro. Cuenta el intento con la misma política de
-- 3 intentos totales (esperas de 1 y 5 minutos) y, al agotarlos, la deja
-- fallida con error_registro.
-- Cada escritura va en su propio punto de recuperación. Si ni siquiera el
-- estado se puede guardar, la ejecución queda como estaba (pendiente, nunca
-- exitosa) y se emite un aviso en el registro del servidor: no se oculta que
-- no pudo persistirse, y la pasada continúa con las demás.
create function privado.registrar_fallo_ejecucion(
  p_ejecucion_id uuid,
  p_ahora timestamptz,
  p_sqlstate text
)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_ejecucion public.ejecuciones_automatizacion;
begin
  begin
    update public.ejecuciones_automatizacion x
    set intentos = x.intentos + 1,
        iniciada_en = coalesce(x.iniciada_en, p_ahora),
        estado = case when x.intentos + 1 >= x.max_intentos then 'fallida' else 'pendiente' end::public.estado_ejecucion,
        terminada_en = case when x.intentos + 1 >= x.max_intentos then p_ahora end,
        proximo_intento_en = case
          when x.intentos + 1 >= x.max_intentos then x.proximo_intento_en
          when x.intentos + 1 = 1 then p_ahora + interval '1 minute'
          else p_ahora + interval '5 minutes'
        end,
        codigo_error = 'error_registro',
        mensaje_error = privado.mensaje_resultado_automatizacion('error_registro'),
        resultado = jsonb_build_object('motivo', 'error_registro')
    where x.id = p_ejecucion_id
      and x.estado = 'pendiente'
    returning * into v_ejecucion;
  exception
    when others then
      raise warning 'Nexo: no se pudo registrar el fallo de la ejecución % (SQLSTATE % y después %); sigue pendiente.',
        p_ejecucion_id, p_sqlstate, sqlstate;
      return;
  end;

  if v_ejecucion.estado = 'fallida' then
    begin
      insert into public.acciones_automatizacion (organizacion_id, ejecucion_id, orden, tipo, estado)
      select v_ejecucion.organizacion_id, p_ejecucion_id, a.posicion::integer, a.valor ->> 'tipo', 'fallida'
      from public.versiones_regla v
      cross join lateral jsonb_array_elements(v.acciones) with ordinality a (valor, posicion)
      where v.id = v_ejecucion.version_regla_id
      on conflict (ejecucion_id, orden) do update set estado = 'fallida';
    exception
      when others then
        raise warning 'Nexo: la ejecución % quedó fallida (%), pero no se pudieron marcar sus acciones (SQLSTATE %).',
          p_ejecucion_id, v_ejecucion.codigo_error, sqlstate;
    end;

    begin
      insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
      values (
        v_ejecucion.organizacion_id, null, 'ejecucion.terminada', 'ejecucion', p_ejecucion_id,
        jsonb_build_object(
          'regla_id', v_ejecucion.regla_id,
          'version_regla_id', v_ejecucion.version_regla_id,
          'evento_id', v_ejecucion.evento_id,
          'estado', v_ejecucion.estado,
          'intentos', v_ejecucion.intentos,
          'codigo', v_ejecucion.codigo_error
        )
      );
    exception
      when others then
        raise warning 'Nexo: la ejecución % quedó fallida (%), pero no se pudo auditar (SQLSTATE %).',
          p_ejecucion_id, v_ejecucion.codigo_error, sqlstate;
    end;
  end if;
end;
$$;

-- 5.7 Procesamiento de la cola: reparto y ejecución, en lotes limitados.
-- Devuelve cuántas ejecuciones intentó en esta pasada.
-- Reparto: para cada evento sin procesar con al menos 10 segundos de
-- antigüedad, una ejecución por cada regla con un periodo de activación que
-- contiene ocurrido_en y una versión publicada antes de ocurrido_en (la de
-- mayor número), si su activador coincide con el tipo del evento.
-- Aislamiento de errores: cada evento y cada ejecución van en su propio punto
-- de recuperación, así un error ordinario de uno no deshace ni detiene los
-- demás de la pasada.
--   Evento: si su reparto falla, no se crea ninguna de sus ejecuciones, se
--   cuenta el fallo y se reintenta en la pasada siguiente; al tercero se
--   descarta (procesado_en con codigo_error = reparto_fallido) y se audita.
--   Ejecución: si falla algo fuera de su subbloque interno, se deshace el
--   intento entero y lo registra privado.registrar_fallo_ejecucion.
-- query_canceled (cancelación o tiempo agotado de la sentencia) no lo captura
-- "when others" y no se intercepta: cancela la pasada entera, como debe
-- poder hacerse, y no queda nada a medias porque la pasada es una sola
-- transacción.
create function privado.procesar_automatizaciones(p_ahora timestamptz)
returns integer
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_limite constant integer := 100;
  v_margen constant interval := interval '10 seconds';
  v_max_intentos_reparto constant integer := 3;
  v_evento record;
  v_ejecucion_id uuid;
  v_procesadas integer := 0;
  v_sqlstate text;
  v_descartado boolean;
begin
  if p_ahora is null then
    raise exception using errcode = 'PT400',
      message = 'Debes indicar el instante de la comprobación.', detail = 'ahora_invalido';
  end if;

  -- Una espera de bloqueo larga se convierte en un fallo transitorio que se
  -- puede contar (ADR-0008, apartado 9).
  perform set_config('lock_timeout', '5s', true);

  -- Reparto
  for v_evento in
    select e.id, e.organizacion_id, e.tipo, e.ocurrido_en
    from public.eventos_automatizacion e
    where e.procesado_en is null
      and e.ocurrido_en <= p_ahora - v_margen
    order by e.ocurrido_en, e.id
    limit v_limite
    for update skip locked
  loop
    begin
      insert into public.ejecuciones_automatizacion (
        organizacion_id, regla_id, version_regla_id, evento_id, proximo_intento_en
      )
      select v_evento.organizacion_id, r.id, v.id, v_evento.id, p_ahora
      from public.reglas_automatizacion r
      join lateral (
        select vr.id, vr.activador
        from public.versiones_regla vr
        where vr.regla_id = r.id
          and vr.estado = 'publicada'
          and vr.publicada_en <= v_evento.ocurrido_en
        order by vr.numero desc
        limit 1
      ) v on true
      where r.organizacion_id = v_evento.organizacion_id
        and v.activador = v_evento.tipo
        and exists (
          select 1
          from public.periodos_activacion_regla p
          where p.regla_id = r.id
            and p.activada_en <= v_evento.ocurrido_en
            and (p.desactivada_en is null or v_evento.ocurrido_en < p.desactivada_en)
        )
      on conflict (regla_id, evento_id) do nothing;

      update public.eventos_automatizacion e
      set procesado_en = p_ahora
      where e.id = v_evento.id;
    exception
      when others then
        -- Se deshizo el reparto de este evento (ninguna de sus ejecuciones
        -- quedó creada a medias). Se cuenta el fallo; al tercero se descarta.
        v_sqlstate := sqlstate;
        v_descartado := false;
        begin
          update public.eventos_automatizacion e
          set intentos_reparto = e.intentos_reparto + 1,
              procesado_en = case when e.intentos_reparto + 1 >= v_max_intentos_reparto then p_ahora end,
              codigo_error = case
                when e.intentos_reparto + 1 >= v_max_intentos_reparto then 'reparto_fallido'
                else e.codigo_error
              end
          where e.id = v_evento.id
          returning e.procesado_en is not null into v_descartado;
        exception
          when others then
            raise warning 'Nexo: no se pudo registrar el fallo de reparto del evento % (SQLSTATE % y después %); sigue sin procesar.',
              v_evento.id, v_sqlstate, sqlstate;
        end;

        if v_descartado then
          begin
            insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
            values (
              v_evento.organizacion_id, null, 'evento.reparto_fallido', 'evento', v_evento.id,
              jsonb_build_object(
                'tipo', v_evento.tipo,
                'intentos', v_max_intentos_reparto,
                'codigo', 'reparto_fallido'
              )
            );
          exception
            when others then
              raise warning 'Nexo: el evento % se descartó (reparto_fallido), pero no se pudo auditar (SQLSTATE %).',
                v_evento.id, sqlstate;
          end;
        end if;
    end;
  end loop;

  -- Ejecución
  for v_ejecucion_id in
    select x.id
    from public.ejecuciones_automatizacion x
    where x.estado = 'pendiente'
      and x.proximo_intento_en <= p_ahora
    order by x.proximo_intento_en, x.id
    limit v_limite
    for update skip locked
  loop
    v_procesadas := v_procesadas + 1;
    begin
      perform privado.ejecutar_automatizacion(v_ejecucion_id, p_ahora);
    exception
      when others then
        -- Se deshizo el intento entero (estado, acciones, notificaciones y
        -- auditoría de esta ejecución); el resto de la pasada sigue.
        perform privado.registrar_fallo_ejecucion(v_ejecucion_id, p_ahora, sqlstate);
    end;
  end loop;

  return v_procesadas;
end;
$$;


-- -----------------------------------------------------------------------------
-- 6. Comprobación programada (Supabase Cron, ADR-0003)
-- El job solo llama a la función versionada. Es un job aparte: el del
-- detector no cambia. cron.schedule con nombre reemplaza el job si ya existe.
-- -----------------------------------------------------------------------------
select cron.schedule(
  'procesar_automatizaciones',
  '* * * * *',
  'select privado.procesar_automatizaciones(now())'
);


-- -----------------------------------------------------------------------------
-- 7. RLS y permisos
-- Ejecuciones y acciones: las ven todos los miembros (matriz: "Ver ejecuciones
-- y sus errores"). La cola de eventos no se expone. Nadie escribe
-- directamente: solo las funciones del sistema.
-- -----------------------------------------------------------------------------
alter table public.eventos_automatizacion enable row level security;
alter table public.ejecuciones_automatizacion enable row level security;
alter table public.acciones_automatizacion enable row level security;

create policy ejecuciones_automatizacion_select on public.ejecuciones_automatizacion
  for select to authenticated
  using (privado.es_miembro(organizacion_id));

create policy acciones_automatizacion_select on public.acciones_automatizacion
  for select to authenticated
  using (privado.es_miembro(organizacion_id));

revoke all on table
  public.eventos_automatizacion,
  public.ejecuciones_automatizacion,
  public.acciones_automatizacion
  from anon, authenticated;

grant select on table
  public.ejecuciones_automatizacion,
  public.acciones_automatizacion
  to authenticated;

-- PostgreSQL concede execute a PUBLIC en cada función nueva (ADR-0004).
-- privado.detectar_tareas_vencidas conserva los permisos de su migración: un
-- create or replace no los cambia.
revoke execute on function
  privado.validar_origen_notificacion(),
  privado.validar_evento_automatizacion(),
  privado.emitir_evento_estado_tarea(),
  privado.etiqueta_estado_tarea(text),
  privado.mensaje_resultado_automatizacion(text),
  privado.condiciones_cumplidas(jsonb, jsonb),
  privado.motivo_omision_automatizacion(
    public.ejecuciones_automatizacion, public.eventos_automatizacion, public.versiones_regla
  ),
  privado.ejecutar_accion_notificar(
    uuid, public.eventos_automatizacion, public.reglas_automatizacion, jsonb
  ),
  privado.ejecutar_automatizacion(uuid, timestamptz),
  privado.registrar_fallo_ejecucion(uuid, timestamptz, text),
  privado.procesar_automatizaciones(timestamptz)
  from public, anon, authenticated;
