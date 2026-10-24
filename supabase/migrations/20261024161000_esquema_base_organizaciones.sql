-- =============================================================================
-- Migración: esquema base de organizaciones (fase 1)
-- Plan: docs/plans/fase-1-organizaciones-y-membresias.md
-- Permisos: docs/security/permissions.md · Nombres: ADR-0005
--
-- Contenido:
--   1. Permisos por defecto: tablas y secuencias nuevas nacen sin acceso.
--   2. Esquema privado y tipo de rol.
--   3. Tablas: perfiles, organizaciones, membresias, auditoria.
--   4. Funciones auxiliares de permisos (usadas por las políticas RLS).
--   5. Triggers de invariantes: perfil al registrarse, actualizado_en,
--      siempre un propietario, organizacion_id inmutable, auditoría inmutable.
--   6. RLS y políticas por operación.
--   7. Permisos (grants) mínimos para el rol authenticated.
--   8. RPC crear_organizacion.
--
-- Las funciones de gestión de miembros (agregar, cambiar rol, quitar, salir)
-- van en la siguiente migración.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Permisos por defecto
-- Supabase concede por defecto a anon y authenticated todos los permisos sobre
-- cada tabla, secuencia y función nueva de public. Los retiramos para que una
-- migración futura que olvide sus permisos no exponga tablas ni secuencias
-- ("denegar por defecto"). service_role conserva los suyos: es la clave
-- secreta del servidor.
-- ATENCIÓN con las funciones: PostgreSQL concede execute a PUBLIC (todos los
-- roles, incluido anon) en cada función nueva, y eso no se puede retirar por
-- esquema. Cada función nueva debe hacer su propio
-- "revoke execute ... from public, anon" (ver ADR-0004).
-- -----------------------------------------------------------------------------
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on functions from anon, authenticated;


-- -----------------------------------------------------------------------------
-- 2. Esquema privado y tipo de rol
-- privado no está expuesto por la Data API. authenticated necesita usage para
-- que las políticas RLS puedan llamar a sus funciones auxiliares.
-- -----------------------------------------------------------------------------
create schema privado;
revoke all on schema privado from public;
grant usage on schema privado to authenticated;

create type public.rol_membresia as enum ('propietario', 'administrador', 'miembro');


-- -----------------------------------------------------------------------------
-- 3. Tablas
-- -----------------------------------------------------------------------------

-- Ficha visible de cada usuario. auth.users no se expone porque contiene datos
-- sensibles (correo, hashes, metadatos de sesión).
create table public.perfiles (
  id uuid primary key references auth.users (id) on delete cascade,
  nombre_visible text not null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint perfiles_nombre_visible_valido
    check (nombre_visible = btrim(nombre_visible) and char_length(nombre_visible) between 1 and 100)
);

-- Cada empresa que usa Nexo.
create table public.organizaciones (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  creado_por uuid references auth.users (id) on delete set null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint organizaciones_nombre_valido
    check (nombre = btrim(nombre) and char_length(nombre) between 1 and 100)
);

-- Quién pertenece a qué organización y con qué rol. La clave primaria
-- compuesta impide que una persona aparezca dos veces en la misma
-- organización. usuario_id apunta a perfiles para que la Data API pueda
-- devolver el nombre visible de cada miembro en la misma consulta.
create table public.membresias (
  organizacion_id uuid not null references public.organizaciones (id) on delete cascade,
  usuario_id uuid not null references public.perfiles (id) on delete cascade,
  rol public.rol_membresia not null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  primary key (organizacion_id, usuario_id)
);

-- Las políticas preguntan "¿es miembro este usuario?" en cada consulta.
-- La clave primaria empieza por organizacion_id; este índice cubre la
-- búsqueda por usuario.
create index membresias_usuario_organizacion_indice
  on public.membresias (usuario_id, organizacion_id);

