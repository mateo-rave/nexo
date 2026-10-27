-- Eventos y ejecución de reglas de automatización (fase 5, bloque 5.2;
-- ADR-0008): emisión de eventos, reparto según el momento del evento,
-- ejecución, idempotencia por regla y evento, una notificación por evento y
-- destinatario, integración con el detector, 3 intentos en total, errores
-- definitivos, tarea borrada, profundidad y ciclos, correspondencia de las
-- notificaciones, RLS y aislamiento.
-- La cola se procesa con instantes fijos de 2100 (posteriores a todos los
-- eventos), así el reparto y los reintentos se prueban con tiempo controlado.
begin;
create extension if not exists pgtap with schema extensions;
select plan(62);

-- Datos sintéticos (como postgres, sin RLS).
-- 1111 propietario_a · 2222 administrador_a · 3333 miembro_a
-- 4444 propietario_b · aaaa organización A · bbbb B · a1a1 proyecto de A
-- Tareas de A, todas con responsable miembro_a:
--   c1..01 Estado · c1..02 Reintentos · c1..03 Recupera · c1..04 Borrada
--   c1..05 Error · c1..06 Vencida · c1..07 Resuelta (las dos últimas vencidas)
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
   (select id from public.versiones_flujo where organizacion_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 'PA');

