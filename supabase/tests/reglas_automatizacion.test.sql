-- Definición de reglas de automatización (fase 5, bloque 5.1; ADR-0008):
-- crear una regla, validación del catálogo cerrado, borradores y versiones
-- publicadas inmutables, periodos de activación (activar, pausar, reactivar),
-- permisos de la matriz, auditoría, RLS y aislamiento entre organizaciones.
begin;
create extension if not exists pgtap with schema extensions;
select plan(70);

-- Datos sintéticos (como postgres, sin RLS).
-- 1111 propietario_a · 2222 administrador_a · 3333 miembro_a
-- 4444 propietario_b · aaaa organización A · bbbb B
-- a1a1 proyecto de A · b1b1 proyecto de B
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
  ('b1b1b1b1-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   (select id from public.versiones_flujo where organizacion_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), 'PB');

-- -----------------------------------------------------------------------------
-- crear_regla
-- -----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select results_eq(
  $$select numero || ':' || estado::text || ':' || activador::text
    from public.crear_regla(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '  Revisión  ', 'tarea_estado_cambiado',
      '[{"tipo": "estado_destino", "estados": ["en_revision"]},
        {"tipo": "proyecto", "proyecto_id": "a1a1a1a1-0000-0000-0000-000000000001"},
        {"tipo": "con_responsable", "valor": true}]',
      '[{"tipo": "notificar", "destinatarios": "propietarios_y_administradores"}]')$$,
  array['1:borrador:tarea_estado_cambiado'],
  'administrador_a crea una regla con su versión 1 en borrador'
);

select ok(
  (select count(*) = 1 from public.reglas_automatizacion where nombre = 'Revisión'),
  'el nombre se guarda sin espacios sobrantes'
);

select ok(
  (select count(*) = 1 from public.auditoria
   where accion = 'regla.creada' and actor_id = '22222222-2222-2222-2222-222222222222'),
  'la creación de la regla queda en auditoría'
);

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'No', 'tarea_vencida', '[]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT403', null,
  'miembro_a no puede crear reglas'
);

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Intruso', 'tarea_vencida', '[]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT403', null,
  'propietario_b no puede crear reglas en A'
);

set local role anon;
select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Anonima', 'tarea_vencida', '[]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  '42501', null,
  'anon no puede ejecutar crear_regla'
);

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '   ', 'tarea_vencida', '[]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT400', 'El nombre debe tener entre 1 y 100 caracteres.',
  'un nombre vacío se rechaza'
);

