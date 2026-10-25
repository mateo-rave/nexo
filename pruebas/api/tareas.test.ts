// Pruebas de integración de API: proyectos y tareas (fase 2, bloque 2; ADR-0007).
// Complementan supabase/tests/proyectos_tareas.test.sql: comprueban a través
// de la Data API, con la clave publicable y la sesión de cada usuario, los
// permisos, el aislamiento, las transiciones, los vencimientos, el cambio de
// zona horaria y la salida de miembros.

import assert from "node:assert/strict";
import {
    comprobarExito,
    comprobarRechazo,
    crearCliente,
    type Escenario,
    llamarRpc,
    prepararEscenario,
    type RechazoEsperado,
    rechazos,
    rechazoSinPermisoExecute,
    type Usuario,
} from "./auxiliares.ts";

// Filas tal como las devuelve la Data API (nombres de columna del contrato).
type Tarea = {
    id: string;
    estado: string;
    responsable_id: string | null;
    fecha_limite: string | null;
    vence_en: string | null;
};

type Auditoria = {
    accion: string;
    actor_id: string | null;
    recurso_id: string | null;
    detalles: Record<string, unknown>;
};

// Códigos de error nuevos de este bloque (campo details del contrato).
function rechazoPropio(estadoHttp: number, details: string, message: string): RechazoEsperado {
    return { estadoHttp, code: `PT${estadoHttp}`, message, details };
}

const rechazosTareas = {
    tarea_no_encontrada: rechazoPropio(
        404,
        "tarea_no_encontrada",
        "La tarea no existe o no tienes acceso a ella.",
    ),
    proyecto_no_encontrado: rechazoPropio(
        404,
        "proyecto_no_encontrado",
        "El proyecto no existe o no tienes acceso a él.",
    ),
    transicion_no_permitida: rechazoPropio(
        409,
        "transicion_no_permitida",
        "El flujo del proyecto no permite ese cambio de estado.",
    ),
};

// El instante tal como lo serializa PostgREST, normalizado a UTC.
function instante(valor: string | null): string | null {
    return valor === null ? null : new Date(valor).toISOString();
}

async function crearProyecto(escenario: Escenario): Promise<string> {
    const resultado = await llamarRpc(
        escenario.usuarios.administrador_a.cliente,
        "crear_proyecto",
        { p_organizacion_id: escenario.organizacionA, p_nombre: "Web" },
    );
    comprobarExito(resultado, 200);
    return (resultado.datos as { id: string }).id;
}

async function crearTarea(
    quien: Usuario,
    proyectoId: string,
    argumentos: Record<string, unknown>,
): Promise<Tarea> {
    const resultado = await llamarRpc(quien.cliente, "crear_tarea", {
        p_proyecto_id: proyectoId,
        ...argumentos,
    });
    comprobarExito(resultado, 200);
    return resultado.datos as Tarea;
}

async function leerTarea(lector: Usuario, tareaId: string): Promise<Tarea[]> {
    const { data, error } = await lector.cliente.supabase
        .from("tareas")
        .select("id, estado, responsable_id, fecha_limite, vence_en")
        .eq("id", tareaId);
    if (error) {
        throw new Error(`No se pudo leer la tarea: ${error.message}`);
    }
    return data as Tarea[];
}

async function leerAuditoria(lector: Usuario, organizacionId: string): Promise<Auditoria[]> {
    const { data, error } = await lector.cliente.supabase
        .from("auditoria")
        .select("accion, actor_id, recurso_id, detalles")
        .eq("organizacion_id", organizacionId)
        .order("id");
    if (error) {
        throw new Error(`No se pudo leer la auditoría: ${error.message}`);
    }
    return data as Auditoria[];
}

Deno.test("crear_tarea: sin sesión, la llamada se rechaza", async () => {
    const escenario = await prepararEscenario();
    const proyectoId = await crearProyecto(escenario);

    const resultado = await llamarRpc(crearCliente(), "crear_tarea", {
        p_proyecto_id: proyectoId,
        p_titulo: "Anónima",
    });

    comprobarRechazo(resultado, rechazoSinPermisoExecute("crear_tarea"));
});