insert into public.tareas (id, organizacion_id, proyecto_id, titulo, responsable_id, fecha_limite) values
  ('c1000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'a1a1a1a1-0000-0000-0000-000000000001', 'Estado', '33333333-3333-3333-3333-333333333333', null),
  ('c1000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'a1a1a1a1-0000-0000-0000-000000000001', 'Reintentos', '33333333-3333-3333-3333-333333333333', null),
  ('c1000000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'a1a1a1a1-0000-0000-0000-000000000001', 'Recupera', '33333333-3333-3333-3333-333333333333', null),
  ('c1000000-0000-0000-0000-000000000004', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'a1a1a1a1-0000-0000-0000-000000000001', 'Borrada', '33333333-3333-3333-3333-333333333333', null),
  ('c1000000-0000-0000-0000-000000000005', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'a1a1a1a1-0000-0000-0000-000000000001', 'Error', '33333333-3333-3333-3333-333333333333', null),
  ('c1000000-0000-0000-0000-000000000006', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'a1a1a1a1-0000-0000-0000-000000000001', 'Vencida', '33333333-3333-3333-3333-333333333333', '2026-01-01'),
  ('c1000000-0000-0000-0000-000000000007', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'a1a1a1a1-0000-0000-0000-000000000001', 'Resuelta', '33333333-3333-3333-3333-333333333333', '2026-01-01');

-- Regla de B, activa desde el principio: nunca debe actuar sobre eventos de A.
set local role authenticated;
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
do $$
declare v public.versiones_regla;
begin
  v := public.crear_regla('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'RB', 'tarea_estado_cambiado', '[]',
    '[{"tipo": "notificar", "destinatarios": "propietarios_y_administradores"}]');
  perform public.publicar_version_regla(v.id);
  perform public.activar_regla(v.regla_id);
end $$;

-- -----------------------------------------------------------------------------
-- 1. Cambio de estado → evento → ejecución exitosa
-- R1: tarea_estado_cambiado a en_curso → notificar a propietarios y
-- administradores.
-- -----------------------------------------------------------------------------
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
declare v public.versiones_regla;
begin
  v := public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'R1', 'tarea_estado_cambiado',
    '[{"tipo": "estado_destino", "estados": ["en_curso"]}]',
    '[{"tipo": "notificar", "destinatarios": "propietarios_y_administradores"}]');
  perform public.publicar_version_regla(v.id);
  perform public.activar_regla(v.regla_id);
  perform public.cambiar_estado_tarea('c1000000-0000-0000-0000-000000000001', 'en_curso');
end $$;

reset role;
select results_eq(
  $$select count(*)::int from public.eventos_automatizacion
    where tarea_id = 'c1000000-0000-0000-0000-000000000001' and tipo = 'tarea_estado_cambiado'$$,
  array[1],
  'un cambio de estado deja un evento en la cola'
);

select ok(
  (select datos ->> 'estado_anterior' = 'pendiente'
      and datos ->> 'estado_nuevo' = 'en_curso'
      and datos ->> 'titulo' = 'Estado'
      and clave_evento = 'tarea_estado_cambiado:' || id::text
      and procesado_en is null
      and profundidad = 0
      and ejecucion_origen_id is null
   from public.eventos_automatizacion
   where tarea_id = 'c1000000-0000-0000-0000-000000000001'),
  'el evento guarda la instantánea del cambio y queda sin procesar'
);

set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select throws_ok(
  $$select id from public.eventos_automatizacion$$,
  '42501', null,
  'la cola de eventos no se expone a los usuarios'
);

reset role;
select results_eq(
  $$select privado.procesar_automatizaciones('2100-01-01 00:00:00+00')$$,
  array[1],
  'el procesamiento crea y ejecuta una ejecución'
);

select ok(
  (select x.estado = 'exitosa'
      and x.intentos = 1
      and x.terminada_en = '2100-01-01 00:00:00+00'
      and x.codigo_error is null
      and x.version_regla_id = (select v.id from public.versiones_regla v where v.regla_id = r.id and v.numero = 1)
   from public.ejecuciones_automatizacion x
   join public.reglas_automatizacion r on r.id = x.regla_id
   where r.nombre = 'R1'),
  'la ejecución es exitosa, en el primer intento y con la versión aplicada'
);

select ok(
  (select a.estado = 'completada'
      and a.tipo = 'notificar'
      and a.resultado -> 'notificados' @> '["11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"]'
      and jsonb_array_length(a.resultado -> 'notificados') = 2
      and a.resultado -> 'omitidos' = '[]'::jsonb
   from public.acciones_automatizacion a
   join public.ejecuciones_automatizacion x on x.id = a.ejecucion_id
   join public.reglas_automatizacion r on r.id = x.regla_id
   where r.nombre = 'R1'),
  'la acción queda completada con sus destinatarios'
);

select set_eq(
  $$select n.destinatario_id::text || ':' || n.titulo || ':' || n.mensaje || ':' || (n.hallazgo_id is null)::text
    from public.notificaciones n
    join public.eventos_automatizacion e on e.id = n.evento_id
    where e.tarea_id = 'c1000000-0000-0000-0000-000000000001'$$,
  array[
    '11111111-1111-1111-1111-111111111111:Regla «R1»:La tarea «Estado» pasó a En curso.:true',
    '22222222-2222-2222-2222-222222222222:Regla «R1»:La tarea «Estado» pasó a En curso.:true'
  ],
  'notifica a propietario y administrador con el evento y la acción de origen'
);

select ok(
  (select procesado_en = '2100-01-01 00:00:00+00' from public.eventos_automatizacion
   where tarea_id = 'c1000000-0000-0000-0000-000000000001'),
  'el evento queda marcado como procesado'
);

select results_eq(
  $$select privado.procesar_automatizaciones('2100-01-01 00:01:00+00')$$,
  array[0],
  'volver a procesar no ejecuta nada más'
);

select results_eq(
  $$select (select count(*) from public.ejecuciones_automatizacion)::int || ':' ||
           (select count(*) from public.notificaciones where evento_id is not null)::int$$,
  array['1:2'],
  'ni duplica ejecuciones ni notificaciones'
);

select ok(
  (select count(*) = 1 from public.auditoria
   where accion = 'ejecucion.terminada' and actor_id is null and detalles ->> 'estado' = 'exitosa'),
  'la ejecución terminada queda en auditoría como acción del sistema'
);

-- -----------------------------------------------------------------------------
-- 2. Condiciones no cumplidas y una notificación por evento y destinatario
-- R2 y R3 hacen lo mismo (en_revision → propietarios y administradores).
-- -----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
declare v public.versiones_regla;
begin
  v := public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'R2', 'tarea_estado_cambiado',
    '[{"tipo": "estado_destino", "estados": ["en_revision"]}]',
    '[{"tipo": "notificar", "destinatarios": "propietarios_y_administradores"}]');
  perform public.publicar_version_regla(v.id);
  perform public.activar_regla(v.regla_id);
  v := public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'R3', 'tarea_estado_cambiado',
    '[{"tipo": "estado_destino", "estados": ["en_revision"]}]',
    '[{"tipo": "notificar", "destinatarios": "propietarios_y_administradores"}]');
  perform public.publicar_version_regla(v.id);
  perform public.activar_regla(v.regla_id);
  perform public.cambiar_estado_tarea('c1000000-0000-0000-0000-000000000001', 'en_revision');
end $$;

reset role;
select results_eq(
  $$select privado.procesar_automatizaciones('2100-01-01 00:02:00+00')$$,
  array[3],
  'el evento se reparte a las tres reglas activas con ese activador'
);

select ok(
  (select x.estado = 'omitida'
      and x.codigo_error = 'condiciones_no_cumplidas'
      and x.mensaje_error = 'El evento no cumple las condiciones de la regla.'
   from public.ejecuciones_automatizacion x
   join public.reglas_automatizacion r on r.id = x.regla_id
   join public.eventos_automatizacion e on e.id = x.evento_id
   where r.nombre = 'R1' and e.datos ->> 'estado_nuevo' = 'en_revision'),
  'R1 queda omitida con su motivo: el evento no cumple sus condiciones'
);

