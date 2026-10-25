-- =============================================================================
-- Migración: gestión de flujos personalizados (fase 2, bloque 4)
-- Decisión: ADR-0007 · Permisos: docs/security/permissions.md
-- Nombres: ADR-0005 · Reparto de capas: ADR-0003 · Bloqueos: ADR-0004
--
-- Las tablas, la validación de la publicación y la inmutabilidad de las
-- versiones publicadas ya existen (migración 20261025034000). Esta migración
-- añade la vía para que propietario y administrador gestionen flujos propios:
--   1. Un solo borrador por flujo (índice único parcial).
--   2. Funciones internas: autorización y alcance de un estado terminal.
--   3. RPC crear_flujo, crear_version_borrador, guardar_borrador_flujo y
--      publicar_version_flujo, con auditoría.
--
-- Un flujo publicado solo se aplica a proyectos nuevos (ADR-0007):
-- crear_proyecto ya acepta la versión publicada que se quiera usar.
-- Orden de bloqueos: organización ("for share", como las RPC de tareas) →
-- flujo o versión ("for update").
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Un solo borrador por flujo
-- Evita borradores paralelos de la misma definición y hace segura la
-- numeración de versiones nuevas. Incluye organizacion_id (un flujo pertenece
-- a una sola organización, así que es equivalente): una fila que intente
-- colgar de un flujo de otra organización la sigue rechazando la clave
-- foránea compuesta, no este índice.
-- -----------------------------------------------------------------------------
create unique index versiones_flujo_un_borrador_indice
  on public.versiones_flujo (organizacion_id, definicion_flujo_id)
  where estado = 'borrador';


-- -----------------------------------------------------------------------------
-- 2. Funciones internas
-- -----------------------------------------------------------------------------

-- 2.1 Pasos comunes de las RPC que gestionan flujos de una organización:
-- read committed, sesión, permiso (propietario o administrador), bloqueo de la
-- organización y segunda comprobación con el rol actual.
create function privado.autorizar_gestion_flujos(p_organizacion_id uuid)
returns uuid
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_usuario_id uuid := (select auth.uid());
begin
  perform privado.exigir_read_committed();

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

  return v_usuario_id;
end;
$$;

-- 2.2 Organización de una versión, comprobando que quien llama es miembro.
-- Quien no lo es recibe el mismo error que si la versión no existiera; los
-- miembros sin permiso reciben después el error de permiso.
create function privado.organizacion_de_version_flujo(p_version_flujo_id uuid)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_organizacion_id uuid;
begin
  select v.organizacion_id into v_organizacion_id
  from public.versiones_flujo v
  where v.id = p_version_flujo_id;

  if v_organizacion_id is null or not privado.es_miembro(v_organizacion_id) then
    raise exception using errcode = 'PT404',
      message = 'La versión del flujo no existe o no tienes acceso a ella.',
      detail = 'version_flujo_no_encontrada';
  end if;

  return v_organizacion_id;
end;
$$;