Deno.test("proyectos y tareas: permisos de creación y fechas límite con y sin hora", async () => {
    const escenario = await prepararEscenario();
    const { usuarios, organizacionA } = escenario;

    const rechazado = await llamarRpc(usuarios.miembro_a.cliente, "crear_proyecto", {
        p_organizacion_id: organizacionA,
        p_nombre: "No",
    });
    comprobarRechazo(rechazado, rechazos.permiso_denegado);

    const proyectoId = await crearProyecto(escenario);

    // Zona de A por defecto: America/Bogota (UTC-5).
    const sinHora = await crearTarea(usuarios.miembro_a, proyectoId, {
        p_titulo: "Sin hora",
        p_fecha_limite: "2026-12-01",
    });
    assert.equal(sinHora.estado, "pendiente");
    assert.equal(sinHora.fecha_limite, "2026-12-01");
    assert.equal(instante(sinHora.vence_en), "2026-12-02T05:00:00.000Z");

    const conHora = await crearTarea(usuarios.miembro_a, proyectoId, {
        p_titulo: "Con hora",
        p_fecha_limite: "2026-12-01",
        p_hora_limite: "17:00",
    });
    assert.equal(conHora.fecha_limite, null);
    assert.equal(instante(conHora.vence_en), "2026-12-01T22:00:00.000Z");
});

Deno.test("aislamiento: propietario_b no ve ni modifica las tareas de A", async () => {
    const escenario = await prepararEscenario();
    const { usuarios } = escenario;
    const proyectoId = await crearProyecto(escenario);
    const tarea = await crearTarea(usuarios.miembro_a, proyectoId, { p_titulo: "De A" });

    assert.deepEqual(await leerTarea(usuarios.propietario_b, tarea.id), []);

    const cambio = await llamarRpc(usuarios.propietario_b.cliente, "cambiar_estado_tarea", {
        p_tarea_id: tarea.id,
        p_estado: "en_curso",
    });
    comprobarRechazo(cambio, rechazosTareas.tarea_no_encontrada);

    const creacion = await llamarRpc(usuarios.propietario_b.cliente, "crear_tarea", {
        p_proyecto_id: proyectoId,
        p_titulo: "Intrusa",
    });
    comprobarRechazo(creacion, rechazosTareas.proyecto_no_encontrado);

    const [sinCambios] = await leerTarea(usuarios.propietario_a, tarea.id);
    assert.equal(sinCambios.estado, "pendiente");
});

Deno.test("cambiar_estado_tarea: transiciones del flujo y auditoría", async () => {
    const escenario = await prepararEscenario();
    const { usuarios, organizacionA } = escenario;
    const proyectoId = await crearProyecto(escenario);
    const tarea = await crearTarea(usuarios.miembro_a, proyectoId, { p_titulo: "Flujo" });

    const salto = await llamarRpc(usuarios.miembro_a.cliente, "cambiar_estado_tarea", {
        p_tarea_id: tarea.id,
        p_estado: "completada",
    });
    comprobarRechazo(salto, rechazosTareas.transicion_no_permitida);

    const avance = await llamarRpc(usuarios.miembro_a.cliente, "cambiar_estado_tarea", {
        p_tarea_id: tarea.id,
        p_estado: "en_curso",
    });
    comprobarExito(avance, 200);
    assert.equal((avance.datos as Tarea).estado, "en_curso");

    const auditoria = await leerAuditoria(usuarios.propietario_a, organizacionA);
    const cambios = auditoria.filter((registro) => registro.accion === "tarea.estado_cambiado");
    assert.deepEqual(cambios, [{
        accion: "tarea.estado_cambiado",
        actor_id: usuarios.miembro_a.id,
        recurso_id: tarea.id,
        detalles: { estado_anterior: "pendiente", estado_nuevo: "en_curso" },
    }]);
});

