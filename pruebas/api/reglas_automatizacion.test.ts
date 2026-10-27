// Pruebas de integración de API: reglas de automatización (fase 5, bloques
// 5.1 y 5.2; ADR-0008). Complementan supabase/tests/reglas_automatizacion.test.sql
// y ejecucion_automatizaciones.test.sql: comprueban a través de la Data API,
// con la clave publicable y la sesión de cada usuario, los permisos de la
// matriz, los códigos de error del catálogo, el ciclo de vida de una regla, el
// aislamiento entre organizaciones y, de extremo a extremo con el job de Cron,
// que una regla actúa sobre un cambio de estado y sobre un vencimiento sin
// duplicar el aviso del detector.
// Este módulo registra sus propios 5 usuarios; el límite de registros del
// Supabase local se subió para ello (supabase/config.toml, decisión A6).

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
    type ResultadoRpc,
    type Usuario,
} from "./auxiliares.ts";

// Filas tal como las devuelve la Data API (nombres de columna del contrato).
type VersionRegla = {
    id: string;
    regla_id: string;
    numero: number;
    estado: string;
    activador: string;
    publicada_en: string | null;
};

type Periodo = {
    id: string;
    regla_id: string;
    activada_en: string;
    desactivada_en: string | null;
};

type Ejecucion = {
    id: string;
    regla_id: string;
    estado: string;
    intentos: number;
    codigo_error: string | null;
};

type Accion = {
    ejecucion_id: string;
    estado: string;
    resultado: { notificados?: string[]; omitidos?: { destinatario_id: string; motivo: string }[] };
};

type Notificacion = {
    id: string;
    destinatario_id: string;
    titulo: string;
    mensaje: string;
    hallazgo_id: string | null;
    evento_id: string | null;
    accion_id: string | null;
};

type Tarea = { id: string; estado: string };

// Códigos de error nuevos de este bloque (campo details del contrato).
function rechazoPropio(estadoHttp: number, details: string, message: string): RechazoEsperado {
    return { estadoHttp, code: `PT${estadoHttp}`, message, details };
}

const rechazosReglas = {
    activador_invalido: rechazoPropio(
        400,
        "activador_invalido",
        "Ese activador no está en el catálogo.",
    ),
    condicion_no_aplicable: rechazoPropio(
        400,
        "condicion_no_aplicable",
        "Esa condición no se puede usar con este activador.",
    ),
    proyecto_invalido: rechazoPropio(
        400,
        "proyecto_invalido",
        "El proyecto no existe en esta organización.",
    ),
    sin_acciones: rechazoPropio(400, "sin_acciones", "La regla debe tener al menos una acción."),
    version_publicada_inmutable: rechazoPropio(
        409,
        "version_publicada_inmutable",
        "Una versión publicada no se puede modificar ni borrar.",
    ),
    version_ya_publicada: rechazoPropio(409, "version_ya_publicada", "La versión ya está publicada."),
    regla_sin_version_publicada: rechazoPropio(
        409,
        "regla_sin_version_publicada",
        "La regla necesita una versión publicada para activarse.",
    ),
    regla_ya_activa: rechazoPropio(409, "regla_ya_activa", "La regla ya está activa."),
    regla_no_activa: rechazoPropio(409, "regla_no_activa", "La regla no está activa."),
    regla_no_encontrada: rechazoPropio(
        404,
        "regla_no_encontrada",
        "La regla no existe o no tienes acceso a ella.",
    ),
};

const avisarAdministracion = [{ tipo: "notificar", destinatarios: "propietarios_y_administradores" }];
const avisarResponsable = [{ tipo: "notificar", destinatarios: "responsable" }];

async function crearProyecto(quien: Usuario, organizacionId: string): Promise<string> {
    const resultado = await llamarRpc(quien.cliente, "crear_proyecto", {
        p_organizacion_id: organizacionId,
        p_nombre: "Web",
    });
    comprobarExito(resultado, 200);
    return (resultado.datos as { id: string }).id;
}

async function crearRegla(
    quien: Usuario,
    organizacionId: string,
    nombre: string,
    activador: string,
    condiciones: unknown[],
    acciones: unknown[],
): Promise<ResultadoRpc> {
    return await llamarRpc(quien.cliente, "crear_regla", {
        p_organizacion_id: organizacionId,
        p_nombre: nombre,
        p_activador: activador,
        p_condiciones: condiciones,
        p_acciones: acciones,
    });
}

