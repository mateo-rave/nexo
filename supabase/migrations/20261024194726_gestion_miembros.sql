-- =============================================================================
-- Migración: gestión de miembros (migración 2 de la fase 1)
-- Plan: docs/plans/fase-1-organizaciones-y-membresias.md
-- Permisos: docs/security/permissions.md · Nombres: ADR-0005 · Bloqueos: ADR-0004
--
-- Contenido:
--   1. Funciones auxiliares privadas: exigir read committed y buscar la única
--      cuenta elegible para un correo.
--   2. RPC agregar_miembro, cambiar_rol_miembro, quitar_miembro y
--      salir_de_organizacion.
--
-- No crea tablas, políticas ni triggers: reutiliza los de la migración 1.
-- membresias y auditoria siguen sin permisos de escritura para los usuarios;
-- estas funciones son la única vía para cambiarlas.
--
-- Orden común de las cuatro RPC (diseño aprobado):
--   0. Rechazar cualquier aislamiento distinto de read committed.
--   1. Comprobar la sesión.
--   2. Comprobación preliminar de permiso, sin bloquear y sin buscar al
--      destinatario por correo. Así nadie ajeno bloquea una organización ni
--      averigua qué correos tienen cuenta.
--   3. Bloquear la organización (for no key update), en una instrucción
--      propia. Todas las operaciones sobre miembros de una organización
--      quedan en fila.
--   4. Volver a comprobar el rol de quien llama, en otra instrucción. En read
--      committed cada instrucción ve lo confirmado justo antes, así que se usa
--      el rol actual tras la espera. El "for share" fija esa fila hasta el
--      final de la transacción.
--   5. Validar datos y destinatario (la fila del destinatario, con for update).
--   6. Escribir el cambio y la auditoría en la misma transacción.
--
-- Las RPC se declaran volatile a propósito: una función stable vería una sola
-- foto de la base de datos y el paso 4 no detectaría cambios recientes.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Funciones auxiliares privadas
-- -----------------------------------------------------------------------------

-- 1.1 Las protecciones de concurrencia (paso 4 y la cuenta de propietarios)
-- solo son correctas en read committed: en repeatable read o serializable las
-- consultas verían la foto del inicio de la transacción. La Data API usa read
-- committed; si algo cambia eso, la operación falla en vez de seguir.
create function privado.exigir_read_committed()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception using
      errcode = 'PT500',
      message = 'Esta operación requiere el nivel de aislamiento read committed.',
      detail = 'aislamiento_no_soportado';
  end if;
end;
$$;