-- -----------------------------------------------------------------------------
-- Validación del catálogo cerrado
-- -----------------------------------------------------------------------------
select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_creada', '[]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT400', 'Ese activador no está en el catálogo.',
  'un activador desconocido se rechaza'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_vencida', '{}',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT400', 'Las condiciones deben ser una lista de condiciones válidas.',
  'unas condiciones que no son una lista se rechazan'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_vencida', '[1]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT400', 'Las condiciones deben ser una lista de condiciones válidas.',
  'una condición que no es un objeto se rechaza'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_vencida',
      '[{"tipo": "prioridad", "valor": "alta"}]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT400', 'Esa condición no está en el catálogo.',
  'una condición desconocida se rechaza'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_vencida',
      '[{"tipo": "con_responsable", "valor": true}, {"tipo": "con_responsable", "valor": false}]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT400', 'Cada tipo de condición puede aparecer una sola vez.',
  'una condición repetida se rechaza'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_vencida',
      '[{"tipo": "estado_destino", "estados": ["en_curso"]}]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT400', 'Esa condición no se puede usar con este activador.',
  'estado_destino no se admite con tarea_vencida'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_estado_cambiado',
      '[{"tipo": "estado_destino", "estados": ["bloqueada"]}]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT400', 'La condición tiene claves o valores no válidos.',
  'un estado fuera del catálogo se rechaza'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_estado_cambiado',
      '[{"tipo": "estado_destino", "estados": []}]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT400', 'La condición tiene claves o valores no válidos.',
  'estado_destino sin estados se rechaza'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_estado_cambiado',
      '[{"tipo": "estado_destino", "estados": ["en_curso", "en_curso"]}]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT400', 'La condición tiene claves o valores no válidos.',
  'estados repetidos se rechazan'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_vencida',
      '[{"tipo": "con_responsable", "valor": true, "extra": 1}]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT400', 'La condición tiene claves o valores no válidos.',
  'una clave de más en una condición se rechaza'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_vencida',
      '[{"tipo": "con_responsable", "valor": "sí"}]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT400', 'La condición tiene claves o valores no válidos.',
  'un valor de tipo incorrecto se rechaza'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_vencida',
      '[{"tipo": "proyecto", "proyecto_id": "abc"}]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT400', 'La condición tiene claves o valores no válidos.',
  'un proyecto_id que no es un uuid se rechaza sin error interno'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_vencida',
      '[{"tipo": "proyecto", "proyecto_id": "b1b1b1b1-0000-0000-0000-000000000001"}]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT400', 'El proyecto no existe en esta organización.',
  'un proyecto de otra organización se rechaza'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_vencida',
      '[{"tipo": "con_responsable", "valor": true}, {"tipo": "proyecto", "proyecto_id": "a1a1a1a1-0000-0000-0000-000000000001"},
        {"tipo": "con_responsable", "valor": false}, {"tipo": "con_responsable", "valor": true},
        {"tipo": "con_responsable", "valor": true}, {"tipo": "con_responsable", "valor": true}]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT400', 'Una regla admite como máximo 5 condiciones.',
  'más de 5 condiciones se rechazan'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_vencida', '[]', '{}')$$,
  'PT400', 'Las acciones deben ser una lista de acciones válidas.',
  'unas acciones que no son una lista se rechazan'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_vencida', '[]', '[]')$$,
  'PT400', 'La regla debe tener al menos una acción.',
  'una regla sin acciones se rechaza'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_vencida', '[]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}, {"tipo": "notificar", "destinatarios": "responsable"},
        {"tipo": "notificar", "destinatarios": "responsable"}, {"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT400', 'Una regla admite como máximo 3 acciones.',
  'más de 3 acciones se rechazan'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_vencida', '[]',
      '[{"tipo": "cambiar_estado", "estado": "cancelada"}]')$$,
  'PT400', 'Esa acción no está en el catálogo.',
  'una acción desconocida se rechaza'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_vencida', '[]',
      '[{"tipo": "notificar", "destinatarios": "todos"}]')$$,
  'PT400', 'La acción tiene claves o valores no válidos.',
  'unos destinatarios fuera del catálogo se rechazan'
);

select throws_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'X', 'tarea_vencida', '[]',
      '[{"tipo": "notificar", "destinatarios": "responsable", "mensaje": "libre"}]')$$,
  'PT400', 'La acción tiene claves o valores no válidos.',
  'una clave de más en una acción se rechaza (sin texto libre)'
);

select lives_ok(
  $$select public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Vencidas', 'tarea_vencida',
      '[{"tipo": "proyecto", "proyecto_id": "A1A1A1A1-0000-0000-0000-000000000001"}, {"tipo": "con_responsable", "valor": false}]',
      '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'una regla tarea_vencida con condiciones válidas se crea (uuid en mayúsculas incluido)'
);

select results_eq(
  $$select count(*)::int from public.reglas_automatizacion$$,
  array[2],
  'ninguna definición rechazada dejó una regla creada'
);

-- -----------------------------------------------------------------------------
-- guardar_borrador_regla
-- -----------------------------------------------------------------------------
select lives_ok(
  $$select public.guardar_borrador_regla(
      (select v.id from public.versiones_regla v join public.reglas_automatizacion r on r.id = v.regla_id
       where r.nombre = 'Revisión' and v.numero = 1),
      'tarea_estado_cambiado',
      '[{"tipo": "estado_destino", "estados": ["en_revision", "completada"]}]',
      '[{"tipo": "notificar", "destinatarios": "propietarios_y_administradores"}]')$$,
  'administrador_a guarda el borrador'
);

select ok(
  (select v.condiciones = '[{"tipo": "estado_destino", "estados": ["en_revision", "completada"]}]'::jsonb
   from public.versiones_regla v join public.reglas_automatizacion r on r.id = v.regla_id
   where r.nombre = 'Revisión' and v.numero = 1)
  and (select count(*) = 1 from public.auditoria where accion = 'version_regla.borrador_guardado'),
  'el borrador guarda la definición nueva y queda en auditoría'
);