select results_eq(
  $$select count(*)::int from public.notificaciones n
    join public.eventos_automatizacion e on e.id = n.evento_id
    where e.datos ->> 'estado_nuevo' = 'en_revision'$$,
  array[2],
  'dos reglas que avisan a las mismas personas por el mismo evento crean una sola notificación por persona'
);

select ok(
  (select count(*) = 2
      and bool_and(x.estado = 'exitosa')
      and sum(jsonb_array_length(a.resultado -> 'omitidos')) = 2
      and bool_and(not exists (
        select 1 from jsonb_array_elements(a.resultado -> 'omitidos') o (valor)
        where o.valor ->> 'motivo' <> 'ya_notificado'))
   from public.ejecuciones_automatizacion x
   join public.reglas_automatizacion r on r.id = x.regla_id
   join public.acciones_automatizacion a on a.ejecucion_id = x.id
   where r.nombre in ('R2', 'R3')),
  'la segunda regla omite a quien ya fue avisado (ya_notificado) y aun así termina exitosa'
);

-- Se pausan R1, R2 y R3 para aislar los escenarios siguientes.
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
begin
  perform public.pausar_regla((select id from public.reglas_automatizacion where nombre = 'R1'));
  perform public.pausar_regla((select id from public.reglas_automatizacion where nombre = 'R2'));
  perform public.pausar_regla((select id from public.reglas_automatizacion where nombre = 'R3'));
end $$;

-- -----------------------------------------------------------------------------
-- 3. Semántica temporal: decide el momento del evento (ADR-0008, apartado 7)
-- R4: tarea_estado_cambiado sin condiciones → notificar al responsable.
-- Los eventos sintéticos se insertan como postgres con su ocurrido_en.
-- -----------------------------------------------------------------------------
do $$
declare v public.versiones_regla;
begin
  v := public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'R4', 'tarea_estado_cambiado', '[]',
    '[{"tipo": "notificar", "destinatarios": "responsable"}]');
  perform public.publicar_version_regla(v.id);
  perform public.activar_regla(v.regla_id);
end $$;

reset role;
-- Evento anterior a la activación (y a la publicación).
insert into public.eventos_automatizacion (organizacion_id, tipo, tarea_id, clave_evento, datos, ocurrido_en)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'tarea_estado_cambiado', 'c1000000-0000-0000-0000-000000000001',
  'prueba:antes',
  '{"titulo": "Estado", "estado_anterior": "pendiente", "estado_nuevo": "en_curso",
    "proyecto_id": "a1a1a1a1-0000-0000-0000-000000000001", "responsable_id": "33333333-3333-3333-3333-333333333333"}',
  '2000-01-01 00:00:00+00');

-- Evento con R4 activa; después se pausa R4; otro evento durante la pausa; y
-- se reactiva R4, todo antes de procesar.
insert into public.eventos_automatizacion (organizacion_id, tipo, tarea_id, clave_evento, datos, ocurrido_en)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'tarea_estado_cambiado', 'c1000000-0000-0000-0000-000000000001',
  'prueba:durante',
  '{"titulo": "Estado", "estado_anterior": "pendiente", "estado_nuevo": "en_curso",
    "proyecto_id": "a1a1a1a1-0000-0000-0000-000000000001", "responsable_id": "33333333-3333-3333-3333-333333333333"}',
  clock_timestamp());

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
begin
  perform public.pausar_regla((select id from public.reglas_automatizacion where nombre = 'R4'));
end $$;

reset role;
insert into public.eventos_automatizacion (organizacion_id, tipo, tarea_id, clave_evento, datos, ocurrido_en)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'tarea_estado_cambiado', 'c1000000-0000-0000-0000-000000000001',
  'prueba:en_pausa',
  '{"titulo": "Estado", "estado_anterior": "pendiente", "estado_nuevo": "en_curso",
    "proyecto_id": "a1a1a1a1-0000-0000-0000-000000000001", "responsable_id": "33333333-3333-3333-3333-333333333333"}',
  clock_timestamp());

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
begin
  perform public.activar_regla((select id from public.reglas_automatizacion where nombre = 'R4'));
end $$;

-- Evento con R4 reactivada; después se publica una versión 2 que ya no lo
-- aceptaría (solo completada).
reset role;
insert into public.eventos_automatizacion (organizacion_id, tipo, tarea_id, clave_evento, datos, ocurrido_en)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'tarea_estado_cambiado', 'c1000000-0000-0000-0000-000000000001',
  'prueba:version',
  '{"titulo": "Estado", "estado_anterior": "pendiente", "estado_nuevo": "en_curso",
    "proyecto_id": "a1a1a1a1-0000-0000-0000-000000000001", "responsable_id": "33333333-3333-3333-3333-333333333333"}',
  clock_timestamp());

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
declare v public.versiones_regla;
begin
  v := public.crear_version_borrador_regla(
    (select v1.id from public.versiones_regla v1 join public.reglas_automatizacion r on r.id = v1.regla_id
     where r.nombre = 'R4' and v1.numero = 1));
  perform public.guardar_borrador_regla(v.id, 'tarea_estado_cambiado',
    '[{"tipo": "estado_destino", "estados": ["completada"]}]',
    '[{"tipo": "notificar", "destinatarios": "responsable"}]');
  perform public.publicar_version_regla(v.id);
