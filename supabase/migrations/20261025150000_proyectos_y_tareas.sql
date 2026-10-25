-- =============================================================================
-- Migración: proyectos y tareas (fase 2, bloque 2)
-- Decisión: ADR-0007 · Permisos: docs/security/permissions.md
-- Nombres: ADR-0005 · Multiempresa: ADR-0002 · Reparto de capas: ADR-0003
-- Migraciones y bloqueos: ADR-0004
--
-- Contenido:
--   1. Tablas proyectos y tareas, con claves foráneas compuestas.
--   2. Funciones internas: vencimiento de una fecha sin hora y tarea vencida.
--   3. Triggers: actualizado_en, organizacion_id inmutable, versión publicada
--      del proyecto, estado inicial, transiciones y cálculo de vence_en.
--   4. Salida de un miembro: sus tareas quedan sin responsable y cada una se
--      audita como acción del sistema.
--   5. RLS (lectura para miembros) y permisos.
--   6. RPC de proyectos: crear_proyecto y archivar_proyecto.
--   7. RPC de tareas: crear_tarea, editar_tarea, asignar_responsable,
--      cambiar_estado_tarea y eliminar_tarea.
--   8. RPC cambiar_zona_horaria.
--
-- Orden de bloqueos (amplía ADR-0004): organización → membresía → tareas.
--   - Las RPC de tareas bloquean primero la organización con "for share" y
--     después la tarea con "for update". No bloquean membresías.
--   - quitar_miembro y salir_de_organizacion ya bloquean la organización con
--     "for no key update", y el trigger de la sección 4 hace lo mismo antes de
--     tocar las tareas (cubre también el borrado de una cuenta desde Auth).
--   - cambiar_zona_horaria bloquea la organización con "for no key update".
--   Como "for share" y "for no key update" chocan entre sí, las operaciones
--   sobre tareas y las que cambian miembros o la zona horaria de una misma
--   organización se ordenan, y nadie espera a otro sosteniendo una fila que
--   el otro necesite: no hay ciclos de bloqueo.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Tablas
-- -----------------------------------------------------------------------------

-- Un proyecto sigue una versión publicada de un flujo de su organización y la
-- conserva siempre (ADR-0007). archivado_en vacío = activo.
create table public.proyectos (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references public.organizaciones (id) on delete cascade,
  version_flujo_id uuid not null,
  nombre text not null,
  descripcion text,
  archivado_en timestamptz,
  creado_por uuid references auth.users (id) on delete set null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  foreign key (organizacion_id, version_flujo_id)
    references public.versiones_flujo (organizacion_id, id),
  constraint proyectos_nombre_valido
    check (nombre = btrim(nombre) and char_length(nombre) between 1 and 100),
  constraint proyectos_descripcion_valida
    check (descripcion is null or char_length(descripcion) between 1 and 2000),
  unique (organizacion_id, id)
);

create index proyectos_organizacion_indice on public.proyectos (organizacion_id);

-- Fecha límite (ADR-0007):
--   - fecha_limite: el día elegido, solo si se eligió sin hora.
--   - vence_en: instante exclusivo a partir del cual la tarea está vencida.
--     Con fecha sin hora lo calcula el trigger (00:00 del día siguiente en la
--     zona de la organización); con hora explícita es la fuente de verdad.
-- El responsable debe ser miembro de la misma organización: clave foránea
-- compuesta hacia membresias, sin acción de borrado. La salida de un miembro
-- vacía antes sus asignaciones (sección 4).
create table public.tareas (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  proyecto_id uuid not null,
  titulo text not null,
  descripcion text,
  estado public.estado_tarea not null,
  responsable_id uuid,
  fecha_limite date,
  vence_en timestamptz,
  creado_por uuid references auth.users (id) on delete set null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  foreign key (organizacion_id, proyecto_id)
    references public.proyectos (organizacion_id, id),
  foreign key (organizacion_id, responsable_id)
    references public.membresias (organizacion_id, usuario_id),
  constraint tareas_titulo_valido
    check (titulo = btrim(titulo) and char_length(titulo) between 1 and 200),
  constraint tareas_descripcion_valida
    check (descripcion is null or char_length(descripcion) between 1 and 5000),
  constraint tareas_fecha_limite_con_vencimiento
    check (fecha_limite is null or vence_en is not null),
  unique (organizacion_id, id)
);

create index tareas_organizacion_proyecto_indice on public.tareas (organizacion_id, proyecto_id);

-- La salida de un miembro busca sus tareas por (organizacion_id, responsable_id).
create index tareas_organizacion_responsable_indice
  on public.tareas (organizacion_id, responsable_id)
  where responsable_id is not null;

-- Para la detección de vencidas: solo tareas abiertas con vencimiento.
create index tareas_vencimiento_abiertas_indice
  on public.tareas (vence_en)
  where vence_en is not null and estado not in ('completada', 'cancelada');


-- -----------------------------------------------------------------------------
-- 2. Funciones internas
-- -----------------------------------------------------------------------------