-- Historial de solo inserción. actor_id no tiene clave foránea a propósito:
-- el historial debe conservarse aunque se borre la cuenta del actor, y una
-- clave foránea con "set null" necesitaría modificar filas de auditoría.
-- organizacion_id sí la tiene (sin cascada): borrar una organización con
-- historial queda bloqueado hasta decidir la retención (decisión pospuesta).
create table public.auditoria (
  id bigint generated always as identity primary key,
  organizacion_id uuid not null references public.organizaciones (id),
  actor_id uuid,
  accion text not null,
  tipo_recurso text not null,
  recurso_id uuid,
  detalles jsonb not null default '{}'::jsonb,
  creado_en timestamptz not null default now(),
  constraint auditoria_accion_valido
    check (accion ~ '^[a-z_]+\.[a-z_]+$'),
  constraint auditoria_tipo_recurso_valido
    check (tipo_recurso ~ '^[a-z_]{1,50}$'),
  constraint auditoria_detalles_valido
    check (jsonb_typeof(detalles) = 'object')
);

-- Consulta habitual: historial de una organización, lo más reciente primero.
create index auditoria_organizacion_creado_en_indice
  on public.auditoria (organizacion_id, creado_en desc);


-- -----------------------------------------------------------------------------
-- 4. Funciones auxiliares de permisos
-- security definer: leen membresias sin pasar por RLS. Si la política de
-- membresias consultara membresias directamente, PostgreSQL volvería a aplicar
-- la misma política sin fin. search_path vacío: todo nombre va calificado, así
-- nadie puede colar un objeto falso con el mismo nombre. Solo devuelven
-- verdadero o falso, siempre sobre el usuario actual (auth.uid()).
-- -----------------------------------------------------------------------------
create function privado.es_miembro(p_organizacion_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.membresias m
    where m.organizacion_id = p_organizacion_id
      and m.usuario_id = (select auth.uid())
  );
$$;

