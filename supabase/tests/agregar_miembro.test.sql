-- agregar_miembro: altas permitidas, permiso antes de buscar el correo,
-- cuentas no elegibles con el mismo mensaje genérico y ningún efecto en los
-- intentos rechazados.
begin;
create extension if not exists pgtap with schema extensions;
select plan(30);

-- Datos sintéticos (como postgres, sin RLS).
-- 1111 propietario_a · 2222 administrador_a · 3333 miembro_a
-- 4444 propietario_b · 5555 sin_membresia
-- c0..01-c0..13 cuentas candidatas en distintos estados
-- aaaa organización A · bbbb organización B
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, is_anonymous, deleted_at, banned_until, is_sso_user) values
  ('11111111-1111-1111-1111-111111111111', 'propietario_a@example.com', now(), '{"nombre_visible": "Propietario A"}', false, null, null, false),
  ('22222222-2222-2222-2222-222222222222', 'administrador_a@example.com', now(), '{"nombre_visible": "Administrador A"}', false, null, null, false),
  ('33333333-3333-3333-3333-333333333333', 'miembro_a@example.com', now(), '{"nombre_visible": "Miembro A"}', false, null, null, false),
  ('44444444-4444-4444-4444-444444444444', 'propietario_b@example.com', now(), '{"nombre_visible": "Propietario B"}', false, null, null, false),
  ('55555555-5555-5555-5555-555555555555', 'sin_membresia@example.com', now(), '{"nombre_visible": "Sin Membresia"}', false, null, null, false),
  ('c0000000-0000-0000-0000-000000000001', 'nuevo_uno@example.com', now(), '{"nombre_visible": "Nuevo Uno"}', false, null, null, false),
  ('c0000000-0000-0000-0000-000000000002', 'nuevo_dos@example.com', now(), '{"nombre_visible": "Nuevo Dos"}', false, null, null, false),
  ('c0000000-0000-0000-0000-000000000003', 'mayusculas@example.com', now(), '{"nombre_visible": "Mayusculas"}', false, null, null, false),
  ('c0000000-0000-0000-0000-000000000004', 'bloqueo_vencido@example.com', now(), '{"nombre_visible": "Bloqueo Vencido"}', false, null, now() - interval '1 day', false),
  ('c0000000-0000-0000-0000-000000000005', 'sin_confirmar@example.com', null, '{"nombre_visible": "Sin Confirmar"}', false, null, null, false),
  ('c0000000-0000-0000-0000-000000000006', 'anonimo@example.com', now(), '{"nombre_visible": "Anonimo"}', true, null, null, false),
  ('c0000000-0000-0000-0000-000000000007', 'eliminado@example.com', now(), '{"nombre_visible": "Eliminado"}', false, now(), null, false),
  ('c0000000-0000-0000-0000-000000000008', 'bloqueado@example.com', now(), '{"nombre_visible": "Bloqueado"}', false, null, now() + interval '1 day', false),
  ('c0000000-0000-0000-0000-000000000009', 'sso@example.com', now(), '{"nombre_visible": "Sso"}', false, null, null, true),
  ('c0000000-0000-0000-0000-000000000010', 'Ambiguo@example.com', now(), '{"nombre_visible": "Ambiguo Mayus"}', false, null, null, false),
  ('c0000000-0000-0000-0000-000000000011', 'ambiguo@example.com', now(), '{"nombre_visible": "Ambiguo"}', false, null, null, false),
  ('c0000000-0000-0000-0000-000000000012', 'libre@example.com', now(), '{"nombre_visible": "Libre"}', false, null, null, false),
  ('c0000000-0000-0000-0000-000000000013', 'nuevo_propietario@example.com', now(), '{"nombre_visible": "Nuevo Propietario"}', false, null, null, false);

insert into public.organizaciones (id, nombre, creado_por) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Organizacion A', '11111111-1111-1111-1111-111111111111'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Organizacion B', '44444444-4444-4444-4444-444444444444');

