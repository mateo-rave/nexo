-- =============================================================================
-- Migración: definición de reglas de automatización (fase 5, bloque 5.1)
-- Decisión: ADR-0008 · Plan: docs/plans/fase-5-reglas-automatizacion.md
-- Permisos: docs/security/permissions.md · Nombres: ADR-0005
-- Multiempresa: ADR-0002 · Reparto de capas: ADR-0003 · Bloqueos: ADR-0004
--
-- Contenido:
--   1. Tipos: tipo_evento_automatizacion y estado_version_regla.
--   2. Tablas: reglas_automatizacion, versiones_regla y
--      periodos_activacion_regla.
--   3. Validación del catálogo cerrado (ADR-0008): activadores
--      tarea_estado_cambiado y tarea_vencida; condiciones estado_destino,
--      proyecto y con_responsable; acción notificar.
--   4. Triggers: actualizado_en, organizacion_id inmutable, versiones
--      publicadas inmutables y periodos de activación protegidos.
--   5. RPC: crear_regla, guardar_borrador_regla,
--      crear_version_borrador_regla, publicar_version_regla, activar_regla y
--      pausar_regla, con auditoría.
--   6. RLS (solo lectura para miembros) y permisos.
--
-- Las marcas de tiempo que deciden si una regla actúa sobre un evento
-- (publicada_en, activada_en, desactivada_en) usan clock_timestamp(): el
-- instante real de la escritura, que avanza dentro de una transacción. Así el
-- orden entre publicar, activar, pausar y los eventos es el real (ADR-0008,
-- apartado 7). Los eventos, las ejecuciones y el procesamiento programado van
-- en la migración siguiente.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Tipos
-- Los activadores de una regla son los tipos de evento que puede recibir.
-- -----------------------------------------------------------------------------
create type public.tipo_evento_automatizacion as enum ('tarea_estado_cambiado', 'tarea_vencida');

create type public.estado_version_regla as enum ('borrador', 'publicada');


-- -----------------------------------------------------------------------------
-- 2. Tablas
-- Todas llevan organizacion_id y las hijas usan claves foráneas compuestas
-- (ADR-0002). Las reglas no se eliminan en esta fase: los periodos impiden
-- borrar una regla que llegó a activarse.
-- -----------------------------------------------------------------------------

-- Una regla. Si está activa no se guarda aquí: lo dicen sus periodos.
create table public.reglas_automatizacion (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references public.organizaciones (id) on delete cascade,
  nombre text not null,
  creado_por uuid references auth.users (id) on delete set null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint reglas_automatizacion_nombre_valido
    check (nombre = btrim(nombre) and char_length(nombre) between 1 and 100),
  unique (organizacion_id, id)
);

-- Una versión numerada de una regla. Nace como borrador, con una definición
-- ya validada; al publicarse queda inmutable (sección 4).
create table public.versiones_regla (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  regla_id uuid not null,
  numero integer not null,
  estado public.estado_version_regla not null default 'borrador',
  activador public.tipo_evento_automatizacion not null,
  condiciones jsonb not null,
  acciones jsonb not null,
  publicada_en timestamptz,
  creado_por uuid references auth.users (id) on delete set null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  foreign key (organizacion_id, regla_id)
    references public.reglas_automatizacion (organizacion_id, id) on delete cascade,
  constraint versiones_regla_numero_valido check (numero > 0),
  constraint versiones_regla_publicada_en_coherente
    check ((estado = 'publicada') = (publicada_en is not null)),
  unique (regla_id, numero),
  -- Para que una ejecución apunte a una versión de su propia regla.
  unique (regla_id, id),
  unique (organizacion_id, id)
);

-- Un solo borrador por regla.
create unique index versiones_regla_un_borrador_indice
  on public.versiones_regla (organizacion_id, regla_id)
  where estado = 'borrador';

-- Búsqueda de la versión publicada vigente en un instante.
create index versiones_regla_publicadas_indice
  on public.versiones_regla (regla_id, numero)
  where estado = 'publicada';