create function privado.tiene_rol(p_organizacion_id uuid, p_roles public.rol_membresia[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.membresias m
    where m.organizacion_id = p_organizacion_id
      and m.usuario_id = (select auth.uid())
      and m.rol = any (p_roles)
  );
$$;

create function privado.tiene_organizacion_en_comun(p_usuario_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.membresias propia
    join public.membresias ajena on ajena.organizacion_id = propia.organizacion_id
    where propia.usuario_id = (select auth.uid())
      and ajena.usuario_id = p_usuario_id
  );
$$;


-- -----------------------------------------------------------------------------
-- 5. Triggers de invariantes
-- -----------------------------------------------------------------------------

-- 5.1 actualizado_en se asigna en el servidor, no lo decide el cliente.
create function privado.asignar_actualizado_en()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.actualizado_en := now();
  return new;
end;
$$;

create trigger perfiles_asignar_actualizado_en
  before update on public.perfiles
  for each row execute function privado.asignar_actualizado_en();

create trigger organizaciones_asignar_actualizado_en
  before update on public.organizaciones
  for each row execute function privado.asignar_actualizado_en();

create trigger membresias_asignar_actualizado_en
  before update on public.membresias
  for each row execute function privado.asignar_actualizado_en();

-- 5.2 Crear el perfil al registrarse. nombre_visible viene de los datos que
-- envía el frontend al registrarse (options.data.nombre_visible). Esos datos
-- los controla el usuario: se usan solo para mostrar, nunca para autorizar.
-- security definer: quien inserta en auth.users es el servicio de Auth, que
-- no tiene permisos sobre public.perfiles.
create function privado.crear_perfil()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.perfiles (id, nombre_visible)
  values (
    new.id,
    coalesce(
      nullif(btrim(left(btrim(new.raw_user_meta_data ->> 'nombre_visible'), 100)), ''),
      'Usuario'
    )
  );
  return new;
end;
$$;

create trigger crear_perfil_al_registrarse
  after insert on auth.users
  for each row execute function privado.crear_perfil();

-- 5.3 Una organización nunca se queda sin propietario. Es la red de seguridad
-- detrás de las funciones de gestión de miembros: aunque una función tuviera
-- un error, la base de datos rechaza el cambio.
-- El "for no key update" bloquea la fila de la organización: si dos
-- propietarios se quitan el rol el uno al otro a la vez, la segunda operación
-- espera a la primera y ve su resultado, en lugar de dejar la organización sin
-- dueño. Es el bloqueo más débil que choca consigo mismo; a diferencia de
-- "for update", no frena las inserciones que solo referencian la organización
-- (claves foráneas, que toman "for key share").
-- Supone el aislamiento read committed (el de la Data API): cada consulta del
-- trigger ve lo confirmado justo antes. Ver ADR-0004.
-- Si la organización se está borrando (cascada), no hay nada que proteger.
create function privado.exigir_propietario()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.rol <> 'propietario' then
    return null;
  end if;

  perform 1
  from public.organizaciones o
  where o.id = old.organizacion_id
  for no key update;

  if not found then
    return null;
  end if;

  if not exists (
    select 1
    from public.membresias m
    where m.organizacion_id = old.organizacion_id
      and m.rol = 'propietario'
  ) then
    raise exception using
      errcode = 'PT409',
      message = 'La organización debe tener al menos un propietario.',
      detail = 'ultimo_propietario';
  end if;

  return null;
end;
$$;

create trigger membresias_exigir_propietario
  after update of rol or delete on public.membresias
  for each row execute function privado.exigir_propietario();

-- 5.4 Una fila no puede cambiar de organización (evita "mudar" datos a otra
-- organización con un update). Se reutilizará en las tablas de negocio.
create function privado.impedir_cambio_organizacion_id()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.organizacion_id is distinct from old.organizacion_id then
    raise exception using
      errcode = 'PT400',
      message = 'No se puede cambiar la organización de este registro.',
      detail = 'organizacion_inmutable';
  end if;
  return new;
end;
$$;

create trigger membresias_impedir_cambio_organizacion_id
  before update on public.membresias
  for each row execute function privado.impedir_cambio_organizacion_id();

-- 5.5 Auditoría de solo inserción. Además de no conceder update/delete a nadie,
-- este trigger rechaza modificaciones incluso con la clave secreta
-- (service_role), que se salta RLS pero no los triggers.
create function privado.impedir_cambios_auditoria()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = 'PT403',
    message = 'El historial de auditoría no se puede modificar.',
    detail = 'auditoria_inmutable';
end;
$$;

create trigger auditoria_impedir_cambios
  before update or delete on public.auditoria
  for each row execute function privado.impedir_cambios_auditoria();

create trigger auditoria_impedir_truncate
  before truncate on public.auditoria
  for each statement execute function privado.impedir_cambios_auditoria();

-- 5.6 Registrar el cambio de nombre de una organización. El cambio se hace por
-- la Data API (una sola tabla), así que la auditoría la escribe un trigger.
-- security definer: authenticated no tiene permiso de insert en auditoria.
create function privado.auditar_organizacion_actualizada()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    new.id,
    (select auth.uid()),
    'organizacion.actualizada',
    'organizacion',
    new.id,
    jsonb_build_object('nombre_anterior', old.nombre, 'nombre_nuevo', new.nombre)
  );
  return null;
end;
$$;

create trigger organizaciones_auditar_actualizacion
  after update of nombre on public.organizaciones
  for each row
  when (old.nombre is distinct from new.nombre)
  execute function privado.auditar_organizacion_actualizada();


-- -----------------------------------------------------------------------------
-- 6. RLS y políticas
-- Políticas solo para authenticated. anon no tiene permisos (sección 7), así
-- que ni siquiera llega a evaluar una política. Lo que no tiene política está
-- denegado.
-- -----------------------------------------------------------------------------
alter table public.perfiles enable row level security;
alter table public.organizaciones enable row level security;
alter table public.membresias enable row level security;
alter table public.auditoria enable row level security;

-- perfiles: ves el tuyo y los de quienes comparten organización contigo.
create policy perfiles_select on public.perfiles
  for select to authenticated
  using (id = (select auth.uid()) or privado.tiene_organizacion_en_comun(id));

-- perfiles: solo editas el tuyo. Insert y delete: sin política (los gestiona
-- el trigger de registro y el borrado de la cuenta).
create policy perfiles_update on public.perfiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- organizaciones: solo las ves si eres miembro.
create policy organizaciones_select on public.organizaciones
  for select to authenticated
  using (privado.es_miembro(id));