-- Vencimiento de una fecha elegida sin hora: las 00:00 del día siguiente en la
-- zona indicada (límite exclusivo). Los cambios de horario los resuelve
-- "at time zone".
create function privado.vence_en_de_fecha(p_fecha date, p_zona_horaria text)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select ((p_fecha + 1)::timestamp at time zone p_zona_horaria);
$$;

-- Regla de vencimiento (ADR-0007): vencida si ahora >= vence_en y el estado no
-- es terminal. El instante "ahora" llega como parámetro para poder probarla
-- con tiempo controlado; la detección programada le pasará la hora real.
create function privado.tarea_vencida(
  p_vence_en timestamptz,
  p_estado public.estado_tarea,
  p_ahora timestamptz
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_vence_en is not null
    and p_ahora >= p_vence_en
    and not privado.es_estado_terminal(p_estado);
$$;


-- -----------------------------------------------------------------------------
-- 3. Triggers
-- -----------------------------------------------------------------------------

create trigger proyectos_asignar_actualizado_en
  before update on public.proyectos
  for each row execute function privado.asignar_actualizado_en();

create trigger tareas_asignar_actualizado_en
  before update on public.tareas
  for each row execute function privado.asignar_actualizado_en();

create trigger proyectos_impedir_cambio_organizacion_id
  before update on public.proyectos
  for each row execute function privado.impedir_cambio_organizacion_id();

create trigger tareas_impedir_cambio_organizacion_id
  before update on public.tareas
  for each row execute function privado.impedir_cambio_organizacion_id();

-- 3.1 Un proyecto nace sobre una versión publicada de su organización y no
-- cambia de versión (ADR-0007, el cambio de versión no entra en el MVP).
create function privado.proteger_proyecto()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if not exists (
      select 1
      from public.versiones_flujo v
      where v.organizacion_id = new.organizacion_id
        and v.id = new.version_flujo_id
        and v.estado = 'publicada'
    ) then
      raise exception using
        errcode = 'PT400',
        message = 'La versión del flujo no está publicada en esta organización.',
        detail = 'version_flujo_no_disponible';
    end if;
  elsif new.version_flujo_id is distinct from old.version_flujo_id then
    raise exception using
      errcode = 'PT400',
      message = 'Un proyecto no puede cambiar de versión de flujo.',
      detail = 'version_proyecto_inmutable';
  end if;
  return new;
end;
$$;

create trigger proyectos_proteger
  before insert or update on public.proyectos
  for each row execute function privado.proteger_proyecto();

-- 3.2 Reglas de una tarea, en un solo trigger para que se apliquen en orden:
--   - una tarea no cambia de proyecto;
--   - al crearse, su estado es el inicial de la versión del proyecto, envíe
--     lo que envíe quien la crea;
--   - un cambio de estado debe ser una transición permitida (misma función
--     que usan las RPC: privado.transicion_permitida);
--   - vence_en se calcula con la zona actual de la organización si la fecha
--     no tiene hora y la tarea está abierta (o se crea, o cambia su fecha).
--     Así se cumple la invariante de ADR-0007, también al reabrir; las
--     tareas cerradas conservan su valor histórico.
-- Protege también frente a la clave secreta (service_role), que se salta RLS
-- pero no los triggers.
create function privado.preparar_tarea()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_version_flujo_id uuid;
  v_zona_horaria text;
begin
  if tg_op = 'UPDATE' and new.proyecto_id is distinct from old.proyecto_id then
    raise exception using
      errcode = 'PT400',
      message = 'Una tarea no puede cambiar de proyecto.',
      detail = 'proyecto_inmutable';
  end if;

  select p.version_flujo_id, o.zona_horaria
  into v_version_flujo_id, v_zona_horaria
  from public.proyectos p
  join public.organizaciones o on o.id = p.organizacion_id
  where p.organizacion_id = new.organizacion_id
    and p.id = new.proyecto_id;

  if v_version_flujo_id is null then
    raise exception using
      errcode = 'PT404',
      message = 'El proyecto no existe o no tienes acceso a él.',
      detail = 'proyecto_no_encontrado';
  end if;

  if tg_op = 'INSERT' then
    select v.estado_inicial into new.estado
    from public.versiones_flujo v
    where v.id = v_version_flujo_id;
  elsif new.estado is distinct from old.estado
        and not privado.transicion_permitida(v_version_flujo_id, old.estado, new.estado) then
    raise exception using
      errcode = 'PT409',
      message = 'El flujo del proyecto no permite ese cambio de estado.',
      detail = 'transicion_no_permitida';
  end if;

  if new.fecha_limite is not null
     and (tg_op = 'INSERT'
          or new.fecha_limite is distinct from old.fecha_limite
          or not privado.es_estado_terminal(new.estado)) then
    new.vence_en := privado.vence_en_de_fecha(new.fecha_limite, v_zona_horaria);
  end if;

  return new;
end;
$$;

create trigger tareas_preparar
  before insert or update on public.tareas
  for each row execute function privado.preparar_tarea();


-- -----------------------------------------------------------------------------
-- 4. Salida de un miembro (ADR-0007)
-- Antes de borrar una membresía (quitar_miembro, salir_de_organizacion o
-- borrado de la cuenta en Auth), sus tareas en esa organización quedan sin
-- responsable y cada una se audita como acción del sistema (actor vacío).
-- Funciona en cualquier versión de PostgreSQL: la clave foránea de
-- responsable no tiene acción de borrado y, como este trigger vacía antes las
-- asignaciones, la comprobación de la clave foránea al final de la
-- instrucción no encuentra filas que la bloqueen.
-- Bloqueos: se bloquea la organización ("for no key update", como
-- exigir_propietario) antes de tocar las tareas. Dentro de las RPC de la
-- migración 2 ya está bloqueada; en el borrado de una cuenta, esto impide que
-- una RPC de tareas asigne a la persona mientras sale y fija el orden
-- organización → tareas. Si el borrado se rechaza después (por ejemplo, el
-- último propietario), todo se deshace, incluida la auditoría.
-- security definer (justificado): quien sale no tiene permiso de escritura en
-- tareas ni en auditoria.
-- -----------------------------------------------------------------------------
create function privado.retirar_responsable_de_tareas()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform 1
  from public.organizaciones o
  where o.id = old.organizacion_id
  for no key update;

  -- La organización se está borrando (cascada): sus tareas también.
  if not found then
    return old;
  end if;

  with retiradas as (
    update public.tareas t
    set responsable_id = null
    where t.organizacion_id = old.organizacion_id
      and t.responsable_id = old.usuario_id
    returning t.id
  )
  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  select
    old.organizacion_id,
    null,
    'tarea.responsable_retirado',
    'tarea',
    r.id,
    jsonb_build_object('responsable_anterior', old.usuario_id, 'motivo', 'membresia_eliminada')
  from retiradas r;

  return old;
end;
$$;

create trigger membresias_retirar_responsable
  before delete on public.membresias
  for each row execute function privado.retirar_responsable_de_tareas();


-- -----------------------------------------------------------------------------
-- 5. RLS y permisos
-- Todos los roles ven los proyectos y tareas de su organización (matriz).
-- Nadie escribe directamente: todas las escrituras van por RPC (ADR-0007).
-- -----------------------------------------------------------------------------
alter table public.proyectos enable row level security;
alter table public.tareas enable row level security;

create policy proyectos_select on public.proyectos
  for select to authenticated
  using (privado.es_miembro(organizacion_id));

create policy tareas_select on public.tareas
  for select to authenticated
  using (privado.es_miembro(organizacion_id));

revoke all on table public.proyectos, public.tareas from anon, authenticated;
grant select on table public.proyectos, public.tareas to authenticated;


-- -----------------------------------------------------------------------------
-- 6. RPC de proyectos
-- Mismo patrón que la migración 2: read committed, sesión, comprobación
-- preliminar sin bloquear, bloqueo de la organización, segunda comprobación
-- con el rol actual, validación, escritura y auditoría en una transacción.
-- security definer (justificado): authenticated no tiene permisos de
-- escritura en proyectos, tareas ni auditoria.
-- -----------------------------------------------------------------------------

-- 6.1 Crea un proyecto sobre la versión indicada o, si no se indica, sobre la
-- última versión publicada del flujo predeterminado de la organización.
create function public.crear_proyecto(
  p_organizacion_id uuid,
  p_nombre text,
  p_descripcion text default null,
  p_version_flujo_id uuid default null
)
returns public.proyectos
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_nombre text := btrim(p_nombre);
  v_descripcion text := nullif(btrim(p_descripcion), '');
  v_version_flujo_id uuid := p_version_flujo_id;
  v_proyecto public.proyectos;
begin
  perform privado.exigir_read_committed();

  v_usuario_id := (select auth.uid());
  if v_usuario_id is null then
    raise exception using errcode = 'PT401',
      message = 'Debes iniciar sesión.', detail = 'sesion_requerida';
  end if;

  if not privado.tiene_rol(p_organizacion_id, array['propietario', 'administrador']::public.rol_membresia[]) then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  perform 1 from public.organizaciones o where o.id = p_organizacion_id for share;
  if not found
     or not privado.tiene_rol(p_organizacion_id, array['propietario', 'administrador']::public.rol_membresia[]) then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  if v_nombre is null or char_length(v_nombre) not between 1 and 100 then
    raise exception using errcode = 'PT400',
      message = 'El nombre debe tener entre 1 y 100 caracteres.', detail = 'nombre_invalido';
  end if;
  if v_descripcion is not null and char_length(v_descripcion) > 2000 then
    raise exception using errcode = 'PT400',
      message = 'La descripción es demasiado larga.', detail = 'descripcion_invalida';
  end if;

  if v_version_flujo_id is null then
    select v.id into v_version_flujo_id
    from public.versiones_flujo v
    join public.definiciones_flujo d
      on d.organizacion_id = v.organizacion_id and d.id = v.definicion_flujo_id
    where d.organizacion_id = p_organizacion_id
      and d.es_predeterminado
      and v.estado = 'publicada'
    order by v.numero desc
    limit 1;
  end if;

  if v_version_flujo_id is null or not exists (
    select 1
    from public.versiones_flujo v
    where v.organizacion_id = p_organizacion_id
      and v.id = v_version_flujo_id
      and v.estado = 'publicada'
  ) then
    raise exception using errcode = 'PT400',
      message = 'La versión del flujo no está publicada en esta organización.',
      detail = 'version_flujo_no_disponible';
  end if;

  insert into public.proyectos (organizacion_id, version_flujo_id, nombre, descripcion, creado_por)
  values (p_organizacion_id, v_version_flujo_id, v_nombre, v_descripcion, v_usuario_id)
  returning * into v_proyecto;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    p_organizacion_id, v_usuario_id, 'proyecto.creado', 'proyecto', v_proyecto.id,
    jsonb_build_object('nombre', v_nombre, 'version_flujo_id', v_version_flujo_id)
  );

  return v_proyecto;
