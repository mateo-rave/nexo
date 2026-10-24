-- crear_organizacion: crea organización + propietario + auditoría de forma
-- atómica y rechaza entradas inválidas.
begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

-- Datos sintéticos (como postgres, sin RLS).
-- 4444 propietario_b · 5555 sin_membresia · bbbb organización B
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'propietario_a@example.com', now(), '{"nombre_visible": "Propietario A"}'),
  ('44444444-4444-4444-4444-444444444444', 'propietario_b@example.com', now(), '{"nombre_visible": "Propietario B"}'),
  ('55555555-5555-5555-5555-555555555555', 'sin_membresia@example.com', now(), '{"nombre_visible": "Sin Membresia"}');

insert into public.organizaciones (id, nombre, creado_por) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Organizacion A', '11111111-1111-1111-1111-111111111111'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Organizacion B', '44444444-4444-4444-4444-444444444444');

insert into public.membresias (organizacion_id, usuario_id, rol) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'propietario'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '44444444-4444-4444-4444-444444444444', 'propietario');

-- Caso feliz: sin_membresia crea su primera organización
set local role authenticated;
set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';

select results_eq(
  $$select nombre from public.crear_organizacion('  Agencia Nueva  ')$$,
  array['Agencia Nueva'],
  'crea la organización con el nombre sin espacios sobrantes'
);

select results_eq(
  $$select o.nombre from public.organizaciones o$$,
  array['Agencia Nueva'],
  'quien la crea la ve (y solo esa)'
);

select results_eq(
  $$select m.rol::text from public.membresias m
    join public.organizaciones o on o.id = m.organizacion_id
    where o.nombre = 'Agencia Nueva'
      and m.usuario_id = '55555555-5555-5555-5555-555555555555'$$,
  array['propietario'],
  'quien la crea queda como propietario'
);

select results_eq(
  $$select a.accion || ':' || a.actor_id::text from public.auditoria a
    join public.organizaciones o on o.id = a.organizacion_id
    where o.nombre = 'Agencia Nueva'$$,
  array['organizacion.creada:55555555-5555-5555-5555-555555555555'],
  'la creación queda en auditoría y el propietario puede leerla'
);

reset role;
select results_eq(
  $$select creado_por from public.organizaciones where nombre = 'Agencia Nueva'$$,
  array['55555555-5555-5555-5555-555555555555']::uuid[],
  'creado_por es quien llamó, no un valor enviado por el cliente'
);

select results_eq(
  $$select count(*)::int from public.membresias m
    join public.organizaciones o on o.id = m.organizacion_id
    where o.nombre = 'Agencia Nueva'$$,
  array[1],
  'la organización nueva tiene exactamente una membresía'
);

-- Crear una organización no da acceso a otras
set local role authenticated;
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select lives_ok(
  $$select public.crear_organizacion('Segunda de B')$$,
  'propietario_b crea otra organización'
);

select results_eq(
  $$select m.rol::text from public.membresias m
    join public.organizaciones o on o.id = m.organizacion_id
    where o.nombre = 'Segunda de B'
      and m.usuario_id = '44444444-4444-4444-4444-444444444444'$$,
  array['propietario'],
  'propietario_b queda como propietario de su segunda organización'
);

select is_empty(
  $$select id from public.organizaciones where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'propietario_b sigue sin ver A'
);

-- Entradas inválidas
select throws_ok(
  $$select public.crear_organizacion('   ')$$,
  'PT400', null,
  'nombre vacío se rechaza'
);

select throws_ok(
  $$select public.crear_organizacion(null)$$,
  'PT400', null,
  'nombre nulo se rechaza'
);

select throws_ok(
  $$select public.crear_organizacion(repeat('x', 101))$$,
  'PT400', null,
  'nombre de más de 100 caracteres se rechaza'
);

-- Sin sesión (rol authenticated pero sin usuario en el JWT)
set local request.jwt.claim.sub = '';
select throws_ok(
  $$select public.crear_organizacion('Sin sesion')$$,
  'PT401', null,
  'sin usuario identificado se rechaza'
);

set local role anon;
select throws_ok(
  $$select public.crear_organizacion('Anonima')$$,
  '42501', null,
  'anon no puede ejecutar crear_organizacion'
);

-- Los intentos fallidos no dejaron organizaciones a medias
reset role;
select results_eq(
  $$select nombre from public.organizaciones order by nombre$$,
  array['Agencia Nueva', 'Organizacion A', 'Organizacion B', 'Segunda de B'],
  'solo existen las organizaciones creadas con éxito'
);

select * from finish();
rollback;