select throws_ok(
  $$select public.guardar_borrador_regla(
      (select v.id from public.versiones_regla v join public.reglas_automatizacion r on r.id = v.regla_id
       where r.nombre = 'Revisión' and v.numero = 1),
      'tarea_estado_cambiado', '[]', '[]')$$,
  'PT400', 'La regla debe tener al menos una acción.',
  'un borrador no se puede guardar con una definición inválida'
);

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select public.guardar_borrador_regla(
      (select v.id from public.versiones_regla v join public.reglas_automatizacion r on r.id = v.regla_id
       where r.nombre = 'Revisión' and v.numero = 1),
      'tarea_vencida', '[]', '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT403', null,
  'miembro_a no puede guardar borradores'
);

reset role;
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$select public.guardar_borrador_regla(
      (select v.id from public.versiones_regla v join public.reglas_automatizacion r on r.id = v.regla_id
       where r.nombre = 'Revisión' and v.numero = 1),
      'tarea_vencida', '[]', '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT404', 'La versión de la regla no existe o no tienes acceso a ella.',
  'propietario_b no puede editar borradores de A (y no sabe si existen)'
);

-- -----------------------------------------------------------------------------
-- publicar_version_regla e inmutabilidad
-- -----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select results_eq(
  $$select estado::text || ':' || (publicada_en is not null)::text
    from public.publicar_version_regla(
      (select v.id from public.versiones_regla v join public.reglas_automatizacion r on r.id = v.regla_id
       where r.nombre = 'Revisión' and v.numero = 1))$$,
  array['publicada:true'],
  'administrador_a publica la versión y queda fijada su fecha de publicación'
);

select throws_ok(
  $$select public.publicar_version_regla(
      (select v.id from public.versiones_regla v join public.reglas_automatizacion r on r.id = v.regla_id
       where r.nombre = 'Revisión' and v.numero = 1))$$,
  'PT409', 'La versión ya está publicada.',
  'una versión no se publica dos veces'
);

select throws_ok(
  $$select public.guardar_borrador_regla(
      (select v.id from public.versiones_regla v join public.reglas_automatizacion r on r.id = v.regla_id
       where r.nombre = 'Revisión' and v.numero = 1),
      'tarea_vencida', '[]', '[{"tipo": "notificar", "destinatarios": "responsable"}]')$$,
  'PT409', 'Una versión publicada no se puede modificar ni borrar.',
  'una versión publicada no se puede editar con la RPC'
);

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select public.publicar_version_regla(
      (select v.id from public.versiones_regla v join public.reglas_automatizacion r on r.id = v.regla_id
       where r.nombre = 'Vencidas' and v.numero = 1))$$,
  'PT403', null,
  'miembro_a no puede publicar'
);

-- Protección directa (como si se usara la clave secreta).
reset role;
select throws_ok(
  $$update public.versiones_regla v set condiciones = '[]'
    from public.reglas_automatizacion r
    where r.id = v.regla_id and r.nombre = 'Revisión' and v.numero = 1$$,
  'PT409', 'Una versión publicada no se puede modificar ni borrar.',
  'una versión publicada no se modifica ni siquiera sin RLS'
);

select throws_ok(
  $$delete from public.versiones_regla v
    using public.reglas_automatizacion r
    where r.id = v.regla_id and r.nombre = 'Revisión' and v.numero = 1$$,
  'PT409', 'Una versión publicada no se puede modificar ni borrar.',
  'una versión publicada no se borra'
);

select throws_ok(
  $$insert into public.versiones_regla (organizacion_id, regla_id, numero, estado, activador, condiciones, acciones)
    select r.organizacion_id, r.id, 9, 'publicada', 'tarea_vencida', '[]',
           '[{"tipo": "notificar", "destinatarios": "responsable"}]'
    from public.reglas_automatizacion r where r.nombre = 'Vencidas'$$,
  'PT400', 'Una versión se crea como borrador y después se publica.',
  'no se puede insertar una versión ya publicada'
);

select throws_ok(
  $$insert into public.versiones_regla (organizacion_id, regla_id, numero, activador, condiciones, acciones)
    select r.organizacion_id, r.id, 9, 'tarea_vencida', '[]', '[]'
    from public.reglas_automatizacion r where r.nombre = 'Vencidas'$$,
  'PT400', 'La regla debe tener al menos una acción.',
  'la validación se aplica también a una inserción directa'
);