end;
$$;

-- 6.2 Archiva o desarchiva un proyecto. Las tareas de un proyecto archivado no
-- se pueden crear ni modificar.
create function public.archivar_proyecto(p_proyecto_id uuid, p_archivado boolean)
returns public.proyectos
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_organizacion_id uuid;
  v_proyecto public.proyectos;
begin
  perform privado.exigir_read_committed();

  v_usuario_id := (select auth.uid());
  if v_usuario_id is null then
    raise exception using errcode = 'PT401',
      message = 'Debes iniciar sesión.', detail = 'sesion_requerida';
  end if;

  if p_archivado is null then
    raise exception using errcode = 'PT400',
      message = 'Debes indicar si el proyecto queda archivado.', detail = 'archivado_invalido';
  end if;

  select p.organizacion_id into v_organizacion_id
  from public.proyectos p
  where p.id = p_proyecto_id;

  if v_organizacion_id is null or not privado.es_miembro(v_organizacion_id) then
    raise exception using errcode = 'PT404',
      message = 'El proyecto no existe o no tienes acceso a él.', detail = 'proyecto_no_encontrado';
  end if;
  if not privado.tiene_rol(v_organizacion_id, array['propietario', 'administrador']::public.rol_membresia[]) then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  perform 1 from public.organizaciones o where o.id = v_organizacion_id for share;
  if not privado.tiene_rol(v_organizacion_id, array['propietario', 'administrador']::public.rol_membresia[]) then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  select * into v_proyecto
  from public.proyectos p
  where p.id = p_proyecto_id
  for update;

  if (v_proyecto.archivado_en is not null) = p_archivado then
    raise exception using errcode = 'PT409',
      message = 'El proyecto ya está en ese estado.', detail = 'proyecto_sin_cambios';
  end if;

  update public.proyectos p
  set archivado_en = case when p_archivado then now() end
  where p.id = p_proyecto_id
  returning * into v_proyecto;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    v_organizacion_id, v_usuario_id,
    case when p_archivado then 'proyecto.archivado' else 'proyecto.desarchivado' end,
    'proyecto', p_proyecto_id, jsonb_build_object('nombre', v_proyecto.nombre)
  );

  return v_proyecto;