-- Periodos en los que la regla estuvo o está activa: [activada_en,
-- desactivada_en). Activar inserta un periodo; pausar lo cierra una sola vez.
-- Un periodo cerrado no cambia y ningún periodo se elimina (sección 4).
create table public.periodos_activacion_regla (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  regla_id uuid not null,
  activada_en timestamptz not null,
  desactivada_en timestamptz,
  creado_en timestamptz not null default now(),
  foreign key (organizacion_id, regla_id)
    references public.reglas_automatizacion (organizacion_id, id) on delete restrict,
  -- Un periodo abierto y cerrado en el mismo instante es vacío: no contiene
  -- ningún evento.
  constraint periodos_activacion_regla_fechas_coherentes
    check (desactivada_en is null or desactivada_en >= activada_en),
  unique (organizacion_id, id)
);

-- Como máximo un periodo abierto por regla, aunque dos peticiones lleguen a
-- la vez.
create unique index periodos_activacion_regla_un_abierto_indice
  on public.periodos_activacion_regla (regla_id)
  where desactivada_en is null;

create index periodos_activacion_regla_regla_indice
  on public.periodos_activacion_regla (regla_id, activada_en);


-- -----------------------------------------------------------------------------
-- 3. Validación del catálogo cerrado (ADR-0008)
-- Una definición es un dato, nunca código. Forma esperada:
--   condiciones: lista (0 a 5) de objetos, cada tipo una sola vez:
--     {"tipo": "estado_destino", "estados": ["en_revision", ...]}
--         (1 a 5 estados distintos del catálogo; solo con tarea_estado_cambiado)
--     {"tipo": "proyecto", "proyecto_id": "<uuid de un proyecto de la organización>"}
--     {"tipo": "con_responsable", "valor": true | false}
--   acciones: lista (1 a 3) de objetos:
--     {"tipo": "notificar",
--      "destinatarios": "responsable" | "propietarios_y_administradores"}
-- Se comprueba elemento a elemento y paso a paso (PostgreSQL no garantiza el
-- orden de evaluación dentro de una misma condición), para devolver siempre
-- un error propio y nunca un error interno de conversión.
-- -----------------------------------------------------------------------------

-- 3.1 Activador recibido como texto: un valor desconocido recibe un error
-- propio en vez del error de conversión del enum.
create function privado.activador_de_texto(p_activador text)
returns public.tipo_evento_automatizacion
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_activador is null
     or not (p_activador = any (enum_range(null::public.tipo_evento_automatizacion)::text[])) then
    raise exception using errcode = 'PT400',
      message = 'Ese activador no está en el catálogo.', detail = 'activador_invalido';
  end if;
  return p_activador::public.tipo_evento_automatizacion;
end;
$$;

-- 3.2 Definición completa de una versión.
create function privado.validar_definicion_regla(
  p_organizacion_id uuid,
  p_activador public.tipo_evento_automatizacion,
  p_condiciones jsonb,
  p_acciones jsonb
)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_elemento jsonb;
  v_valor jsonb;
  v_tipo text;
  v_claves text[];
  v_tipos text[] := '{}';
  v_catalogo_estados text[] := enum_range(null::public.estado_tarea)::text[];
  v_texto text;
