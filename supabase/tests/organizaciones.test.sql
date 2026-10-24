-- organizaciones: aislamiento entre A y B y edición por rol.
begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

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

set local role authenticated;

-- Lectura
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select results_eq(
  $$select id from public.organizaciones$$,
  array['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa']::uuid[],
  'miembro_a ve solo la organización A'
);

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select results_eq(
  $$select id from public.organizaciones$$,
  array['bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb']::uuid[],
  'propietario_b ve solo la organización B'
);

select is_empty(
  $$select id from public.organizaciones where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'propietario_b no encuentra A ni pidiéndola por id'
);

set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
select is_empty(
  $$select id from public.organizaciones$$,
  'sin_membresia no ve ninguna organización'
);

-- Escrituras denegadas
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select is_empty(
  $$update public.organizaciones set nombre = 'Hackeada'
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    returning id$$,
  'propietario_b no puede renombrar A'
);

select throws_ok(
  $$delete from public.organizaciones where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  '42501', null,
  'propietario_b no puede borrar A'
);

select throws_ok(
  $$insert into public.organizaciones (nombre) values ('Directa')$$,
  '42501', null,
  'nadie crea organizaciones sin crear_organizacion'
);

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select is_empty(
  $$update public.organizaciones set nombre = 'Cambiada por miembro'
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    returning id$$,
  'miembro_a no puede renombrar A'
);

set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
select is_empty(
  $$update public.organizaciones set nombre = 'Cambiada sin membresia'
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    returning id$$,
  'sin_membresia no puede renombrar A'
);

select throws_ok(
  $$delete from public.organizaciones where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  '42501', null,
  'sin_membresia no puede borrar A'
);

reset role;
select results_eq(
  $$select nombre from public.organizaciones where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  array['Organizacion A'],
  'tras los intentos denegados, A sigue intacta'
);

select is_empty(
  $$select id from public.auditoria where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'los intentos denegados no dejan auditoría'
);

-- Escrituras permitidas
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select results_eq(
  $$update public.organizaciones set nombre = 'Organizacion A renombrada'
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    returning nombre$$,
  array['Organizacion A renombrada'],
  'administrador_a renombra A'
);

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select results_eq(
  $$update public.organizaciones set nombre = 'Organizacion A'
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    returning nombre$$,
  array['Organizacion A'],
  'propietario_a renombra A'
);

select throws_ok(
  $$update public.organizaciones set creado_por = '44444444-4444-4444-4444-444444444444'
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  '42501', null,
  'solo el nombre es editable (creado_por no)'
);

select throws_ok(
  $$update public.organizaciones set nombre = '   '
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  '23514', null,
  'un nombre vacío se rechaza'
);

-- Cada cambio de nombre queda auditado con su autor
reset role;
select results_eq(
  $$select actor_id from public.auditoria
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and accion = 'organizacion.actualizada'
    order by id$$,
  array[
    '22222222-2222-2222-2222-222222222222',
    '11111111-1111-1111-1111-111111111111'
  ]::uuid[],
  'los dos cambios de nombre quedan en auditoría con su autor'
);

select results_eq(
  $$select creado_por from public.organizaciones where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  array['11111111-1111-1111-1111-111111111111']::uuid[],
  'creado_por sigue siendo propietario_a tras el intento denegado'
);

set local role anon;
select throws_ok(
  $$select * from public.organizaciones$$,
  '42501', null,
  'anon no puede leer organizaciones'
);

select * from finish();
rollback;