end $$;

reset role;
select lives_ok(
  $$select privado.procesar_automatizaciones('2100-01-01 00:03:00+00')$$,
  'se procesan los eventos sintéticos'
);

select is_empty(
  $$select x.id from public.ejecuciones_automatizacion x
    join public.eventos_automatizacion e on e.id = x.evento_id
    where e.clave_evento = 'prueba:antes'$$,
  'un evento anterior a la activación no ejecuta ninguna regla, aunque estén activas al procesarlo'
);

select ok(
  (select x.estado = 'exitosa'
   from public.ejecuciones_automatizacion x
   join public.reglas_automatizacion r on r.id = x.regla_id
   join public.eventos_automatizacion e on e.id = x.evento_id
   where r.nombre = 'R4' and e.clave_evento = 'prueba:durante'),
  'un evento ocurrido con la regla activa la ejecuta, aunque se pausara antes de procesarlo'
);

select is_empty(
  $$select x.id from public.ejecuciones_automatizacion x
    join public.eventos_automatizacion e on e.id = x.evento_id
    where e.clave_evento = 'prueba:en_pausa'$$,
  'un evento ocurrido durante una pausa no la ejecuta, aunque se reactivara antes de procesarlo'
);

select ok(
  (select x.estado = 'exitosa'
      and x.version_regla_id = (select v.id from public.versiones_regla v where v.regla_id = r.id and v.numero = 1)
   from public.ejecuciones_automatizacion x
   join public.reglas_automatizacion r on r.id = x.regla_id
   join public.eventos_automatizacion e on e.id = x.evento_id
   where r.nombre = 'R4' and e.clave_evento = 'prueba:version'),
  'un evento usa la versión publicada antes de él, aunque se publique otra antes de procesarlo'
);

select results_eq(
  $$select count(*)::int from public.ejecuciones_automatizacion x
    join public.reglas_automatizacion r on r.id = x.regla_id where r.nombre = 'R4'$$,
  array[2],
  'procesar más tarde no cambia qué eventos ejecutan la regla'
);

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
begin
  perform public.pausar_regla((select id from public.reglas_automatizacion where nombre = 'R4'));
end $$;

-- -----------------------------------------------------------------------------
-- 4. Integración con el detector de vencimientos
-- RV: tarea_vencida → responsable (ya avisado por el detector).
-- RV2: tarea_vencida → propietarios y administradores.
-- -----------------------------------------------------------------------------
do $$
declare v public.versiones_regla;
begin
  v := public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'RV', 'tarea_vencida', '[]',
    '[{"tipo": "notificar", "destinatarios": "responsable"}]');
  perform public.publicar_version_regla(v.id);
  perform public.activar_regla(v.regla_id);
  v := public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'RV2', 'tarea_vencida', '[]',
    '[{"tipo": "notificar", "destinatarios": "propietarios_y_administradores"}]');
  perform public.publicar_version_regla(v.id);
  perform public.activar_regla(v.regla_id);
end $$;

reset role;
select results_eq(
  $$select privado.detectar_tareas_vencidas(clock_timestamp() + interval '1 minute')$$,
  array[2],
  'el detector crea los dos hallazgos'
);

select ok(
  (select count(*) = 2
      and bool_and(e.hallazgo_id = h.id)
      and bool_and(e.clave_evento = 'tarea_vencida:' || h.id::text)
      and bool_and(e.ocurrido_en = h.detectado_en)
      and bool_and(e.tarea_id = h.tarea_id)
   from public.eventos_automatizacion e
   join public.hallazgos h on h.id = e.hallazgo_id
   where e.tipo = 'tarea_vencida'),
  'cada hallazgo nuevo anuncia un evento tarea_vencida con su hallazgo, en el instante de la detección'
);

select results_eq(
  $$select privado.detectar_tareas_vencidas(clock_timestamp() + interval '2 minutes') || ':' ||
           (select count(*) from public.eventos_automatizacion where tipo = 'tarea_vencida')::int$$,
  array['0:2'],
  'volver a detectar no duplica hallazgos ni eventos'
);

-- El hallazgo de Resuelta se resuelve antes de procesar.
update public.hallazgos set resuelto_en = now(), resuelto_por = '22222222-2222-2222-2222-222222222222'
where tarea_id = 'c1000000-0000-0000-0000-000000000007';