begin
  if p_activador is null then
    raise exception using errcode = 'PT400',
      message = 'Ese activador no está en el catálogo.', detail = 'activador_invalido';
  end if;

  -- Condiciones
  if p_condiciones is null or jsonb_typeof(p_condiciones) <> 'array' then
    raise exception using errcode = 'PT400',
      message = 'Las condiciones deben ser una lista de condiciones válidas.',
      detail = 'condiciones_invalidas';
  end if;
  if jsonb_array_length(p_condiciones) > 5 then
    raise exception using errcode = 'PT400',
      message = 'Una regla admite como máximo 5 condiciones.', detail = 'demasiadas_condiciones';
  end if;

  for v_elemento in select e.valor from jsonb_array_elements(p_condiciones) e (valor) loop
    if jsonb_typeof(v_elemento) <> 'object' then
      raise exception using errcode = 'PT400',
        message = 'Las condiciones deben ser una lista de condiciones válidas.',
        detail = 'condiciones_invalidas';
    end if;
    if jsonb_typeof(v_elemento -> 'tipo') is distinct from 'string' then
      raise exception using errcode = 'PT400',
        message = 'Las condiciones deben ser una lista de condiciones válidas.',
        detail = 'condiciones_invalidas';
    end if;

    v_tipo := v_elemento ->> 'tipo';
    if not (v_tipo = any (array['estado_destino', 'proyecto', 'con_responsable'])) then
      raise exception using errcode = 'PT400',
        message = 'Esa condición no está en el catálogo.', detail = 'condicion_desconocida';
    end if;
    if v_tipo = any (v_tipos) then
      raise exception using errcode = 'PT400',
        message = 'Cada tipo de condición puede aparecer una sola vez.', detail = 'condicion_repetida';
    end if;
    v_tipos := v_tipos || v_tipo;

    select array_agg(k.clave order by k.clave) into v_claves
    from jsonb_object_keys(v_elemento) k (clave);

    if v_tipo = 'estado_destino' then
      if p_activador <> 'tarea_estado_cambiado' then
        raise exception using errcode = 'PT400',
          message = 'Esa condición no se puede usar con este activador.', detail = 'condicion_no_aplicable';
      end if;
      if v_claves is distinct from array['estados', 'tipo']
         or jsonb_typeof(v_elemento -> 'estados') is distinct from 'array' then
        raise exception using errcode = 'PT400',
          message = 'La condición tiene claves o valores no válidos.', detail = 'condicion_invalida';
      end if;
      if jsonb_array_length(v_elemento -> 'estados') not between 1 and 5 then
        raise exception using errcode = 'PT400',
          message = 'La condición tiene claves o valores no válidos.', detail = 'condicion_invalida';
      end if;
      for v_valor in select e.valor from jsonb_array_elements(v_elemento -> 'estados') e (valor) loop
        if jsonb_typeof(v_valor) <> 'string' then
          raise exception using errcode = 'PT400',
            message = 'La condición tiene claves o valores no válidos.', detail = 'condicion_invalida';
        end if;
        if not ((v_valor #>> '{}') = any (v_catalogo_estados)) then
          raise exception using errcode = 'PT400',
            message = 'La condición tiene claves o valores no válidos.', detail = 'condicion_invalida';
        end if;
      end loop;
      if (select count(distinct e.valor) from jsonb_array_elements_text(v_elemento -> 'estados') e (valor))
         <> jsonb_array_length(v_elemento -> 'estados') then
        raise exception using errcode = 'PT400',
          message = 'La condición tiene claves o valores no válidos.', detail = 'condicion_invalida';
      end if;

    elsif v_tipo = 'proyecto' then
      if v_claves is distinct from array['proyecto_id', 'tipo']
         or jsonb_typeof(v_elemento -> 'proyecto_id') is distinct from 'string' then
        raise exception using errcode = 'PT400',
          message = 'La condición tiene claves o valores no válidos.', detail = 'condicion_invalida';
      end if;
      v_texto := v_elemento ->> 'proyecto_id';
      if v_texto !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
        raise exception using errcode = 'PT400',
          message = 'La condición tiene claves o valores no válidos.', detail = 'condicion_invalida';
      end if;
      if not exists (
        select 1
        from public.proyectos p
        where p.organizacion_id = p_organizacion_id
          and p.id = v_texto::uuid
      ) then
        raise exception using errcode = 'PT400',
          message = 'El proyecto no existe en esta organización.', detail = 'proyecto_invalido';
      end if;

    else
      -- con_responsable
      if v_claves is distinct from array['tipo', 'valor']
         or jsonb_typeof(v_elemento -> 'valor') is distinct from 'boolean' then
        raise exception using errcode = 'PT400',
          message = 'La condición tiene claves o valores no válidos.', detail = 'condicion_invalida';
      end if;
    end if;
  end loop;

  -- Acciones
  if p_acciones is null or jsonb_typeof(p_acciones) <> 'array' then
    raise exception using errcode = 'PT400',
      message = 'Las acciones deben ser una lista de acciones válidas.', detail = 'acciones_invalidas';
  end if;
  if jsonb_array_length(p_acciones) = 0 then
    raise exception using errcode = 'PT400',
      message = 'La regla debe tener al menos una acción.', detail = 'sin_acciones';
  end if;
  if jsonb_array_length(p_acciones) > 3 then
    raise exception using errcode = 'PT400',
      message = 'Una regla admite como máximo 3 acciones.', detail = 'demasiadas_acciones';
  end if;

  for v_elemento in select e.valor from jsonb_array_elements(p_acciones) e (valor) loop
    if jsonb_typeof(v_elemento) <> 'object' then
      raise exception using errcode = 'PT400',
        message = 'Las acciones deben ser una lista de acciones válidas.', detail = 'acciones_invalidas';
    end if;
    if jsonb_typeof(v_elemento -> 'tipo') is distinct from 'string' then
      raise exception using errcode = 'PT400',
        message = 'Las acciones deben ser una lista de acciones válidas.', detail = 'acciones_invalidas';
    end if;
    if (v_elemento ->> 'tipo') <> 'notificar' then
      raise exception using errcode = 'PT400',
        message = 'Esa acción no está en el catálogo.', detail = 'accion_desconocida';
    end if;

    select array_agg(k.clave order by k.clave) into v_claves
    from jsonb_object_keys(v_elemento) k (clave);

    if v_claves is distinct from array['destinatarios', 'tipo']
       or jsonb_typeof(v_elemento -> 'destinatarios') is distinct from 'string' then
      raise exception using errcode = 'PT400',
        message = 'La acción tiene claves o valores no válidos.', detail = 'accion_invalida';
    end if;
    if not ((v_elemento ->> 'destinatarios') = any (array['responsable', 'propietarios_y_administradores'])) then
      raise exception using errcode = 'PT400',
        message = 'La acción tiene claves o valores no válidos.', detail = 'accion_invalida';
    end if;
  end loop;
end;
$$;


-- -----------------------------------------------------------------------------
-- 4. Triggers
-- Protegen también frente a la clave secreta (service_role), que se salta RLS
-- pero no los triggers.
-- -----------------------------------------------------------------------------

-- 4.1 actualizado_en y organizacion_id inmutable (funciones de la migración 1).
create trigger reglas_automatizacion_asignar_actualizado_en
  before update on public.reglas_automatizacion
  for each row execute function privado.asignar_actualizado_en();

create trigger versiones_regla_asignar_actualizado_en
  before update on public.versiones_regla
  for each row execute function privado.asignar_actualizado_en();

create trigger reglas_automatizacion_impedir_cambio_organizacion_id
  before update on public.reglas_automatizacion
  for each row execute function privado.impedir_cambio_organizacion_id();

create trigger versiones_regla_impedir_cambio_organizacion_id
  before update on public.versiones_regla
  for each row execute function privado.impedir_cambio_organizacion_id();

-- 4.2 Versiones: se crean como borrador con una definición válida; solo se
-- publican desde borrador; una publicada no se modifica ni se borra. Fija
-- publicada_en al publicar: el motor decide con ella qué versión aplica a un
-- evento.
create function privado.proteger_version_regla()
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
    perform privado.validar_definicion_regla(new.organizacion_id, new.activador, new.condiciones, new.acciones);
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

  if new.regla_id is distinct from old.regla_id or new.numero is distinct from old.numero then
    raise exception using
      errcode = 'PT400',
      message = 'Una versión no puede cambiar de regla ni de número.',
      detail = 'version_regla_inmutable';
  end if;

  perform privado.validar_definicion_regla(new.organizacion_id, new.activador, new.condiciones, new.acciones);

  if new.estado = 'publicada' then
    new.publicada_en := clock_timestamp();
  end if;

  return new;
end;
$$;

create trigger versiones_regla_proteger
  before insert or update or delete on public.versiones_regla
  for each row execute function privado.proteger_version_regla();

-- 4.3 Periodos de activación (ADR-0008, apartado 7): el único cambio posible
-- es cerrar un periodo abierto, una sola vez; cerrado es inmutable; ningún
-- periodo se elimina ni se trunca.
create function privado.proteger_periodo_activacion_regla()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op in ('DELETE', 'TRUNCATE') then
    raise exception using
      errcode = 'PT409',
      message = 'Los periodos de activación no se pueden eliminar.',
      detail = 'periodo_no_eliminable';
  end if;

  if old.desactivada_en is not null then
    raise exception using
      errcode = 'PT409',
      message = 'Un periodo de activación cerrado no se puede modificar.',
      detail = 'periodo_cerrado_inmutable';
  end if;

  if new.desactivada_en is null
     or new.id is distinct from old.id
     or new.organizacion_id is distinct from old.organizacion_id
     or new.regla_id is distinct from old.regla_id
     or new.activada_en is distinct from old.activada_en
     or new.creado_en is distinct from old.creado_en then
    raise exception using
      errcode = 'PT400',
      message = 'Un periodo de activación solo admite su cierre.',
      detail = 'periodo_cambio_no_permitido';
  end if;

  return new;
end;
$$;

create trigger periodos_activacion_regla_proteger
  before update or delete on public.periodos_activacion_regla
  for each row execute function privado.proteger_periodo_activacion_regla();

create trigger periodos_activacion_regla_impedir_truncate
  before truncate on public.periodos_activacion_regla
  for each statement execute function privado.proteger_periodo_activacion_regla();


-- -----------------------------------------------------------------------------
-- 5. RPC
-- security definer (justificado): authenticated no tiene permisos de
-- escritura en las tablas de reglas ni en auditoria.
-- Autorización: la matriz agrupa "Flujos, reglas y ejecuciones" con los mismos
-- roles, así que se reutiliza privado.autorizar_gestion_flujos (read
-- committed, sesión, propietario o administrador, bloqueo de la organización
-- "for share" y segunda comprobación).
-- Orden de bloqueos: organización ("for share") → regla ("for update") →
-- versión ("for update").
-- -----------------------------------------------------------------------------

-- 5.1 Organización de una regla o de una versión, comprobando que quien llama
-- es miembro. Quien no lo es recibe el mismo error que si no existiera.
create function privado.organizacion_de_regla(p_regla_id uuid)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_organizacion_id uuid;
begin
  select r.organizacion_id into v_organizacion_id
  from public.reglas_automatizacion r
  where r.id = p_regla_id;

  if v_organizacion_id is null or not privado.es_miembro(v_organizacion_id) then
    raise exception using errcode = 'PT404',
      message = 'La regla no existe o no tienes acceso a ella.', detail = 'regla_no_encontrada';
  end if;

  return v_organizacion_id;
end;
$$;

create function privado.organizacion_de_version_regla(p_version_regla_id uuid)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_organizacion_id uuid;
begin
  select v.organizacion_id into v_organizacion_id
  from public.versiones_regla v
  where v.id = p_version_regla_id;

  if v_organizacion_id is null or not privado.es_miembro(v_organizacion_id) then
    raise exception using errcode = 'PT404',
      message = 'La versión de la regla no existe o no tienes acceso a ella.',
      detail = 'version_regla_no_encontrada';
  end if;

  return v_organizacion_id;
end;
$$;

-- 5.2 Crear una regla con su versión 1 en borrador. La definición se valida
-- al insertar la versión (trigger); si no es válida, no se crea nada.
create function public.crear_regla(
  p_organizacion_id uuid,
  p_nombre text,
  p_activador text,
  p_condiciones jsonb,
  p_acciones jsonb
)
returns public.versiones_regla
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_nombre text := btrim(p_nombre);
  v_activador public.tipo_evento_automatizacion;
  v_regla_id uuid;
  v_version public.versiones_regla;
begin
  v_usuario_id := privado.autorizar_gestion_flujos(p_organizacion_id);

  if v_nombre is null or char_length(v_nombre) not between 1 and 100 then
    raise exception using errcode = 'PT400',
      message = 'El nombre debe tener entre 1 y 100 caracteres.', detail = 'nombre_invalido';
  end if;

  v_activador := privado.activador_de_texto(p_activador);

  insert into public.reglas_automatizacion (organizacion_id, nombre, creado_por)
  values (p_organizacion_id, v_nombre, v_usuario_id)
  returning id into v_regla_id;

  insert into public.versiones_regla (
    organizacion_id, regla_id, numero, activador, condiciones, acciones, creado_por
  )
  values (p_organizacion_id, v_regla_id, 1, v_activador, p_condiciones, p_acciones, v_usuario_id)
  returning * into v_version;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    p_organizacion_id, v_usuario_id, 'regla.creada', 'regla', v_regla_id,
    jsonb_build_object('nombre', v_nombre, 'version_regla_id', v_version.id, 'activador', v_activador)
  );

  return v_version;
end;
$$;

-- 5.3 Guardar la definición completa de un borrador.
create function public.guardar_borrador_regla(
  p_version_regla_id uuid,
  p_activador text,
  p_condiciones jsonb,
  p_acciones jsonb
)
returns public.versiones_regla
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_organizacion_id uuid;
  v_activador public.tipo_evento_automatizacion;
  v_version public.versiones_regla;
begin
  v_organizacion_id := privado.organizacion_de_version_regla(p_version_regla_id);
  v_usuario_id := privado.autorizar_gestion_flujos(v_organizacion_id);

  select * into v_version
  from public.versiones_regla v
  where v.id = p_version_regla_id
  for update;

  if v_version.estado = 'publicada' then
    raise exception using errcode = 'PT409',
      message = 'Una versión publicada no se puede modificar ni borrar.',
      detail = 'version_publicada_inmutable';
  end if;

  v_activador := privado.activador_de_texto(p_activador);

  update public.versiones_regla v
  set activador = v_activador, condiciones = p_condiciones, acciones = p_acciones
  where v.id = p_version_regla_id
  returning * into v_version;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    v_organizacion_id, v_usuario_id, 'version_regla.borrador_guardado', 'version_regla', p_version_regla_id,
    jsonb_build_object('regla_id', v_version.regla_id, 'numero', v_version.numero, 'activador', v_activador)
  );

  return v_version;
