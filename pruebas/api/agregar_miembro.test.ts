// Pruebas de integración de API: agregar_miembro (migración 2 de la fase 1).
// Complementan supabase/tests/agregar_miembro.test.sql: aquí se comprueba la
// respuesta HTTP real de PostgREST con la clave publicable.

import assert from "node:assert/strict";
import {
    comprobarExito,
    comprobarNuevaAuditoria,
    comprobarRechazo,
    correoSintetico,
    crearCliente,
    leerEstado,
    llamarRpc,
    prepararEscenario,
    rechazos,
    rechazoSinPermisoExecute,
    rolDe,
} from "./auxiliares.ts";

Deno.test("agregar_miembro: sin sesión, la llamada se rechaza sin cambios", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(crearCliente(), "agregar_miembro", {
        p_organizacion_id: organizacionA,
        p_correo: usuarios.sin_membresia.correo,
        p_rol: "miembro",
    });

    comprobarRechazo(resultado, rechazoSinPermisoExecute("agregar_miembro"));
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("agregar_miembro: el propietario añade un miembro y la respuesta no incluye el correo", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const persona = usuarios.sin_membresia;
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.propietario_a.cliente, "agregar_miembro", {
        p_organizacion_id: organizacionA,
        p_correo: persona.correo,
        p_rol: "miembro",
    });

    comprobarExito(resultado, 200);
    assert.deepEqual(resultado.datos, [
        { usuario_id: persona.id, nombre_visible: persona.nombreVisible, rol: "miembro" },
    ]);
    const cuerpo = JSON.stringify(resultado.datos);
    assert.ok(!cuerpo.includes(persona.correo), "la respuesta no debe incluir el correo");
    assert.ok(!cuerpo.includes("@"), "la respuesta no debe incluir ningún correo");

    const despues = await leerEstado(usuarios.propietario_a, organizacionA);
    assert.equal(rolDe(despues, persona), "miembro");
    comprobarNuevaAuditoria(antes, despues, {
        accion: "miembro.agregado",
        actor_id: usuarios.propietario_a.id,
        recurso_id: persona.id,
        detalles: { rol: "miembro" },
    });
});

Deno.test("agregar_miembro: el propietario puede añadir con rol administrador o propietario", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();

    for (
        const [persona, rol] of [
            [usuarios.sin_membresia, "administrador"],
            [usuarios.propietario_b, "propietario"],
        ] as const
    ) {
        const resultado = await llamarRpc(usuarios.propietario_a.cliente, "agregar_miembro", {
            p_organizacion_id: organizacionA,
            p_correo: persona.correo,
            p_rol: rol,
        });
        comprobarExito(resultado, 200);
        assert.equal(
            rolDe(await leerEstado(usuarios.propietario_a, organizacionA), persona),
            rol,
        );
    }
});

Deno.test("agregar_miembro: el correo se normaliza (espacios y mayúsculas)", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const persona = usuarios.sin_membresia;

    const resultado = await llamarRpc(usuarios.propietario_a.cliente, "agregar_miembro", {
        p_organizacion_id: organizacionA,
        p_correo: `  ${persona.correo.toUpperCase()}  `,
        p_rol: "miembro",
    });

    comprobarExito(resultado, 200);
    assert.equal(
        rolDe(await leerEstado(usuarios.propietario_a, organizacionA), persona),
        "miembro",
    );
});

Deno.test("agregar_miembro: el administrador añade un miembro", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.administrador_a.cliente, "agregar_miembro", {
        p_organizacion_id: organizacionA,
        p_correo: usuarios.sin_membresia.correo,
        p_rol: "miembro",
    });

    comprobarExito(resultado, 200);
    const despues = await leerEstado(usuarios.propietario_a, organizacionA);
    comprobarNuevaAuditoria(antes, despues, {
        accion: "miembro.agregado",
        actor_id: usuarios.administrador_a.id,
        recurso_id: usuarios.sin_membresia.id,
        detalles: { rol: "miembro" },
    });
});