// Crea, publica y activa una regla; devuelve su id.
async function crearReglaActiva(
    quien: Usuario,
    organizacionId: string,
    nombre: string,
    activador: string,
    condiciones: unknown[],
    acciones: unknown[],
): Promise<string> {
    const creada = await crearRegla(quien, organizacionId, nombre, activador, condiciones, acciones);
    comprobarExito(creada, 200);
    const version = creada.datos as VersionRegla;

    const publicada = await llamarRpc(quien.cliente, "publicar_version_regla", {
        p_version_regla_id: version.id,
    });
    comprobarExito(publicada, 200);

    const activada = await llamarRpc(quien.cliente, "activar_regla", { p_regla_id: version.regla_id });
    comprobarExito(activada, 200);
    return version.regla_id;
}

async function leerFilas<T>(
    lector: Usuario,
    tabla: string,
    columnas: string,
    filtros: Record<string, string>,
): Promise<T[]> {
    let consulta = lector.cliente.supabase.from(tabla).select(columnas);
    for (const [columna, valor] of Object.entries(filtros)) {
        consulta = consulta.eq(columna, valor);
    }
    const { data, error } = await consulta;
    if (error) {
        throw new Error(`No se pudo leer ${tabla}: ${error.message}`);
    }
    return data as T[];
}

// El procesamiento no se puede llamar desde la API: lo ejecuta el job de Cron
// cada minuto. Se espera, consultando cada pocos segundos, a que la regla
// tenga el número esperado de ejecuciones y ninguna siga pendiente.
async function esperarEjecuciones(
    lector: Usuario,
    reglaId: string,
    cuantas: number,
): Promise<Ejecucion[]> {
    const limiteMs = 170_000;
    const inicio = Date.now();
    while (Date.now() - inicio < limiteMs) {
        const ejecuciones = await leerFilas<Ejecucion>(
            lector,
            "ejecuciones_automatizacion",
            "id, regla_id, estado, intentos, codigo_error",
            { regla_id: reglaId },
        );
        if (
            ejecuciones.length >= cuantas &&
            ejecuciones.every((ejecucion) => ejecucion.estado !== "pendiente")
        ) {
            assert.equal(ejecuciones.length, cuantas, "una ejecución por regla y evento");
            return ejecuciones;
        }
        await new Promise((resolver) => setTimeout(resolver, 5_000));
    }
    throw new Error(`El job de Cron no terminó las ejecuciones en ${limiteMs / 1000} s.`);
}

Deno.test("crear_regla: sin sesión, la llamada se rechaza", async () => {
    const escenario = await prepararEscenario();

    const resultado = await crearRegla(
        { ...escenario.usuarios.propietario_a, cliente: crearCliente() },
        escenario.organizacionA,
        "Anónima",
        "tarea_vencida",
        [],
        avisarResponsable,
    );

    comprobarRechazo(resultado, rechazoSinPermisoExecute("crear_regla"));
});