end;
$$;

-- 5.4 Crear un borrador nuevo copiando una versión publicada de la misma
-- regla. Una regla solo tiene un borrador.
create function public.crear_version_borrador_regla(p_version_regla_id uuid)
returns public.versiones_regla
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_organizacion_id uuid;
  v_origen public.versiones_regla;
  v_numero integer;
  v_version public.versiones_regla;
begin
  v_organizacion_id := privado.organizacion_de_version_regla(p_version_regla_id);
  v_usuario_id := privado.autorizar_gestion_flujos(v_organizacion_id);

  select * into v_origen
  from public.versiones_regla v
  where v.id = p_version_regla_id;

  if v_origen.estado <> 'publicada' then
    raise exception using errcode = 'PT400',
      message = 'Solo se puede copiar una versión publicada.', detail = 'version_no_publicada';
  end if;

  -- Bloquea la regla: dos copias simultáneas no calculan el mismo número.
  perform 1
  from public.reglas_automatizacion r
  where r.organizacion_id = v_organizacion_id
    and r.id = v_origen.regla_id
  for update;

  if exists (
    select 1
    from public.versiones_regla v
    where v.regla_id = v_origen.regla_id
      and v.estado = 'borrador'
  ) then
    raise exception using errcode = 'PT409',
      message = 'Esta regla ya tiene una versión en borrador.', detail = 'borrador_existente';
  end if;

  select max(v.numero) + 1 into v_numero
  from public.versiones_regla v
  where v.regla_id = v_origen.regla_id;

  insert into public.versiones_regla (
    organizacion_id, regla_id, numero, activador, condiciones, acciones, creado_por
  )
  values (
    v_organizacion_id, v_origen.regla_id, v_numero, v_origen.activador,
    v_origen.condiciones, v_origen.acciones, v_usuario_id
  )
  returning * into v_version;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    v_organizacion_id, v_usuario_id, 'version_regla.borrador_creado', 'version_regla', v_version.id,
    jsonb_build_object('regla_id', v_version.regla_id, 'numero', v_numero, 'copiada_de', v_origen.id)
  );

  return v_version;