Deno.test("agregar_miembro: el administrador no puede añadir administradores ni propietarios", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    for (const rol of ["administrador", "propietario"]) {
        const resultado = await llamarRpc(usuarios.administrador_a.cliente, "agregar_miembro", {
            p_organizacion_id: organizacionA,
            p_correo: usuarios.sin_membresia.correo,
            p_rol: rol,
        });
        comprobarRechazo(resultado, rechazos.rol_no_permitido);
    }

    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("agregar_miembro: un miembro no puede añadir a nadie", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.miembro_a.cliente, "agregar_miembro", {
        p_organizacion_id: organizacionA,
        p_correo: usuarios.sin_membresia.correo,
        p_rol: "miembro",
    });

    comprobarRechazo(resultado, rechazos.permiso_denegado);
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("agregar_miembro: desde otra organización se rechaza igual exista o no el correo", async () => {
    const { usuarios, organizacionA, organizacionB } = await prepararEscenario();
    const antesA = await leerEstado(usuarios.propietario_a, organizacionA);
    const antesB = await leerEstado(usuarios.propietario_b, organizacionB);

    const resultados = [];
    for (const quien of [usuarios.propietario_b, usuarios.sin_membresia]) {
        for (const correo of [usuarios.miembro_a.correo, correoSintetico("no_existe")]) {
            const resultado = await llamarRpc(quien.cliente, "agregar_miembro", {
                p_organizacion_id: organizacionA,
                p_correo: correo,
                p_rol: "miembro",
            });
            comprobarRechazo(resultado, rechazos.permiso_denegado);
            resultados.push(resultado);
        }
    }
    // Respuestas idénticas: no revelan qué correos tienen cuenta.
    for (const resultado of resultados) {
        assert.deepEqual(resultado, resultados[0]);
    }

    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antesA);
    assert.deepEqual(await leerEstado(usuarios.propietario_b, organizacionB), antesB);
});

Deno.test("agregar_miembro: una organización inexistente da el mismo rechazo que una ajena", async () => {
    const { usuarios, organizacionA, organizacionB } = await prepararEscenario();
    const antesA = await leerEstado(usuarios.propietario_a, organizacionA);
    const antesB = await leerEstado(usuarios.propietario_b, organizacionB);

    const inexistente = await llamarRpc(usuarios.propietario_a.cliente, "agregar_miembro", {
        p_organizacion_id: crypto.randomUUID(),
        p_correo: usuarios.sin_membresia.correo,
        p_rol: "miembro",
    });
    const ajena = await llamarRpc(usuarios.propietario_b.cliente, "agregar_miembro", {
        p_organizacion_id: organizacionA,
        p_correo: usuarios.sin_membresia.correo,
        p_rol: "miembro",
    });

    comprobarRechazo(inexistente, rechazos.permiso_denegado);
    assert.deepEqual(inexistente, ajena);
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antesA);
    assert.deepEqual(await leerEstado(usuarios.propietario_b, organizacionB), antesB);
});

Deno.test("agregar_miembro: un correo sin cuenta da el mensaje genérico", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.propietario_a.cliente, "agregar_miembro", {
        p_organizacion_id: organizacionA,
        p_correo: correoSintetico("no_existe"),
        p_rol: "miembro",
    });

    comprobarRechazo(resultado, rechazos.usuario_no_disponible);
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("agregar_miembro: correo vacío y rol ausente se rechazan", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const sinCorreo = await llamarRpc(usuarios.propietario_a.cliente, "agregar_miembro", {
        p_organizacion_id: organizacionA,
        p_correo: "   ",
        p_rol: "miembro",
    });
    comprobarRechazo(sinCorreo, rechazos.correo_invalido);

    const sinRol = await llamarRpc(usuarios.propietario_a.cliente, "agregar_miembro", {
        p_organizacion_id: organizacionA,
        p_correo: usuarios.sin_membresia.correo,
        p_rol: null,
    });
    comprobarRechazo(sinRol, rechazos.rol_invalido);

    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("agregar_miembro: un rol que no existe lo rechaza PostgreSQL antes de la función", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.propietario_a.cliente, "agregar_miembro", {
        p_organizacion_id: organizacionA,
        p_correo: usuarios.sin_membresia.correo,
        p_rol: "superusuario",
    });

    // 22P02: valor no válido para el tipo rol_membresia. PostgREST responde 400.
    assert.equal(resultado.estadoHttp, 400);
    assert.equal(resultado.error?.code, "22P02");
    assert.equal(resultado.datos, null);
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("agregar_miembro: quien ya es miembro no se añade dos veces", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.propietario_a.cliente, "agregar_miembro", {
        p_organizacion_id: organizacionA,
        p_correo: usuarios.miembro_a.correo,
        p_rol: "administrador",
    });

    comprobarRechazo(resultado, rechazos.ya_es_miembro);
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});