Deno.test("reglas: permisos, catálogo cerrado y ciclo de vida de versiones y periodos", async () => {
    const escenario: Escenario = await prepararEscenario();
    const { usuarios, organizacionA, organizacionB } = escenario;
    const proyectoB = await crearProyecto(usuarios.propietario_b, organizacionB);

    // Permisos de la matriz
    comprobarRechazo(
        await crearRegla(usuarios.miembro_a, organizacionA, "No", "tarea_vencida", [], avisarResponsable),
        rechazos.permiso_denegado,
    );
    comprobarRechazo(
        await crearRegla(usuarios.propietario_b, organizacionA, "Intruso", "tarea_vencida", [], avisarResponsable),
        rechazos.permiso_denegado,
    );

    // Catálogo cerrado, con códigos propios
    const administrador = usuarios.administrador_a;
    comprobarRechazo(
        await crearRegla(administrador, organizacionA, "X", "tarea_creada", [], avisarResponsable),
        rechazosReglas.activador_invalido,
    );
    comprobarRechazo(
        await crearRegla(
            administrador,
            organizacionA,
            "X",
            "tarea_vencida",
            [{ tipo: "estado_destino", estados: ["en_curso"] }],
            avisarResponsable,
        ),
        rechazosReglas.condicion_no_aplicable,
    );
    comprobarRechazo(
        await crearRegla(
            administrador,
            organizacionA,
            "X",
            "tarea_vencida",
            [{ tipo: "proyecto", proyecto_id: proyectoB }],
            avisarResponsable,
        ),
        rechazosReglas.proyecto_invalido,
    );
    comprobarRechazo(
        await crearRegla(administrador, organizacionA, "X", "tarea_vencida", [], []),
        rechazosReglas.sin_acciones,
    );

    // Crear y publicar
    const creada = await crearRegla(
        administrador,
        organizacionA,
        "Revisión",
        "tarea_estado_cambiado",
        [{ tipo: "estado_destino", estados: ["en_revision"] }],
        avisarAdministracion,
    );
    comprobarExito(creada, 200);
    const version = creada.datos as VersionRegla;
    assert.equal(version.numero, 1);
    assert.equal(version.estado, "borrador");
    assert.equal(version.publicada_en, null);

    comprobarRechazo(
        await llamarRpc(administrador.cliente, "activar_regla", { p_regla_id: version.regla_id }),
        rechazosReglas.regla_sin_version_publicada,
    );

    const publicada = await llamarRpc(administrador.cliente, "publicar_version_regla", {
        p_version_regla_id: version.id,
    });
    comprobarExito(publicada, 200);
    assert.equal((publicada.datos as VersionRegla).estado, "publicada");
    assert.notEqual((publicada.datos as VersionRegla).publicada_en, null);

    comprobarRechazo(
        await llamarRpc(administrador.cliente, "publicar_version_regla", { p_version_regla_id: version.id }),
        rechazosReglas.version_ya_publicada,
    );
    comprobarRechazo(
        await llamarRpc(administrador.cliente, "guardar_borrador_regla", {
            p_version_regla_id: version.id,
            p_activador: "tarea_vencida",
            p_condiciones: [],
            p_acciones: avisarResponsable,
        }),
        rechazosReglas.version_publicada_inmutable,
    );

    // Activar, pausar y aislamiento
    const activada = await llamarRpc(administrador.cliente, "activar_regla", {
        p_regla_id: version.regla_id,
    });
    comprobarExito(activada, 200);
    assert.equal((activada.datos as Periodo).desactivada_en, null);

    comprobarRechazo(
        await llamarRpc(administrador.cliente, "activar_regla", { p_regla_id: version.regla_id }),
        rechazosReglas.regla_ya_activa,
    );
    comprobarRechazo(
        await llamarRpc(usuarios.miembro_a.cliente, "pausar_regla", { p_regla_id: version.regla_id }),
        rechazos.permiso_denegado,
    );
    comprobarRechazo(
        await llamarRpc(usuarios.propietario_b.cliente, "pausar_regla", { p_regla_id: version.regla_id }),
        rechazosReglas.regla_no_encontrada,
    );

    const pausada = await llamarRpc(administrador.cliente, "pausar_regla", {
        p_regla_id: version.regla_id,
    });
    comprobarExito(pausada, 200);
    assert.notEqual((pausada.datos as Periodo).desactivada_en, null);

    comprobarRechazo(
        await llamarRpc(administrador.cliente, "pausar_regla", { p_regla_id: version.regla_id }),
        rechazosReglas.regla_no_activa,
    );

    // Lectura con RLS
    const filtro = { regla_id: version.regla_id };
    assert.equal(
        (await leerFilas<VersionRegla>(usuarios.miembro_a, "versiones_regla", "id", filtro)).length,
        1,
        "un miembro ve las versiones de su organización",
    );
    assert.equal(
        (await leerFilas<Periodo>(usuarios.miembro_a, "periodos_activacion_regla", "id", filtro)).length,
        1,
        "un miembro ve los periodos de su organización",
    );
    assert.deepEqual(
        await leerFilas<VersionRegla>(usuarios.propietario_b, "versiones_regla", "id", filtro),
        [],
        "otra organización no ve nada",
    );

    // Nadie escribe directamente
    const directa = await administrador.cliente.supabase
        .from("reglas_automatizacion")
        .insert({ organizacion_id: organizacionA, nombre: "Directa" });
    assert.ok(directa.error, "la Data API no permite insertar reglas");
    assert.equal(directa.error.code, "42501");
});

