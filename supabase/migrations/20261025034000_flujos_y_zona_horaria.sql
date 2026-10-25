-- =============================================================================
-- Migración: flujos versionados y zona horaria (fase 2, bloque 1)
-- Decisión: ADR-0007 · Permisos: docs/security/permissions.md
-- Nombres: ADR-0005 · Multiempresa: ADR-0002 · Migraciones: ADR-0004
--
-- Contenido:
--   1. Tipos: estado_tarea (catálogo fijo) y estado_version_flujo.
--   2. organizaciones.zona_horaria, con su validación.
--   3. Tablas del módulo flujos: definiciones_flujo, versiones_flujo,
--      estados_version_flujo y transiciones_version_flujo.
--   4. Funciones internas: estado terminal y transición permitida.
--   5. Triggers: actualizado_en, organizacion_id inmutable, publicación
--      validada y versiones publicadas inmutables.
--   6. Flujo predeterminado: función, trigger al crear una organización y
--      relleno de las organizaciones existentes.
--   7. RLS (solo lectura para miembros) y permisos.
--
-- No modifica las migraciones 1 y 2 ni la función crear_organizacion: el flujo
-- predeterminado lo crea un trigger sobre organizaciones, así existe sea cual
-- sea la vía de inserción. Crear borradores y publicar versiones desde la API,
-- proyectos, tareas y el cambio de zona horaria (que recalcula vencimientos)
-- van en migraciones posteriores.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Tipos
-- completada y cancelada son los estados terminales (ADR-0007): nunca vencen
-- y no cuentan como trabajo abierto.
-- -----------------------------------------------------------------------------
create type public.estado_tarea as enum ('pendiente', 'en_curso', 'en_revision', 'completada', 'cancelada');

create type public.estado_version_flujo as enum ('borrador', 'publicada');


-- -----------------------------------------------------------------------------
-- 2. Zona horaria de la organización
-- Referencia para vencimientos, detección y métricas (ADR-0007). Por la Data
-- API solo se puede actualizar nombre (grant de la migración 1), así que la
-- zona solo cambiará mediante una RPC que recalcule los vencimientos.
-- Un check no puede consultar tablas: la validación contra el catálogo de
-- PostgreSQL la hace un trigger. Se rechazan los alias posix/ y right/.
-- -----------------------------------------------------------------------------
alter table public.organizaciones
  add column zona_horaria text not null default 'America/Bogota';

create function privado.validar_zona_horaria()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.zona_horaria like 'posix/%'
     or new.zona_horaria like 'right/%'
     or not exists (
       select 1 from pg_catalog.pg_timezone_names z where z.name = new.zona_horaria
     ) then
    raise exception using
      errcode = 'PT400',
      message = 'La zona horaria no es válida.',
      detail = 'zona_horaria_invalida';
  end if;
  return new;
end;
$$;

create trigger organizaciones_validar_zona_horaria
  before insert or update of zona_horaria on public.organizaciones
  for each row execute function privado.validar_zona_horaria();


-- -----------------------------------------------------------------------------
-- 3. Tablas del módulo flujos
-- Los flujos se guardan en filas, no en jsonb (ADR-0007): las restricciones y
-- las claves foráneas validan su estructura. Todas llevan organizacion_id y
-- las hijas usan claves foráneas compuestas (ADR-0002), así la base de datos
-- impide mezclar filas de organizaciones distintas.
-- -----------------------------------------------------------------------------

-- Un flujo de una organización. Cada organización tiene exactamente un flujo
-- predeterminado (índice único parcial más abajo).
create table public.definiciones_flujo (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references public.organizaciones (id) on delete cascade,
  nombre text not null,
  es_predeterminado boolean not null default false,
  creado_por uuid references auth.users (id) on delete set null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint definiciones_flujo_nombre_valido
    check (nombre = btrim(nombre) and char_length(nombre) between 1 and 100),
  unique (organizacion_id, id)
);

create unique index definiciones_flujo_un_predeterminado_indice
  on public.definiciones_flujo (organizacion_id)
  where es_predeterminado;

-- Una versión numerada de un flujo. Nace como borrador; al publicarse queda
-- inmutable (trigger de la sección 5). Los proyectos apuntarán a una versión
-- publicada mediante (organizacion_id, id).
create table public.versiones_flujo (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  definicion_flujo_id uuid not null,
  numero integer not null,
  estado public.estado_version_flujo not null default 'borrador',
  estado_inicial public.estado_tarea not null,
  publicada_en timestamptz,
  creado_por uuid references auth.users (id) on delete set null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  foreign key (organizacion_id, definicion_flujo_id)
    references public.definiciones_flujo (organizacion_id, id) on delete cascade,
  constraint versiones_flujo_numero_valido check (numero > 0),
  constraint versiones_flujo_estado_inicial_no_terminal
    check (estado_inicial not in ('completada', 'cancelada')),
  constraint versiones_flujo_publicada_en_coherente
    check ((estado = 'publicada') = (publicada_en is not null)),
  unique (definicion_flujo_id, numero),
  unique (organizacion_id, id)
);