-- -----------------------------------------------------------------------------
-- crear_version_borrador_regla
-- -----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select results_eq(
  $$select numero || ':' || estado::text
    from public.crear_version_borrador_regla(
      (select v.id from public.versiones_regla v join public.reglas_automatizacion r on r.id = v.regla_id
       where r.nombre = 'Revisión' and v.numero = 1))$$,
  array['2:borrador'],
  'copiar una versión publicada crea la versión 2 en borrador'
);

select ok(
  (select v2.activador = v1.activador and v2.condiciones = v1.condiciones and v2.acciones = v1.acciones
   from public.versiones_regla v1
   join public.versiones_regla v2 on v2.regla_id = v1.regla_id and v2.numero = 2
   join public.reglas_automatizacion r on r.id = v1.regla_id
   where r.nombre = 'Revisión' and v1.numero = 1),
  'el borrador copia la definición de la versión publicada'
);

select throws_ok(
  $$select public.crear_version_borrador_regla(
      (select v.id from public.versiones_regla v join public.reglas_automatizacion r on r.id = v.regla_id
       where r.nombre = 'Revisión' and v.numero = 1))$$,
  'PT409', 'Esta regla ya tiene una versión en borrador.',
  'una regla solo tiene un borrador'
);

select throws_ok(
  $$select public.crear_version_borrador_regla(
      (select v.id from public.versiones_regla v join public.reglas_automatizacion r on r.id = v.regla_id
       where r.nombre = 'Revisión' and v.numero = 2))$$,
  'PT400', 'Solo se puede copiar una versión publicada.',
  'no se puede copiar un borrador'
);

-- -----------------------------------------------------------------------------
-- activar_regla y pausar_regla
-- -----------------------------------------------------------------------------
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select public.activar_regla((select id from public.reglas_automatizacion where nombre = 'Revisión'))$$,
  'PT403', null,
  'miembro_a no puede activar reglas'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select throws_ok(
  $$select public.activar_regla((select id from public.reglas_automatizacion where nombre = 'Vencidas'))$$,
  'PT409', 'La regla necesita una versión publicada para activarse.',
  'no se puede activar una regla sin versión publicada'
);

select results_eq(
  $$select (desactivada_en is null)::text
    from public.activar_regla((select id from public.reglas_automatizacion where nombre = 'Revisión'))$$,
  array['true'],
  'activar abre un periodo'
);

select throws_ok(
  $$select public.activar_regla((select id from public.reglas_automatizacion where nombre = 'Revisión'))$$,
  'PT409', 'La regla ya está activa.',
  'activar una regla activa se rechaza'
);

select results_eq(
  $$select count(*)::int from public.periodos_activacion_regla p
    join public.reglas_automatizacion r on r.id = p.regla_id where r.nombre = 'Revisión'$$,
  array[1],
  'el rechazo no crea un segundo periodo'
);

select ok(
  (select count(*) = 1 from public.auditoria
   where accion = 'regla.activada' and actor_id = '22222222-2222-2222-2222-222222222222'),
  'la activación queda en auditoría'
);

select results_eq(
  $$select (desactivada_en is not null and desactivada_en >= activada_en)::text
    from public.pausar_regla((select id from public.reglas_automatizacion where nombre = 'Revisión'))$$,
  array['true'],
  'pausar cierra el periodo abierto'
);

select throws_ok(
  $$select public.pausar_regla((select id from public.reglas_automatizacion where nombre = 'Revisión'))$$,
  'PT409', 'La regla no está activa.',
  'pausar una regla que no está activa se rechaza'
);

select lives_ok(
  $$select public.activar_regla((select id from public.reglas_automatizacion where nombre = 'Revisión'))$$,
  'reactivar abre un periodo nuevo'
);

select ok(
  (select count(*) = 2
      and count(*) filter (where desactivada_en is null) = 1
      and max(activada_en) >= min(desactivada_en)
   from public.periodos_activacion_regla p
   join public.reglas_automatizacion r on r.id = p.regla_id where r.nombre = 'Revisión'),
  'tras reactivar hay dos periodos que no se solapan y uno solo abierto'
);

select ok(
  (select count(*) = 1 from public.auditoria where accion = 'regla.pausada'),
  'la pausa queda en auditoría'
);