-- 2.3 ¿Desde el estado inicial se puede llegar a algún estado terminal? Si no,
-- las tareas de ese flujo no podrían terminar nunca. UNION (no UNION ALL)
-- detiene la recursión cuando no aparecen estados nuevos.
create function privado.flujo_tiene_salida(p_version_flujo_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  with recursive alcanzables (estado) as (
    select v.estado_inicial
    from public.versiones_flujo v
    where v.id = p_version_flujo_id
    union
    select t.estado_destino
    from public.transiciones_version_flujo t
    join alcanzables a on a.estado = t.estado_origen
    where t.version_flujo_id = p_version_flujo_id
  )
  select exists (select 1 from alcanzables a where privado.es_estado_terminal(a.estado));
$$;


-- -----------------------------------------------------------------------------
-- 3. RPC
-- security definer (justificado): authenticated no tiene permisos de
-- escritura en las tablas de flujos ni en auditoria.
-- -----------------------------------------------------------------------------

-- 3.1 Crear un flujo y su versión 1 en borrador, sin estados ni transiciones.
-- El estado inicial provisional es pendiente; se fija al guardar el borrador.
create function public.crear_flujo(p_organizacion_id uuid, p_nombre text)
returns public.versiones_flujo
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_nombre text := btrim(p_nombre);
  v_definicion_id uuid;
  v_version public.versiones_flujo;
begin
  v_usuario_id := privado.autorizar_gestion_flujos(p_organizacion_id);

  if v_nombre is null or char_length(v_nombre) not between 1 and 100 then
    raise exception using errcode = 'PT400',
      message = 'El nombre debe tener entre 1 y 100 caracteres.', detail = 'nombre_invalido';
  end if;

  insert into public.definiciones_flujo (organizacion_id, nombre, creado_por)
  values (p_organizacion_id, v_nombre, v_usuario_id)
  returning id into v_definicion_id;

  insert into public.versiones_flujo (organizacion_id, definicion_flujo_id, numero, estado_inicial, creado_por)
  values (p_organizacion_id, v_definicion_id, 1, 'pendiente', v_usuario_id)
  returning * into v_version;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    p_organizacion_id, v_usuario_id, 'flujo.creado', 'flujo', v_definicion_id,
    jsonb_build_object('nombre', v_nombre, 'version_flujo_id', v_version.id)
  );

  return v_version;
end;
$$;

-- 3.2 Crear un borrador nuevo copiando una versión publicada del mismo flujo
-- (estado inicial, estados y transiciones). Un flujo solo tiene un borrador.
create function public.crear_version_borrador(p_version_flujo_id uuid)
returns public.versiones_flujo
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_organizacion_id uuid;
  v_origen public.versiones_flujo;
  v_numero integer;
  v_version public.versiones_flujo;
begin
  v_organizacion_id := privado.organizacion_de_version_flujo(p_version_flujo_id);
  v_usuario_id := privado.autorizar_gestion_flujos(v_organizacion_id);

  select * into v_origen
  from public.versiones_flujo v
  where v.id = p_version_flujo_id;

  if v_origen.estado <> 'publicada' then
    raise exception using errcode = 'PT400',
      message = 'Solo se puede copiar una versión publicada.', detail = 'version_no_publicada';
  end if;

  -- Bloquea el flujo: dos copias simultáneas no calculan el mismo número.
  perform 1
  from public.definiciones_flujo d
  where d.organizacion_id = v_organizacion_id
    and d.id = v_origen.definicion_flujo_id
  for update;

  if exists (
    select 1
    from public.versiones_flujo v
    where v.definicion_flujo_id = v_origen.definicion_flujo_id
      and v.estado = 'borrador'
  ) then
    raise exception using errcode = 'PT409',
      message = 'Este flujo ya tiene una versión en borrador.', detail = 'borrador_existente';
  end if;

  select max(v.numero) + 1 into v_numero
  from public.versiones_flujo v
  where v.definicion_flujo_id = v_origen.definicion_flujo_id;

  insert into public.versiones_flujo (organizacion_id, definicion_flujo_id, numero, estado_inicial, creado_por)
  values (v_organizacion_id, v_origen.definicion_flujo_id, v_numero, v_origen.estado_inicial, v_usuario_id)
  returning * into v_version;

  insert into public.estados_version_flujo (organizacion_id, version_flujo_id, estado)
  select v_organizacion_id, v_version.id, e.estado
  from public.estados_version_flujo e
  where e.version_flujo_id = v_origen.id;

  insert into public.transiciones_version_flujo (organizacion_id, version_flujo_id, estado_origen, estado_destino)
  select v_organizacion_id, v_version.id, t.estado_origen, t.estado_destino
  from public.transiciones_version_flujo t
  where t.version_flujo_id = v_origen.id;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    v_organizacion_id, v_usuario_id, 'version_flujo.borrador_creado', 'version_flujo', v_version.id,
    jsonb_build_object(
      'definicion_flujo_id', v_version.definicion_flujo_id,
      'numero', v_numero,
      'copiada_de', v_origen.id
    )
  );

  return v_version;
end;
$$;

