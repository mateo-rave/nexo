// Pruebas de integración de API: cambiar_rol_miembro (migración 2 de la fase 1).
// Complementan supabase/tests/cambiar_rol_miembro.test.sql.

import assert from "node:assert/strict";
import {
    cambiarRol,
    comprobarExito,
    comprobarNuevaAuditoria,
    comprobarRechazo,
    crearCliente,
    leerEstado,
    llamarRpc,
    prepararEscenario,
    rechazos,
    rechazoSinPermisoExecute,
    rolDe,
} from "./auxiliares.ts";

Deno.test("cambiar_rol_miembro: sin sesión, la llamada se rechaza sin cambios", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(crearCliente(), "cambiar_rol_miembro", {
        p_organizacion_id: organizacionA,
        p_usuario_id: usuarios.miembro_a.id,
        p_rol: "administrador",
    });

    comprobarRechazo(resultado, rechazoSinPermisoExecute("cambiar_rol_miembro"));
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("cambiar_rol_miembro: el propietario cambia el rol y queda auditado", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.propietario_a.cliente, "cambiar_rol_miembro", {
        p_organizacion_id: organizacionA,
        p_usuario_id: usuarios.miembro_a.id,
        p_rol: "administrador",
    });

    // La función devuelve void: PostgREST responde 204 sin cuerpo.
    comprobarExito(resultado, 204);
    assert.equal(resultado.datos, null);

    const despues = await leerEstado(usuarios.propietario_a, organizacionA);
    assert.equal(rolDe(despues, usuarios.miembro_a), "administrador");
    comprobarNuevaAuditoria(antes, despues, {
        accion: "miembro.rol_cambiado",
        actor_id: usuarios.propietario_a.id,
        recurso_id: usuarios.miembro_a.id,
        detalles: { rol_anterior: "miembro", rol_nuevo: "administrador" },
    });
});

Deno.test("cambiar_rol_miembro: el mismo rol se rechaza sin cambios", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.propietario_a.cliente, "cambiar_rol_miembro", {
        p_organizacion_id: organizacionA,
        p_usuario_id: usuarios.administrador_a.id,
        p_rol: "administrador",
    });

    comprobarRechazo(resultado, rechazos.rol_sin_cambios);
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("cambiar_rol_miembro: el último propietario no puede dejar de serlo", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.propietario_a.cliente, "cambiar_rol_miembro", {
        p_organizacion_id: organizacionA,
        p_usuario_id: usuarios.propietario_a.id,
        p_rol: "administrador",
    });

    comprobarRechazo(resultado, rechazos.ultimo_propietario);
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("cambiar_rol_miembro: con otro propietario, el propietario puede cambiar su propio rol", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    await cambiarRol(
        usuarios.propietario_a,
        organizacionA,
        usuarios.administrador_a,
        "propietario",
    );

    const resultado = await llamarRpc(usuarios.propietario_a.cliente, "cambiar_rol_miembro", {
        p_organizacion_id: organizacionA,
        p_usuario_id: usuarios.propietario_a.id,
        p_rol: "administrador",
    });

    comprobarExito(resultado, 204);
    const despues = await leerEstado(usuarios.administrador_a, organizacionA);
    assert.equal(rolDe(despues, usuarios.propietario_a), "administrador");
    assert.equal(rolDe(despues, usuarios.administrador_a), "propietario");
});

Deno.test("cambiar_rol_miembro: administrador y miembro no pueden cambiar roles", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    for (const quien of [usuarios.administrador_a, usuarios.miembro_a]) {
        const resultado = await llamarRpc(quien.cliente, "cambiar_rol_miembro", {
            p_organizacion_id: organizacionA,
            p_usuario_id: usuarios.miembro_a.id,
            p_rol: "administrador",
        });
        comprobarRechazo(resultado, rechazos.permiso_denegado);
    }

    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("cambiar_rol_miembro: desde otra organización o sin membresía se rechaza sin cambios", async () => {
    const { usuarios, organizacionA, organizacionB } = await prepararEscenario();
    const antesA = await leerEstado(usuarios.propietario_a, organizacionA);
    const antesB = await leerEstado(usuarios.propietario_b, organizacionB);

    for (const quien of [usuarios.propietario_b, usuarios.sin_membresia]) {
        const resultado = await llamarRpc(quien.cliente, "cambiar_rol_miembro", {
            p_organizacion_id: organizacionA,
            p_usuario_id: usuarios.propietario_a.id,
            p_rol: "miembro",
        });
        comprobarRechazo(resultado, rechazos.permiso_denegado);
    }

    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antesA);
    assert.deepEqual(await leerEstado(usuarios.propietario_b, organizacionB), antesB);
});

Deno.test("cambiar_rol_miembro: una organización inexistente da el mismo rechazo que una ajena", async () => {
    const { usuarios, organizacionA, organizacionB } = await prepararEscenario();
    const antesA = await leerEstado(usuarios.propietario_a, organizacionA);
    const antesB = await leerEstado(usuarios.propietario_b, organizacionB);

    const inexistente = await llamarRpc(usuarios.propietario_a.cliente, "cambiar_rol_miembro", {
        p_organizacion_id: crypto.randomUUID(),
        p_usuario_id: usuarios.miembro_a.id,
        p_rol: "administrador",
    });
    const ajena = await llamarRpc(usuarios.propietario_b.cliente, "cambiar_rol_miembro", {
        p_organizacion_id: organizacionA,
        p_usuario_id: usuarios.miembro_a.id,
        p_rol: "administrador",
    });

    comprobarRechazo(inexistente, rechazos.permiso_denegado);
    assert.deepEqual(inexistente, ajena);
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antesA);
    assert.deepEqual(await leerEstado(usuarios.propietario_b, organizacionB), antesB);
});

Deno.test("cambiar_rol_miembro: quien no es miembro no se puede cambiar", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.propietario_a.cliente, "cambiar_rol_miembro", {
        p_organizacion_id: organizacionA,
        p_usuario_id: usuarios.sin_membresia.id,
        p_rol: "administrador",
    });

    comprobarRechazo(resultado, rechazos.miembro_no_encontrado);
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("cambiar_rol_miembro: el rol ausente se rechaza", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.propietario_a.cliente, "cambiar_rol_miembro", {
        p_organizacion_id: organizacionA,
        p_usuario_id: usuarios.miembro_a.id,
        p_rol: null,
    });

    comprobarRechazo(resultado, rechazos.rol_invalido);
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});
