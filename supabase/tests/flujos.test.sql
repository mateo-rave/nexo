-- Flujos versionados y zona horaria (fase 2, bloque 1; ADR-0007):
-- flujo predeterminado de cada organización, transiciones, inmutabilidad de
-- las versiones publicadas, validación de la publicación, claves foráneas
-- compuestas, RLS de solo lectura y validación de la zona horaria.
begin;
create extension if not exists pgtap with schema extensions;
select plan(48);

-- Datos sintéticos (como postgres, sin RLS). Insertar las organizaciones
-- dispara el trigger que crea su flujo predeterminado.
-- 1111 propietario_a · 2222 administrador_a · 3333 miembro_a
-- 4444 propietario_b · 5555 sin_membresia · aaaa organización A · bbbb B
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'propietario_a@example.com', now(), '{"nombre_visible": "Propietario A"}'),
  ('22222222-2222-2222-2222-222222222222', 'administrador_a@example.com', now(), '{"nombre_visible": "Administrador A"}'),
  ('33333333-3333-3333-3333-333333333333', 'miembro_a@example.com', now(), '{"nombre_visible": "Miembro A"}'),
  ('44444444-4444-4444-4444-444444444444', 'propietario_b@example.com', now(), '{"nombre_visible": "Propietario B"}'),
  ('55555555-5555-5555-5555-555555555555', 'sin_membresia@example.com', now(), '{"nombre_visible": "Sin Membresia"}');

insert into public.organizaciones (id, nombre, creado_por) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Organizacion A', '11111111-1111-1111-1111-111111111111'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Organizacion B', '44444444-4444-4444-4444-444444444444');

insert into public.membresias (organizacion_id, usuario_id, rol) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'propietario'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'administrador'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'miembro'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '44444444-4444-4444-4444-444444444444', 'propietario');

-- -----------------------------------------------------------------------------
-- Flujo predeterminado
-- -----------------------------------------------------------------------------
select results_eq(
  $$select organizacion_id from public.definiciones_flujo
    where es_predeterminado
      and organizacion_id in ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
    order by organizacion_id$$,
  array['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb']::uuid[],
  'cada organización nueva tiene exactamente un flujo predeterminado'
);

select results_eq(
  $$select numero || ':' || estado::text || ':' || estado_inicial::text
    from public.versiones_flujo
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  array['1:publicada:pendiente'],
  'el flujo predeterminado tiene una versión 1 publicada que empieza en pendiente'
);