end;
$$;


-- -----------------------------------------------------------------------------
-- 7. RPC de tareas
-- -----------------------------------------------------------------------------

-- 7.1 Pasos comunes de las RPC que modifican una tarea existente: sesión,
-- membresía, bloqueo de la organización y segunda comprobación. Devuelve el
-- rol actual de quien llama. Quien no es miembro de la organización de la
-- tarea recibe el mismo error que si la tarea no existiera.
create function privado.autorizar_escritura_tarea(p_tarea_id uuid)
returns public.rol_membresia
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_usuario_id uuid := (select auth.uid());
  v_organizacion_id uuid;
  v_rol public.rol_membresia;
begin
  perform privado.exigir_read_committed();

  if v_usuario_id is null then
    raise exception using errcode = 'PT401',
      message = 'Debes iniciar sesión.', detail = 'sesion_requerida';
  end if;

  select t.organizacion_id into v_organizacion_id
  from public.tareas t
  where t.id = p_tarea_id;

  select m.rol into v_rol
  from public.membresias m
  where m.organizacion_id = v_organizacion_id
    and m.usuario_id = v_usuario_id;

  if v_rol is null then
    raise exception using errcode = 'PT404',
      message = 'La tarea no existe o no tienes acceso a ella.', detail = 'tarea_no_encontrada';
  end if;

  perform 1 from public.organizaciones o where o.id = v_organizacion_id for share;

  v_rol := null;
  select m.rol into v_rol
  from public.membresias m
  where m.organizacion_id = v_organizacion_id
    and m.usuario_id = v_usuario_id;

  if v_rol is null then
    raise exception using errcode = 'PT404',
      message = 'La tarea no existe o no tienes acceso a ella.', detail = 'tarea_no_encontrada';
  end if;

  return v_rol;
