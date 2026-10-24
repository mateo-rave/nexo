-- membresias: lectura por organización, escrituras directas prohibidas e
-- invariante "siempre un propietario".
begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

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
  $$select usuario_id from public.membresias order by usuario_id$$,
  array[
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333'
  ]::uuid[],
  'miembro_a ve los miembros de A'
);

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select is_empty(
  $$select usuario_id from public.membresias where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'propietario_b no ve los miembros de A'
);

set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
select is_empty(
  $$select usuario_id from public.membresias$$,
  'sin_membresia no ve ninguna membresía'
);

-- Ataque principal: asignarse propietario de una organización ajena
select throws_ok(
  $$insert into public.membresias (organizacion_id, usuario_id, rol)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '55555555-5555-5555-5555-555555555555', 'propietario')$$,
  '42501', null,
  'sin_membresia no puede hacerse propietario de A'
);

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$insert into public.membresias (organizacion_id, usuario_id, rol)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '44444444-4444-4444-4444-444444444444', 'propietario')$$,
  '42501', null,
  'propietario_b no puede entrar en A'
);

-- Ascenso propio
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$update public.membresias set rol = 'propietario'
    where usuario_id = '33333333-3333-3333-3333-333333333333'$$,
  '42501', null,
  'miembro_a no puede ascenderse'
);

-- Ni siquiera propietario_a escribe directamente: debe usar las funciones
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select throws_ok(
  $$insert into public.membresias (organizacion_id, usuario_id, rol)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '55555555-5555-5555-5555-555555555555', 'miembro')$$,
  '42501', null,
  'propietario_a no inserta membresías directamente'
);

select throws_ok(
  $$update public.membresias set rol = 'administrador'
    where usuario_id = '33333333-3333-3333-3333-333333333333'$$,
  '42501', null,
  'propietario_a no cambia roles directamente'
);

select throws_ok(
  $$delete from public.membresias where usuario_id = '33333333-3333-3333-3333-333333333333'$$,
  '42501', null,
  'propietario_a no borra membresías directamente'
);

-- Las filas objetivo siguen intactas
reset role;
select results_eq(
  $$select usuario_id::text || ':' || rol::text from public.membresias
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    order by usuario_id$$,
  array[
    '11111111-1111-1111-1111-111111111111:propietario',
    '22222222-2222-2222-2222-222222222222:administrador',
    '33333333-3333-3333-3333-333333333333:miembro'
  ],
  'las membresías de A siguen intactas tras los intentos'
);

-- Invariantes, probadas como postgres (simulan una función con errores)
select throws_ok(
  $$delete from public.membresias
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and usuario_id = '11111111-1111-1111-1111-111111111111'$$,
  'PT409', null,
  'no se puede quitar al único propietario'
);

select throws_ok(
  $$update public.membresias set rol = 'miembro'
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and usuario_id = '11111111-1111-1111-1111-111111111111'$$,
  'PT409', null,
  'no se puede degradar al único propietario'
);

select throws_ok(
  $$delete from auth.users where id = '44444444-4444-4444-4444-444444444444'$$,
  'PT409', null,
  'borrar la cuenta del único propietario se bloquea'
);

-- Tras los tres rechazos, cada organización conserva su propietario (la
-- membresía de propietario_b sigue, así que su cuenta y su perfil también)
select results_eq(
  $$select usuario_id::text || ':' || organizacion_id::text from public.membresias
    where rol = 'propietario'
    order by usuario_id$$,
  array[
    '11111111-1111-1111-1111-111111111111:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '44444444-4444-4444-4444-444444444444:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
  ],
  'los propietarios de A y B siguen en su sitio tras los intentos rechazados'
);

select lives_ok(
  $$update public.membresias set rol = 'propietario'
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and usuario_id = '22222222-2222-2222-2222-222222222222'$$,
  'se puede añadir un segundo propietario'
);

select lives_ok(
  $$update public.membresias set rol = 'miembro'
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and usuario_id = '11111111-1111-1111-1111-111111111111'$$,
  'con otro propietario, el primero sí puede dejar de serlo'
);

select results_eq(
  $$select usuario_id::text || ':' || rol::text from public.membresias
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    order by usuario_id$$,
  array[
    '11111111-1111-1111-1111-111111111111:miembro',
    '22222222-2222-2222-2222-222222222222:propietario',
    '33333333-3333-3333-3333-333333333333:miembro'
  ],
  'los roles de A quedan como se pidió: administrador_a es el nuevo propietario'
);

select throws_ok(
  $$update public.membresias set organizacion_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    where usuario_id = '33333333-3333-3333-3333-333333333333'$$,
  'PT400', null,
  'una membresía no puede cambiar de organización'
);

select throws_ok(
  $$insert into public.membresias (organizacion_id, usuario_id, rol)
    values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '55555555-5555-5555-5555-555555555555', 'superadmin')$$,
  '22P02', null,
  'un rol que no existe se rechaza'
);

select throws_ok(
  $$insert into public.membresias (organizacion_id, usuario_id, rol)
    values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '44444444-4444-4444-4444-444444444444', 'miembro')$$,
  '23505', null,
  'una persona no puede estar dos veces en la misma organización'
);

-- Pérdida de acceso: al retirar la membresía de miembro_a, deja de ver A en
-- la siguiente consulta (las políticas leen membresias en cada petición)
delete from public.membresias
where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
  and usuario_id = '33333333-3333-3333-3333-333333333333';

set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';

select is_empty(
  $$select id from public.organizaciones$$,
  'tras retirar su membresía, miembro_a ya no ve la organización A'
);

select is_empty(
  $$select usuario_id from public.membresias$$,
  'tras retirar su membresía, miembro_a ya no ve los miembros de A'
);

select results_eq(
  $$select id from public.perfiles$$,
  array['33333333-3333-3333-3333-333333333333']::uuid[],
  'tras retirar su membresía, miembro_a solo ve su propio perfil'
);

reset role;
set local role anon;
select throws_ok(
  $$select * from public.membresias$$,
  '42501', null,
  'anon no puede leer membresías'
);

select * from finish();
rollback;