-- organizaciones: propietario y administrador editan. Insert: solo con
-- crear_organizacion. Delete: pospuesto (sin política).
create policy organizaciones_update on public.organizaciones
  for update to authenticated
  using (privado.tiene_rol(id, array['propietario', 'administrador']::public.rol_membresia[]))
  with check (privado.tiene_rol(id, array['propietario', 'administrador']::public.rol_membresia[]));

-- membresias: ves los miembros de tus organizaciones. Escrituras: solo con
-- funciones, que validan las reglas de rol dentro de una transacción.
create policy membresias_select on public.membresias
  for select to authenticated
  using (privado.es_miembro(organizacion_id));

-- auditoria: solo propietario y administrador la leen. Nadie escribe
-- directamente.
create policy auditoria_select on public.auditoria
  for select to authenticated
  using (privado.tiene_rol(organizacion_id, array['propietario', 'administrador']::public.rol_membresia[]));


-- -----------------------------------------------------------------------------
-- 7. Permisos (grants)
-- RLS decide qué filas; los grants deciden qué operaciones y qué columnas.
-- Las actualizaciones se limitan a la columna editable para que nadie cambie
-- id, creado_por ni fechas.
-- -----------------------------------------------------------------------------
revoke all on table public.perfiles, public.organizaciones, public.membresias, public.auditoria
  from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

grant select on table public.perfiles, public.organizaciones, public.membresias, public.auditoria
  to authenticated;
grant update (nombre_visible) on table public.perfiles to authenticated;
grant update (nombre) on table public.organizaciones to authenticated;

-- PostgreSQL deja ejecutar cualquier función a todos (PUBLIC) por defecto.
revoke execute on all functions in schema privado from public, anon, authenticated;
grant execute on function
  privado.es_miembro(uuid),
  privado.tiene_rol(uuid, public.rol_membresia[]),
  privado.tiene_organizacion_en_comun(uuid)
  to authenticated;


-- -----------------------------------------------------------------------------
-- 8. RPC crear_organizacion
-- Crea la organización, la membresía propietario de quien llama y el registro
-- de auditoría en una sola transacción: o se hacen las tres cosas o ninguna.
-- Es la única forma de obtener el rol propietario sin que otro propietario lo
-- conceda, y solo sobre una organización nueva cuyo id genera el servidor.
-- security definer (justificado): authenticated no tiene permiso de insert en
-- ninguna de las tres tablas, precisamente para que nadie pueda insertarse
-- como propietario por la Data API.
-- -----------------------------------------------------------------------------
create function public.crear_organizacion(p_nombre text)
returns public.organizaciones
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid := (select auth.uid());
  v_nombre text := btrim(p_nombre);
  v_organizacion public.organizaciones;
begin
  if v_usuario_id is null then
    raise exception using
      errcode = 'PT401',
      message = 'Debes iniciar sesión.',
      detail = 'sesion_requerida';
  end if;

  if v_nombre is null or char_length(v_nombre) not between 1 and 100 then
    raise exception using
      errcode = 'PT400',
      message = 'El nombre debe tener entre 1 y 100 caracteres.',
      detail = 'nombre_invalido';
  end if;

  if not exists (select 1 from public.perfiles p where p.id = v_usuario_id) then
    raise exception using
      errcode = 'PT400',
      message = 'Tu cuenta no tiene perfil. Contacta con soporte.',
      detail = 'perfil_inexistente';
  end if;

  insert into public.organizaciones (nombre, creado_por)
  values (v_nombre, v_usuario_id)
  returning * into v_organizacion;

  insert into public.membresias (organizacion_id, usuario_id, rol)
  values (v_organizacion.id, v_usuario_id, 'propietario');

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    v_organizacion.id,
    v_usuario_id,
    'organizacion.creada',
    'organizacion',
    v_organizacion.id,
    jsonb_build_object('nombre', v_nombre, 'rol', 'propietario')
  );

  return v_organizacion;
end;
$$;

revoke execute on function public.crear_organizacion(text) from public, anon;
grant execute on function public.crear_organizacion(text) to authenticated;