-- 1.2 Devuelve el id de la única cuenta elegible para un correo, o null.
-- Elegible: correo confirmado, no anónima, no eliminada, no bloqueada ahora
-- y no SSO. Cualquier otro caso (no existe, no elegible, ambiguo) devuelve
-- null, y quien llama responde con el mismo mensaje genérico.
-- La comparación es exacta sobre el correo normalizado: Supabase Auth guarda
-- los correos en minúsculas y el índice único users_email_partial_key
-- (email) where is_sso_user = false garantiza una sola cuenta no SSO por
-- correo exacto (verificado en nexo-dev el 2026-10-24).
-- Ese índice distingue mayúsculas, así que se rechaza también el caso en que
-- exista otra cuenta no SSO cuyo correo solo difiera en mayúsculas (posible
-- si alguien insertara filas directamente por SQL).
-- security definer: lee auth.users, a la que los usuarios no tienen acceso.
-- Solo la llaman las RPC de esta migración; nadie más tiene execute.
create function privado.buscar_usuario_confirmado(p_correo text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_correo text := lower(btrim(p_correo));
  v_ids uuid[];
begin
  if v_correo is null or v_correo = '' then
    return null;
  end if;

  -- Ambigüedad por mayúsculas: otra cuenta no SSO con el mismo correo salvo
  -- mayúsculas. Se comprueba con cualquier cuenta, sea elegible o no.
  if exists (
    select 1
    from auth.users u
    where lower(u.email) = v_correo
      and u.email <> v_correo
      and u.is_sso_user = false
  ) then
    return null;
  end if;

  -- Defensa adicional: si no sale exactamente una cuenta, no se elige ninguna.
  select array_agg(c.id) into v_ids
  from (
    select u.id
    from auth.users u
    where u.email = v_correo
      and u.is_sso_user = false
      and u.email_confirmed_at is not null
      and u.is_anonymous = false
      and u.deleted_at is null
      and (u.banned_until is null or u.banned_until <= now())
    limit 2
  ) c;

  if coalesce(array_length(v_ids, 1), 0) <> 1 then
    return null;
  end if;

  return v_ids[1];
end;
$$;

revoke execute on function privado.exigir_read_committed() from public, anon, authenticated;
revoke execute on function privado.buscar_usuario_confirmado(text) from public, anon, authenticated;


-- -----------------------------------------------------------------------------
-- 2. RPC de gestión de miembros
-- Todas: security definer (los usuarios no pueden escribir en membresias ni
-- en auditoria), search_path vacío, volatile, execute solo para authenticated.
-- El organizacion_id recibido nunca autoriza nada por sí mismo: el rol se lee
-- siempre de membresias con auth.uid(). Los mensajes de permiso son los mismos
-- exista o no la organización.
-- -----------------------------------------------------------------------------

-- 2.1 agregar_miembro: añade a una persona con cuenta confirmada.
-- propietario: cualquier rol. administrador: solo miembro.
-- El permiso (incluido el rol pedido) se comprueba antes de buscar el correo.
create function public.agregar_miembro(
  p_organizacion_id uuid,
  p_correo text,
  p_rol public.rol_membresia
)
returns table (usuario_id uuid, nombre_visible text, rol public.rol_membresia)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_usuario_id uuid;
  v_rol_actual public.rol_membresia;
  v_destino_id uuid;
begin
  -- 0. Aislamiento
  perform privado.exigir_read_committed();

  -- 1. Sesión
  v_usuario_id := (select auth.uid());
  if v_usuario_id is null then
    raise exception using errcode = 'PT401',
      message = 'Debes iniciar sesión.', detail = 'sesion_requerida';
  end if;

  -- 2. Comprobación preliminar (sin bloqueo y sin mirar el correo)
  select m.rol into v_rol_actual
  from public.membresias m
  where m.organizacion_id = p_organizacion_id
    and m.usuario_id = v_usuario_id;

  if v_rol_actual is null or v_rol_actual not in ('propietario', 'administrador') then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;
  if v_rol_actual = 'administrador' and p_rol is distinct from 'miembro' then
    raise exception using errcode = 'PT403',
      message = 'Tu rol no permite asignar o gestionar ese rol.',
      detail = 'rol_no_permitido';
  end if;

  -- 3. Bloqueo de la organización
  perform 1
  from public.organizaciones o
  where o.id = p_organizacion_id
  for no key update;

  if not found then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  -- 4. Segunda comprobación, con el rol actual tras la espera
  v_rol_actual := null;
  select m.rol into v_rol_actual
  from public.membresias m
  where m.organizacion_id = p_organizacion_id
    and m.usuario_id = v_usuario_id
  for share;

  if v_rol_actual is null or v_rol_actual not in ('propietario', 'administrador') then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;
  if v_rol_actual = 'administrador' and p_rol is distinct from 'miembro' then
    raise exception using errcode = 'PT403',
      message = 'Tu rol no permite asignar o gestionar ese rol.',
      detail = 'rol_no_permitido';
  end if;

  -- 5. Datos y destinatario
  if p_rol is null then
    raise exception using errcode = 'PT400',
      message = 'Debes indicar un rol válido.', detail = 'rol_invalido';
  end if;
  if p_correo is null or btrim(p_correo) = '' or char_length(btrim(p_correo)) > 320 then
    raise exception using errcode = 'PT400',
      message = 'Debes indicar un correo válido.', detail = 'correo_invalido';
  end if;

  v_destino_id := privado.buscar_usuario_confirmado(p_correo);
  if v_destino_id is null then
    raise exception using errcode = 'PT400',
      message = 'No se pudo añadir a esta persona.', detail = 'usuario_no_disponible';
  end if;

  if exists (
    select 1
    from public.membresias m
    where m.organizacion_id = p_organizacion_id
      and m.usuario_id = v_destino_id
  ) then
    raise exception using errcode = 'PT409',
      message = 'Esta persona ya es miembro de la organización.', detail = 'ya_es_miembro';
  end if;

  -- 6. Escritura y auditoría
  begin
    insert into public.membresias (organizacion_id, usuario_id, rol)
    values (p_organizacion_id, v_destino_id, p_rol);
  exception
    -- Una segunda alta simultánea de la misma persona (la clave primaria lo
    -- impide aunque el bloqueo fallara).
    when unique_violation then
      raise exception using errcode = 'PT409',
        message = 'Esta persona ya es miembro de la organización.', detail = 'ya_es_miembro';
    -- La cuenta se borró entre la búsqueda y la inserción: mismo mensaje
    -- genérico, sin mostrar el nombre de la restricción.
    when foreign_key_violation then
      raise exception using errcode = 'PT400',
        message = 'No se pudo añadir a esta persona.', detail = 'usuario_no_disponible';
  end;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    p_organizacion_id,
    v_usuario_id,
    'miembro.agregado',
    'membresia',
    v_destino_id,
    jsonb_build_object('rol', p_rol)
  );

  -- Devuelve id, nombre visible y rol; nunca el correo.
  return query
  select p.id, p.nombre_visible, p_rol
  from public.perfiles p
  where p.id = v_destino_id;
