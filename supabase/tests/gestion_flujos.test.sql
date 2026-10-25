-- Gestión de flujos personalizados (fase 2, bloque 4; ADR-0007): crear un
-- flujo, guardar su borrador de forma atómica, publicarlo, copiar una versión
-- publicada a un borrador nuevo, permisos de la matriz, auditoría,
-- inmutabilidad, uso en proyectos y aislamiento entre organizaciones.
begin;
create extension if not exists pgtap with schema extensions;
select plan(50);

-- Datos sintéticos (como postgres, sin RLS).
-- 1111 propietario_a · 2222 administrador_a · 3333 miembro_a
-- 4444 propietario_b · aaaa organización A · bbbb B
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'propietario_a@example.com', now(), '{"nombre_visible": "Propietario A"}'),
  ('22222222-2222-2222-2222-222222222222', 'administrador_a@example.com', now(), '{"nombre_visible": "Administrador A"}'),
  ('33333333-3333-3333-3333-333333333333', 'miembro_a@example.com', now(), '{"nombre_visible": "Miembro A"}'),
  ('44444444-4444-4444-4444-444444444444', 'propietario_b@example.com', now(), '{"nombre_visible": "Propietario B"}');

insert into public.organizaciones (id, nombre, creado_por) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Organizacion A', '11111111-1111-1111-1111-111111111111'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Organizacion B', '44444444-4444-4444-4444-444444444444');

insert into public.membresias (organizacion_id, usuario_id, rol) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'propietario'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'administrador'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'miembro'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '44444444-4444-4444-4444-444444444444', 'propietario');

-- -----------------------------------------------------------------------------
-- crear_flujo
-- -----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select results_eq(
  $$select numero || ':' || estado::text from public.crear_flujo('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '  Diseño  ')$$,
  array['1:borrador'],
  'administrador_a crea un flujo con su versión 1 en borrador'
);

select ok(
  (select not es_predeterminado from public.definiciones_flujo where nombre = 'Diseño'),
  'el flujo creado no es el predeterminado y su nombre se guarda sin espacios sobrantes'
);

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select public.crear_flujo('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'No')$$,
  'PT403', null,
  'miembro_a no puede crear flujos'
);

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$select public.crear_flujo('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Intruso')$$,
  'PT403', null,
  'propietario_b no puede crear flujos en A'
);

set local role anon;
select throws_ok(
  $$select public.crear_flujo('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Anonimo')$$,
  '42501', null,
  'anon no puede ejecutar crear_flujo'
);

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select throws_ok(
  $$select public.crear_flujo('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '   ')$$,
  'PT400', null,
  'un nombre vacío se rechaza'
);

-- -----------------------------------------------------------------------------
-- guardar_borrador_flujo: reemplazo atómico y validaciones
-- -----------------------------------------------------------------------------
select lives_ok(
  $$select public.guardar_borrador_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1),
      array['pendiente', 'en_curso', 'completada']::public.estado_tarea[], 'pendiente',
      '[{"origen": "pendiente", "destino": "en_curso"}, {"origen": "en_curso", "destino": "completada"}]')$$,
  'administrador_a guarda estados, estado inicial y transiciones del borrador'
);

select set_eq(
  $$select e.estado::text from public.estados_version_flujo e
    join public.versiones_flujo v on v.id = e.version_flujo_id
    join public.definiciones_flujo d on d.id = v.definicion_flujo_id
    where d.nombre = 'Diseño' and v.numero = 1$$,
  array['pendiente', 'en_curso', 'completada'],
  'el borrador tiene los estados guardados'
);

select set_eq(
  $$select t.estado_origen::text || '>' || t.estado_destino::text from public.transiciones_version_flujo t
    join public.versiones_flujo v on v.id = t.version_flujo_id
    join public.definiciones_flujo d on d.id = v.definicion_flujo_id
    where d.nombre = 'Diseño' and v.numero = 1$$,
  array['pendiente>en_curso', 'en_curso>completada'],
  'el borrador tiene las transiciones guardadas'
);

select lives_ok(
  $$select public.guardar_borrador_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1),
      array['pendiente', 'completada', 'cancelada']::public.estado_tarea[], 'pendiente',
      '[{"origen": "pendiente", "destino": "completada"}, {"origen": "pendiente", "destino": "cancelada"}]')$$,
  'guardar otra vez reemplaza todo el contenido'
);

select set_eq(
  $$select t.estado_origen::text || '>' || t.estado_destino::text from public.transiciones_version_flujo t
    join public.versiones_flujo v on v.id = t.version_flujo_id
    join public.definiciones_flujo d on d.id = v.definicion_flujo_id
    where d.nombre = 'Diseño' and v.numero = 1$$,
  array['pendiente>completada', 'pendiente>cancelada'],
  'las transiciones anteriores se sustituyen'
);

select set_eq(
  $$select e.estado::text from public.estados_version_flujo e
    join public.versiones_flujo v on v.id = e.version_flujo_id
    join public.definiciones_flujo d on d.id = v.definicion_flujo_id
    where d.nombre = 'Diseño' and v.numero = 1$$,
  array['pendiente', 'completada', 'cancelada'],
  'los estados anteriores se sustituyen'
);