end;
$$;

-- 7.2 Bloquea la tarea (después de la organización) y comprueba que su
-- proyecto no esté archivado.
create function privado.bloquear_tarea(p_tarea_id uuid)
returns public.tareas
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_tarea public.tareas;
begin
  select * into v_tarea
  from public.tareas t
  where t.id = p_tarea_id
  for update;

  if not found then
    raise exception using errcode = 'PT404',
      message = 'La tarea no existe o no tienes acceso a ella.', detail = 'tarea_no_encontrada';
  end if;

  if exists (
    select 1
    from public.proyectos p
    where p.organizacion_id = v_tarea.organizacion_id
      and p.id = v_tarea.proyecto_id
      and p.archivado_en is not null
  ) then
    raise exception using errcode = 'PT409',
      message = 'El proyecto está archivado.', detail = 'proyecto_archivado';
  end if;

  return v_tarea;
end;
$$;

-- 7.3 Matriz: miembro edita y cambia el estado solo si es responsable o
-- creador de la tarea; propietario y administrador, siempre.
-- coalesce: sin creador ni responsable, la comparación daría null, y un
-- "if not null" en PL/pgSQL no rechazaría la operación.
create function privado.puede_gestionar_tarea(p_rol public.rol_membresia, p_tarea public.tareas)
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(
    p_rol in ('propietario', 'administrador')
      or (select auth.uid()) = p_tarea.creado_por
      or (select auth.uid()) = p_tarea.responsable_id,
    false
  );
$$;

-- 7.4 Validación y cálculo de la fecha límite elegida (ADR-0007). Con hora,
-- se convierte con la zona de la organización y se guarda solo el instante;
-- sin hora, se guarda el día y el trigger calcula vence_en.
create function privado.validar_responsable(p_organizacion_id uuid, p_responsable_id uuid)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_responsable_id is not null and not exists (
    select 1
    from public.membresias m
    where m.organizacion_id = p_organizacion_id
      and m.usuario_id = p_responsable_id
  ) then
    raise exception using errcode = 'PT400',
      message = 'El responsable debe ser miembro de la organización.',
      detail = 'responsable_no_es_miembro';
  end if;
end;
$$;

create function privado.validar_texto_tarea(p_titulo text, p_descripcion text)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_titulo is null or char_length(p_titulo) not between 1 and 200 then
    raise exception using errcode = 'PT400',
      message = 'El título debe tener entre 1 y 200 caracteres.', detail = 'titulo_invalido';
  end if;
  if p_descripcion is not null and char_length(p_descripcion) > 5000 then
    raise exception using errcode = 'PT400',
      message = 'La descripción es demasiado larga.', detail = 'descripcion_invalida';
  end if;
end;
$$;

create function privado.vence_en_con_hora(
  p_organizacion_id uuid,
  p_fecha_limite date,
  p_hora_limite time
)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_hora_limite is null then
    return null;
  end if;
  if p_fecha_limite is null then
    raise exception using errcode = 'PT400',
      message = 'Para indicar una hora, indica también el día.', detail = 'hora_sin_fecha';
  end if;
  return (
    select (p_fecha_limite + p_hora_limite) at time zone o.zona_horaria
    from public.organizaciones o
    where o.id = p_organizacion_id
  );
end;
$$;

-- 7.5 Crear una tarea: cualquier miembro (matriz), en un proyecto activo.
create function public.crear_tarea(
  p_proyecto_id uuid,
  p_titulo text,
  p_descripcion text default null,
  p_responsable_id uuid default null,
  p_fecha_limite date default null,
  p_hora_limite time default null
)
returns public.tareas
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_organizacion_id uuid;
  v_archivado_en timestamptz;
  v_titulo text := btrim(p_titulo);
  v_descripcion text := nullif(btrim(p_descripcion), '');
  v_vence_en timestamptz;
  v_tarea public.tareas;
