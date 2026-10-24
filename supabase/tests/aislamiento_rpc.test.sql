-- Las cuatro RPC de gestión de miembros rechazan cualquier aislamiento
-- distinto de read committed, antes de mirar la sesión o las membresías, y
-- sin dejar cambios ni auditoría.
-- Este archivo abre su transacción en repeatable read a propósito.
begin transaction isolation level repeatable read;
create extension if not exists pgtap with schema extensions;
select plan(12);

-- Datos sintéticos (como postgres, sin RLS).
-- 1111 propietario_a · 3333 miembro_a · 5555 sin_membresia · c0..01 libre
-- aaaa organización A
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'propietario_a@example.com', now(), '{"nombre_visible": "Propietario A"}'),
  ('33333333-3333-3333-3333-333333333333', 'miembro_a@example.com', now(), '{"nombre_visible": "Miembro A"}'),
  ('55555555-5555-5555-5555-555555555555', 'sin_membresia@example.com', now(), '{"nombre_visible": "Sin Membresia"}'),
  ('c0000000-0000-0000-0000-000000000001', 'libre@example.com', now(), '{"nombre_visible": "Libre"}');

insert into public.organizaciones (id, nombre, creado_por) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Organizacion A', '11111111-1111-1111-1111-111111111111');

insert into public.membresias (organizacion_id, usuario_id, rol) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'propietario'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'miembro');

select is(
  current_setting('transaction_isolation'),
  'repeatable read',
  'la prueba se ejecuta realmente en repeatable read'
);

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'libre@example.com', 'miembro')$$,
  'PT500', 'Esta operación requiere el nivel de aislamiento read committed.',
  'agregar_miembro rechaza repeatable read'
);

select throws_ok(
  $$select public.cambiar_rol_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'administrador')$$,
  'PT500', 'Esta operación requiere el nivel de aislamiento read committed.',
  'cambiar_rol_miembro rechaza repeatable read'
);

select throws_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333')$$,
  'PT500', 'Esta operación requiere el nivel de aislamiento read committed.',
  'quitar_miembro rechaza repeatable read'
);

-- propietario_a es el único propietario: si el aislamiento no se comprobara
-- primero, el error sería ultimo_propietario (PT409)
select throws_ok(
  $$select public.salir_de_organizacion('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$,
  'PT500', 'Esta operación requiere el nivel de aislamiento read committed.',
  'salir_de_organizacion rechaza repeatable read antes de cualquier otra regla'
);

-- El aislamiento se comprueba antes que el permiso y antes que la sesión
set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
select throws_ok(
  $$select * from public.agregar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'libre@example.com', 'miembro')$$,
  'PT500', 'Esta operación requiere el nivel de aislamiento read committed.',
  'sin permiso, el error sigue siendo el de aislamiento (se comprueba antes de mirar membresías)'
);

-- sin_membresia no tiene permiso en A: si el aislamiento se comprobara
-- después de la autorización, estas llamadas fallarían con PT403
select throws_ok(
  $$select public.cambiar_rol_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'administrador')$$,
  'PT500', 'Esta operación requiere el nivel de aislamiento read committed.',
  'cambiar_rol_miembro sin permiso: el error es el de aislamiento, no el de permiso'
);

select throws_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333')$$,
  'PT500', 'Esta operación requiere el nivel de aislamiento read committed.',
  'quitar_miembro sin permiso: el error es el de aislamiento, no el de permiso'
);

select throws_ok(
  $$select public.salir_de_organizacion('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$,
  'PT500', 'Esta operación requiere el nivel de aislamiento read committed.',
  'salir_de_organizacion sin permiso: el error es el de aislamiento, no el de permiso'
);

set local request.jwt.claim.sub = '';
select throws_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333')$$,
  'PT500', 'Esta operación requiere el nivel de aislamiento read committed.',
  'sin sesión, el error sigue siendo el de aislamiento'
);

reset role;
select results_eq(
  $$select usuario_id::text || ':' || rol::text from public.membresias
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    order by usuario_id$$,
  array[
    '11111111-1111-1111-1111-111111111111:propietario',
    '33333333-3333-3333-3333-333333333333:miembro'
  ],
  'las membresías siguen intactas'
);

select is_empty(
  $$select id from public.auditoria$$,
  'no se creó ninguna auditoría'
);

select * from finish();
rollback;