select lives_ok(
  $$select privado.procesar_automatizaciones('2100-01-01 00:06:00+00')$$,
  'se procesan los eventos de vencimiento'
);

select ok(
  (select x.estado = 'exitosa'
      and a.estado = 'completada'
      and a.resultado -> 'notificados' = '[]'::jsonb
      and a.resultado -> 'omitidos' = '[{"destinatario_id": "33333333-3333-3333-3333-333333333333", "motivo": "ya_notificado"}]'::jsonb
   from public.ejecuciones_automatizacion x
   join public.reglas_automatizacion r on r.id = x.regla_id
   join public.acciones_automatizacion a on a.ejecucion_id = x.id
   join public.eventos_automatizacion e on e.id = x.evento_id
   where r.nombre = 'RV' and e.tarea_id = 'c1000000-0000-0000-0000-000000000006'),
  'la regla no vuelve a avisar al responsable que ya avisó el detector'
);

select set_eq(
  $$select n.destinatario_id::text || ':' || (n.evento_id is null)::text
    from public.notificaciones n
    join public.hallazgos h on h.id = n.hallazgo_id
    where h.tarea_id = 'c1000000-0000-0000-0000-000000000006'$$,
  array[
    '33333333-3333-3333-3333-333333333333:true',
    '11111111-1111-1111-1111-111111111111:false',
    '22222222-2222-2222-2222-222222222222:false'
  ],
  'la notificación del detector no cambia y RV2 avisa a propietario y administrador con el mismo hallazgo'
);

select ok(
  (select count(*) = 2 and bool_and(x.estado = 'omitida' and x.codigo_error = 'hallazgo_resuelto')
   from public.ejecuciones_automatizacion x
   join public.eventos_automatizacion e on e.id = x.evento_id
   where e.tarea_id = 'c1000000-0000-0000-0000-000000000007'),
  'con el hallazgo ya resuelto, las reglas quedan omitidas'
);

-- -----------------------------------------------------------------------------
-- 5. Restricción de origen y correspondencia de las notificaciones
-- -----------------------------------------------------------------------------
select throws_ok(
  $$insert into public.notificaciones (organizacion_id, destinatario_id, evento_id, accion_id, titulo, mensaje)
    select x.organizacion_id, '33333333-3333-3333-3333-333333333333', x.evento_id, a.id, 'T', 'M'
    from public.ejecuciones_automatizacion x
    join public.reglas_automatizacion r on r.id = x.regla_id
    join public.acciones_automatizacion a on a.ejecucion_id = x.id
    join public.eventos_automatizacion e on e.id = x.evento_id
    where r.nombre = 'RV2' and e.tarea_id = 'c1000000-0000-0000-0000-000000000006'$$,
  'PT400', 'La notificación no corresponde a su evento.',
  'una notificación de una regla sobre un vencimiento no puede omitir el hallazgo'
);

select throws_ok(
  $$insert into public.notificaciones (organizacion_id, destinatario_id, evento_id, accion_id, titulo, mensaje)
    select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333',
           (select e.id from public.eventos_automatizacion e
            where e.tarea_id = 'c1000000-0000-0000-0000-000000000001' and e.clave_evento like 'tarea_estado_cambiado:%'
            order by e.ocurrido_en limit 1),
           a.id, 'T', 'M'
    from public.acciones_automatizacion a
    join public.ejecuciones_automatizacion x on x.id = a.ejecucion_id
    join public.reglas_automatizacion r on r.id = x.regla_id
    where r.nombre = 'R4'
    limit 1$$,
  'PT400', 'La notificación no corresponde a su evento.',
  'la acción debe pertenecer a una ejecución del mismo evento'
);

select throws_ok(
  $$insert into public.notificaciones (organizacion_id, destinatario_id, accion_id, titulo, mensaje)
    select a.organizacion_id, '33333333-3333-3333-3333-333333333333', a.id, 'T', 'M'
    from public.acciones_automatizacion a
    join public.ejecuciones_automatizacion x on x.id = a.ejecucion_id
    join public.reglas_automatizacion r on r.id = x.regla_id
    where r.nombre = 'R4'
    limit 1$$,
  '23514', null,
  'una acción sin evento no es un origen válido (evento y acción van juntos)'
);

select throws_ok(
  $$insert into public.notificaciones (organizacion_id, destinatario_id, titulo, mensaje)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'T', 'M')$$,
  '23514', null,
  'una notificación sin ningún origen se rechaza'
);

select lives_ok(
  $$insert into public.notificaciones (organizacion_id, destinatario_id, hallazgo_id, titulo, mensaje)
    select h.organizacion_id, '11111111-1111-1111-1111-111111111111', h.id, 'Tarea vencida', 'M'
    from public.hallazgos h where h.tarea_id = 'c1000000-0000-0000-0000-000000000007'$$,
  'la forma del detector (solo hallazgo) sigue siendo válida'
);

