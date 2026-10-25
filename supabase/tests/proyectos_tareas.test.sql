-- Proyectos y tareas (fase 2, bloque 2; ADR-0007): permisos de la matriz,
-- aislamiento entre organizaciones, transiciones del flujo, fechas límite con
-- y sin hora, regla de vencimiento, cambio de zona horaria y salida de
-- miembros (responsable retirado y auditado como acción del sistema).
begin;
create extension if not exists pgtap with schema extensions;
select plan(73);

-- Datos sintéticos (como postgres, sin RLS). Las organizaciones reciben su
-- flujo predeterminado por trigger.
-- 1111 propietario_a · 2222 administrador_a · 3333 miembro_a
-- 4444 propietario_b · 5555 sin_membresia · aaaa organización A · bbbb B
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

-- -----------------------------------------------------------------------------
-- Proyectos
-- -----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select results_eq(
  $$select nombre from public.crear_proyecto('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '  Web  ')$$,
  array['Web'],
  'administrador_a crea un proyecto (nombre sin espacios sobrantes)'
);

select ok(
  (select p.version_flujo_id from public.proyectos p where p.nombre = 'Web')
    = (select v.id from public.versiones_flujo v
       where v.organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and v.numero = 1),
  'sin versión indicada, el proyecto usa la versión publicada del flujo predeterminado'
);

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select public.crear_proyecto('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'No')$$,
  'PT403', null,
  'miembro_a no puede crear proyectos'
);

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$select public.crear_proyecto('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Intruso')$$,
  'PT403', null,
  'propietario_b no puede crear proyectos en A'
);

-- Como postgres (ve la versión de A) pero con la identidad de propietario_b:
-- la RPC rechaza una versión de otra organización.
reset role;
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$select public.crear_proyecto('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Con flujo ajeno', null,
      (select v.id from public.versiones_flujo v
       where v.organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and v.numero = 1))$$,
  'PT400', null,
  'un proyecto de B no puede usar una versión de flujo de A'
);

set local role anon;
select throws_ok(
  $$select public.crear_proyecto('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Anonimo')$$,
  '42501', null,
  'anon no puede ejecutar crear_proyecto'
);

reset role;
select results_eq(
  $$select accion || ':' || actor_id::text from public.auditoria
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and tipo_recurso = 'proyecto'$$,
  array['proyecto.creado:22222222-2222-2222-2222-222222222222'],
  'la creación del proyecto queda en auditoría con su autor'
);

-- -----------------------------------------------------------------------------
-- Archivar
-- -----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select public.archivar_proyecto((select id from public.proyectos where nombre = 'Web'), true)$$,
  'PT403', null,
  'miembro_a no puede archivar proyectos'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select lives_ok(
  $$select public.archivar_proyecto((select id from public.proyectos where nombre = 'Web'), true)$$,
  'administrador_a archiva el proyecto'
);

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select public.crear_tarea((select id from public.proyectos where nombre = 'Web'), 'En archivado')$$,
  'PT409', null,
  'no se crean tareas en un proyecto archivado'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select throws_ok(
  $$select public.archivar_proyecto((select id from public.proyectos where nombre = 'Web'), true)$$,
  'PT409', null,
  'archivar un proyecto ya archivado se rechaza'
);

select lives_ok(
  $$select public.archivar_proyecto((select id from public.proyectos where nombre = 'Web'), false)$$,
  'administrador_a lo desarchiva'
);

-- -----------------------------------------------------------------------------
-- Crear tareas y fechas límite (zona de A: America/Bogota, UTC-5)
-- -----------------------------------------------------------------------------
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';

select results_eq(
  $$select estado::text from public.crear_tarea(
      (select id from public.proyectos where nombre = 'Web'), 'T1', null,
      '33333333-3333-3333-3333-333333333333', '2026-12-01')$$,
  array['pendiente'],
  'miembro_a crea una tarea, que empieza en el estado inicial del flujo'
);