-- 3.3 Guardar el contenido completo de un borrador de una vez: reemplaza sus
-- estados, su estado inicial y sus transiciones en una sola transacción. Si
-- algo no es válido, no cambia nada.
-- p_transiciones: lista JSON de objetos {"origen": ..., "destino": ...}, con
-- nombres de estados del catálogo. Se valida aquí para devolver errores
-- propios y no errores internos de conversión.
create function public.guardar_borrador_flujo(
  p_version_flujo_id uuid,
  p_estados public.estado_tarea[],
  p_estado_inicial public.estado_tarea,
  p_transiciones jsonb
)
returns public.versiones_flujo
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_organizacion_id uuid;
  v_version public.versiones_flujo;
  v_estados public.estado_tarea[];
  v_catalogo text[] := enum_range(null::public.estado_tarea)::text[];
  v_transiciones integer;
begin
  v_organizacion_id := privado.organizacion_de_version_flujo(p_version_flujo_id);
  v_usuario_id := privado.autorizar_gestion_flujos(v_organizacion_id);

  select * into v_version
  from public.versiones_flujo v
  where v.id = p_version_flujo_id
  for update;

  if v_version.estado = 'publicada' then
    raise exception using errcode = 'PT409',
      message = 'Una versión publicada no se puede modificar ni borrar.',
      detail = 'version_publicada_inmutable';
  end if;

  -- Estados
  if p_estados is null
     or cardinality(p_estados) = 0
     or exists (select 1 from unnest(p_estados) e (estado) where e.estado is null) then
    raise exception using errcode = 'PT400',
      message = 'Debes indicar al menos un estado válido.', detail = 'estados_invalidos';
  end if;

  select array_agg(distinct e.estado) into v_estados
  from unnest(p_estados) e (estado);

  if p_estado_inicial is null or not (p_estado_inicial = any (v_estados)) then
    raise exception using errcode = 'PT400',
      message = 'El estado inicial debe ser uno de los estados de la versión.',
      detail = 'estado_inicial_no_incluido';
  end if;
  if privado.es_estado_terminal(p_estado_inicial) then
    raise exception using errcode = 'PT400',
      message = 'El estado inicial no puede ser terminal.', detail = 'estado_inicial_terminal';
  end if;
  if not exists (select 1 from unnest(v_estados) e (estado) where privado.es_estado_terminal(e.estado)) then
    raise exception using errcode = 'PT400',
      message = 'La versión debe incluir al menos un estado terminal.', detail = 'sin_estado_terminal';
  end if;

  -- Transiciones: primero la forma (lista de objetos), después las claves y
  -- los valores. Se comprueba en pasos separados porque PostgreSQL no
  -- garantiza el orden de evaluación de las condiciones de un mismo "or".
  if p_transiciones is null or jsonb_typeof(p_transiciones) <> 'array' then
    raise exception using errcode = 'PT400',
      message = 'Las transiciones deben ser una lista de pares de origen y destino válidos.',
      detail = 'transiciones_invalidas';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_transiciones) e (valor)
    where jsonb_typeof(e.valor) <> 'object'
  ) then
    raise exception using errcode = 'PT400',
      message = 'Las transiciones deben ser una lista de pares de origen y destino válidos.',
      detail = 'transiciones_invalidas';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_transiciones) e (valor)
    where (select array_agg(k.clave order by k.clave) from jsonb_object_keys(e.valor) k (clave))
            is distinct from array['destino', 'origen']
       or jsonb_typeof(e.valor -> 'origen') <> 'string'
       or jsonb_typeof(e.valor -> 'destino') <> 'string'
  ) then
    raise exception using errcode = 'PT400',
      message = 'Las transiciones deben ser una lista de pares de origen y destino válidos.',
      detail = 'transiciones_invalidas';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_transiciones) e (valor)
    where not (e.valor ->> 'origen' = any (v_catalogo))
       or not (e.valor ->> 'destino' = any (v_catalogo))
  ) then
    raise exception using errcode = 'PT400',
      message = 'Las transiciones deben ser una lista de pares de origen y destino válidos.',
      detail = 'transiciones_invalidas';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_transiciones) e (valor)
    where e.valor ->> 'origen' = e.valor ->> 'destino'
       or not ((e.valor ->> 'origen')::public.estado_tarea = any (v_estados))
       or not ((e.valor ->> 'destino')::public.estado_tarea = any (v_estados))
  ) then
    raise exception using errcode = 'PT400',
      message = 'Cada transición debe unir dos estados distintos de la versión.',
      detail = 'transicion_invalida';
  end if;

  -- Reemplazo del contenido (los triggers permiten tocar un borrador).
  delete from public.transiciones_version_flujo t where t.version_flujo_id = p_version_flujo_id;
  delete from public.estados_version_flujo e where e.version_flujo_id = p_version_flujo_id;

  update public.versiones_flujo v
  set estado_inicial = p_estado_inicial
  where v.id = p_version_flujo_id
  returning * into v_version;

  insert into public.estados_version_flujo (organizacion_id, version_flujo_id, estado)
  select v_organizacion_id, p_version_flujo_id, e.estado
  from unnest(v_estados) e (estado);

  insert into public.transiciones_version_flujo (organizacion_id, version_flujo_id, estado_origen, estado_destino)
  select distinct v_organizacion_id, p_version_flujo_id,
         (e.valor ->> 'origen')::public.estado_tarea,
         (e.valor ->> 'destino')::public.estado_tarea
  from jsonb_array_elements(p_transiciones) e (valor);
  get diagnostics v_transiciones = row_count;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    v_organizacion_id, v_usuario_id, 'version_flujo.borrador_guardado', 'version_flujo', p_version_flujo_id,
    jsonb_build_object(
      'estados', to_jsonb(v_estados),
      'estado_inicial', p_estado_inicial,
      'transiciones', v_transiciones
    )
  );

  return v_version;
