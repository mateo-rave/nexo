-- =============================================================================
-- Migración: detección de tareas vencidas, hallazgos y notificaciones
-- (fase 2, bloque 3)
-- Decisión: ADR-0007 (vencimiento y deduplicación) · Reparto: ADR-0003
-- Permisos: docs/security/permissions.md · Nombres: ADR-0005
-- Multiempresa: ADR-0002 · Migraciones y bloqueos: ADR-0004
--
-- Contenido:
--   1. Tipos: tipo_hallazgo y prioridad_hallazgo.
--   2. Tablas hallazgos y notificaciones, con claves foráneas compuestas.
--   3. Detección: privado.detectar_tareas_vencidas(ahora), idempotente.
--   4. Comprobación programada con Supabase Cron (pg_cron).
--   5. RLS y permisos.
--   6. RPC resolver_hallazgo y marcar_notificacion_leida.
--
-- Una tarea está vencida según privado.tarea_vencida (ahora >= vence_en y
-- estado no terminal). La detección recibe "ahora" como parámetro para poder
-- probarla con tiempo controlado; el job programado le pasa now().
-- Deduplicación (ADR-0007): la clave usa la fecha límite tal como la eligió
-- el usuario (el día si no tiene hora; el instante si la tiene), nunca el
-- instante recalculado. Un cambio de zona horaria no duplica un hallazgo; un
-- cambio de fecha límite sí puede generar uno nuevo.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Tipos
-- -----------------------------------------------------------------------------
create type public.tipo_hallazgo as enum ('tarea_vencida');

create type public.prioridad_hallazgo as enum ('baja', 'media', 'alta');


-- -----------------------------------------------------------------------------
-- 2. Tablas
-- -----------------------------------------------------------------------------

-- Un bloqueo detectado, con su evidencia (RF-032). Solo lo crea el sistema.
-- Si la tarea se elimina, sus hallazgos también (la eliminación queda en
-- auditoría).
create table public.hallazgos (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  tarea_id uuid not null,
  tipo public.tipo_hallazgo not null,
  prioridad public.prioridad_hallazgo not null,
  clave_deduplicacion text not null,
  evidencia jsonb not null,
  detectado_en timestamptz not null,
  resuelto_en timestamptz,
  resuelto_por uuid references auth.users (id) on delete set null,
  creado_en timestamptz not null default now(),
  foreign key (organizacion_id, tarea_id)
    references public.tareas (organizacion_id, id) on delete cascade,
  constraint hallazgos_evidencia_valida check (jsonb_typeof(evidencia) = 'object'),
  constraint hallazgos_resolucion_coherente check (resuelto_por is null or resuelto_en is not null),
  unique (organizacion_id, clave_deduplicacion),
  unique (organizacion_id, id)
);

create index hallazgos_organizacion_detectado_en_indice
  on public.hallazgos (organizacion_id, detectado_en desc);

create index hallazgos_organizacion_tarea_indice
  on public.hallazgos (organizacion_id, tarea_id);

-- Notificación interna para un miembro. Una por hallazgo y destinatario. Si
-- el destinatario deja la organización, sus notificaciones se borran con su
-- membresía; si el hallazgo desaparece (tarea eliminada), también.
create table public.notificaciones (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  destinatario_id uuid not null,
  hallazgo_id uuid not null,
  titulo text not null,
  mensaje text not null,
  leida_en timestamptz,
  creado_en timestamptz not null default now(),
  foreign key (organizacion_id, destinatario_id)
    references public.membresias (organizacion_id, usuario_id) on delete cascade,
  foreign key (organizacion_id, hallazgo_id)
    references public.hallazgos (organizacion_id, id) on delete cascade,
  unique (hallazgo_id, destinatario_id)
);

create index notificaciones_destinatario_indice
  on public.notificaciones (destinatario_id, creado_en desc);

create trigger hallazgos_impedir_cambio_organizacion_id
  before update on public.hallazgos
  for each row execute function privado.impedir_cambio_organizacion_id();

create trigger notificaciones_impedir_cambio_organizacion_id
  before update on public.notificaciones
  for each row execute function privado.impedir_cambio_organizacion_id();