insert into public.membresias (organizacion_id, usuario_id, rol) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'propietario'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'administrador'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'miembro'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '44444444-4444-4444-4444-444444444444', 'propietario');

set local role authenticated;

-- Altas permitidas
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select results_eq(
  $$select usuario_id::text || ':' || nombre_visible || ':' || rol::text
    from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'nuevo_uno@example.com', 'administrador')$$,
  array['c0000000-0000-0000-0000-000000000001:Nuevo Uno:administrador'],
  'propietario_a añade un administrador y recibe id, nombre visible y rol'
);

select results_eq(
  $$select a.nombre collate "default"
    from pg_proc p, unnest(p.proargnames, p.proargmodes) as a(nombre, modo)
    where p.oid = 'public.agregar_miembro(uuid, text, public.rol_membresia)'::regprocedure
      and a.modo = 't'
    order by a.nombre$$,
  array['nombre_visible', 'rol', 'usuario_id'],
  'la respuesta solo tiene usuario_id, nombre_visible y rol (nunca el correo)'
);

select results_eq(
  $$select usuario_id
    from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '  MAYUSCULAS@Example.COM  ', 'miembro')$$,
  array['c0000000-0000-0000-0000-000000000003']::uuid[],
  'el correo se encuentra aunque llegue con mayúsculas y espacios'
);

select results_eq(
  $$select usuario_id
    from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bloqueo_vencido@example.com', 'miembro')$$,
  array['c0000000-0000-0000-0000-000000000004']::uuid[],
  'una cuenta cuyo bloqueo ya venció es elegible'
);

select results_eq(
  $$select usuario_id::text || ':' || nombre_visible || ':' || rol::text
    from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'nuevo_propietario@example.com', 'propietario')$$,
  array['c0000000-0000-0000-0000-000000000013:Nuevo Propietario:propietario'],
  'propietario_a añade a otra persona como propietario'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select results_eq(
  $$select usuario_id::text || ':' || nombre_visible || ':' || rol::text
    from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'nuevo_dos@example.com', 'miembro')$$,
  array['c0000000-0000-0000-0000-000000000002:Nuevo Dos:miembro'],
  'administrador_a añade un miembro'
);

-- El permiso se comprueba antes de buscar el correo
select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'no_existe@example.com', 'administrador')$$,
  'PT403', 'Tu rol no permite asignar o gestionar ese rol.',
  'administrador_a no puede nombrar administradores (error de rol antes de mirar el correo)'
);

select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'libre@example.com', 'propietario')$$,
  'PT403', 'Tu rol no permite asignar o gestionar ese rol.',
  'administrador_a no puede nombrar propietarios'
);

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'no_existe@example.com', 'miembro')$$,
  'PT403', 'No tienes permiso para realizar esta acción en esta organización.',
  'miembro_a con un correo inexistente recibe error de permiso, no de correo'
);

select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'libre@example.com', 'miembro')$$,
  'PT403', 'No tienes permiso para realizar esta acción en esta organización.',
  'miembro_a no puede añadir miembros'
);

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'libre@example.com', 'miembro')$$,
  'PT403', 'No tienes permiso para realizar esta acción en esta organización.',
  'propietario_b no puede añadir miembros a A'
);

set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'libre@example.com', 'miembro')$$,
  'PT403', 'No tienes permiso para realizar esta acción en esta organización.',
  'sin_membresia no puede añadir miembros a A'
);

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select throws_ok(
  $$select * from public.agregar_miembro('dddddddd-dddd-dddd-dddd-dddddddddddd', 'libre@example.com', 'miembro')$$,
  'PT403', 'No tienes permiso para realizar esta acción en esta organización.',
  'una organización inexistente da el mismo error que una ajena'
);

set local request.jwt.claim.sub = '';
select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'libre@example.com', 'miembro')$$,
  'PT401', null,
  'sin usuario identificado se rechaza'
);

-- Destinatarios no válidos (quien llama sí tiene permiso)
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'miembro_a@example.com', 'miembro')$$,
  'PT409', null,
  'no se puede añadir a quien ya es miembro'
);

