-- salir_de_organizacion: cualquier miembro puede salir salvo el último
-- propietario, pierde el acceso y los intentos rechazados no tienen efecto.
begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

-- Datos sintéticos (como postgres, sin RLS).
-- 1111 propietario_a · 2222 administrador_a · 3333 miembro_a
-- 4444 propietario_b · 5555 sin_membresia · c0..01 propietario_dos (en A)
-- aaaa organización A · bbbb organización B
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'propietario_a@example.com', now(), '{"nombre_visible": "Propietario A"}'),
  ('22222222-2222-2222-2222-222222222222', 'administrador_a@example.com', now(), '{"nombre_visible": "Administrador A"}'),
  ('33333333-3333-3333-3333-333333333333', 'miembro_a@example.com', now(), '{"nombre_visible": "Miembro A"}'),
  ('44444444-4444-4444-4444-444444444444', 'propietario_b@example.com', now(), '{"nombre_visible": "Propietario B"}'),
  ('55555555-5555-5555-5555-555555555555', 'sin_membresia@example.com', now(), '{"nombre_visible": "Sin Membresia"}'),
  ('c0000000-0000-0000-0000-000000000001', 'propietario_dos@example.com', now(), '{"nombre_visible": "Propietario Dos"}');

insert into public.organizaciones (id, nombre, creado_por) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Organizacion A', '11111111-1111-1111-1111-111111111111'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Organizacion B', '44444444-4444-4444-4444-444444444444');

insert into public.membresias (organizacion_id, usuario_id, rol) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'propietario'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'administrador'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'miembro'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'c0000000-0000-0000-0000-000000000001', 'propietario'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '44444444-4444-4444-4444-444444444444', 'propietario');

set local role authenticated;

-- Rechazos
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$select public.salir_de_organizacion('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')$$,
  'PT409', 'La organización debe tener al menos un propietario.',
  'el único propietario de B no puede salir'
);

select throws_ok(
  $$select public.salir_de_organizacion('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$,
  'PT403', 'No tienes permiso para realizar esta acción en esta organización.',
  'propietario_b no puede "salir" de A, donde no es miembro'
);

set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
select throws_ok(
  $$select public.salir_de_organizacion('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$,
  'PT403', 'No tienes permiso para realizar esta acción en esta organización.',
  'sin_membresia no puede salir de A'
);

select throws_ok(
  $$select public.salir_de_organizacion('dddddddd-dddd-dddd-dddd-dddddddddddd')$$,
  'PT403', 'No tienes permiso para realizar esta acción en esta organización.',
  'una organización inexistente da el mismo error que una ajena'
);

set local request.jwt.claim.sub = '';
select throws_ok(
  $$select public.salir_de_organizacion('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$,
  'PT401', null,
  'sin usuario identificado se rechaza'
);

-- Tras los rechazos, nada cambió
reset role;
select results_eq(
  $$select organizacion_id::text || ':' || usuario_id::text || ':' || rol::text
    from public.membresias order by organizacion_id, usuario_id$$,
  array[
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:11111111-1111-1111-1111-111111111111:propietario',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:22222222-2222-2222-2222-222222222222:administrador',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:33333333-3333-3333-3333-333333333333:miembro',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:c0000000-0000-0000-0000-000000000001:propietario',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb:44444444-4444-4444-4444-444444444444:propietario'
  ],
  'tras los rechazos, todas las membresías siguen intactas'
);

select is_empty(
  $$select id from public.auditoria$$,
  'los rechazos no dejan auditoría'
);

-- Salidas permitidas
set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select lives_ok(
  $$select public.salir_de_organizacion('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$,
  'miembro_a sale de A'
);

select is_empty(
  $$select id from public.organizaciones$$,
  'tras salir, miembro_a ya no ve la organización A'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select lives_ok(
  $$select public.salir_de_organizacion('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$,
  'administrador_a sale de A'
);

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select lives_ok(
  $$select public.salir_de_organizacion('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$,
  'propietario_a sale de A porque queda otro propietario'
);

-- Ahora propietario_dos es el último propietario de A
set local request.jwt.claim.sub = 'c0000000-0000-0000-0000-000000000001';
select throws_ok(
  $$select public.salir_de_organizacion('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$,
  'PT409', 'La organización debe tener al menos un propietario.',
  'el propietario que queda ya no puede salir'
);

reset role;
select results_eq(
  $$select usuario_id::text || ':' || rol::text from public.membresias
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  array['c0000000-0000-0000-0000-000000000001:propietario'],
  'en A solo queda propietario_dos'
);

select results_eq(
  $$select actor_id::text || ':' || accion || ':' || recurso_id::text || ':' || (detalles ->> 'rol')
    from public.auditoria
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    order by id$$,
  array[
    '33333333-3333-3333-3333-333333333333:miembro.salio:33333333-3333-3333-3333-333333333333:miembro',
    '22222222-2222-2222-2222-222222222222:miembro.salio:22222222-2222-2222-2222-222222222222:administrador',
    '11111111-1111-1111-1111-111111111111:miembro.salio:11111111-1111-1111-1111-111111111111:propietario'
  ],
  'cada salida permitida deja su auditoría; el intento rechazado no deja ninguna'
);

set local role anon;
select throws_ok(
  $$select public.salir_de_organizacion('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$,
  '42501', null,
  'anon no puede ejecutar salir_de_organizacion'
);

select * from finish();
rollback;