end;
$$;

-- 5.5 Publicar un borrador. Desde ese momento la versión es inmutable y su
-- publicada_en (fijada por el trigger) decide a qué eventos se aplica.
create function public.publicar_version_regla(p_version_regla_id uuid)
returns public.versiones_regla
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_organizacion_id uuid;
  v_version public.versiones_regla;
begin
  v_organizacion_id := privado.organizacion_de_version_regla(p_version_regla_id);
  v_usuario_id := privado.autorizar_gestion_flujos(v_organizacion_id);

  select * into v_version
  from public.versiones_regla v
  where v.id = p_version_regla_id
  for update;

  if v_version.estado = 'publicada' then
    raise exception using errcode = 'PT409',
      message = 'La versión ya está publicada.', detail = 'version_ya_publicada';
  end if;

  update public.versiones_regla v
  set estado = 'publicada'
  where v.id = p_version_regla_id
  returning * into v_version;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    v_organizacion_id, v_usuario_id, 'version_regla.publicada', 'version_regla', p_version_regla_id,
    jsonb_build_object('regla_id', v_version.regla_id, 'numero', v_version.numero, 'publicada_en', v_version.publicada_en)
  );

  return v_version;
end;
$$;

-- 5.6 Activar una regla: abre un periodo de activación. Exige una versión
-- publicada y que el periodo nuevo no empiece antes del fin del anterior.
create function public.activar_regla(p_regla_id uuid)
returns public.periodos_activacion_regla
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_organizacion_id uuid;
  v_ahora timestamptz;
  v_periodo public.periodos_activacion_regla;