create index versiones_flujo_organizacion_definicion_indice
  on public.versiones_flujo (organizacion_id, definicion_flujo_id);

-- Estados del catálogo que usa cada versión.
create table public.estados_version_flujo (
  organizacion_id uuid not null,
  version_flujo_id uuid not null,
  estado public.estado_tarea not null,
  creado_en timestamptz not null default now(),
  primary key (version_flujo_id, estado),
  foreign key (organizacion_id, version_flujo_id)
    references public.versiones_flujo (organizacion_id, id) on delete cascade,
  unique (organizacion_id, version_flujo_id, estado)
);

-- Transiciones permitidas entre estados de la misma versión. Las claves
-- foráneas obligan a que origen y destino sean estados de esa versión.
create table public.transiciones_version_flujo (
  organizacion_id uuid not null,
  version_flujo_id uuid not null,
  estado_origen public.estado_tarea not null,
  estado_destino public.estado_tarea not null,
  creado_en timestamptz not null default now(),
  primary key (version_flujo_id, estado_origen, estado_destino),
  foreign key (organizacion_id, version_flujo_id, estado_origen)
    references public.estados_version_flujo (organizacion_id, version_flujo_id, estado) on delete cascade,
  foreign key (organizacion_id, version_flujo_id, estado_destino)
    references public.estados_version_flujo (organizacion_id, version_flujo_id, estado) on delete cascade,
  constraint transiciones_version_flujo_sin_bucle
    check (estado_origen <> estado_destino)
);


-- -----------------------------------------------------------------------------
-- 4. Funciones internas del módulo flujos
-- Las usarán las RPC y los triggers de tareas (ADR-0007: la RPC y el trigger
-- comparten la misma regla). No son RPC: nadie puede ejecutarlas desde la API
-- (sección 7).
-- -----------------------------------------------------------------------------
create function privado.es_estado_terminal(p_estado public.estado_tarea)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_estado in ('completada', 'cancelada');
$$;

create function privado.transicion_permitida(
  p_version_flujo_id uuid,
  p_estado_origen public.estado_tarea,
  p_estado_destino public.estado_tarea
)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.transiciones_version_flujo t
    where t.version_flujo_id = p_version_flujo_id
      and t.estado_origen = p_estado_origen
      and t.estado_destino = p_estado_destino
  );
$$;


-- -----------------------------------------------------------------------------
-- 5. Triggers
-- -----------------------------------------------------------------------------

-- 5.1 actualizado_en y organizacion_id inmutable (funciones de la migración 1).
create trigger definiciones_flujo_asignar_actualizado_en
  before update on public.definiciones_flujo
  for each row execute function privado.asignar_actualizado_en();

create trigger versiones_flujo_asignar_actualizado_en
  before update on public.versiones_flujo
  for each row execute function privado.asignar_actualizado_en();

create trigger definiciones_flujo_impedir_cambio_organizacion_id
  before update on public.definiciones_flujo
  for each row execute function privado.impedir_cambio_organizacion_id();

create trigger versiones_flujo_impedir_cambio_organizacion_id
  before update on public.versiones_flujo
  for each row execute function privado.impedir_cambio_organizacion_id();

create trigger estados_version_flujo_impedir_cambio_organizacion_id
  before update on public.estados_version_flujo
  for each row execute function privado.impedir_cambio_organizacion_id();

create trigger transiciones_version_flujo_impedir_cambio_organizacion_id
  before update on public.transiciones_version_flujo
  for each row execute function privado.impedir_cambio_organizacion_id();

-- 5.2 Versiones: solo se publican desde borrador, la publicación se valida y
-- una versión publicada no se modifica ni se borra. Protege también frente a
-- la clave secreta (service_role), que se salta RLS pero no los triggers.
create function privado.proteger_version_flujo()
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

create trigger versiones_flujo_proteger
  before insert or update or delete on public.versiones_flujo
  for each row execute function privado.proteger_version_flujo();

-- 5.3 Estados y transiciones de una versión publicada tampoco cambian. Si la
-- versión ya no existe (borrado en cascada de un borrador), no hay nada que
-- proteger.
create function privado.proteger_contenido_version_flujo()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_versiones uuid[];
begin
  if tg_op = 'INSERT' then
    v_versiones := array[new.version_flujo_id];
  elsif tg_op = 'UPDATE' then
    v_versiones := array[old.version_flujo_id, new.version_flujo_id];
  else
    v_versiones := array[old.version_flujo_id];
  end if;

  if exists (
    select 1
    from public.versiones_flujo v
    where v.id = any (v_versiones)
      and v.estado = 'publicada'
  ) then
    raise exception using
      errcode = 'PT409',
      message = 'Una versión publicada no se puede modificar ni borrar.',
      detail = 'version_publicada_inmutable';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger estados_version_flujo_proteger
  before insert or update or delete on public.estados_version_flujo
  for each row execute function privado.proteger_contenido_version_flujo();

create trigger transiciones_version_flujo_proteger
  before insert or update or delete on public.transiciones_version_flujo
  for each row execute function privado.proteger_contenido_version_flujo();