end;
$$;

-- 2.2 cambiar_rol_miembro: solo propietario. Puede cambiar su propio rol (D2)
-- si queda otro propietario.
create function public.cambiar_rol_miembro(
  p_organizacion_id uuid,
  p_usuario_id uuid,
  p_rol public.rol_membresia
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_rol_actual public.rol_membresia;
  v_rol_destino public.rol_membresia;
begin
  -- 0. Aislamiento
  perform privado.exigir_read_committed();

  -- 1. Sesión
  v_usuario_id := (select auth.uid());
  if v_usuario_id is null then
    raise exception using errcode = 'PT401',
      message = 'Debes iniciar sesión.', detail = 'sesion_requerida';
  end if;

  -- 2. Comprobación preliminar
  select m.rol into v_rol_actual
  from public.membresias m
  where m.organizacion_id = p_organizacion_id
    and m.usuario_id = v_usuario_id;

  if v_rol_actual is distinct from 'propietario' then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  -- 3. Bloqueo de la organización
  perform 1
  from public.organizaciones o
  where o.id = p_organizacion_id
  for no key update;

  if not found then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  -- 4. Segunda comprobación, con el rol actual tras la espera
  v_rol_actual := null;
  select m.rol into v_rol_actual
  from public.membresias m
  where m.organizacion_id = p_organizacion_id
    and m.usuario_id = v_usuario_id
  for share;

  if v_rol_actual is distinct from 'propietario' then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  -- 5. Datos y destinatario
  if p_rol is null then
    raise exception using errcode = 'PT400',
      message = 'Debes indicar un rol válido.', detail = 'rol_invalido';
  end if;

  select m.rol into v_rol_destino
  from public.membresias m
  where m.organizacion_id = p_organizacion_id
    and m.usuario_id = p_usuario_id
  for update;

  if v_rol_destino is null then
    raise exception using errcode = 'PT404',
      message = 'Esa persona no es miembro de la organización.', detail = 'miembro_no_encontrado';
  end if;
  if v_rol_destino = p_rol then
    raise exception using errcode = 'PT409',
      message = 'La persona ya tiene ese rol.', detail = 'rol_sin_cambios';
  end if;
  if v_rol_destino = 'propietario' and not exists (
    select 1
    from public.membresias m
    where m.organizacion_id = p_organizacion_id
      and m.rol = 'propietario'
      and m.usuario_id <> p_usuario_id
  ) then
    raise exception using errcode = 'PT409',
      message = 'La organización debe tener al menos un propietario.', detail = 'ultimo_propietario';
  end if;

  -- 6. Escritura y auditoría (el trigger exigir_propietario sigue de respaldo)
  update public.membresias m
  set rol = p_rol
  where m.organizacion_id = p_organizacion_id
    and m.usuario_id = p_usuario_id;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    p_organizacion_id,
    v_usuario_id,
    'miembro.rol_cambiado',
    'membresia',
    p_usuario_id,
    jsonb_build_object('rol_anterior', v_rol_destino, 'rol_nuevo', p_rol)
  );
end;
$$;