select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'no_existe@example.com', 'miembro')$$,
  'PT400', 'No se pudo añadir a esta persona.',
  'correo no registrado: mensaje genérico'
);

select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'sin_confirmar@example.com', 'miembro')$$,
  'PT400', 'No se pudo añadir a esta persona.',
  'cuenta sin confirmar: el mismo mensaje genérico'
);

select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'anonimo@example.com', 'miembro')$$,
  'PT400', 'No se pudo añadir a esta persona.',
  'cuenta anónima: el mismo mensaje genérico'
);

select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'eliminado@example.com', 'miembro')$$,
  'PT400', 'No se pudo añadir a esta persona.',
  'cuenta eliminada: el mismo mensaje genérico'
);

select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bloqueado@example.com', 'miembro')$$,
  'PT400', 'No se pudo añadir a esta persona.',
  'cuenta bloqueada: el mismo mensaje genérico'
);

select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'sso@example.com', 'miembro')$$,
  'PT400', 'No se pudo añadir a esta persona.',
  'cuenta SSO: el mismo mensaje genérico'
);

select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'ambiguo@example.com', 'miembro')$$,
  'PT400', 'No se pudo añadir a esta persona.',
  'correo ambiguo por mayúsculas: el mismo mensaje genérico, sin elegir ninguna cuenta'
);

select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '   ', 'miembro')$$,
  'PT400', 'Debes indicar un correo válido.',
  'un correo vacío se rechaza'
);

select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', null, 'miembro')$$,
  'PT400', 'Debes indicar un correo válido.',
  'un correo nulo se rechaza'
);

select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'libre@example.com', null)$$,
  'PT400', 'Debes indicar un rol válido.',
  'un rol nulo se rechaza'
);

set local role anon;
select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'libre@example.com', 'miembro')$$,
  '42501', null,
  'anon no puede ejecutar agregar_miembro'
);

-- Resultado final: solo las seis altas permitidas, nada de los rechazos
reset role;
select results_eq(
  $$select usuario_id::text || ':' || rol::text from public.membresias
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    order by usuario_id$$,
  array[
    '11111111-1111-1111-1111-111111111111:propietario',
    '22222222-2222-2222-2222-222222222222:administrador',
    '33333333-3333-3333-3333-333333333333:miembro',
    'c0000000-0000-0000-0000-000000000001:administrador',
    'c0000000-0000-0000-0000-000000000002:miembro',
    'c0000000-0000-0000-0000-000000000003:miembro',
    'c0000000-0000-0000-0000-000000000004:miembro',
    'c0000000-0000-0000-0000-000000000013:propietario'
  ],
  'las membresías de A son exactamente las de las altas permitidas'
);

select results_eq(
  $$select usuario_id::text || ':' || rol::text from public.membresias
    where organizacion_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'$$,
  array['44444444-4444-4444-4444-444444444444:propietario'],
  'las membresías de B siguen intactas'
);

select results_eq(
  $$select actor_id::text || ':' || accion || ':' || recurso_id::text || ':' || (detalles ->> 'rol')
    from public.auditoria
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    order by id$$,
  array[
    '11111111-1111-1111-1111-111111111111:miembro.agregado:c0000000-0000-0000-0000-000000000001:administrador',
    '11111111-1111-1111-1111-111111111111:miembro.agregado:c0000000-0000-0000-0000-000000000003:miembro',
    '11111111-1111-1111-1111-111111111111:miembro.agregado:c0000000-0000-0000-0000-000000000004:miembro',
    '11111111-1111-1111-1111-111111111111:miembro.agregado:c0000000-0000-0000-0000-000000000013:propietario',
    '22222222-2222-2222-2222-222222222222:miembro.agregado:c0000000-0000-0000-0000-000000000002:miembro'
  ],
  'cada alta permitida deja una auditoría con su autor; los rechazos no dejan ninguna'
);

select is_empty(
  $$select id from public.auditoria where organizacion_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'$$,
  'no hay auditoría en B'
);

select * from finish();
rollback;