begin
  perform privado.exigir_read_committed();

  v_usuario_id := (select auth.uid());
  if v_usuario_id is null then
    raise exception using errcode = 'PT401',
      message = 'Debes iniciar sesión.', detail = 'sesion_requerida';
  end if;

  select p.organizacion_id into v_organizacion_id
  from public.proyectos p
  where p.id = p_proyecto_id;

  if v_organizacion_id is null or not privado.es_miembro(v_organizacion_id) then
    raise exception using errcode = 'PT404',
      message = 'El proyecto no existe o no tienes acceso a él.', detail = 'proyecto_no_encontrado';
  end if;

  perform 1 from public.organizaciones o where o.id = v_organizacion_id for share;
  if not privado.es_miembro(v_organizacion_id) then
    raise exception using errcode = 'PT404',
      message = 'El proyecto no existe o no tienes acceso a él.', detail = 'proyecto_no_encontrado';
  end if;

  -- for share: espera a un archivado en curso del mismo proyecto.
  select p.archivado_en into v_archivado_en
  from public.proyectos p
  where p.id = p_proyecto_id
  for share;

  if v_archivado_en is not null then
    raise exception using errcode = 'PT409',
      message = 'El proyecto está archivado.', detail = 'proyecto_archivado';
  end if;

  perform privado.validar_texto_tarea(v_titulo, v_descripcion);
  perform privado.validar_responsable(v_organizacion_id, p_responsable_id);
  v_vence_en := privado.vence_en_con_hora(v_organizacion_id, p_fecha_limite, p_hora_limite);

  insert into public.tareas (
    organizacion_id, proyecto_id, titulo, descripcion, responsable_id,
    fecha_limite, vence_en, creado_por
  )
  values (
    v_organizacion_id, p_proyecto_id, v_titulo, v_descripcion, p_responsable_id,
    case when p_hora_limite is null then p_fecha_limite end, v_vence_en, v_usuario_id
  )
  returning * into v_tarea;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    v_organizacion_id, v_usuario_id, 'tarea.creada', 'tarea', v_tarea.id,
    jsonb_build_object(
      'titulo', v_tarea.titulo,
      'proyecto_id', v_tarea.proyecto_id,
      'estado', v_tarea.estado,
      'responsable_id', v_tarea.responsable_id,
      'fecha_limite', v_tarea.fecha_limite,
      'vence_en', v_tarea.vence_en
    )
  );

  return v_tarea;
end;
$$;

-- 7.6 Editar título, descripción y fecha límite. Reemplaza los tres valores:
-- quien llama envía siempre todos (null = vacío). Matriz: miembro solo si es
-- responsable o creador.
create function public.editar_tarea(
  p_tarea_id uuid,
  p_titulo text,
  p_descripcion text,
  p_fecha_limite date,
  p_hora_limite time
)
returns public.tareas
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid := (select auth.uid());
  v_rol public.rol_membresia;
  v_tarea public.tareas;
  v_nueva public.tareas;
  v_titulo text := btrim(p_titulo);
  v_descripcion text := nullif(btrim(p_descripcion), '');
  v_fecha_limite date;
  v_vence_en timestamptz;
begin
  v_rol := privado.autorizar_escritura_tarea(p_tarea_id);
  v_tarea := privado.bloquear_tarea(p_tarea_id);

  if not privado.puede_gestionar_tarea(v_rol, v_tarea) then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  perform privado.validar_texto_tarea(v_titulo, v_descripcion);
  v_vence_en := privado.vence_en_con_hora(v_tarea.organizacion_id, p_fecha_limite, p_hora_limite);
  v_fecha_limite := case when p_hora_limite is null then p_fecha_limite end;

  if v_titulo = v_tarea.titulo
     and v_descripcion is not distinct from v_tarea.descripcion
     and v_fecha_limite is not distinct from v_tarea.fecha_limite
     and (v_fecha_limite is not null or v_vence_en is not distinct from v_tarea.vence_en) then
    raise exception using errcode = 'PT409',
      message = 'La tarea ya tiene esos datos.', detail = 'tarea_sin_cambios';
  end if;

  update public.tareas t
  set titulo = v_titulo,
      descripcion = v_descripcion,
      fecha_limite = v_fecha_limite,
      vence_en = v_vence_en
  where t.id = p_tarea_id
  returning * into v_nueva;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    v_tarea.organizacion_id, v_usuario_id, 'tarea.editada', 'tarea', p_tarea_id,
    jsonb_build_object(
      'antes', jsonb_build_object(
        'titulo', v_tarea.titulo, 'descripcion', v_tarea.descripcion,
        'fecha_limite', v_tarea.fecha_limite, 'vence_en', v_tarea.vence_en),
      'despues', jsonb_build_object(
        'titulo', v_nueva.titulo, 'descripcion', v_nueva.descripcion,
        'fecha_limite', v_nueva.fecha_limite, 'vence_en', v_nueva.vence_en)
    )
  );

  return v_nueva;
end;
$$;

-- 7.7 Asignar o quitar el responsable: cualquier miembro (matriz), solo a
-- miembros de la misma organización.
create function public.asignar_responsable(p_tarea_id uuid, p_responsable_id uuid)
returns public.tareas
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid := (select auth.uid());
  v_tarea public.tareas;
  v_nueva public.tareas;
begin
  perform privado.autorizar_escritura_tarea(p_tarea_id);
  v_tarea := privado.bloquear_tarea(p_tarea_id);

  if p_responsable_id is not distinct from v_tarea.responsable_id then
    raise exception using errcode = 'PT409',
      message = 'La tarea ya tiene ese responsable.', detail = 'responsable_sin_cambios';
  end if;

  perform privado.validar_responsable(v_tarea.organizacion_id, p_responsable_id);

  update public.tareas t
  set responsable_id = p_responsable_id
  where t.id = p_tarea_id
  returning * into v_nueva;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    v_tarea.organizacion_id, v_usuario_id, 'tarea.reasignada', 'tarea', p_tarea_id,
    jsonb_build_object('responsable_anterior', v_tarea.responsable_id, 'responsable_nuevo', p_responsable_id)
  );

  return v_nueva;