-- 2.3 quitar_miembro: propietario quita a cualquiera (incluido otro
-- propietario, D6); administrador solo a miembro. Nadie se quita a sí mismo
-- por esta vía (D3): para eso está salir_de_organizacion.
create function public.quitar_miembro(
  p_organizacion_id uuid,
  p_usuario_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_rol_actual public.rol_membresia;
  v_rol_destino public.rol_membresia;
begin
  -- 0. Aislamiento
  perform privado.exigir_read_committed();

  -- 1. Sesión
  v_usuario_id := (select auth.uid());
  if v_usuario_id is null then
    raise exception using errcode = 'PT401',
      message = 'Debes iniciar sesión.', detail = 'sesion_requerida';
  end if;

  -- 2. Comprobación preliminar
  select m.rol into v_rol_actual
  from public.membresias m
  where m.organizacion_id = p_organizacion_id
    and m.usuario_id = v_usuario_id;

  if v_rol_actual is null or v_rol_actual not in ('propietario', 'administrador') then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  -- 3. Bloqueo de la organización
  perform 1
  from public.organizaciones o
  where o.id = p_organizacion_id
  for no key update;

  if not found then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  -- 4. Segunda comprobación, con el rol actual tras la espera
  v_rol_actual := null;
  select m.rol into v_rol_actual
  from public.membresias m
  where m.organizacion_id = p_organizacion_id
    and m.usuario_id = v_usuario_id
  for share;

  if v_rol_actual is null or v_rol_actual not in ('propietario', 'administrador') then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  -- 5. Datos y destinatario
  if p_usuario_id = v_usuario_id then
    raise exception using errcode = 'PT400',
      message = 'Para salir de la organización usa salir_de_organizacion.',
      detail = 'accion_no_permitida';
  end if;

  select m.rol into v_rol_destino
  from public.membresias m
  where m.organizacion_id = p_organizacion_id
    and m.usuario_id = p_usuario_id
  for update;

  if v_rol_destino is null then
    raise exception using errcode = 'PT404',
      message = 'Esa persona no es miembro de la organización.', detail = 'miembro_no_encontrado';
  end if;
  if v_rol_actual = 'administrador' and v_rol_destino <> 'miembro' then
    raise exception using errcode = 'PT403',
      message = 'Tu rol no permite asignar o gestionar ese rol.',
      detail = 'rol_no_permitido';
  end if;
  -- Defensivo: con D3 quien llama sigue siendo propietario, así que el
  -- destinatario nunca es el último; el trigger exigir_propietario también lo
  -- impediría.
  if v_rol_destino = 'propietario' and not exists (
    select 1
    from public.membresias m
    where m.organizacion_id = p_organizacion_id
      and m.rol = 'propietario'
      and m.usuario_id <> p_usuario_id
  ) then
    raise exception using errcode = 'PT409',
      message = 'La organización debe tener al menos un propietario.', detail = 'ultimo_propietario';
  end if;

  -- 6. Escritura y auditoría
  delete from public.membresias m
  where m.organizacion_id = p_organizacion_id
    and m.usuario_id = p_usuario_id;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    p_organizacion_id,
    v_usuario_id,
    'miembro.quitado',
    'membresia',
    p_usuario_id,
    jsonb_build_object('rol', v_rol_destino)
  );
end;
$$;

-- 2.4 salir_de_organizacion: cualquier miembro, salvo el último propietario.
create function public.salir_de_organizacion(p_organizacion_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_rol_actual public.rol_membresia;
begin
  -- 0. Aislamiento
  perform privado.exigir_read_committed();

  -- 1. Sesión
  v_usuario_id := (select auth.uid());
  if v_usuario_id is null then
    raise exception using errcode = 'PT401',
      message = 'Debes iniciar sesión.', detail = 'sesion_requerida';
  end if;

  -- 2. Comprobación preliminar: basta con ser miembro
  select m.rol into v_rol_actual
  from public.membresias m
  where m.organizacion_id = p_organizacion_id
    and m.usuario_id = v_usuario_id;

  if v_rol_actual is null then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  -- 3. Bloqueo de la organización
  perform 1
  from public.organizaciones o
  where o.id = p_organizacion_id
  for no key update;

  if not found then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  -- 4. Segunda comprobación, con el rol actual tras la espera
  v_rol_actual := null;
  select m.rol into v_rol_actual
  from public.membresias m
  where m.organizacion_id = p_organizacion_id
    and m.usuario_id = v_usuario_id
  for share;

  if v_rol_actual is null then
    raise exception using errcode = 'PT403',
      message = 'No tienes permiso para realizar esta acción en esta organización.',
      detail = 'permiso_denegado';
  end if;

  -- 5. El último propietario no puede salir
  if v_rol_actual = 'propietario' and not exists (
    select 1
    from public.membresias m
    where m.organizacion_id = p_organizacion_id
      and m.rol = 'propietario'
      and m.usuario_id <> v_usuario_id
  ) then
    raise exception using errcode = 'PT409',
      message = 'La organización debe tener al menos un propietario.', detail = 'ultimo_propietario';
  end if;

  -- 6. Escritura y auditoría
  delete from public.membresias m
  where m.organizacion_id = p_organizacion_id
    and m.usuario_id = v_usuario_id;

  insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles)
  values (
    p_organizacion_id,
    v_usuario_id,
    'miembro.salio',
    'membresia',
    v_usuario_id,
    jsonb_build_object('rol', v_rol_actual)
  );
end;
$$;

-- PostgreSQL concede execute a PUBLIC en cada función nueva (ADR-0004).
revoke execute on function
  public.agregar_miembro(uuid, text, public.rol_membresia),
  public.cambiar_rol_miembro(uuid, uuid, public.rol_membresia),
  public.quitar_miembro(uuid, uuid),
  public.salir_de_organizacion(uuid)
  from public, anon;
grant execute on function
  public.agregar_miembro(uuid, text, public.rol_membresia),
  public.cambiar_rol_miembro(uuid, uuid, public.rol_membresia),
  public.quitar_miembro(uuid, uuid),
  public.salir_de_organizacion(uuid)
  to authenticated;
