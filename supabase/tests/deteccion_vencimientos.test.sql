-- Detección de tareas vencidas, hallazgos y notificaciones (fase 2, bloque 3;
-- ADR-0007): detección con "ahora" controlado, deduplicación por fecha límite
-- elegida, destinatarios, RLS, resolución de hallazgos, lectura de
-- notificaciones, cascadas y job programado.
begin;
create extension if not exists pgtap with schema extensions;
select plan(45);

-- Datos sintéticos (como postgres, sin RLS).
-- 1111 propietario_a · 2222 administrador_a · 3333 miembro_a
-- 4444 propietario_b · aaaa organización A · bbbb B
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'propietario_a@example.com', now(), '{"nombre_visible": "Propietario A"}'),
  ('22222222-2222-2222-2222-222222222222', 'administrador_a@example.com', now(), '{"nombre_visible": "Administrador A"}'),
  ('33333333-3333-3333-3333-333333333333', 'miembro_a@example.com', now(), '{"nombre_visible": "Miembro A"}'),
  ('44444444-4444-4444-4444-444444444444', 'propietario_b@example.com', now(), '{"nombre_visible": "Propietario B"}');

insert into public.organizaciones (id, nombre, creado_por) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Organizacion A', '11111111-1111-1111-1111-111111111111'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Organizacion B', '44444444-4444-4444-4444-444444444444');

insert into public.membresias (organizacion_id, usuario_id, rol) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'propietario'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'administrador'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'miembro'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '44444444-4444-4444-4444-444444444444', 'propietario');

insert into public.proyectos (id, organizacion_id, version_flujo_id, nombre) values
  ('a1a1a1a1-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   (select id from public.versiones_flujo where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 'PA'),
  ('a2a2a2a2-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   (select id from public.versiones_flujo where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 'Archivado'),
  ('b1b1b1b1-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   (select id from public.versiones_flujo where organizacion_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), 'PB');

-- Zona de A y B: America/Bogota (UTC-5).
-- V1: sin hora, vence 2026-10-02 05:00 UTC, responsable miembro_a.
-- V2: con hora, vence 2026-10-10 15:00 UTC, sin responsable.
-- F: futura. C: completada. AR: en un proyecto archivado.
-- E: con hora, vence 2026-10-25 00:00 UTC (para el límite exacto).
-- B1: de B, vencida, responsable propietario_b.
insert into public.tareas (organizacion_id, proyecto_id, titulo, responsable_id, fecha_limite, vence_en) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a1a1a1a1-0000-0000-0000-000000000001', 'V1',
   '33333333-3333-3333-3333-333333333333', '2026-10-01', null),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a1a1a1a1-0000-0000-0000-000000000001', 'V2',
   null, null, '2026-10-10 15:00:00+00'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a1a1a1a1-0000-0000-0000-000000000001', 'F',
   null, '2026-12-31', null),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a1a1a1a1-0000-0000-0000-000000000001', 'C',
   null, '2026-10-01', null),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a2a2a2a2-0000-0000-0000-000000000002', 'AR',
   null, '2026-10-01', null),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a1a1a1a1-0000-0000-0000-000000000001', 'E',
   null, null, '2026-10-25 00:00:00+00'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'b1b1b1b1-0000-0000-0000-000000000001', 'B1',
   '44444444-4444-4444-4444-444444444444', '2026-10-01', null);

update public.tareas set estado = 'en_curso' where titulo = 'C';
update public.tareas set estado = 'en_revision' where titulo = 'C';
update public.tareas set estado = 'completada' where titulo = 'C';
update public.proyectos set archivado_en = now() where nombre = 'Archivado';

-- -----------------------------------------------------------------------------
-- Detección con "ahora" controlado
-- -----------------------------------------------------------------------------
select results_eq(
  $$select privado.detectar_tareas_vencidas('2026-10-20 12:00:00+00')$$,
  array[3],
  'detecta las tres tareas vencidas (de A y de B) y devuelve cuántos hallazgos creó'
);

select set_eq(
  $$select t.titulo from public.hallazgos h join public.tareas t on t.id = h.tarea_id$$,
  array['V1', 'V2', 'B1'],
  'crea un hallazgo por cada tarea vencida'
);

select results_eq(
  $$select privado.detectar_tareas_vencidas('2026-10-20 12:00:00+00')$$,
  array[0],
  'volver a ejecutar la detección no crea nada'
);

select results_eq(
  $$select count(*)::int from public.hallazgos$$,
  array[3],
  'no hay hallazgos duplicados'
);

select ok(
  (select h.clave_deduplicacion = 'tarea_vencida:' || t.id::text || ':dia:2026-10-01'
   from public.hallazgos h join public.tareas t on t.id = h.tarea_id where t.titulo = 'V1'),
  'sin hora: la clave usa el día elegido'
);