select ok(
  (select publicada_en is not null from public.versiones_flujo
   where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'la versión publicada registra cuándo se publicó'
);

select set_eq(
  $$select estado::text from public.estados_version_flujo
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  array['pendiente', 'en_curso', 'en_revision', 'completada', 'cancelada'],
  'el flujo predeterminado usa los cinco estados del catálogo'
);

select set_eq(
  $$select estado_origen::text || '>' || estado_destino::text
    from public.transiciones_version_flujo
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  array[
    'pendiente>en_curso', 'pendiente>cancelada',
    'en_curso>en_revision', 'en_curso>cancelada',
    'en_revision>en_curso', 'en_revision>completada', 'en_revision>cancelada',
    'completada>en_curso'
  ],
  'el flujo predeterminado tiene exactamente las ocho transiciones aprobadas'
);

select results_eq(
  $$select zona_horaria from public.organizaciones where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  array['America/Bogota'],
  'la zona horaria por defecto es America/Bogota'
);

-- -----------------------------------------------------------------------------
-- Funciones internas
-- -----------------------------------------------------------------------------
select ok(
  privado.transicion_permitida(
    (select id from public.versiones_flujo where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    'pendiente', 'en_curso'),
  'transicion_permitida acepta pendiente → en_curso'
);

select ok(
  not privado.transicion_permitida(
    (select id from public.versiones_flujo where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    'pendiente', 'completada'),
  'transicion_permitida rechaza saltarse estados (pendiente → completada)'
);

select ok(
  not privado.transicion_permitida(
    (select id from public.versiones_flujo where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    'cancelada', 'en_curso'),
  'cancelada no tiene transiciones de salida'
);

select ok(
  privado.transicion_permitida(
    (select id from public.versiones_flujo where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    'completada', 'en_curso'),
  'una tarea completada se puede reabrir (completada → en_curso)'
);

select ok(
  privado.es_estado_terminal('completada')
    and privado.es_estado_terminal('cancelada')
    and not privado.es_estado_terminal('pendiente')
    and not privado.es_estado_terminal('en_curso')
    and not privado.es_estado_terminal('en_revision'),
  'solo completada y cancelada son terminales'
);

-- -----------------------------------------------------------------------------
-- Versiones publicadas inmutables (como postgres: los triggers protegen
-- incluso frente a roles que se saltan RLS)
-- -----------------------------------------------------------------------------
select throws_ok(
  $$update public.versiones_flujo set estado_inicial = 'en_curso'
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and numero = 1$$,
  'PT409', null,
  'una versión publicada no se puede modificar'
);

select throws_ok(
  $$delete from public.versiones_flujo
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and numero = 1$$,
  'PT409', null,
  'una versión publicada no se puede borrar'
);

select throws_ok(
  $$insert into public.transiciones_version_flujo (organizacion_id, version_flujo_id, estado_origen, estado_destino)
    select organizacion_id, id, 'pendiente', 'en_revision' from public.versiones_flujo
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and numero = 1$$,
  'PT409', null,
  'no se pueden añadir transiciones a una versión publicada'
);

select throws_ok(
  $$delete from public.estados_version_flujo
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and estado = 'en_revision'$$,
  'PT409', null,
  'no se pueden quitar estados de una versión publicada'
);

select throws_ok(
  $$insert into public.versiones_flujo (organizacion_id, definicion_flujo_id, numero, estado, estado_inicial)
    select organizacion_id, id, 9, 'publicada', 'pendiente' from public.definiciones_flujo
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and es_predeterminado$$,
  'PT400', null,
  'una versión no puede crearse directamente como publicada'
);

-- -----------------------------------------------------------------------------
-- Publicación validada de un borrador
-- -----------------------------------------------------------------------------
select lives_ok(
  $$insert into public.versiones_flujo (id, organizacion_id, definicion_flujo_id, numero, estado_inicial)
    select 'd2d2d2d2-0000-0000-0000-000000000002', organizacion_id, id, 2, 'en_curso'
    from public.definiciones_flujo
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and es_predeterminado$$,
  'se puede crear una versión en borrador'
);

select lives_ok(
  $$insert into public.estados_version_flujo (organizacion_id, version_flujo_id, estado)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'd2d2d2d2-0000-0000-0000-000000000002', 'en_curso')$$,
  'se pueden añadir estados a un borrador'
);

select throws_ok(
  $$update public.versiones_flujo set estado = 'publicada'
    where id = 'd2d2d2d2-0000-0000-0000-000000000002'$$,
  'PT400', null,
  'no se publica una versión sin estado terminal'
);

update public.versiones_flujo set estado_inicial = 'pendiente'
  where id = 'd2d2d2d2-0000-0000-0000-000000000002';
insert into public.estados_version_flujo (organizacion_id, version_flujo_id, estado)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'd2d2d2d2-0000-0000-0000-000000000002', 'completada');

select throws_ok(
  $$update public.versiones_flujo set estado = 'publicada'
    where id = 'd2d2d2d2-0000-0000-0000-000000000002'$$,
  'PT400', null,
  'no se publica una versión cuyo estado inicial no está entre sus estados'
);

insert into public.estados_version_flujo (organizacion_id, version_flujo_id, estado)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'd2d2d2d2-0000-0000-0000-000000000002', 'pendiente');

select lives_ok(
  $$update public.versiones_flujo set estado = 'publicada'
    where id = 'd2d2d2d2-0000-0000-0000-000000000002'$$,
  'una versión válida se publica'
);

select throws_ok(
  $$insert into public.versiones_flujo (organizacion_id, definicion_flujo_id, numero, estado_inicial)
    select organizacion_id, id, 3, 'cancelada' from public.definiciones_flujo
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and es_predeterminado$$,
  '23514', null,
  'el estado inicial no puede ser terminal'
);

-- -----------------------------------------------------------------------------
-- Claves foráneas compuestas e invariantes entre organizaciones
-- -----------------------------------------------------------------------------
insert into public.versiones_flujo (id, organizacion_id, definicion_flujo_id, numero, estado_inicial)
  select 'd3d3d3d3-0000-0000-0000-000000000003', organizacion_id, id, 3, 'pendiente'
  from public.definiciones_flujo
  where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and es_predeterminado;

select throws_ok(
  $$insert into public.versiones_flujo (organizacion_id, definicion_flujo_id, numero, estado_inicial)
    select 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', id, 4, 'pendiente' from public.definiciones_flujo
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and es_predeterminado$$,
  '23503', null,
  'una versión de B no puede pertenecer a un flujo de A'
);

select throws_ok(
  $$insert into public.estados_version_flujo (organizacion_id, version_flujo_id, estado)
    values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'd3d3d3d3-0000-0000-0000-000000000003', 'pendiente')$$,
  '23503', null,
  'un estado de B no puede colgar de una versión de A'
);

select throws_ok(
  $$update public.definiciones_flujo set organizacion_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'PT400', null,
  'un flujo no puede cambiar de organización'
);

select throws_ok(
  $$insert into public.definiciones_flujo (organizacion_id, nombre, es_predeterminado)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Otro predeterminado', true)$$,
  '23505', null,
  'una organización no puede tener dos flujos predeterminados'
);

-- -----------------------------------------------------------------------------
-- RLS: lectura solo para miembros de la organización
-- -----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';

select results_eq(
  $$select count(*)::int from public.definiciones_flujo$$,
  array[1],
  'miembro_a ve el flujo de A y ninguno más'
);

select is_empty(
  $$select id from public.versiones_flujo where organizacion_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'$$,
  'miembro_a no ve las versiones de B'
);

select results_eq(
  $$select count(*)::int from public.transiciones_version_flujo$$,
  array[8],
  'miembro_a ve las transiciones de A (las de B no)'
);

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';

select is_empty(
  $$select id from public.definiciones_flujo where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'propietario_b no ve los flujos de A'
);

select is_empty(
  $$select id from public.versiones_flujo where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'propietario_b no ve las versiones de A'
);

select is_empty(
  $$select estado from public.estados_version_flujo where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'propietario_b no ve los estados de las versiones de A'
);

select is_empty(
  $$select estado_origen from public.transiciones_version_flujo where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'propietario_b no ve las transiciones de A'
);

set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';

select is_empty(
  $$select id from public.definiciones_flujo$$,
  'sin_membresia no ve ningún flujo'
);

select is_empty(
  $$select estado_origen from public.transiciones_version_flujo$$,
  'sin_membresia no ve ninguna transición'
);

-- Nadie escribe directamente, ni siquiera el propietario
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select throws_ok(
  $$insert into public.definiciones_flujo (organizacion_id, nombre)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Flujo propio')$$,
  '42501', null,
  'propietario_a no puede crear flujos directamente'
);

select throws_ok(
  $$update public.versiones_flujo set numero = 99
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  '42501', null,
  'propietario_a no puede editar versiones directamente'
);

select throws_ok(
  $$delete from public.transiciones_version_flujo
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  '42501', null,
  'propietario_a no puede borrar transiciones directamente'
);

select ok(
  not has_column_privilege('authenticated', 'public.organizaciones', 'zona_horaria', 'update'),
  'authenticated no puede cambiar la zona horaria por la Data API'
);

set local role anon;
select throws_ok(
  $$select id from public.definiciones_flujo$$,
  '42501', null,
  'anon no puede leer los flujos'
);

-- -----------------------------------------------------------------------------
-- crear_organizacion: el contrato no cambia y la organización nace con su flujo
-- -----------------------------------------------------------------------------
reset role;
set local role authenticated;
set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';

select results_eq(
  $$select zona_horaria from public.crear_organizacion('Agencia Con Flujo')$$,
  array['America/Bogota'],
  'crear_organizacion devuelve también la zona horaria por defecto'
);

select results_eq(
  $$select d.nombre from public.definiciones_flujo d
    join public.organizaciones o on o.id = d.organizacion_id
    where o.nombre = 'Agencia Con Flujo' and d.es_predeterminado$$,
  array['Flujo predeterminado'],
  'la organización creada con la RPC tiene su flujo predeterminado y quien la crea lo ve'
);

select results_eq(
  $$select v.estado::text from public.versiones_flujo v
    join public.organizaciones o on o.id = v.organizacion_id
    where o.nombre = 'Agencia Con Flujo'$$,
  array['publicada'],
  'su versión predeterminada está publicada'
);

select results_eq(
  $$select a.accion from public.auditoria a
    join public.organizaciones o on o.id = a.organizacion_id
    where o.nombre = 'Agencia Con Flujo'$$,
  array['organizacion.creada'],
  'la creación automática del flujo no añade registros de auditoría'
);

-- -----------------------------------------------------------------------------
-- Validación de la zona horaria
-- -----------------------------------------------------------------------------
reset role;

select throws_ok(
  $$update public.organizaciones set zona_horaria = 'Marte/Olimpo'
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'PT400', null,
  'una zona horaria inexistente se rechaza'
);

select throws_ok(
  $$update public.organizaciones set zona_horaria = 'posix/America/Bogota'
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'PT400', null,
  'los alias posix/ se rechazan'
);

select lives_ok(
  $$update public.organizaciones set zona_horaria = 'America/Mexico_City'
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'una zona horaria válida se acepta'
);

select throws_ok(
  $$insert into public.organizaciones (nombre, zona_horaria) values ('Zona Mala', 'Nada/Nada')$$,
  'PT400', null,
  'una organización no puede crearse con una zona horaria inválida'
);

select * from finish();
rollback;