reset role;
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$select public.pausar_regla((select id from public.reglas_automatizacion where nombre = 'Revisión'))$$,
  'PT404', 'La regla no existe o no tienes acceso a ella.',
  'propietario_b no puede pausar reglas de A (y no sabe si existen)'
);

-- -----------------------------------------------------------------------------
-- Periodos de activación: protección directa (como postgres, sin RLS)
-- -----------------------------------------------------------------------------
select throws_ok(
  $$insert into public.periodos_activacion_regla (organizacion_id, regla_id, activada_en)
    select organizacion_id, id, clock_timestamp() from public.reglas_automatizacion where nombre = 'Revisión'$$,
  '23505', null,
  'el índice único impide un segundo periodo abierto aunque se inserte fuera de la RPC'
);

select throws_ok(
  $$update public.periodos_activacion_regla p set desactivada_en = p.desactivada_en + interval '1 day'
    from public.reglas_automatizacion r
    where r.id = p.regla_id and r.nombre = 'Revisión' and p.desactivada_en is not null$$,
  'PT409', 'Un periodo de activación cerrado no se puede modificar.',
  'un periodo cerrado no cambia su cierre'
);

select throws_ok(
  $$update public.periodos_activacion_regla p set desactivada_en = null
    from public.reglas_automatizacion r
    where r.id = p.regla_id and r.nombre = 'Revisión' and p.desactivada_en is not null$$,
  'PT409', 'Un periodo de activación cerrado no se puede modificar.',
  'un periodo cerrado no se reabre'
);

select throws_ok(
  $$update public.periodos_activacion_regla p set activada_en = p.activada_en - interval '1 day'
    from public.reglas_automatizacion r
    where r.id = p.regla_id and r.nombre = 'Revisión' and p.desactivada_en is null$$,
  'PT400', 'Un periodo de activación solo admite su cierre.',
  'un periodo abierto no admite otro cambio que su cierre'
);

select throws_ok(
  $$delete from public.periodos_activacion_regla p
    using public.reglas_automatizacion r
    where r.id = p.regla_id and r.nombre = 'Revisión'$$,
  'PT409', 'Los periodos de activación no se pueden eliminar.',
  'ningún periodo se puede borrar'
);

select throws_ok(
  $$truncate public.periodos_activacion_regla$$,
  'PT409', 'Los periodos de activación no se pueden eliminar.',
  'la tabla de periodos no se puede truncar'
);

select throws_ok(
  $$insert into public.periodos_activacion_regla (organizacion_id, regla_id, activada_en, desactivada_en)
    select organizacion_id, id, '2026-01-02 00:00:00+00', '2026-01-01 00:00:00+00'
    from public.reglas_automatizacion where nombre = 'Vencidas'$$,
  '23514', null,
  'un cierre anterior a la apertura se rechaza'
);

-- -----------------------------------------------------------------------------
-- RLS y aislamiento
-- -----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';

select results_eq(
  $$select (select count(*) from public.reglas_automatizacion)::int || ':' ||
           (select count(*) from public.versiones_regla)::int || ':' ||
           (select count(*) from public.periodos_activacion_regla)::int$$,
  array['2:3:2'],
  'miembro_a ve las reglas, versiones y periodos de A'
);

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select is_empty(
  $$select id from public.reglas_automatizacion
    union all select id from public.versiones_regla
    union all select id from public.periodos_activacion_regla$$,
  'propietario_b no ve nada de las reglas de A'
);

set local role anon;
select throws_ok(
  $$select id from public.reglas_automatizacion$$,
  '42501', null,
  'anon no puede leer reglas'
);

reset role;
select ok(
  not has_table_privilege('authenticated', 'public.reglas_automatizacion', 'insert, update, delete, truncate')
  and not has_table_privilege('authenticated', 'public.versiones_regla', 'insert, update, delete, truncate')
  and not has_table_privilege('authenticated', 'public.periodos_activacion_regla', 'insert, update, delete, truncate'),
  'authenticated no puede escribir directamente en las tablas de reglas'
);

select ok(
  not has_function_privilege('authenticated',
    'privado.validar_definicion_regla(uuid, public.tipo_evento_automatizacion, jsonb, jsonb)', 'execute'),
  'authenticated no puede llamar a la validación interna'
);

select * from finish();
rollback;