-- -----------------------------------------------------------------------------
-- 3. Detección
-- -----------------------------------------------------------------------------

-- Clave de deduplicación de un hallazgo de vencimiento (ADR-0007).
create function privado.clave_hallazgo_vencimiento(
  p_tarea_id uuid,
  p_fecha_limite date,
  p_vence_en timestamptz
)
returns text
language sql
stable
set search_path = ''
as $$
  select 'tarea_vencida:' || p_tarea_id::text || ':' ||
    case
      when p_fecha_limite is not null then 'dia:' || to_char(p_fecha_limite, 'YYYY-MM-DD')
      else 'instante:' || to_char(p_vence_en at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    end;
$$;

-- Crea los hallazgos de las tareas vencidas en "p_ahora", sus notificaciones
-- y su auditoría (acción del sistema), y devuelve cuántos hallazgos nuevos
-- creó. Ejecutarla varias veces no duplica nada: el hallazgo tiene una clave
-- única y las inserciones usan "on conflict do nothing".
-- Destinatarios: el responsable de la tarea; si no tiene, el propietario y
-- los administradores de la organización.
-- Se procesa organización a organización, bloqueando cada una con "for
-- share", igual que las RPC de tareas (ADR-0007): espera a que termine una
-- salida de miembro o un cambio de zona horaria en curso y después lee el
-- estado confirmado, así nunca notifica a quien ya salió. Las tareas de
-- proyectos archivados no se detectan.
-- No es una RPC: la ejecuta el job programado (sección 4) y nadie más puede
-- llamarla desde la API (sección 5).
create function privado.detectar_tareas_vencidas(p_ahora timestamptz)
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
      select t.id, t.organizacion_id, t.titulo, t.estado, t.responsable_id,
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
    )
    select count(*) into v_nuevos from nuevos;

    v_total := v_total + v_nuevos;
  end loop;

  return v_total;
end;
$$;


-- -----------------------------------------------------------------------------
-- 4. Comprobación programada (Supabase Cron, ADR-0003)
-- El job solo llama a la función versionada; no contiene lógica. Cada minuto:
-- con el índice de tareas abiertas con vencimiento, la consulta es barata, y
-- volver a ejecutarla no duplica nada. cron.schedule con nombre reemplaza el
-- job si ya existe, así la migración se puede repetir sin crear otro.
-- -----------------------------------------------------------------------------
create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule(
  'detectar_tareas_vencidas',
  '* * * * *',
  'select privado.detectar_tareas_vencidas(now())'
);


-- -----------------------------------------------------------------------------
-- 5. RLS y permisos
-- Hallazgos: los ven todos los miembros de la organización (matriz).
-- Notificaciones: cada persona ve solo las suyas (matriz: nadie ve las de
-- otras personas). Nadie escribe directamente.
-- -----------------------------------------------------------------------------
alter table public.hallazgos enable row level security;
alter table public.notificaciones enable row level security;

create policy hallazgos_select on public.hallazgos
  for select to authenticated
  using (privado.es_miembro(organizacion_id));

create policy notificaciones_select on public.notificaciones
  for select to authenticated
  using (destinatario_id = (select auth.uid()));

revoke all on table public.hallazgos, public.notificaciones from anon, authenticated;
grant select on table public.hallazgos, public.notificaciones to authenticated;


-- -----------------------------------------------------------------------------
-- 6. RPC
-- security definer (justificado): authenticated no tiene permisos de
-- escritura en hallazgos, notificaciones ni auditoria.
-- -----------------------------------------------------------------------------

-- 6.1 Marcar un hallazgo como resuelto. Matriz: propietario y administrador;
-- miembro solo si es responsable de la tarea afectada. Quien no es miembro
-- recibe el mismo error que si el hallazgo no existiera.
create function public.resolver_hallazgo(p_hallazgo_id uuid)
returns public.hallazgos
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_organizacion_id uuid;
  v_rol public.rol_membresia;
  v_responsable_id uuid;
  v_hallazgo public.hallazgos;