select throws_ok(
  $$select public.guardar_borrador_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1),
      array['pendiente', 'completada']::public.estado_tarea[], 'en_curso', '[]')$$,
  'PT400', null,
  'el estado inicial debe estar entre los estados'
);

select throws_ok(
  $$select public.guardar_borrador_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1),
      array['pendiente', 'completada']::public.estado_tarea[], 'completada', '[]')$$,
  'PT400', null,
  'el estado inicial no puede ser terminal'
);

select throws_ok(
  $$select public.guardar_borrador_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1),
      array['pendiente', 'en_curso']::public.estado_tarea[], 'pendiente', '[]')$$,
  'PT400', null,
  'la versión debe incluir un estado terminal'
);

select throws_ok(
  $$select public.guardar_borrador_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1),
      array['pendiente', 'completada']::public.estado_tarea[], 'pendiente',
      '[{"origen": "pendiente", "destino": "en_revision"}]')$$,
  'PT400', null,
  'una transición hacia un estado que no está en la versión se rechaza'
);

select throws_ok(
  $$select public.guardar_borrador_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1),
      array['pendiente', 'completada']::public.estado_tarea[], 'pendiente',
      '[{"origen": "pendiente", "destino": "pendiente"}]')$$,
  'PT400', null,
  'una transición de un estado a sí mismo se rechaza'
);

select throws_ok(
  $$select public.guardar_borrador_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1),
      array['pendiente', 'completada']::public.estado_tarea[], 'pendiente',
      '{"origen": "pendiente", "destino": "completada"}')$$,
  'PT400', null,
  'las transiciones deben ser una lista'
);

select throws_ok(
  $$select public.guardar_borrador_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1),
      array['pendiente', 'completada']::public.estado_tarea[], 'pendiente',
      '[{"origen": "pendiente"}]')$$,
  'PT400', null,
  'cada transición necesita origen y destino'
);

select throws_ok(
  $$select public.guardar_borrador_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1),
      array['pendiente', 'completada']::public.estado_tarea[], 'pendiente',
      '[{"origen": "pendiente", "destino": "inexistente"}]')$$,
  'PT400', null,
  'un estado que no existe en el catálogo se rechaza'
);

select throws_ok(
  $$select public.guardar_borrador_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1),
      array['pendiente', 'completada']::public.estado_tarea[], 'pendiente', '["pendiente"]')$$,
  'PT400', null,
  'cada transición debe ser un objeto'
);

select set_eq(
  $$select t.estado_origen::text || '>' || t.estado_destino::text from public.transiciones_version_flujo t
    join public.versiones_flujo v on v.id = t.version_flujo_id
    join public.definiciones_flujo d on d.id = v.definicion_flujo_id
    where d.nombre = 'Diseño' and v.numero = 1$$,
  array['pendiente>completada', 'pendiente>cancelada'],
  'un guardado rechazado no cambia nada'
);

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select public.guardar_borrador_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1),
      array['pendiente', 'completada']::public.estado_tarea[], 'pendiente', '[]')$$,
  'PT403', null,
  'miembro_a no puede editar borradores'
);

reset role;
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$select public.guardar_borrador_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1),
      array['pendiente', 'completada']::public.estado_tarea[], 'pendiente', '[]')$$,
  'PT404', null,
  'propietario_b no puede editar borradores de A'
);

-- -----------------------------------------------------------------------------
-- publicar_version_flujo
-- -----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select lives_ok(
  $$select public.crear_flujo('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Atascado')$$,
  'administrador_a crea otro flujo'
);

select lives_ok(
  $$select public.guardar_borrador_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Atascado' and v.numero = 1),
      array['pendiente', 'completada']::public.estado_tarea[], 'pendiente', '[]')$$,
  'un borrador sin transiciones se puede guardar'
);

select throws_ok(
  $$select public.publicar_version_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Atascado' and v.numero = 1))$$,
  'PT400', null,
  'no se publica un flujo en el que las tareas no podrían terminar nunca'
);

select lives_ok(
  $$select public.publicar_version_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1))$$,
  'administrador_a publica el borrador válido'
);

select ok(
  (select v.estado = 'publicada' and v.publicada_en is not null
   from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
   where d.nombre = 'Diseño' and v.numero = 1),
  'la versión queda publicada con su fecha'
);

select throws_ok(
  $$select public.guardar_borrador_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1),
      array['pendiente', 'completada']::public.estado_tarea[], 'pendiente', '[]')$$,
  'PT409', null,
  'una versión publicada no se puede editar'
);

select throws_ok(
  $$select public.publicar_version_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1))$$,
  'PT409', null,
  'una versión publicada no se publica otra vez'
);

reset role;
select results_eq(
  $$select count(*)::int from public.auditoria
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and accion = 'version_flujo.publicada'$$,
  array[1],
  'solo la publicación correcta queda en auditoría'
);