select ok(
  (select h.clave_deduplicacion = 'tarea_vencida:' || t.id::text || ':instante:2026-10-10T15:00:00.000000Z'
   from public.hallazgos h join public.tareas t on t.id = h.tarea_id where t.titulo = 'V2'),
  'con hora: la clave usa el instante elegido'
);

select ok(
  (select h.tipo = 'tarea_vencida'
      and h.prioridad = 'alta'
      and h.detectado_en = '2026-10-20 12:00:00+00'
      and h.evidencia ->> 'fecha_limite' = '2026-10-01'
      and h.evidencia ->> 'zona_horaria' = 'America/Bogota'
      and h.evidencia ->> 'titulo' = 'V1'
   from public.hallazgos h join public.tareas t on t.id = h.tarea_id where t.titulo = 'V1'),
  'el hallazgo guarda su evidencia, fecha y prioridad'
);

select set_eq(
  $$select t.titulo || ':' || n.destinatario_id::text
    from public.notificaciones n
    join public.hallazgos h on h.id = n.hallazgo_id
    join public.tareas t on t.id = h.tarea_id$$,
  array[
    'V1:33333333-3333-3333-3333-333333333333',
    'V2:11111111-1111-1111-1111-111111111111',
    'V2:22222222-2222-2222-2222-222222222222',
    'B1:44444444-4444-4444-4444-444444444444'
  ],
  'notifica al responsable; sin responsable, al propietario y los administradores'
);

select results_eq(
  $$select count(*)::int from public.auditoria where accion = 'hallazgo.creado' and actor_id is null$$,
  array[3],
  'cada hallazgo queda en auditoría como acción del sistema'
);

select is_empty(
  $$select t.titulo from public.hallazgos h join public.tareas t on t.id = h.tarea_id
    where t.titulo in ('F', 'C', 'AR')$$,
  'no se detectan tareas futuras, terminadas ni de proyectos archivados'
);

-- Límite exclusivo: ahora >= vence_en
select results_eq(
  $$select privado.detectar_tareas_vencidas('2026-10-24 23:59:59.999999+00')$$,
  array[0],
  'un microsegundo antes del límite la tarea todavía no está vencida'
);

select results_eq(
  $$select privado.detectar_tareas_vencidas('2026-10-25 00:00:00+00')$$,
  array[1],
  'en el instante exacto del límite la tarea ya está vencida'
);

-- Cambiar la fecha límite genera un hallazgo nuevo
update public.tareas set fecha_limite = '2026-10-05' where titulo = 'V1';

select results_eq(
  $$select privado.detectar_tareas_vencidas('2026-10-25 00:00:00+00')$$,
  array[1],
  'una fecha límite nueva que también vence genera un hallazgo nuevo'
);

select results_eq(
  $$select count(*)::int from public.hallazgos h join public.tareas t on t.id = h.tarea_id where t.titulo = 'V1'$$,
  array[2],
  'V1 tiene un hallazgo por cada fecha límite vencida'
);

-- Cambiar la zona horaria recalcula vence_en pero no duplica hallazgos
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select lives_ok(
  $$select public.cambiar_zona_horaria('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Europe/Madrid')$$,
  'propietario_a cambia la zona horaria de A'
);

reset role;
select results_eq(
  $$select privado.detectar_tareas_vencidas('2026-10-25 00:00:00+00')$$,
  array[0],
  'un cambio de zona horaria no duplica hallazgos'
);

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';

select results_eq(
  $$select count(*)::int from public.hallazgos$$,
  array[4],
  'miembro_a ve los hallazgos de A'
);

select is_empty(
  $$select id from public.hallazgos where organizacion_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'$$,
  'miembro_a no ve los hallazgos de B'
);

select results_eq(
  $$select count(*)::int from public.notificaciones$$,
  array[2],
  'miembro_a ve sus dos notificaciones'
);