begin
  v_organizacion_id := privado.organizacion_de_regla(p_regla_id);
  v_usuario_id := privado.autorizar_gestion_flujos(v_organizacion_id);

  perform 1
  from public.reglas_automatizacion r
  where r.organizacion_id = v_organizacion_id
    and r.id = p_regla_id
  for update;

  if exists (
    select 1
    from public.periodos_activacion_regla p
    where p.regla_id = p_regla_id
      and p.desactivada_en is null
  ) then
    raise exception using errcode = 'PT409',
      message = 'La regla ya está activa.', detail = 'regla_ya_activa';
  end if;

  if not exists (
    select 1
    from public.versiones_regla v
    where v.regla_id = p_regla_id
      and v.estado = 'publicada'
  ) then
    raise exception using errcode = 'PT409',
      message = 'La regla necesita una versión publicada para activarse.',
      detail = 'regla_sin_version_publicada';
  end if;

  v_ahora := clock_timestamp();

  if exists (
    select 1
    from public.periodos_activacion_regla p
    where p.regla_id = p_regla_id
      and p.desactivada_en > v_ahora
  ) then
    raise exception using errcode = 'PT409',
      message = 'La activación no puede empezar antes del fin del periodo anterior.',
      detail = 'activacion_no_valida';
  end if;

  insert into public.periodos_activacion_regla (organizacion_id, regla_id, activada_en)
  values (v_organizacion_id, p_regla_id, v_ahora)
  returning * into v_periodo;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    v_organizacion_id, v_usuario_id, 'regla.activada', 'regla', p_regla_id,
    jsonb_build_object('periodo_id', v_periodo.id, 'activada_en', v_periodo.activada_en)
  );

  return v_periodo;
