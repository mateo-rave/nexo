-- cambiar_rol_miembro: solo propietario, traspaso de propiedad (D2), mismo
-- rol rechazado (D4), último propietario protegido y ningún efecto en los
-- intentos rechazados.
begin;
create extension if not exists pgtap with schema extensions;
select plan(21);

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

-- Rechazos por permiso
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select throws_ok(
  $$select public.cambiar_rol_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'administrador')$$,
  'PT403', 'No tienes permiso para realizar esta acción en esta organización.',
  'administrador_a no puede cambiar roles'
);

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select public.cambiar_rol_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'propietario')$$,
  'PT403', 'No tienes permiso para realizar esta acción en esta organización.',
  'miembro_a no puede ascenderse'
);

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$select public.cambiar_rol_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'administrador')$$,
  'PT403', 'No tienes permiso para realizar esta acción en esta organización.',
  'propietario_b no puede cambiar roles en A'
);

set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
select throws_ok(
  $$select public.cambiar_rol_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'administrador')$$,
  'PT403', 'No tienes permiso para realizar esta acción en esta organización.',
  'sin_membresia no puede cambiar roles en A'
);

set local request.jwt.claim.sub = '';
select throws_ok(
  $$select public.cambiar_rol_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'administrador')$$,
  'PT401', null,
  'sin usuario identificado se rechaza'
);

-- Rechazos por datos (propietario_a sí tiene permiso)
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select throws_ok(
  $$select public.cambiar_rol_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'miembro')$$,
  'PT409', 'La persona ya tiene ese rol.',
  'pedir el mismo rol se rechaza con rol_sin_cambios'
);

select throws_ok(
  $$select public.cambiar_rol_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '55555555-5555-5555-5555-555555555555', 'miembro')$$,
  'PT404', null,
  'no se puede cambiar el rol de quien no es miembro'
);

select throws_ok(
  $$select public.cambiar_rol_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '44444444-4444-4444-4444-444444444444', 'miembro')$$,
  'PT404', null,
  'un usuario de B no se encuentra con el organizacion_id de A'
);

select throws_ok(
  $$select public.cambiar_rol_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', null)$$,
  'PT400', 'Debes indicar un rol válido.',
  'un rol nulo se rechaza'
);

select throws_ok(
  $$select public.cambiar_rol_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'administrador')$$,
  'PT409', 'La organización debe tener al menos un propietario.',
  'el único propietario de A no puede bajarse el rol'
);

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$select public.cambiar_rol_miembro('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '44444444-4444-4444-4444-444444444444', 'miembro')$$,
  'PT409', 'La organización debe tener al menos un propietario.',
  'el único propietario de B no puede bajarse el rol'
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
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb:44444444-4444-4444-4444-444444444444:propietario'
  ],
  'tras los rechazos, todas las membresías siguen intactas'
);

select is_empty(
  $$select id from public.auditoria$$,
  'los rechazos no dejan auditoría'
);

-- Cambios permitidos
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select lives_ok(
  $$select public.cambiar_rol_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'administrador')$$,
  'propietario_a sube a miembro_a a administrador'
);

reset role;
select results_eq(
  $$select rol::text from public.membresias
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and usuario_id = '33333333-3333-3333-3333-333333333333'$$,
  array['administrador'],
  'miembro_a queda como administrador'
);

-- Traspaso de propiedad (D2): primero sube a otro, luego se baja a sí mismo
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select lives_ok(
  $$select public.cambiar_rol_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'propietario')$$,
  'propietario_a sube a administrador_a a propietario'
);

select lives_ok(
  $$select public.cambiar_rol_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'administrador')$$,
  'con otro propietario, propietario_a puede bajarse a administrador'
);

reset role;
select results_eq(
  $$select usuario_id::text || ':' || rol::text from public.membresias
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    order by usuario_id$$,
  array[
    '11111111-1111-1111-1111-111111111111:administrador',
    '22222222-2222-2222-2222-222222222222:propietario',
    '33333333-3333-3333-3333-333333333333:administrador'
  ],
  'los roles de A quedan como se pidió tras el traspaso'
);

-- Se usa el rol actual: el antiguo propietario ya no puede cambiar roles
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select throws_ok(
  $$select public.cambiar_rol_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'miembro')$$,
  'PT403', 'No tienes permiso para realizar esta acción en esta organización.',
  'tras bajarse, el antiguo propietario ya no puede cambiar roles'
);

reset role;
select results_eq(
  $$select actor_id::text || ':' || accion || ':' || recurso_id::text || ':'
           || (detalles ->> 'rol_anterior') || ':' || (detalles ->> 'rol_nuevo')
    from public.auditoria
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    order by id$$,
  array[
    '11111111-1111-1111-1111-111111111111:miembro.rol_cambiado:33333333-3333-3333-3333-333333333333:miembro:administrador',
    '11111111-1111-1111-1111-111111111111:miembro.rol_cambiado:22222222-2222-2222-2222-222222222222:administrador:propietario',
    '11111111-1111-1111-1111-111111111111:miembro.rol_cambiado:11111111-1111-1111-1111-111111111111:propietario:administrador'
  ],
  'cada cambio permitido deja su auditoría con rol anterior y nuevo'
);

set local role anon;
select throws_ok(
  $$select public.cambiar_rol_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'miembro')$$,
  '42501', null,
  'anon no puede ejecutar cambiar_rol_miembro'
);

select * from finish();
rollback;