-- -----------------------------------------------------------------------------
-- 6. Reintentos: 3 intentos en total, incluido el primero
-- RR: tarea_estado_cambiado a en_curso → responsable. Un trigger de prueba
-- simula fallos al insertar ciertas notificaciones:
--   «Reintentos»: siempre un fallo transitorio (bloqueo no disponible);
--   «Recupera»: un fallo transitorio la primera vez;
--   «Error»: un error que no es transitorio.
-- -----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
declare v public.versiones_regla;
begin
  v := public.crear_regla('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'RR', 'tarea_estado_cambiado',
    '[{"tipo": "estado_destino", "estados": ["en_curso"]}]',
    '[{"tipo": "notificar", "destinatarios": "responsable"}]');
  perform public.publicar_version_regla(v.id);
  perform public.activar_regla(v.regla_id);
end $$;

reset role;
create sequence public.prueba_fallos_recupera;

create function public.prueba_fallo_notificacion()
returns trigger
language plpgsql
as $$
begin
  if new.mensaje like '%«Reintentos»%' then
    raise exception using errcode = '55P03', message = 'bloqueo de prueba';
  end if;
  if new.mensaje like '%«Recupera»%' then
    if nextval('public.prueba_fallos_recupera') = 1 then
      raise exception using errcode = '55P03', message = 'bloqueo de prueba';
    end if;
  end if;
  if new.mensaje like '%«Error»%' then
    raise exception 'error de prueba';
  end if;
  return new;
end;
$$;

create trigger notificaciones_prueba_fallo
  before insert on public.notificaciones
  for each row execute function public.prueba_fallo_notificacion();

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
begin
  perform public.cambiar_estado_tarea('c1000000-0000-0000-0000-000000000002', 'en_curso');
end $$;

reset role;
select lives_ok(
  $$select privado.procesar_automatizaciones('2100-01-01 01:00:00+00')$$,
  'intento 1 con un fallo transitorio'
);

select ok(
  (select x.estado = 'pendiente'
      and x.intentos = 1
      and x.proximo_intento_en = '2100-01-01 01:01:00+00'
      and x.codigo_error = 'fallo_transitorio'
      and not exists (select 1 from public.acciones_automatizacion a where a.ejecucion_id = x.id)
      and not exists (select 1 from public.notificaciones n where n.evento_id = x.evento_id)
   from public.ejecuciones_automatizacion x
   join public.eventos_automatizacion e on e.id = x.evento_id
   where e.tarea_id = 'c1000000-0000-0000-0000-000000000002'),
  'tras el intento 1 sigue pendiente, con el siguiente a 1 minuto y sin efectos parciales'
);

select lives_ok(
  $$select privado.procesar_automatizaciones('2100-01-01 01:00:30+00')$$,
  'se procesa antes de que pase la espera'
);

select ok(
  (select x.intentos = 1
   from public.ejecuciones_automatizacion x
   join public.eventos_automatizacion e on e.id = x.evento_id
   where e.tarea_id = 'c1000000-0000-0000-0000-000000000002'),
  'no se reintenta antes de la espera'
);

select lives_ok(
  $$select privado.procesar_automatizaciones('2100-01-01 01:01:00+00')$$,
  'intento 2 con un fallo transitorio'
);

select ok(
  (select x.estado = 'pendiente'
      and x.intentos = 2
      and x.proximo_intento_en = '2100-01-01 01:06:00+00'
   from public.ejecuciones_automatizacion x
   join public.eventos_automatizacion e on e.id = x.evento_id
   where e.tarea_id = 'c1000000-0000-0000-0000-000000000002'),
  'tras el intento 2 sigue pendiente, con el siguiente a 5 minutos'
);

select lives_ok(
  $$select privado.procesar_automatizaciones('2100-01-01 01:06:00+00')$$,
  'intento 3 con un fallo transitorio'
);

select ok(
  (select x.estado = 'fallida'
      and x.intentos = 3
      and x.codigo_error = 'reintentos_agotados'
      and x.mensaje_error = 'No se pudo completar tras agotar los intentos.'
      and x.terminada_en = '2100-01-01 01:06:00+00'
      and (select count(*) = 1 and bool_and(a.estado = 'fallida')
           from public.acciones_automatizacion a where a.ejecucion_id = x.id)
      and not exists (select 1 from public.notificaciones n where n.evento_id = x.evento_id)
   from public.ejecuciones_automatizacion x
   join public.eventos_automatizacion e on e.id = x.evento_id
   where e.tarea_id = 'c1000000-0000-0000-0000-000000000002'),
  'tras el intento 3 queda fallida, con su acción fallida y sin notificaciones'
);

select results_eq(
  $$select privado.procesar_automatizaciones('2100-01-01 02:06:00+00')$$,
  array[0],
  'una ejecución fallida no se vuelve a tomar'
);