end;
$$;

-- 3.4 Publicar un borrador. El trigger de versiones valida el estado inicial y
-- el estado terminal; aquí se exige además que el flujo tenga salida. Una vez
-- publicada, la versión es inmutable.
create function public.publicar_version_flujo(p_version_flujo_id uuid)
returns public.versiones_flujo
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_organizacion_id uuid;
  v_version public.versiones_flujo;
begin
  v_organizacion_id := privado.organizacion_de_version_flujo(p_version_flujo_id);
  v_usuario_id := privado.autorizar_gestion_flujos(v_organizacion_id);

  select * into v_version
  from public.versiones_flujo v
  where v.id = p_version_flujo_id
  for update;

  if v_version.estado = 'publicada' then
    raise exception using errcode = 'PT409',
      message = 'La versión ya está publicada.', detail = 'version_ya_publicada';
  end if;

  if not privado.flujo_tiene_salida(p_version_flujo_id) then
    raise exception using errcode = 'PT400',
      message = 'Desde el estado inicial debe poder llegarse a un estado terminal.',
      detail = 'flujo_sin_salida';
  end if;

  update public.versiones_flujo v
  set estado = 'publicada'
  where v.id = p_version_flujo_id
  returning * into v_version;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    v_organizacion_id, v_usuario_id, 'version_flujo.publicada', 'version_flujo', p_version_flujo_id,
    jsonb_build_object('definicion_flujo_id', v_version.definicion_flujo_id, 'numero', v_version.numero)
  );

  return v_version;
end;
$$;


-- -----------------------------------------------------------------------------
-- 4. Permisos de ejecución
-- PostgreSQL concede execute a PUBLIC en cada función nueva (ADR-0004).
-- -----------------------------------------------------------------------------
revoke execute on function
  privado.autorizar_gestion_flujos(uuid),
  privado.organizacion_de_version_flujo(uuid),
  privado.flujo_tiene_salida(uuid)
  from public, anon, authenticated;

revoke execute on function
  public.crear_flujo(uuid, text),
  public.crear_version_borrador(uuid),
  public.guardar_borrador_flujo(uuid, public.estado_tarea[], public.estado_tarea, jsonb),
  public.publicar_version_flujo(uuid)
  from public, anon;

grant execute on function
  public.crear_flujo(uuid, text),
  public.crear_version_borrador(uuid),
  public.guardar_borrador_flujo(uuid, public.estado_tarea[], public.estado_tarea, jsonb),
  public.publicar_version_flujo(uuid)
  to authenticated;
