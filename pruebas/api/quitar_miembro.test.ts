// Pruebas de integración de API: quitar_miembro (migración 2 de la fase 1).
// Complementan supabase/tests/quitar_miembro.test.sql.

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

Deno.test("quitar_miembro: sin sesión, la llamada se rechaza sin cambios", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(crearCliente(), "quitar_miembro", {
        p_organizacion_id: organizacionA,
        p_usuario_id: usuarios.miembro_a.id,
    });

    comprobarRechazo(resultado, rechazoSinPermisoExecute("quitar_miembro"));
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("quitar_miembro: el propietario quita a un miembro, que pierde el acceso", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.propietario_a.cliente, "quitar_miembro", {
        p_organizacion_id: organizacionA,
        p_usuario_id: usuarios.miembro_a.id,
    });

    comprobarExito(resultado, 204);
    const despues = await leerEstado(usuarios.propietario_a, organizacionA);
    assert.equal(rolDe(despues, usuarios.miembro_a), undefined);
    comprobarNuevaAuditoria(antes, despues, {
        accion: "miembro.quitado",
        actor_id: usuarios.propietario_a.id,
        recurso_id: usuarios.miembro_a.id,
        detalles: { rol: "miembro" },
    });

    // En la siguiente petición ya no ve la organización ni sus miembros.
    const visto = await leerEstado(usuarios.miembro_a, organizacionA);
    assert.deepEqual(visto.membresias, []);
    const organizaciones = await usuarios.miembro_a.cliente.supabase
        .from("organizaciones")
        .select("id")
        .eq("id", organizacionA);
    assert.equal(organizaciones.error, null);
    assert.deepEqual(organizaciones.data, []);
});

Deno.test("quitar_miembro: el propietario quita a un administrador", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();

    const resultado = await llamarRpc(usuarios.propietario_a.cliente, "quitar_miembro", {
        p_organizacion_id: organizacionA,
        p_usuario_id: usuarios.administrador_a.id,
    });

    comprobarExito(resultado, 204);
    const despues = await leerEstado(usuarios.propietario_a, organizacionA);
    assert.equal(rolDe(despues, usuarios.administrador_a), undefined);
});

Deno.test("quitar_miembro: un propietario puede quitar a otro propietario (riesgo D6)", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    await cambiarRol(
        usuarios.propietario_a,
        organizacionA,
        usuarios.administrador_a,
        "propietario",
    );

    const resultado = await llamarRpc(usuarios.propietario_a.cliente, "quitar_miembro", {
        p_organizacion_id: organizacionA,
        p_usuario_id: usuarios.administrador_a.id,
    });

    comprobarExito(resultado, 204);
    const despues = await leerEstado(usuarios.propietario_a, organizacionA);
    assert.equal(rolDe(despues, usuarios.administrador_a), undefined);
    assert.equal(rolDe(despues, usuarios.propietario_a), "propietario");
});

Deno.test("quitar_miembro: el administrador quita a un miembro", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.administrador_a.cliente, "quitar_miembro", {
        p_organizacion_id: organizacionA,
        p_usuario_id: usuarios.miembro_a.id,
    });

    comprobarExito(resultado, 204);
    const despues = await leerEstado(usuarios.propietario_a, organizacionA);
    comprobarNuevaAuditoria(antes, despues, {
        accion: "miembro.quitado",
        actor_id: usuarios.administrador_a.id,
        recurso_id: usuarios.miembro_a.id,
        detalles: { rol: "miembro" },
    });
});

Deno.test("quitar_miembro: el administrador no puede quitar a un propietario", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.administrador_a.cliente, "quitar_miembro", {
        p_organizacion_id: organizacionA,
        p_usuario_id: usuarios.propietario_a.id,
    });

    comprobarRechazo(resultado, rechazos.rol_no_permitido);
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("quitar_miembro: un miembro no puede quitar a nadie", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.miembro_a.cliente, "quitar_miembro", {
        p_organizacion_id: organizacionA,
        p_usuario_id: usuarios.administrador_a.id,
    });

    comprobarRechazo(resultado, rechazos.permiso_denegado);
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("quitar_miembro: nadie se quita a sí mismo por esta vía", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    for (const quien of [usuarios.propietario_a, usuarios.administrador_a]) {
        const resultado = await llamarRpc(quien.cliente, "quitar_miembro", {
            p_organizacion_id: organizacionA,
            p_usuario_id: quien.id,
        });
        comprobarRechazo(resultado, rechazos.accion_no_permitida);
    }

    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("quitar_miembro: quien no es miembro no se puede quitar", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.propietario_a.cliente, "quitar_miembro", {
        p_organizacion_id: organizacionA,
        p_usuario_id: usuarios.sin_membresia.id,
    });

    comprobarRechazo(resultado, rechazos.miembro_no_encontrado);
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("quitar_miembro: desde otra organización o sin membresía se rechaza sin cambios", async () => {
    const { usuarios, organizacionA, organizacionB } = await prepararEscenario();
    const antesA = await leerEstado(usuarios.propietario_a, organizacionA);
    const antesB = await leerEstado(usuarios.propietario_b, organizacionB);

    for (const quien of [usuarios.propietario_b, usuarios.sin_membresia]) {
        const resultado = await llamarRpc(quien.cliente, "quitar_miembro", {
            p_organizacion_id: organizacionA,
            p_usuario_id: usuarios.miembro_a.id,
        });
        comprobarRechazo(resultado, rechazos.permiso_denegado);
    }

    // Tampoco desde B, aunque el destinatario se indique con el id de B.
    const cruzada = await llamarRpc(usuarios.propietario_a.cliente, "quitar_miembro", {
        p_organizacion_id: organizacionB,
        p_usuario_id: usuarios.propietario_b.id,
    });
    comprobarRechazo(cruzada, rechazos.permiso_denegado);

    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antesA);
    assert.deepEqual(await leerEstado(usuarios.propietario_b, organizacionB), antesB);
});