end;
$$;

-- 7.8 Cambiar el estado: transición permitida por el flujo del proyecto y
-- permiso de la matriz, sin excepciones por transición (ADR-0007). El
-- trigger preparar_tarea vuelve a validar la transición.
create function public.cambiar_estado_tarea(p_tarea_id uuid, p_estado public.estado_tarea)
returns public.tareas
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid := (select auth.uid());
  v_rol public.rol_membresia;
  v_tarea public.tareas;
  v_nueva public.tareas;
  v_version_flujo_id uuid;
begin
  v_rol := privado.autorizar_escritura_tarea(p_tarea_id);
  v_tarea := privado.bloquear_tarea(p_tarea_id);

  if not privado.puede_gestionar_tarea(v_rol, v_tarea) then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  if p_estado is null then
    raise exception using errcode = 'PT400',
      message = 'Debes indicar un estado válido.', detail = 'estado_invalido';
  end if;
  if p_estado = v_tarea.estado then
    raise exception using errcode = 'PT409',
      message = 'La tarea ya está en ese estado.', detail = 'estado_sin_cambios';
  end if;

  select p.version_flujo_id into v_version_flujo_id
  from public.proyectos p
  where p.organizacion_id = v_tarea.organizacion_id
    and p.id = v_tarea.proyecto_id;

  if not privado.transicion_permitida(v_version_flujo_id, v_tarea.estado, p_estado) then
    raise exception using errcode = 'PT409',
      message = 'El flujo del proyecto no permite ese cambio de estado.',
      detail = 'transicion_no_permitida';
  end if;

  update public.tareas t
  set estado = p_estado
  where t.id = p_tarea_id
  returning * into v_nueva;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    v_tarea.organizacion_id, v_usuario_id, 'tarea.estado_cambiado', 'tarea', p_tarea_id,
    jsonb_build_object('estado_anterior', v_tarea.estado, 'estado_nuevo', p_estado)
  );

  return v_nueva;
end;
$$;

-- 7.9 Eliminar una tarea: solo propietario y administrador (matriz).
create function public.eliminar_tarea(p_tarea_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid := (select auth.uid());
  v_rol public.rol_membresia;
  v_tarea public.tareas;
begin
  v_rol := privado.autorizar_escritura_tarea(p_tarea_id);
  v_tarea := privado.bloquear_tarea(p_tarea_id);

  if v_rol not in ('propietario', 'administrador') then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  delete from public.tareas t where t.id = p_tarea_id;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    v_tarea.organizacion_id, v_usuario_id, 'tarea.eliminada', 'tarea', p_tarea_id,
    jsonb_build_object('titulo', v_tarea.titulo, 'proyecto_id', v_tarea.proyecto_id, 'estado', v_tarea.estado)
  );
end;
$$;


-- -----------------------------------------------------------------------------
-- 8. RPC cambiar_zona_horaria (ADR-0007)
-- propietario y administrador ("Editar nombre y datos de la organización").
-- En una transacción: cambia la zona (validada por su trigger), recalcula
-- vence_en de las tareas abiertas con fecha sin hora y conserva las tareas
-- con hora explícita y las cerradas.
-- -----------------------------------------------------------------------------
create function public.cambiar_zona_horaria(p_organizacion_id uuid, p_zona_horaria text)
returns public.organizaciones
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_zona_horaria text := btrim(p_zona_horaria);
  v_anterior text;
  v_recalculadas integer;
  v_organizacion public.organizaciones;
begin
  perform privado.exigir_read_committed();

  v_usuario_id := (select auth.uid());
  if v_usuario_id is null then
    raise exception using errcode = 'PT401',
      message = 'Debes iniciar sesión.', detail = 'sesion_requerida';
  end if;

  if not privado.tiene_rol(p_organizacion_id, array['propietario', 'administrador']::public.rol_membresia[]) then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  select o.zona_horaria into v_anterior
  from public.organizaciones o
  where o.id = p_organizacion_id
  for no key update;

  if not found
     or not privado.tiene_rol(p_organizacion_id, array['propietario', 'administrador']::public.rol_membresia[]) then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  if v_zona_horaria is null or v_zona_horaria = '' then
    raise exception using errcode = 'PT400',
      message = 'La zona horaria no es válida.', detail = 'zona_horaria_invalida';
  end if;
  if v_zona_horaria = v_anterior then
    raise exception using errcode = 'PT409',
      message = 'La organización ya tiene esa zona horaria.', detail = 'zona_horaria_sin_cambios';
  end if;

  update public.organizaciones o
  set zona_horaria = v_zona_horaria
  where o.id = p_organizacion_id
  returning * into v_organizacion;

  update public.tareas t
  set vence_en = privado.vence_en_de_fecha(t.fecha_limite, v_zona_horaria)
  where t.organizacion_id = p_organizacion_id
    and t.fecha_limite is not null
    and not privado.es_estado_terminal(t.estado);
  get diagnostics v_recalculadas = row_count;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    p_organizacion_id, v_usuario_id, 'organizacion.zona_horaria_cambiada', 'organizacion', p_organizacion_id,
    jsonb_build_object(
      'zona_horaria_anterior', v_anterior,
      'zona_horaria_nueva', v_zona_horaria,
      'tareas_recalculadas', v_recalculadas
    )
  );

  return v_organizacion;
