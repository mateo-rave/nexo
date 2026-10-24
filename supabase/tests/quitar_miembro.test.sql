-- quitar_miembro: propietario quita a cualquiera (incluido otro propietario,
-- D6), administrador solo a miembro, nadie a sí mismo (D3) y ningún efecto en
-- los intentos rechazados.
begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

-- Datos sintéticos (como postgres, sin RLS).
-- 1111 propietario_a · 2222 administrador_a · 3333 miembro_a
-- 4444 propietario_b · 5555 sin_membresia
-- c0..01 miembro_dos · c0..02 administrador_dos · c0..03 propietario_dos (en A)
-- aaaa organización A · bbbb organización B
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'propietario_a@example.com', now(), '{"nombre_visible": "Propietario A"}'),
  ('22222222-2222-2222-2222-222222222222', 'administrador_a@example.com', now(), '{"nombre_visible": "Administrador A"}'),
  ('33333333-3333-3333-3333-333333333333', 'miembro_a@example.com', now(), '{"nombre_visible": "Miembro A"}'),
  ('44444444-4444-4444-4444-444444444444', 'propietario_b@example.com', now(), '{"nombre_visible": "Propietario B"}'),
  ('55555555-5555-5555-5555-555555555555', 'sin_membresia@example.com', now(), '{"nombre_visible": "Sin Membresia"}'),
  ('c0000000-0000-0000-0000-000000000001', 'miembro_dos@example.com', now(), '{"nombre_visible": "Miembro Dos"}'),
  ('c0000000-0000-0000-0000-000000000002', 'administrador_dos@example.com', now(), '{"nombre_visible": "Administrador Dos"}'),
  ('c0000000-0000-0000-0000-000000000003', 'propietario_dos@example.com', now(), '{"nombre_visible": "Propietario Dos"}');

insert into public.organizaciones (id, nombre, creado_por) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Organizacion A', '11111111-1111-1111-1111-111111111111'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Organizacion B', '44444444-4444-4444-4444-444444444444');

insert into public.membresias (organizacion_id, usuario_id, rol) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'propietario'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'administrador'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'miembro'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'c0000000-0000-0000-0000-000000000001', 'miembro'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'c0000000-0000-0000-0000-000000000002', 'administrador'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'c0000000-0000-0000-0000-000000000003', 'propietario'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '44444444-4444-4444-4444-444444444444', 'propietario');

set local role authenticated;

-- Rechazos por permiso
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'c0000000-0000-0000-0000-000000000001')$$,
  'PT403', 'No tienes permiso para realizar esta acción en esta organización.',
  'miembro_a no puede quitar miembros'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select throws_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'c0000000-0000-0000-0000-000000000002')$$,
  'PT403', 'Tu rol no permite asignar o gestionar ese rol.',
  'administrador_a no puede quitar a otro administrador'
);

select throws_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111')$$,
  'PT403', 'Tu rol no permite asignar o gestionar ese rol.',
  'administrador_a no puede quitar a un propietario'
);

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333')$$,
  'PT403', 'No tienes permiso para realizar esta acción en esta organización.',
  'propietario_b no puede quitar miembros de A'
);

set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
select throws_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333')$$,
  'PT403', 'No tienes permiso para realizar esta acción en esta organización.',
  'sin_membresia no puede quitar miembros de A'
);

set local request.jwt.claim.sub = '';
select throws_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333')$$,
  'PT401', null,
  'sin usuario identificado se rechaza'
);

-- Quitarse a uno mismo no se permite por esta vía (D3)
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select throws_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111')$$,
  'PT400', 'Para salir de la organización usa salir_de_organizacion.',
  'propietario_a no puede quitarse a sí mismo con quitar_miembro'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select throws_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222')$$,
  'PT400', 'Para salir de la organización usa salir_de_organizacion.',
  'administrador_a no puede quitarse a sí mismo con quitar_miembro'
);

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$select public.quitar_miembro('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '44444444-4444-4444-4444-444444444444')$$,
  'PT400', 'Para salir de la organización usa salir_de_organizacion.',
  'el único propietario de B tampoco puede quitarse con quitar_miembro'
);

-- Destinatarios no válidos
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select throws_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '55555555-5555-5555-5555-555555555555')$$,
  'PT404', null,
  'no se puede quitar a quien no es miembro'
);

select throws_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '44444444-4444-4444-4444-444444444444')$$,
  'PT404', null,
  'un usuario de B no se encuentra con el organizacion_id de A'
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
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:c0000000-0000-0000-0000-000000000001:miembro',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:c0000000-0000-0000-0000-000000000002:administrador',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:c0000000-0000-0000-0000-000000000003:propietario',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb:44444444-4444-4444-4444-444444444444:propietario'
  ],
  'tras los rechazos, todas las membresías siguen intactas'
);

select is_empty(
  $$select id from public.auditoria$$,
  'los rechazos no dejan auditoría'
);

-- Bajas permitidas
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select lives_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'c0000000-0000-0000-0000-000000000001')$$,
  'administrador_a quita a un miembro'
);

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select lives_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'c0000000-0000-0000-0000-000000000002')$$,
  'propietario_a quita a un administrador'
);

select lives_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'c0000000-0000-0000-0000-000000000003')$$,
  'propietario_a quita a otro propietario (D6)'
);

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
  'en A quedan exactamente los tres miembros no quitados'
);

select results_eq(
  $$select actor_id::text || ':' || accion || ':' || recurso_id::text || ':' || (detalles ->> 'rol')
    from public.auditoria
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    order by id$$,
  array[
    '22222222-2222-2222-2222-222222222222:miembro.quitado:c0000000-0000-0000-0000-000000000001:miembro',
    '11111111-1111-1111-1111-111111111111:miembro.quitado:c0000000-0000-0000-0000-000000000002:administrador',
    '11111111-1111-1111-1111-111111111111:miembro.quitado:c0000000-0000-0000-0000-000000000003:propietario'
  ],
  'cada baja permitida deja su auditoría con el rol que tenía'
);

-- La persona quitada pierde el acceso en la siguiente consulta
set local role authenticated;
set local request.jwt.claim.sub = 'c0000000-0000-0000-0000-000000000001';
select is_empty(
  $$select id from public.organizaciones$$,
  'miembro_dos ya no ve la organización A'
);

set local role anon;
select throws_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333')$$,
  '42501', null,
  'anon no puede ejecutar quitar_miembro'
);

select * from finish();
rollback;