Deno.test("ejecución programada: una regla avisa cuando una tarea pasa a revisión", async () => {
    const escenario = await prepararEscenario();
    const { usuarios, organizacionA } = escenario;
    const administrador = usuarios.administrador_a;
    const proyectoId = await crearProyecto(administrador, organizacionA);

    const reglaId = await crearReglaActiva(
        administrador,
        organizacionA,
        "Aviso de revisión",
        "tarea_estado_cambiado",
        [{ tipo: "estado_destino", estados: ["en_revision"] }],
        avisarAdministracion,
    );

    const creada = await llamarRpc(administrador.cliente, "crear_tarea", {
        p_proyecto_id: proyectoId,
        p_titulo: "Revisar textos",
    });
    comprobarExito(creada, 200);
    const tarea = creada.datos as Tarea;

    for (const estado of ["en_curso", "en_revision"]) {
        const cambio = await llamarRpc(administrador.cliente, "cambiar_estado_tarea", {
            p_tarea_id: tarea.id,
            p_estado: estado,
        });
        comprobarExito(cambio, 200);
    }

    // Dos eventos: en_curso no cumple la condición; en_revision sí.
    const ejecuciones = await esperarEjecuciones(usuarios.miembro_a, reglaId, 2);
    const estados = ejecuciones.map((ejecucion) => ejecucion.estado).sort();
    assert.deepEqual(estados, ["exitosa", "omitida"]);
    const omitida = ejecuciones.find((ejecucion) => ejecucion.estado === "omitida");
    assert.equal(omitida?.codigo_error, "condiciones_no_cumplidas");
    const exitosa = ejecuciones.find((ejecucion) => ejecucion.estado === "exitosa");
    assert.equal(exitosa?.intentos, 1);

    // Destinatarios: propietario y administrador; el miembro no.
    const mensaje = "La tarea «Revisar textos» pasó a En revisión.";
    for (const persona of [usuarios.propietario_a, usuarios.administrador_a]) {
        const propias = await leerFilas<Notificacion>(
            persona,
            "notificaciones",
            "id, destinatario_id, titulo, mensaje, hallazgo_id, evento_id, accion_id",
            { organizacion_id: organizacionA, mensaje },
        );
        assert.equal(propias.length, 1, `${persona.etiqueta} recibe una notificación`);
        assert.equal(propias[0].titulo, "Regla «Aviso de revisión»");
        assert.equal(propias[0].hallazgo_id, null);
        assert.notEqual(propias[0].evento_id, null);
        assert.notEqual(propias[0].accion_id, null);
    }
    assert.deepEqual(
        await leerFilas<Notificacion>(usuarios.miembro_a, "notificaciones", "id", {
            organizacion_id: organizacionA,
            mensaje,
        }),
        [],
    );

    // Aislamiento y cola no expuesta
    assert.deepEqual(
        await leerFilas<Ejecucion>(usuarios.propietario_b, "ejecuciones_automatizacion", "id", {
            regla_id: reglaId,
        }),
        [],
    );
    const cola = await usuarios.miembro_a.cliente.supabase.from("eventos_automatizacion").select("id");
    assert.ok(cola.error, "la cola de eventos no se expone");
    assert.equal(cola.error.code, "42501");
});

Deno.test("ejecución programada: una regla sobre vencimientos no duplica el aviso del detector", async () => {
    const escenario = await prepararEscenario();
    const { usuarios, organizacionA } = escenario;
    const administrador = usuarios.administrador_a;
    const proyectoId = await crearProyecto(administrador, organizacionA);

    // La regla se activa antes de que exista el vencimiento.
    const reglaId = await crearReglaActiva(
        administrador,
        organizacionA,
        "Aviso de vencimiento",
        "tarea_vencida",
        [],
        avisarResponsable,
    );

    // Un día de hace tres días: sin hora vence a las 00:00 del día siguiente
    // en Bogotá, que ya pasó.
    const haceTresDias = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    const creada = await llamarRpc(administrador.cliente, "crear_tarea", {
        p_proyecto_id: proyectoId,
        p_titulo: "Entregar informe",
        p_responsable_id: usuarios.miembro_a.id,
        p_fecha_limite: haceTresDias,
    });
    comprobarExito(creada, 200);

    // El detector crea el hallazgo y avisa al responsable; después el motor
    // procesa el evento: la regla no le crea una segunda notificación.
    const [ejecucion] = await esperarEjecuciones(usuarios.miembro_a, reglaId, 1);
    assert.equal(ejecucion.estado, "exitosa");

    const [accion] = await leerFilas<Accion>(
        usuarios.miembro_a,
        "acciones_automatizacion",
        "ejecucion_id, estado, resultado",
        { ejecucion_id: ejecucion.id },
    );
    assert.equal(accion.estado, "completada");
    assert.deepEqual(accion.resultado.notificados, []);
    assert.deepEqual(accion.resultado.omitidos, [
        { destinatario_id: usuarios.miembro_a.id, motivo: "ya_notificado" },
    ]);

    const avisos = await leerFilas<Notificacion>(
        usuarios.miembro_a,
        "notificaciones",
        "id, destinatario_id, titulo, mensaje, hallazgo_id, evento_id, accion_id",
        { organizacion_id: organizacionA, mensaje: "La tarea «Entregar informe» superó su fecha límite." },
    );
    assert.equal(avisos.length, 1, "el responsable tiene un solo aviso de este vencimiento");
    assert.equal(avisos[0].titulo, "Tarea vencida", "es el aviso del detector");
    assert.equal(avisos[0].evento_id, null);
});
