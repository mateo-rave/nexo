-- perfiles: creación automática, lectura entre compañeros y edición propia.
begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

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

-- Trigger de registro
select results_eq(
  $$select nombre_visible from public.perfiles where id = '11111111-1111-1111-1111-111111111111'$$,
  array['Propietario A'],
  'el registro crea el perfil con el nombre enviado'
);

insert into auth.users (id, email, raw_user_meta_data) values
  ('66666666-6666-6666-6666-666666666666', 'sin_nombre@example.com', '{}'),
  ('77777777-7777-7777-7777-777777777777', 'con_espacios@example.com', '{"nombre_visible": "   Ana   "}');

select results_eq(
  $$select nombre_visible from public.perfiles where id = '66666666-6666-6666-6666-666666666666'$$,
  array['Usuario'],
  'sin nombre enviado, el perfil usa "Usuario"'
);

select results_eq(
  $$select nombre_visible from public.perfiles where id = '77777777-7777-7777-7777-777777777777'$$,
  array['Ana'],
  'el nombre enviado se guarda sin espacios sobrantes'
);

-- Como miembro_a
set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';

select results_eq(
  $$select id from public.perfiles order by id$$,
  array[
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333'
  ]::uuid[],
  'miembro_a ve su perfil y los de sus compañeros de A'
);

select is_empty(
  $$select id from public.perfiles where id = '44444444-4444-4444-4444-444444444444'$$,
  'miembro_a no ve el perfil de propietario_b'
);

select results_eq(
  $$update public.perfiles set nombre_visible = 'Miembro A editado'
    where id = '33333333-3333-3333-3333-333333333333'
    returning nombre_visible$$,
  array['Miembro A editado'],
  'miembro_a edita su propio nombre'
);

select is_empty(
  $$update public.perfiles set nombre_visible = 'Hackeado'
    where id = '22222222-2222-2222-2222-222222222222'
    returning id$$,
  'miembro_a no edita el perfil de administrador_a'
);

select throws_ok(
  $$update public.perfiles set id = '55555555-5555-5555-5555-555555555555'
    where id = '33333333-3333-3333-3333-333333333333'$$,
  '42501', null,
  'nadie puede cambiar el id de su perfil'
);

select throws_ok(
  $$update public.perfiles set nombre_visible = ''
    where id = '33333333-3333-3333-3333-333333333333'$$,
  '23514', null,
  'un nombre vacío se rechaza'
);

select throws_ok(
  $$insert into public.perfiles (id, nombre_visible)
    values ('55555555-5555-5555-5555-555555555555', 'Falso')$$,
  '42501', null,
  'nadie crea perfiles directamente'
);

select throws_ok(
  $$delete from public.perfiles where id = '33333333-3333-3333-3333-333333333333'$$,
  '42501', null,
  'nadie borra perfiles directamente'
);

-- Como sin_membresia
set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';

select results_eq(
  $$select id from public.perfiles$$,
  array['55555555-5555-5555-5555-555555555555']::uuid[],
  'sin_membresia solo ve su propio perfil'
);

select is_empty(
  $$update public.perfiles set nombre_visible = 'Hackeado'
    where id = '11111111-1111-1111-1111-111111111111'
    returning id$$,
  'sin_membresia no edita el perfil de propietario_a'
);

-- Como propietario_b
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';

select results_eq(
  $$select id from public.perfiles$$,
  array['44444444-4444-4444-4444-444444444444']::uuid[],
  'propietario_b no ve perfiles de la organización A'
);

select is_empty(
  $$update public.perfiles set nombre_visible = 'Hackeado'
    where id = '33333333-3333-3333-3333-333333333333'
    returning id$$,
  'propietario_b no edita el perfil de miembro_a (otra organización)'
);

-- Las filas objetivo de los intentos denegados siguen intactas
reset role;
select results_eq(
  $$select nombre_visible from public.perfiles where id = '22222222-2222-2222-2222-222222222222'$$,
  array['Administrador A'],
  'el perfil de administrador_a sigue intacto'
);

select results_eq(
  $$select nombre_visible from public.perfiles where id = '11111111-1111-1111-1111-111111111111'$$,
  array['Propietario A'],
  'el perfil de propietario_a sigue intacto'
);

select results_eq(
  $$select nombre_visible from public.perfiles where id = '33333333-3333-3333-3333-333333333333'$$,
  array['Miembro A editado'],
  'el perfil de miembro_a sigue con su propio cambio (ni borrado ni editado por otros)'
);

select results_eq(
  $$select nombre_visible from public.perfiles where id = '55555555-5555-5555-5555-555555555555'$$,
  array['Sin Membresia'],
  'el perfil de sin_membresia no fue suplantado por el insert denegado'
);

-- Visitante anónimo
set local role anon;
select throws_ok(
  $$select * from public.perfiles$$,
  '42501', null,
  'anon no puede leer perfiles'
);

select * from finish();
rollback;
