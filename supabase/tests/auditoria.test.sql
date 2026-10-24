-- auditoria: lectura solo por propietario/administrador de la organización y
-- registros inmutables para todos.
begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

-- Datos sintéticos (como postgres, sin RLS).
-- 1111 propietario_a · 2222 administrador_a · 3333 miembro_a
-- 4444 propietario_b · 5555 sin_membresia
-- aaaa organización A · bbbb organización B
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

insert into public.auditoria (organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'organizacion.creada', 'organizacion', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '{"nombre": "Organizacion A"}'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'miembro.agregado', 'membresia', '33333333-3333-3333-3333-333333333333', '{"rol": "miembro"}'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '44444444-4444-4444-4444-444444444444', 'organizacion.creada', 'organizacion', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '{"nombre": "Organizacion B"}');

set local role authenticated;

-- Lectura permitida
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select results_eq(
  $$select accion from public.auditoria order by id$$,
  array['organizacion.creada', 'miembro.agregado'],
  'propietario_a lee la auditoría de A (y solo la de A)'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select results_eq(
  $$select count(*)::int from public.auditoria$$,
  array[2],
  'administrador_a lee la auditoría de A'
);

-- Lectura denegada
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select is_empty(
  $$select id from public.auditoria$$,
  'miembro_a no lee la auditoría'
);

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select is_empty(
  $$select id from public.auditoria where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'propietario_b no lee la auditoría de A'
);

select results_eq(
  $$select organizacion_id from public.auditoria$$,
  array['bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb']::uuid[],
  'propietario_b lee solo la auditoría de B'
);

set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
select is_empty(
  $$select id from public.auditoria$$,
  'sin_membresia no lee ninguna auditoría'
);

-- Escritura denegada incluso al propietario
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select throws_ok(
  $$insert into public.auditoria (organizacion_id, accion, tipo_recurso)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'organizacion.creada', 'organizacion')$$,
  '42501', null,
  'propietario_a no puede inventar registros de auditoría'
);

select throws_ok(
  $$update public.auditoria set accion = 'organizacion.actualizada'$$,
  '42501', null,
  'propietario_a no puede editar la auditoría'
);

select throws_ok(
  $$delete from public.auditoria$$,
  '42501', null,
  'propietario_a no puede borrar la auditoría'
);

-- Inmutable también para roles con más privilegios (postgres simula la clave
-- secreta o una función con errores): lo impide el trigger
reset role;
select throws_ok(
  $$update public.auditoria set detalles = '{}'$$,
  'PT403', null,
  'nadie puede editar la auditoría, ni con privilegios elevados'
);

select throws_ok(
  $$delete from public.auditoria$$,
  'PT403', null,
  'nadie puede borrar la auditoría, ni con privilegios elevados'
);

select throws_ok(
  $$truncate public.auditoria$$,
  'PT403', null,
  'nadie puede vaciar la auditoría con truncate'
);

select throws_ok(
  $$insert into public.auditoria (organizacion_id, accion, tipo_recurso, detalles)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'texto libre', 'organizacion', '[]')$$,
  '23514', null,
  'una acción o unos detalles con formato inválido se rechazan'
);

-- Contar filas no basta: un update no cambia el número de filas. Se compara
-- el contenido completo de cada registro.
select results_eq(
  $$select organizacion_id, actor_id, accion, tipo_recurso, recurso_id, detalles
    from public.auditoria
    order by id$$,
  $$values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, '11111111-1111-1111-1111-111111111111'::uuid,
     'organizacion.creada'::text, 'organizacion'::text,
     'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, '{"nombre": "Organizacion A"}'::jsonb),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, '11111111-1111-1111-1111-111111111111'::uuid,
     'miembro.agregado'::text, 'membresia'::text,
     '33333333-3333-3333-3333-333333333333'::uuid, '{"rol": "miembro"}'::jsonb),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid, '44444444-4444-4444-4444-444444444444'::uuid,
     'organizacion.creada'::text, 'organizacion'::text,
     'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid, '{"nombre": "Organizacion B"}'::jsonb)$$,
  'los tres registros siguen exactamente igual tras los intentos de cambio'
);

set local role anon;
select throws_ok(
  $$select * from public.auditoria$$,
  '42501', null,
  'anon no puede leer la auditoría'
);

select * from finish();
rollback;