select ok(
  (select x.intentos = 3
   from public.ejecuciones_automatizacion x
   join public.eventos_automatizacion e on e.id = x.evento_id
   where e.tarea_id = 'c1000000-0000-0000-0000-000000000002'),
  'no hay un cuarto intento'
);

select ok(
  (select count(*) = 1 from public.auditoria a
   join public.ejecuciones_automatizacion x on x.id = a.recurso_id
   join public.eventos_automatizacion e on e.id = x.evento_id
   where a.accion = 'ejecucion.terminada'
     and e.tarea_id = 'c1000000-0000-0000-0000-000000000002'
     and a.detalles ->> 'estado' = 'fallida'
     and (a.detalles ->> 'intentos')::int = 3),
  'la ejecución fallida queda en auditoría con sus intentos'
);

-- Un fallo transitorio seguido de un éxito.
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
begin
  perform public.cambiar_estado_tarea('c1000000-0000-0000-0000-000000000003', 'en_curso');
end $$;

reset role;
select results_eq(
  $$select privado.procesar_automatizaciones('2100-01-01 03:00:00+00')$$,
  array[1],
  'intento 1 de Recupera, con un fallo transitorio'
);

select results_eq(
  $$select privado.procesar_automatizaciones('2100-01-01 03:01:00+00')$$,
  array[1],
  'intento 2 de Recupera'
);

select ok(
  (select x.estado = 'exitosa' and x.intentos = 2 and x.codigo_error is null
   from public.ejecuciones_automatizacion x
   join public.eventos_automatizacion e on e.id = x.evento_id
   where e.tarea_id = 'c1000000-0000-0000-0000-000000000003')
  and (select count(*) = 1 from public.notificaciones n
       join public.eventos_automatizacion e on e.id = n.evento_id
       where e.tarea_id = 'c1000000-0000-0000-0000-000000000003'),
  'un fallo transitorio seguido de un éxito deja la ejecución exitosa en el intento 2'
);

-- Un error que no es transitorio.
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
begin
  perform public.cambiar_estado_tarea('c1000000-0000-0000-0000-000000000005', 'en_curso');
end $$;

reset role;
select results_eq(
  $$select privado.procesar_automatizaciones('2100-01-01 04:00:00+00')$$,
  array[1],
  'se procesa la ejecución de Error'
);

select ok(
  (select x.estado = 'fallida'
      and x.intentos = 1
      and x.codigo_error = 'error_interno'
      and x.mensaje_error = 'No se pudo completar la ejecución.'
      and not exists (select 1 from public.notificaciones n where n.evento_id = x.evento_id)
   from public.ejecuciones_automatizacion x
   join public.eventos_automatizacion e on e.id = x.evento_id
   where e.tarea_id = 'c1000000-0000-0000-0000-000000000005'),
  'un error que no es transitorio deja la ejecución fallida en el primer intento, sin efectos ni detalles internos'
);

drop trigger notificaciones_prueba_fallo on public.notificaciones;

-- -----------------------------------------------------------------------------
-- 7. Tarea borrada antes de procesar
-- -----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
begin
  perform public.cambiar_estado_tarea('c1000000-0000-0000-0000-000000000004', 'en_curso');
  perform public.eliminar_tarea('c1000000-0000-0000-0000-000000000004');
end $$;

reset role;
select ok(
  (select e.tarea_id is null and e.datos ->> 'titulo' = 'Borrada'
   from public.eventos_automatizacion e where e.datos ->> 'titulo' = 'Borrada'),
  'al borrar la tarea, el evento se conserva con su instantánea y sin la referencia'
);

select results_eq(
  $$select privado.procesar_automatizaciones('2100-01-01 05:00:00+00')$$,
  array[1],
  'se procesa el evento de la tarea borrada'
);

select ok(
  (select x.estado = 'omitida' and x.codigo_error = 'tarea_no_disponible'
   from public.ejecuciones_automatizacion x
   join public.eventos_automatizacion e on e.id = x.evento_id
   where e.datos ->> 'titulo' = 'Borrada'),
  'la ejecución de una tarea borrada queda omitida'
);

-- -----------------------------------------------------------------------------
-- 8. Profundidad y ciclos (ADR-0008, apartado 10), con eventos preparados
-- -----------------------------------------------------------------------------
insert into public.eventos_automatizacion (
  organizacion_id, tipo, tarea_id, clave_evento, datos, ocurrido_en, profundidad
)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'tarea_estado_cambiado', 'c1000000-0000-0000-0000-000000000001',
  'prueba:profundidad',
  '{"titulo": "Estado", "estado_anterior": "pendiente", "estado_nuevo": "en_curso",
    "proyecto_id": "a1a1a1a1-0000-0000-0000-000000000001", "responsable_id": "33333333-3333-3333-3333-333333333333"}',
  clock_timestamp(), 4);