select ok(
  (select fecha_limite = '2026-12-01' and vence_en = '2026-12-02 05:00:00+00'::timestamptz
   from public.tareas where titulo = 'T1'),
  'sin hora: guarda el día y vence a las 00:00 del día siguiente en Bogotá'
);

select results_eq(
  $$select fecha_limite is null and vence_en = '2026-12-01 22:00:00+00'::timestamptz
    from public.crear_tarea((select id from public.proyectos where nombre = 'Web'), 'T2', null, null,
      '2026-12-01', '17:00')$$,
  array[true],
  'con hora: guarda solo el instante, convertido con la zona de la organización'
);

select throws_ok(
  $$select public.crear_tarea((select id from public.proyectos where nombre = 'Web'), 'Hora sola', null, null,
      null, '17:00')$$,
  'PT400', null,
  'una hora sin día se rechaza'
);

select throws_ok(
  $$select public.crear_tarea((select id from public.proyectos where nombre = 'Web'), 'Ajeno', null,
      '44444444-4444-4444-4444-444444444444')$$,
  'PT400', null,
  'el responsable debe ser miembro de la organización'
);

select lives_ok(
  $$select public.crear_tarea((select id from public.proyectos where nombre = 'Web'), 'T5', null, null,
      '2026-12-01')$$,
  'miembro_a crea otra tarea sin hora (se cancelará)'
);

select throws_ok(
  $$insert into public.tareas (organizacion_id, proyecto_id, titulo, estado)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', (select id from public.proyectos where nombre = 'Web'),
      'Directa', 'pendiente')$$,
  '42501', null,
  'authenticated no puede insertar tareas directamente'
);

select results_eq(
  $$select count(*)::int from public.tareas$$,
  array[3],
  'miembro_a ve las tareas de su organización'
);

reset role;
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$select public.crear_tarea((select id from public.proyectos where nombre = 'Web'), 'Intrusa')$$,
  'PT404', null,
  'propietario_b no puede crear tareas en un proyecto de A'
);

set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
select throws_ok(
  $$select public.crear_tarea((select id from public.proyectos where nombre = 'Web'), 'Sin membresia')$$,
  'PT404', null,
  'sin_membresia no puede crear tareas'
);

set local role authenticated;
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select is_empty(
  $$select id from public.tareas$$,
  'propietario_b no ve las tareas de A'
);

select is_empty(
  $$select id from public.proyectos$$,
  'propietario_b no ve los proyectos de A'
);

-- -----------------------------------------------------------------------------
-- Editar y asignar
-- -----------------------------------------------------------------------------
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select lives_ok(
  $$select public.crear_tarea((select id from public.proyectos where nombre = 'Web'), 'T3', null,
      '22222222-2222-2222-2222-222222222222')$$,
  'administrador_a crea una tarea asignada a sí mismo'
);

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select public.editar_tarea((select id from public.tareas where titulo = 'T3'), 'T3', 'Cambio', null, null)$$,
  'PT403', null,
  'miembro_a no edita una tarea de la que no es responsable ni creador'
);

select results_eq(
  $$select descripcion from public.editar_tarea((select id from public.tareas where titulo = 'T1'), 'T1',
      'Con descripción', '2026-12-01', null)$$,
  array['Con descripción'],
  'miembro_a edita una tarea que creó'
);

select throws_ok(
  $$select public.editar_tarea((select id from public.tareas where titulo = 'T1'), 'T1',
      'Con descripción', '2026-12-01', null)$$,
  'PT409', null,
  'editar sin cambios se rechaza'
);

select lives_ok(
  $$select public.asignar_responsable((select id from public.tareas where titulo = 'T3'),
      '33333333-3333-3333-3333-333333333333')$$,
  'cualquier miembro puede asignar responsable (miembro_a se asigna T3)'
);

select lives_ok(
  $$select public.cambiar_estado_tarea((select id from public.tareas where titulo = 'T3'), 'en_curso')$$,
  'como responsable, miembro_a cambia el estado de T3'
);