begin
  perform privado.exigir_read_committed();

  v_usuario_id := (select auth.uid());
  if v_usuario_id is null then
    raise exception using errcode = 'PT401',
      message = 'Debes iniciar sesión.', detail = 'sesion_requerida';
  end if;

  select h.organizacion_id into v_organizacion_id
  from public.hallazgos h
  where h.id = p_hallazgo_id;

  if v_organizacion_id is null or not privado.es_miembro(v_organizacion_id) then
    raise exception using errcode = 'PT404',
      message = 'El hallazgo no existe o no tienes acceso a él.', detail = 'hallazgo_no_encontrado';
  end if;

  perform 1 from public.organizaciones o where o.id = v_organizacion_id for share;

  select m.rol into v_rol
  from public.membresias m
  where m.organizacion_id = v_organizacion_id
    and m.usuario_id = v_usuario_id;

  if v_rol is null then
    raise exception using errcode = 'PT404',
      message = 'El hallazgo no existe o no tienes acceso a él.', detail = 'hallazgo_no_encontrado';
  end if;

  select * into v_hallazgo
  from public.hallazgos h
  where h.id = p_hallazgo_id
  for update;

  if not found then
    raise exception using errcode = 'PT404',
      message = 'El hallazgo no existe o no tienes acceso a él.', detail = 'hallazgo_no_encontrado';
  end if;

  select t.responsable_id into v_responsable_id
  from public.tareas t
  where t.organizacion_id = v_hallazgo.organizacion_id
    and t.id = v_hallazgo.tarea_id;

  if not coalesce(
    v_rol in ('propietario', 'administrador') or v_responsable_id = v_usuario_id,
    false
  ) then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  if v_hallazgo.resuelto_en is not null then
    raise exception using errcode = 'PT409',
      message = 'El hallazgo ya está resuelto.', detail = 'hallazgo_ya_resuelto';
  end if;

  update public.hallazgos h
  set resuelto_en = now(), resuelto_por = v_usuario_id
  where h.id = p_hallazgo_id
  returning * into v_hallazgo;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    v_hallazgo.organizacion_id, v_usuario_id, 'hallazgo.resuelto', 'hallazgo', p_hallazgo_id,
    jsonb_build_object('tipo', v_hallazgo.tipo, 'tarea_id', v_hallazgo.tarea_id)
  );

  return v_hallazgo;
end;
$$;

-- 6.2 Marcar una notificación propia como leída. Idempotente: si ya estaba
-- leída, la devuelve sin cambios. Una notificación ajena recibe el mismo
-- error que una inexistente. No se audita (no figura en la lista de
-- operaciones auditadas de permissions.md).
create function public.marcar_notificacion_leida(p_notificacion_id uuid)
returns public.notificaciones
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid := (select auth.uid());
  v_notificacion public.notificaciones;
begin
  if v_usuario_id is null then
    raise exception using errcode = 'PT401',
      message = 'Debes iniciar sesión.', detail = 'sesion_requerida';
  end if;

  update public.notificaciones n
  set leida_en = coalesce(n.leida_en, now())
  where n.id = p_notificacion_id
    and n.destinatario_id = v_usuario_id
  returning * into v_notificacion;

  if not found then
    raise exception using errcode = 'PT404',
      message = 'La notificación no existe o no tienes acceso a ella.',
      detail = 'notificacion_no_encontrada';
  end if;

  return v_notificacion;
end;
$$;


-- -----------------------------------------------------------------------------
-- 7. Permisos de ejecución
-- PostgreSQL concede execute a PUBLIC en cada función nueva (ADR-0004).
-- -----------------------------------------------------------------------------
revoke execute on function
  privado.clave_hallazgo_vencimiento(uuid, date, timestamptz),
  privado.detectar_tareas_vencidas(timestamptz)
  from public, anon, authenticated;

revoke execute on function
  public.resolver_hallazgo(uuid),
  public.marcar_notificacion_leida(uuid)
  from public, anon;

grant execute on function
  public.resolver_hallazgo(uuid),
  public.marcar_notificacion_leida(uuid)
  to authenticated;