end;
$$;


-- -----------------------------------------------------------------------------
-- 9. Corrección de la migración de flujos: borrar la cuenta de quien creó una
-- versión publicada. versiones_flujo.creado_por tiene "on delete set null" y
-- el trigger de inmutabilidad rechazaba esa actualización, así que no se
-- podía borrar, por ejemplo, la cuenta de quien creó una organización (figura
-- como creador de su flujo predeterminado). Una versión publicada admite ahora
-- solo ese cambio: creado_por pasa a vacío (más actualizado_en, que asigna su
-- propio trigger) y todo lo demás queda igual.
-- -----------------------------------------------------------------------------
create or replace function privado.proteger_version_flujo()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.estado = 'publicada' then
      raise exception using
        errcode = 'PT400',
        message = 'Una versión se crea como borrador y después se publica.',
        detail = 'publicacion_directa_no_permitida';
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.estado = 'publicada'
     and old.creado_por is not null
     and new.creado_por is null
     and (new.id, new.organizacion_id, new.definicion_flujo_id, new.numero, new.estado,
          new.estado_inicial, new.publicada_en, new.creado_en)
         is not distinct from
         (old.id, old.organizacion_id, old.definicion_flujo_id, old.numero, old.estado,
          old.estado_inicial, old.publicada_en, old.creado_en) then
    return new;
  end if;

  if old.estado = 'publicada' then
    raise exception using
      errcode = 'PT409',
      message = 'Una versión publicada no se puede modificar ni borrar.',
      detail = 'version_publicada_inmutable';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  if new.definicion_flujo_id is distinct from old.definicion_flujo_id then
    raise exception using
      errcode = 'PT400',
      message = 'Una versión no puede cambiar de flujo.',
      detail = 'version_flujo_inmutable';
  end if;

  if new.estado = 'publicada' then
    if not exists (
      select 1
      from public.estados_version_flujo e
      where e.version_flujo_id = new.id
        and e.estado = new.estado_inicial
    ) then
      raise exception using
        errcode = 'PT400',
        message = 'El estado inicial debe ser uno de los estados de la versión.',
        detail = 'estado_inicial_no_incluido';
    end if;

    if not exists (
      select 1
      from public.estados_version_flujo e
      where e.version_flujo_id = new.id
        and privado.es_estado_terminal(e.estado)
    ) then
      raise exception using
        errcode = 'PT400',
        message = 'La versión debe incluir al menos un estado terminal.',
        detail = 'sin_estado_terminal';
    end if;

    new.publicada_en := now();
  end if;

  return new;
end;
$$;

revoke execute on function privado.proteger_version_flujo() from public, anon, authenticated;


-- -----------------------------------------------------------------------------
-- 10. Permisos de ejecución
-- PostgreSQL concede execute a PUBLIC en cada función nueva (ADR-0004).
-- -----------------------------------------------------------------------------
revoke execute on function
  privado.vence_en_de_fecha(date, text),
  privado.tarea_vencida(timestamptz, public.estado_tarea, timestamptz),
  privado.proteger_proyecto(),
  privado.preparar_tarea(),
  privado.retirar_responsable_de_tareas(),
  privado.autorizar_escritura_tarea(uuid),
  privado.bloquear_tarea(uuid),
  privado.puede_gestionar_tarea(public.rol_membresia, public.tareas),
  privado.validar_responsable(uuid, uuid),
  privado.validar_texto_tarea(text, text),
  privado.vence_en_con_hora(uuid, date, time)
  from public, anon, authenticated;

revoke execute on function
  public.crear_proyecto(uuid, text, text, uuid),
  public.archivar_proyecto(uuid, boolean),
  public.crear_tarea(uuid, text, text, uuid, date, time),
  public.editar_tarea(uuid, text, text, date, time),
  public.asignar_responsable(uuid, uuid),
  public.cambiar_estado_tarea(uuid, public.estado_tarea),
  public.eliminar_tarea(uuid),
  public.cambiar_zona_horaria(uuid, text)
  from public, anon;

grant execute on function
  public.crear_proyecto(uuid, text, text, uuid),
  public.archivar_proyecto(uuid, boolean),
  public.crear_tarea(uuid, text, text, uuid, date, time),
  public.editar_tarea(uuid, text, text, date, time),
  public.asignar_responsable(uuid, uuid),
  public.cambiar_estado_tarea(uuid, public.estado_tarea),
  public.eliminar_tarea(uuid),
  public.cambiar_zona_horaria(uuid, text)
  to authenticated;