-- -----------------------------------------------------------------------------
-- 6. Flujo predeterminado (ADR-0007)
-- pendiente → en_curso → en_revision → completada; en_revision → en_curso
-- (devolver a trabajo); completada → en_curso (reabrir); cualquier estado no
-- terminal → cancelada. cancelada no tiene salida. Estado inicial: pendiente.
-- La creación automática no escribe en auditoría: forma parte de la creación
-- de la organización, que ya queda registrada como organizacion.creada. Las
-- publicaciones que hagan las personas sí se auditarán.
-- -----------------------------------------------------------------------------
create function privado.crear_flujo_predeterminado(p_organizacion_id uuid, p_creado_por uuid)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_definicion_id uuid;
  v_version_id uuid;
begin
  insert into public.definiciones_flujo (organizacion_id, nombre, es_predeterminado, creado_por)
  values (p_organizacion_id, 'Flujo predeterminado', true, p_creado_por)
  returning id into v_definicion_id;

  insert into public.versiones_flujo (organizacion_id, definicion_flujo_id, numero, estado_inicial, creado_por)
  values (p_organizacion_id, v_definicion_id, 1, 'pendiente', p_creado_por)
  returning id into v_version_id;

  insert into public.estados_version_flujo (organizacion_id, version_flujo_id, estado)
  select p_organizacion_id, v_version_id, e.estado
  from unnest(enum_range(null::public.estado_tarea)) as e (estado);

  insert into public.transiciones_version_flujo (organizacion_id, version_flujo_id, estado_origen, estado_destino)
  values
    (p_organizacion_id, v_version_id, 'pendiente', 'en_curso'),
    (p_organizacion_id, v_version_id, 'pendiente', 'cancelada'),
    (p_organizacion_id, v_version_id, 'en_curso', 'en_revision'),
    (p_organizacion_id, v_version_id, 'en_curso', 'cancelada'),
    (p_organizacion_id, v_version_id, 'en_revision', 'en_curso'),
    (p_organizacion_id, v_version_id, 'en_revision', 'completada'),
    (p_organizacion_id, v_version_id, 'en_revision', 'cancelada'),
    (p_organizacion_id, v_version_id, 'completada', 'en_curso');

  update public.versiones_flujo
  set estado = 'publicada'
  where id = v_version_id;

  return v_version_id;
end;
$$;

-- security definer (justificado): quien crea la organización no tiene permiso
-- de insert en las tablas de flujos. Solo crea el flujo de la fila recién
-- insertada; no recibe datos del cliente.
create function privado.crear_flujo_al_crear_organizacion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform privado.crear_flujo_predeterminado(new.id, new.creado_por);
  return null;
end;
$$;

create trigger organizaciones_crear_flujo_predeterminado
  after insert on public.organizaciones
  for each row execute function privado.crear_flujo_al_crear_organizacion();

-- Relleno: las organizaciones creadas antes de esta migración reciben su flujo.
select privado.crear_flujo_predeterminado(o.id, o.creado_por)
from public.organizaciones o
where not exists (
  select 1
  from public.definiciones_flujo d
  where d.organizacion_id = o.id
    and d.es_predeterminado
);


-- -----------------------------------------------------------------------------
-- 7. RLS y permisos
-- Todos los roles ven los flujos de su organización (matriz: "Ver flujos y
-- reglas"). Nadie escribe directamente: crear borradores y publicar se hará
-- con RPC en una migración posterior.
-- -----------------------------------------------------------------------------
alter table public.definiciones_flujo enable row level security;
alter table public.versiones_flujo enable row level security;
alter table public.estados_version_flujo enable row level security;
alter table public.transiciones_version_flujo enable row level security;

create policy definiciones_flujo_select on public.definiciones_flujo
  for select to authenticated
  using (privado.es_miembro(organizacion_id));

create policy versiones_flujo_select on public.versiones_flujo
  for select to authenticated
  using (privado.es_miembro(organizacion_id));

create policy estados_version_flujo_select on public.estados_version_flujo
  for select to authenticated
  using (privado.es_miembro(organizacion_id));

create policy transiciones_version_flujo_select on public.transiciones_version_flujo
  for select to authenticated
  using (privado.es_miembro(organizacion_id));

revoke all on table
  public.definiciones_flujo,
  public.versiones_flujo,
  public.estados_version_flujo,
  public.transiciones_version_flujo
  from anon, authenticated;

grant select on table
  public.definiciones_flujo,
  public.versiones_flujo,
  public.estados_version_flujo,
  public.transiciones_version_flujo
  to authenticated;

-- PostgreSQL concede execute a PUBLIC en cada función nueva (ADR-0004).
revoke execute on function
  privado.validar_zona_horaria(),
  privado.es_estado_terminal(public.estado_tarea),
  privado.transicion_permitida(uuid, public.estado_tarea, public.estado_tarea),
  privado.proteger_version_flujo(),
  privado.proteger_contenido_version_flujo(),
  privado.crear_flujo_predeterminado(uuid, uuid),
  privado.crear_flujo_al_crear_organizacion()
  from public, anon, authenticated;