end;
$$;

-- 5.7 Pausar una regla: cierra su periodo abierto. No cancela los eventos
-- ocurridos mientras estaba activa (ADR-0008, apartado 7).
create function public.pausar_regla(p_regla_id uuid)
returns public.periodos_activacion_regla
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_organizacion_id uuid;
  v_periodo public.periodos_activacion_regla;
begin
  v_organizacion_id := privado.organizacion_de_regla(p_regla_id);
  v_usuario_id := privado.autorizar_gestion_flujos(v_organizacion_id);

  perform 1
  from public.reglas_automatizacion r
  where r.organizacion_id = v_organizacion_id
    and r.id = p_regla_id
  for update;

  update public.periodos_activacion_regla p
  set desactivada_en = clock_timestamp()
  where p.regla_id = p_regla_id
    and p.desactivada_en is null
  returning * into v_periodo;

  if not found then
    raise exception using errcode = 'PT409',
      message = 'La regla no está activa.', detail = 'regla_no_activa';
  end if;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    v_organizacion_id, v_usuario_id, 'regla.pausada', 'regla', p_regla_id,
    jsonb_build_object('periodo_id', v_periodo.id, 'desactivada_en', v_periodo.desactivada_en)
  );

  return v_periodo;
end;
$$;


-- -----------------------------------------------------------------------------
-- 6. RLS y permisos
-- Todos los miembros ven las reglas de su organización (matriz: "Ver flujos y
-- reglas"). Nadie escribe directamente: solo las RPC de la sección 5.
-- -----------------------------------------------------------------------------
alter table public.reglas_automatizacion enable row level security;
alter table public.versiones_regla enable row level security;
alter table public.periodos_activacion_regla enable row level security;

create policy reglas_automatizacion_select on public.reglas_automatizacion
  for select to authenticated
  using (privado.es_miembro(organizacion_id));

create policy versiones_regla_select on public.versiones_regla
  for select to authenticated
  using (privado.es_miembro(organizacion_id));

create policy periodos_activacion_regla_select on public.periodos_activacion_regla
  for select to authenticated
  using (privado.es_miembro(organizacion_id));

revoke all on table
  public.reglas_automatizacion,
  public.versiones_regla,
  public.periodos_activacion_regla
  from anon, authenticated;

grant select on table
  public.reglas_automatizacion,
  public.versiones_regla,
  public.periodos_activacion_regla
  to authenticated;

-- PostgreSQL concede execute a PUBLIC en cada función nueva (ADR-0004).
revoke execute on function
  privado.activador_de_texto(text),
  privado.validar_definicion_regla(uuid, public.tipo_evento_automatizacion, jsonb, jsonb),
  privado.proteger_version_regla(),
  privado.proteger_periodo_activacion_regla(),
  privado.organizacion_de_regla(uuid),
  privado.organizacion_de_version_regla(uuid)
  from public, anon, authenticated;

revoke execute on function
  public.crear_regla(uuid, text, text, jsonb, jsonb),
  public.guardar_borrador_regla(uuid, text, jsonb, jsonb),
  public.crear_version_borrador_regla(uuid),
  public.publicar_version_regla(uuid),
  public.activar_regla(uuid),
  public.pausar_regla(uuid)
  from public, anon;

grant execute on function
  public.crear_regla(uuid, text, text, jsonb, jsonb),
  public.guardar_borrador_regla(uuid, text, jsonb, jsonb),
  public.crear_version_borrador_regla(uuid),
  public.publicar_version_regla(uuid),
  public.activar_regla(uuid),
  public.pausar_regla(uuid)
  to authenticated;