-- -----------------------------------------------------------------------------
-- Transiciones del flujo predeterminado
-- -----------------------------------------------------------------------------
select throws_ok(
  $$select public.cambiar_estado_tarea((select id from public.tareas where titulo = 'T1'), 'completada')$$,
  'PT409', null,
  'pendiente → completada no está permitida'
);

select throws_ok(
  $$select public.cambiar_estado_tarea((select id from public.tareas where titulo = 'T1'), 'pendiente')$$,
  'PT409', null,
  'cambiar al mismo estado se rechaza'
);

select lives_ok(
  $$select public.cambiar_estado_tarea((select id from public.tareas where titulo = 'T1'), 'en_curso')$$,
  'pendiente → en_curso'
);

select lives_ok(
  $$select public.cambiar_estado_tarea((select id from public.tareas where titulo = 'T1'), 'en_revision')$$,
  'en_curso → en_revision'
);

select lives_ok(
  $$select public.cambiar_estado_tarea((select id from public.tareas where titulo = 'T1'), 'completada')$$,
  'en_revision → completada'
);

select lives_ok(
  $$select public.cambiar_estado_tarea((select id from public.tareas where titulo = 'T1'), 'en_curso')$$,
  'completada → en_curso (reabrir) con el permiso de la matriz'
);

select lives_ok(
  $$select public.cambiar_estado_tarea((select id from public.tareas where titulo = 'T5'), 'cancelada')$$,
  'pendiente → cancelada'
);

select throws_ok(
  $$select public.cambiar_estado_tarea((select id from public.tareas where titulo = 'T5'), 'en_curso')$$,
  'PT409', null,
  'cancelada no tiene transiciones de salida'
);

reset role;
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$select public.cambiar_estado_tarea((select id from public.tareas where titulo = 'T1'), 'en_revision')$$,
  'PT404', null,
  'propietario_b no puede cambiar el estado de una tarea de A'
);

select throws_ok(
  $$update public.tareas set estado = 'completada' where titulo = 'T1'$$,
  'PT409', null,
  'el trigger rechaza una transición no permitida aunque se salte la RPC'
);

select results_eq(
  $$select count(*)::int from public.auditoria
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and accion = 'tarea.estado_cambiado'$$,
  array[6],
  'cada cambio de estado queda en auditoría (y los rechazados no)'
);

-- El estado enviado al insertar se ignora: siempre empieza en el inicial.
insert into public.tareas (organizacion_id, proyecto_id, titulo, estado)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', (select id from public.proyectos where nombre = 'Web'),
  'Directa', 'completada');

select results_eq(
  $$select estado::text from public.tareas where titulo = 'Directa'$$,
  array['pendiente'],
  'una tarea nueva siempre empieza en el estado inicial del flujo'
);

-- -----------------------------------------------------------------------------
-- Regla de vencimiento: límite exclusivo, ahora >= vence_en
-- -----------------------------------------------------------------------------
select ok(
  privado.tarea_vencida('2026-12-02 05:00:00+00', 'en_curso', '2026-12-02 05:00:00+00'),
  'en el instante exacto del límite la tarea ya está vencida'
);

select ok(
  not privado.tarea_vencida('2026-12-02 05:00:00+00', 'en_curso', '2026-12-02 04:59:59.999999+00'),
  'un microsegundo antes todavía no está vencida'
);

select ok(
  not privado.tarea_vencida('2026-12-02 05:00:00+00', 'completada', '2026-12-10 00:00:00+00'),
  'una tarea terminada nunca está vencida'
);

select ok(
  not privado.tarea_vencida(null, 'en_curso', now()),
  'sin fecha límite no vence'
);

-- -----------------------------------------------------------------------------
-- Eliminar
-- -----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select public.eliminar_tarea((select id from public.tareas where titulo = 'T2'))$$,
  'PT403', null,
  'miembro_a no puede eliminar tareas'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select lives_ok(
  $$select public.eliminar_tarea((select id from public.tareas where titulo = 'Directa'))$$,
  'administrador_a elimina una tarea'
);