select set_eq(
  $$select distinct accion from public.auditoria
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and tipo_recurso in ('flujo', 'version_flujo')$$,
  array['flujo.creado', 'version_flujo.borrador_guardado', 'version_flujo.publicada'],
  'crear, guardar y publicar quedan en auditoría'
);

-- -----------------------------------------------------------------------------
-- crear_version_borrador
-- -----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select public.crear_version_borrador(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1))$$,
  'PT403', null,
  'miembro_a no puede crear versiones'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select results_eq(
  $$select numero || ':' || estado::text || ':' || estado_inicial::text
    from public.crear_version_borrador(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1))$$,
  array['2:borrador:pendiente'],
  'copiar la versión publicada crea la versión 2 en borrador'
);

select set_eq(
  $$select e.estado::text from public.estados_version_flujo e
    join public.versiones_flujo v on v.id = e.version_flujo_id
    join public.definiciones_flujo d on d.id = v.definicion_flujo_id
    where d.nombre = 'Diseño' and v.numero = 2$$,
  array['pendiente', 'completada', 'cancelada'],
  'el borrador nuevo copia los estados'
);

select set_eq(
  $$select t.estado_origen::text || '>' || t.estado_destino::text from public.transiciones_version_flujo t
    join public.versiones_flujo v on v.id = t.version_flujo_id
    join public.definiciones_flujo d on d.id = v.definicion_flujo_id
    where d.nombre = 'Diseño' and v.numero = 2$$,
  array['pendiente>completada', 'pendiente>cancelada'],
  'el borrador nuevo copia las transiciones'
);

select throws_ok(
  $$select public.crear_version_borrador(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1))$$,
  'PT409', null,
  'un flujo no puede tener dos borradores'
);

select throws_ok(
  $$select public.crear_version_borrador(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 2))$$,
  'PT400', null,
  'solo se copia una versión publicada'
);

select lives_ok(
  $$select public.guardar_borrador_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 2),
      array['pendiente', 'en_curso', 'completada', 'cancelada']::public.estado_tarea[], 'pendiente',
      '[{"origen": "pendiente", "destino": "en_curso"}, {"origen": "en_curso", "destino": "completada"},
        {"origen": "pendiente", "destino": "cancelada"}]')$$,
  'el borrador nuevo se edita'
);

select lives_ok(
  $$select public.publicar_version_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 2))$$,
  'y se publica'
);

select set_eq(
  $$select t.estado_origen::text || '>' || t.estado_destino::text from public.transiciones_version_flujo t
    join public.versiones_flujo v on v.id = t.version_flujo_id
    join public.definiciones_flujo d on d.id = v.definicion_flujo_id
    where d.nombre = 'Diseño' and v.numero = 1$$,
  array['pendiente>completada', 'pendiente>cancelada'],
  'la versión 1 publicada no cambia'
);

-- -----------------------------------------------------------------------------
-- Un proyecto con el flujo personalizado lo aplica a sus tareas
-- -----------------------------------------------------------------------------
select lives_ok(
  $$select public.crear_proyecto('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Con Diseño', null,
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 1))$$,
  'administrador_a crea un proyecto con la versión 1 de Diseño'
);

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select lives_ok(
  $$select public.crear_tarea((select id from public.proyectos where nombre = 'Con Diseño'), 'TD')$$,
  'miembro_a crea una tarea en ese proyecto'
);

select lives_ok(
  $$select public.cambiar_estado_tarea((select id from public.tareas where titulo = 'TD'), 'completada')$$,
  'la tarea sigue el flujo personalizado (pendiente → completada, que el predeterminado no permite)'
);

-- -----------------------------------------------------------------------------
-- Aislamiento e invariantes
-- -----------------------------------------------------------------------------
reset role;
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$select public.crear_version_borrador(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Diseño' and v.numero = 2))$$,
  'PT404', null,
  'propietario_b no puede copiar versiones de A'
);

select throws_ok(
  $$select public.publicar_version_flujo(
      (select v.id from public.versiones_flujo v join public.definiciones_flujo d on d.id = v.definicion_flujo_id
       where d.nombre = 'Atascado' and v.numero = 1))$$,
  'PT404', null,
  'propietario_b no puede publicar borradores de A'
);

set local role authenticated;
select is_empty(
  $$select id from public.definiciones_flujo where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'propietario_b no ve los flujos de A'
);

reset role;
select throws_ok(
  $$insert into public.versiones_flujo (organizacion_id, definicion_flujo_id, numero, estado_inicial)
    select organizacion_id, id, 2, 'pendiente' from public.definiciones_flujo where nombre = 'Atascado'$$,
  '23505', null,
  'la base de datos impide un segundo borrador del mismo flujo'
);

select ok(
  not has_function_privilege('anon',
    'public.guardar_borrador_flujo(uuid, public.estado_tarea[], public.estado_tarea, jsonb)', 'execute'),
  'anon no puede ejecutar guardar_borrador_flujo'
);

select * from finish();
rollback;