insert into public.eventos_automatizacion (
  organizacion_id, tipo, tarea_id, clave_evento, datos, ocurrido_en, ejecucion_origen_id, profundidad
)
select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'tarea_estado_cambiado', 'c1000000-0000-0000-0000-000000000001',
  'prueba:ciclo',
  '{"titulo": "Estado", "estado_anterior": "pendiente", "estado_nuevo": "en_curso",
    "proyecto_id": "a1a1a1a1-0000-0000-0000-000000000001", "responsable_id": "33333333-3333-3333-3333-333333333333"}',
  clock_timestamp(), x.id, 1
from public.ejecuciones_automatizacion x
join public.eventos_automatizacion e on e.id = x.evento_id
where e.tarea_id = 'c1000000-0000-0000-0000-000000000003';

select lives_ok(
  $$select privado.procesar_automatizaciones('2100-01-01 06:00:00+00')$$,
  'se procesan los eventos de profundidad y ciclo'
);

select ok(
  (select x.estado = 'omitida' and x.codigo_error = 'profundidad_maxima'
   from public.ejecuciones_automatizacion x
   join public.eventos_automatizacion e on e.id = x.evento_id
   where e.clave_evento = 'prueba:profundidad'),
  'un evento que supera la profundidad máxima no ejecuta la regla'
);

select ok(
  (select x.estado = 'omitida' and x.codigo_error = 'ciclo_detectado'
   from public.ejecuciones_automatizacion x
   join public.eventos_automatizacion e on e.id = x.evento_id
   where e.clave_evento = 'prueba:ciclo'),
  'una regla no se ejecuta por un evento que ella misma causó'
);

-- El trigger de tareas hereda el origen que fija el motor en la transacción.
do $$
begin
  perform set_config('nexo.ejecucion_origen_id',
    (select x.id::text from public.ejecuciones_automatizacion x
     join public.eventos_automatizacion e on e.id = x.evento_id
     where e.tarea_id = 'c1000000-0000-0000-0000-000000000003'),
    true);
end $$;

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
begin
  perform public.cambiar_estado_tarea('c1000000-0000-0000-0000-000000000001', 'en_curso');
end $$;

reset role;
select ok(
  (select e.ejecucion_origen_id = (
            select x.id from public.ejecuciones_automatizacion x
            join public.eventos_automatizacion o on o.id = x.evento_id
            where o.tarea_id = 'c1000000-0000-0000-0000-000000000003')
      and e.profundidad = 1
   from public.eventos_automatizacion e
   where e.tarea_id = 'c1000000-0000-0000-0000-000000000001'
     and e.clave_evento like 'tarea_estado_cambiado:%'
   order by e.ocurrido_en desc
   limit 1),
  'un cambio de estado causado por una ejecución hereda su origen y profundidad + 1'
);

do $$
begin
  perform set_config('nexo.ejecucion_origen_id', '', true);
end $$;

-- -----------------------------------------------------------------------------
-- 9. RLS, aislamiento y permisos
-- -----------------------------------------------------------------------------
select is_empty(
  $$select x.id from public.ejecuciones_automatizacion x
    join public.reglas_automatizacion r on r.id = x.regla_id where r.nombre = 'RB'$$,
  'una regla de B nunca actúa sobre eventos de A'
);

set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select ok(
  (select count(*) > 0 from public.ejecuciones_automatizacion)
  and (select count(*) > 0 from public.acciones_automatizacion),
  'miembro_a ve las ejecuciones y acciones de A'
);

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select is_empty(
  $$select id from public.ejecuciones_automatizacion union all select id from public.acciones_automatizacion$$,
  'propietario_b no ve las ejecuciones ni las acciones de A'
);

reset role;
select ok(
  not has_table_privilege('authenticated', 'public.eventos_automatizacion', 'select, insert, update, delete, truncate')
  and not has_table_privilege('authenticated', 'public.ejecuciones_automatizacion', 'insert, update, delete, truncate')
  and not has_table_privilege('authenticated', 'public.acciones_automatizacion', 'insert, update, delete, truncate'),
  'authenticated no lee la cola ni escribe en ejecuciones ni acciones'
);

select ok(
  not has_function_privilege('authenticated', 'privado.procesar_automatizaciones(timestamptz)', 'execute')
  and not has_function_privilege('authenticated', 'privado.ejecutar_automatizacion(uuid, timestamptz)', 'execute'),
  'nadie puede lanzar el procesamiento desde la API'
);

select results_eq(
  $$select schedule || ' | ' || command from cron.job where jobname = 'procesar_automatizaciones'$$,
  array['* * * * * | select privado.procesar_automatizaciones(now())'],
  'el job programado procesa la cola cada minuto'
);

select * from finish();
rollback;