reset role;
select results_eq(
  $$select accion || ':' || (detalles ->> 'titulo') from public.auditoria
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and accion = 'tarea.eliminada'$$,
  array['tarea.eliminada:Directa'],
  'la eliminación queda en auditoría'
);

-- -----------------------------------------------------------------------------
-- Cambio de zona horaria
-- T1: abierta y sin hora → se recalcula. T2: con hora → conserva el instante.
-- T5: cancelada (cerrada) y sin hora → conserva su valor histórico.
-- -----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select public.cambiar_zona_horaria('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Europe/Madrid')$$,
  'PT403', null,
  'miembro_a no puede cambiar la zona horaria'
);

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select results_eq(
  $$select zona_horaria from public.cambiar_zona_horaria('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Europe/Madrid')$$,
  array['Europe/Madrid'],
  'propietario_a cambia la zona horaria'
);

select ok(
  (select vence_en = '2026-12-01 23:00:00+00'::timestamptz from public.tareas where titulo = 'T1'),
  'la tarea abierta sin hora vence ahora a las 00:00 del día siguiente en Madrid'
);

select ok(
  (select vence_en = '2026-12-01 22:00:00+00'::timestamptz from public.tareas where titulo = 'T2'),
  'la tarea con hora explícita conserva su instante'
);

select ok(
  (select vence_en = '2026-12-02 05:00:00+00'::timestamptz from public.tareas where titulo = 'T5'),
  'la tarea cerrada conserva su vencimiento histórico'
);

select results_eq(
  $$select (detalles ->> 'zona_horaria_anterior') || '>' || (detalles ->> 'zona_horaria_nueva') || ':' ||
           (detalles ->> 'tareas_recalculadas')
    from public.auditoria
    where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and accion = 'organizacion.zona_horaria_cambiada'$$,
  array['America/Bogota>Europe/Madrid:1'],
  'el cambio de zona queda en auditoría con las tareas recalculadas'
);

select throws_ok(
  $$select public.cambiar_zona_horaria('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Europe/Madrid')$$,
  'PT409', null,
  'cambiar a la misma zona se rechaza'
);

select throws_ok(
  $$select public.cambiar_zona_horaria('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Nada/Nada')$$,
  'PT400', null,
  'una zona horaria inválida se rechaza'
);

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select results_eq(
  $$select vence_en = '2026-12-10 23:00:00+00'::timestamptz
    from public.crear_tarea((select id from public.proyectos where nombre = 'Web'), 'T6', null, null,
      '2026-12-10')$$,
  array[true],
  'las tareas nuevas usan la zona actual de la organización'
);

-- -----------------------------------------------------------------------------
-- Salida de miembros: responsable retirado y auditado como sistema
-- miembro_a es responsable de T1 y T3.
-- -----------------------------------------------------------------------------
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select lives_ok(
  $$select public.quitar_miembro('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333')$$,
  'propietario_a quita a miembro_a, que tenía tareas asignadas'
);

reset role;
select is_empty(
  $$select id from public.tareas where responsable_id = '33333333-3333-3333-3333-333333333333'$$,
  'las tareas de quien sale quedan sin responsable'
);

select set_eq(
  $$select t.titulo from public.auditoria a
    join public.tareas t on t.id = a.recurso_id
    where a.organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and a.accion = 'tarea.responsable_retirado'
      and a.actor_id is null
      and a.detalles ->> 'responsable_anterior' = '33333333-3333-3333-3333-333333333333'$$,
  array['T1', 'T3'],
  'se registra una auditoría por tarea, como acción del sistema'
);

-- Borrado de la cuenta desde Auth (cascada auth.users → perfiles → membresias).
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select lives_ok(
  $$select public.asignar_responsable((select id from public.tareas where titulo = 'T2'),
      '22222222-2222-2222-2222-222222222222')$$,
  'administrador_a se asigna T2'
);