Deno.test("permisos: miembro no edita ni elimina tareas ajenas; administrador elimina", async () => {
    const escenario = await prepararEscenario();
    const { usuarios } = escenario;
    const proyectoId = await crearProyecto(escenario);
    const ajena = await crearTarea(usuarios.administrador_a, proyectoId, {
        p_titulo: "Del administrador",
        p_responsable_id: usuarios.administrador_a.id,
    });

    const edicion = await llamarRpc(usuarios.miembro_a.cliente, "editar_tarea", {
        p_tarea_id: ajena.id,
        p_titulo: "Cambio",
        p_descripcion: null,
        p_fecha_limite: null,
        p_hora_limite: null,
    });
    comprobarRechazo(edicion, rechazos.permiso_denegado);

    const borrado = await llamarRpc(usuarios.miembro_a.cliente, "eliminar_tarea", {
        p_tarea_id: ajena.id,
    });
    comprobarRechazo(borrado, rechazos.permiso_denegado);

    const eliminacion = await llamarRpc(usuarios.administrador_a.cliente, "eliminar_tarea", {
        p_tarea_id: ajena.id,
    });
    comprobarExito(eliminacion, 204);
    assert.deepEqual(await leerTarea(usuarios.propietario_a, ajena.id), []);
});

Deno.test("cambiar_zona_horaria: recalcula las tareas abiertas sin hora y conserva las de hora", async () => {
    const escenario = await prepararEscenario();
    const { usuarios, organizacionA } = escenario;
    const proyectoId = await crearProyecto(escenario);
    const sinHora = await crearTarea(usuarios.miembro_a, proyectoId, {
        p_titulo: "Sin hora",
        p_fecha_limite: "2026-12-01",
    });
    const conHora = await crearTarea(usuarios.miembro_a, proyectoId, {
        p_titulo: "Con hora",
        p_fecha_limite: "2026-12-01",
        p_hora_limite: "17:00",
    });

    const rechazado = await llamarRpc(usuarios.miembro_a.cliente, "cambiar_zona_horaria", {
        p_organizacion_id: organizacionA,
        p_zona_horaria: "Europe/Madrid",
    });
    comprobarRechazo(rechazado, rechazos.permiso_denegado);

    const cambio = await llamarRpc(usuarios.propietario_a.cliente, "cambiar_zona_horaria", {
        p_organizacion_id: organizacionA,
        p_zona_horaria: "Europe/Madrid",
    });
    comprobarExito(cambio, 200);
    assert.equal((cambio.datos as { zona_horaria: string }).zona_horaria, "Europe/Madrid");

    const [recalculada] = await leerTarea(usuarios.miembro_a, sinHora.id);
    assert.equal(instante(recalculada.vence_en), "2026-12-01T23:00:00.000Z");

    const [conservada] = await leerTarea(usuarios.miembro_a, conHora.id);
    assert.equal(instante(conservada.vence_en), "2026-12-01T22:00:00.000Z");
});

Deno.test("salir_de_organizacion: las tareas quedan sin responsable y se audita como sistema", async () => {
    const escenario = await prepararEscenario();
    const { usuarios, organizacionA } = escenario;
    const proyectoId = await crearProyecto(escenario);
    const tarea = await crearTarea(usuarios.administrador_a, proyectoId, {
        p_titulo: "Asignada",
        p_responsable_id: usuarios.miembro_a.id,
    });

    const salida = await llamarRpc(usuarios.miembro_a.cliente, "salir_de_organizacion", {
        p_organizacion_id: organizacionA,
    });
    comprobarExito(salida, 204);

    const [despues] = await leerTarea(usuarios.propietario_a, tarea.id);
    assert.equal(despues.responsable_id, null);

    const auditoria = await leerAuditoria(usuarios.propietario_a, organizacionA);
    const retiradas = auditoria.filter((registro) =>
        registro.accion === "tarea.responsable_retirado"
    );
    assert.deepEqual(retiradas, [{
        accion: "tarea.responsable_retirado",
        actor_id: null,
        recurso_id: tarea.id,
        detalles: { responsable_anterior: usuarios.miembro_a.id, motivo: "membresia_eliminada" },
    }]);
});