select is_empty(
  $$select id from public.notificaciones where destinatario_id <> '33333333-3333-3333-3333-333333333333'$$,
  'miembro_a no ve notificaciones de otras personas'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select results_eq(
  $$select count(*)::int from public.notificaciones$$,
  array[2],
  'administrador_a ve solo las suyas (tareas sin responsable)'
);

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select is_empty(
  $$select id from public.hallazgos where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'propietario_b no ve los hallazgos de A'
);

select is_empty(
  $$select id from public.notificaciones where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'propietario_b no ve las notificaciones de A'
);

set local role anon;
select throws_ok(
  $$select id from public.hallazgos$$,
  '42501', null,
  'anon no puede leer hallazgos'
);

select throws_ok(
  $$select id from public.notificaciones$$,
  '42501', null,
  'anon no puede leer notificaciones'
);

reset role;
select ok(
  not has_table_privilege('authenticated', 'public.hallazgos', 'insert, update, delete, truncate'),
  'authenticated no puede escribir directamente en hallazgos'
);

select ok(
  not has_table_privilege('authenticated', 'public.notificaciones', 'insert, update, delete, truncate'),
  'authenticated no puede escribir directamente en notificaciones'
);

select ok(
  not has_function_privilege('authenticated', 'privado.detectar_tareas_vencidas(timestamptz)', 'execute'),
  'nadie puede ejecutar la detección desde la API'
);

-- -----------------------------------------------------------------------------
-- Notificaciones leídas
-- -----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';

select ok(
  (select leida_en is not null
   from public.marcar_notificacion_leida((select id from public.notificaciones order by creado_en, id limit 1))),
  'miembro_a marca como leída una notificación suya'
);

select lives_ok(
  $$select public.marcar_notificacion_leida((select id from public.notificaciones order by creado_en, id limit 1))$$,
  'marcarla otra vez no falla (idempotente)'
);

reset role;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select public.marcar_notificacion_leida(
      (select id from public.notificaciones where destinatario_id = '22222222-2222-2222-2222-222222222222' limit 1))$$,
  'PT404', null,
  'miembro_a no puede marcar una notificación ajena'
);

-- -----------------------------------------------------------------------------
-- Resolver hallazgos
-- -----------------------------------------------------------------------------
select throws_ok(
  $$select public.resolver_hallazgo(
      (select h.id from public.hallazgos h join public.tareas t on t.id = h.tarea_id where t.titulo = 'V2'))$$,
  'PT403', null,
  'miembro_a no resuelve un hallazgo de una tarea de la que no es responsable'
);

set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select lives_ok(
  $$select public.resolver_hallazgo(
      (select h.id from public.hallazgos h join public.tareas t on t.id = h.tarea_id
       where t.titulo = 'V1' order by h.detectado_en limit 1))$$,
  'miembro_a resuelve un hallazgo de una tarea de la que es responsable'
);

select throws_ok(
  $$select public.resolver_hallazgo(
      (select h.id from public.hallazgos h join public.tareas t on t.id = h.tarea_id
       where t.titulo = 'V1' order by h.detectado_en limit 1))$$,
  'PT409', null,
  'un hallazgo ya resuelto no se resuelve otra vez'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select lives_ok(
  $$select public.resolver_hallazgo(
      (select h.id from public.hallazgos h join public.tareas t on t.id = h.tarea_id where t.titulo = 'V2'))$$,
  'administrador_a resuelve cualquier hallazgo de A'
);

reset role;
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$select public.resolver_hallazgo(
      (select h.id from public.hallazgos h join public.tareas t on t.id = h.tarea_id
       where t.titulo = 'V1' order by h.detectado_en desc limit 1))$$,
  'PT404', null,
  'propietario_b no puede resolver hallazgos de A'
);

select results_eq(
  $$select count(*)::int from public.auditoria
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and accion = 'hallazgo.resuelto'$$,
  array[2],
  'cada resolución queda en auditoría'
);

select results_eq(
  $$select privado.detectar_tareas_vencidas('2026-10-25 00:00:00+00')$$,
  array[0],
  'un hallazgo resuelto no se vuelve a crear para la misma fecha límite'
);

-- -----------------------------------------------------------------------------
-- Cascadas
-- -----------------------------------------------------------------------------
select lives_ok(
  $$delete from public.tareas where titulo = 'V2'$$,
  'se elimina una tarea con hallazgo y notificaciones'
);

select ok(
  not exists (select 1 from public.hallazgos where evidencia ->> 'titulo' = 'V2')
    and not exists (select 1 from public.notificaciones where mensaje like '%«V2»%'),
  'sus hallazgos y notificaciones desaparecen con ella'
);

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select lives_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333')$$,
  'propietario_a quita a miembro_a'
);

reset role;
select is_empty(
  $$select id from public.notificaciones where destinatario_id = '33333333-3333-3333-3333-333333333333'$$,
  'las notificaciones de quien sale se borran con su membresía'
);

select results_eq(
  $$select count(*)::int from public.hallazgos h join public.tareas t on t.id = h.tarea_id where t.titulo = 'V1'$$,
  array[2],
  'los hallazgos de la organización se conservan'
);

-- -----------------------------------------------------------------------------
-- Comprobación programada
-- -----------------------------------------------------------------------------
select results_eq(
  $$select schedule || ' | ' || command from cron.job where jobname = 'detectar_tareas_vencidas'$$,
  array['* * * * * | select privado.detectar_tareas_vencidas(now())'],
  'el job de Cron llama cada minuto a la función de detección'
);

select throws_ok(
  $$select privado.detectar_tareas_vencidas(null)$$,
  'PT400', null,
  'la detección exige un instante'
);

select * from finish();
rollback;