select lives_ok(
  $$delete from auth.users where id = '22222222-2222-2222-2222-222222222222'$$,
  'se borra la cuenta de administrador_a'
);

select ok(
  (select responsable_id is null from public.tareas where titulo = 'T2')
    and exists (
      select 1 from public.auditoria
      where accion = 'tarea.responsable_retirado'
        and actor_id is null
        and recurso_id = (select id from public.tareas where titulo = 'T2')
    ),
  'al borrar una cuenta, sus tareas quedan sin responsable y se audita como sistema'
);

-- Borrar la cuenta de quien creó una versión publicada (corrección de la
-- migración de flujos): solo se vacía creado_por.
insert into public.versiones_flujo (id, organizacion_id, definicion_flujo_id, numero, estado_inicial, creado_por)
  select 'b2b2b2b2-0000-0000-0000-000000000002', organizacion_id, id, 2, 'pendiente',
         '55555555-5555-5555-5555-555555555555'
  from public.definiciones_flujo
  where organizacion_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' and es_predeterminado;
insert into public.estados_version_flujo (organizacion_id, version_flujo_id, estado) values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'b2b2b2b2-0000-0000-0000-000000000002', 'pendiente'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'b2b2b2b2-0000-0000-0000-000000000002', 'completada');
update public.versiones_flujo set estado = 'publicada' where id = 'b2b2b2b2-0000-0000-0000-000000000002';

select lives_ok(
  $$delete from auth.users where id = '55555555-5555-5555-5555-555555555555'$$,
  'se puede borrar la cuenta de quien creó una versión publicada'
);

select ok(
  (select creado_por is null and estado = 'publicada' and numero = 2
   from public.versiones_flujo where id = 'b2b2b2b2-0000-0000-0000-000000000002'),
  'la versión publicada solo pierde su creador; el resto queda igual'
);

-- -----------------------------------------------------------------------------
-- Aislamiento e invariantes (como postgres)
-- -----------------------------------------------------------------------------
select throws_ok(
  $$insert into public.tareas (organizacion_id, proyecto_id, titulo)
    values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', (select id from public.proyectos where nombre = 'Web'), 'Cruzada')$$,
  'PT404', null,
  'una tarea de B no puede colgar de un proyecto de A'
);

select throws_ok(
  $$update public.tareas set organizacion_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' where titulo = 'T2'$$,
  'PT400', null,
  'una tarea no puede cambiar de organización'
);

select throws_ok(
  $$update public.tareas set responsable_id = '44444444-4444-4444-4444-444444444444' where titulo = 'T2'$$,
  '23503', null,
  'la clave foránea impide asignar a alguien que no es miembro de la organización'
);

select throws_ok(
  $$update public.proyectos set version_flujo_id = (
      select v.id from public.versiones_flujo v
      where v.organizacion_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' and v.numero = 1)
    where nombre = 'Web'$$,
  'PT400', null,
  'un proyecto no puede cambiar de versión de flujo'
);

insert into public.versiones_flujo (id, organizacion_id, definicion_flujo_id, numero, estado_inicial)
  select 'e2e2e2e2-0000-0000-0000-000000000002', organizacion_id, id, 2, 'pendiente'
  from public.definiciones_flujo
  where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and es_predeterminado;

select throws_ok(
  $$insert into public.proyectos (organizacion_id, version_flujo_id, nombre)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'e2e2e2e2-0000-0000-0000-000000000002', 'Sobre borrador')$$,
  'PT400', null,
  'un proyecto no puede usar una versión en borrador'
);

select ok(
  not has_table_privilege('authenticated', 'public.tareas', 'insert, update, delete, truncate'),
  'authenticated no puede escribir directamente en tareas'
);

select ok(
  not has_table_privilege('authenticated', 'public.proyectos', 'insert, update, delete, truncate'),
  'authenticated no puede escribir directamente en proyectos'
);

select * from finish();
rollback;
