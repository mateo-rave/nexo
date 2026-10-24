// Pruebas de integración de API: salir_de_organizacion (migración 2 de la fase 1).
// Complementan supabase/tests/salir_de_organizacion.test.sql.

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

Deno.test("salir_de_organizacion: sin sesión, la llamada se rechaza sin cambios", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(crearCliente(), "salir_de_organizacion", {
        p_organizacion_id: organizacionA,
    });

    comprobarRechazo(resultado, rechazoSinPermisoExecute("salir_de_organizacion"));
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("salir_de_organizacion: un miembro sale, queda auditado y pierde el acceso", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.miembro_a.cliente, "salir_de_organizacion", {
        p_organizacion_id: organizacionA,
    });

    comprobarExito(resultado, 204);
    assert.equal(resultado.datos, null);

    const despues = await leerEstado(usuarios.propietario_a, organizacionA);
    assert.equal(rolDe(despues, usuarios.miembro_a), undefined);
    comprobarNuevaAuditoria(antes, despues, {
        accion: "miembro.salio",
        actor_id: usuarios.miembro_a.id,
        recurso_id: usuarios.miembro_a.id,
        detalles: { rol: "miembro" },
    });

    const visto = await leerEstado(usuarios.miembro_a, organizacionA);
    assert.deepEqual(visto.membresias, []);
});

Deno.test("salir_de_organizacion: un administrador sale", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();

    const resultado = await llamarRpc(usuarios.administrador_a.cliente, "salir_de_organizacion", {
        p_organizacion_id: organizacionA,
    });

    comprobarExito(resultado, 204);
    const despues = await leerEstado(usuarios.propietario_a, organizacionA);
    assert.equal(rolDe(despues, usuarios.administrador_a), undefined);
});

Deno.test("salir_de_organizacion: el último propietario no puede salir", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    const antes = await leerEstado(usuarios.propietario_a, organizacionA);

    const resultado = await llamarRpc(usuarios.propietario_a.cliente, "salir_de_organizacion", {
        p_organizacion_id: organizacionA,
    });

    comprobarRechazo(resultado, rechazos.ultimo_propietario);
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antes);
});

Deno.test("salir_de_organizacion: un propietario sale si queda otro propietario", async () => {
    const { usuarios, organizacionA } = await prepararEscenario();
    await cambiarRol(
        usuarios.propietario_a,
        organizacionA,
        usuarios.administrador_a,
        "propietario",
    );

    const resultado = await llamarRpc(usuarios.propietario_a.cliente, "salir_de_organizacion", {
        p_organizacion_id: organizacionA,
    });

    comprobarExito(resultado, 204);
    const despues = await leerEstado(usuarios.administrador_a, organizacionA);
    assert.equal(rolDe(despues, usuarios.propietario_a), undefined);
    assert.equal(rolDe(despues, usuarios.administrador_a), "propietario");
});

Deno.test("salir_de_organizacion: quien no es miembro de A no puede salir de A", async () => {
    const { usuarios, organizacionA, organizacionB } = await prepararEscenario();
    const antesA = await leerEstado(usuarios.propietario_a, organizacionA);
    const antesB = await leerEstado(usuarios.propietario_b, organizacionB);

    for (const quien of [usuarios.propietario_b, usuarios.sin_membresia]) {
        const resultado = await llamarRpc(quien.cliente, "salir_de_organizacion", {
            p_organizacion_id: organizacionA,
        });
        comprobarRechazo(resultado, rechazos.permiso_denegado);
    }

    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antesA);
    assert.deepEqual(await leerEstado(usuarios.propietario_b, organizacionB), antesB);
});

Deno.test("salir_de_organizacion: una organización inexistente da el mismo rechazo que una ajena", async () => {
    const { usuarios, organizacionA, organizacionB } = await prepararEscenario();
    const antesA = await leerEstado(usuarios.propietario_a, organizacionA);
    const antesB = await leerEstado(usuarios.propietario_b, organizacionB);

    const inexistente = await llamarRpc(usuarios.propietario_b.cliente, "salir_de_organizacion", {
        p_organizacion_id: crypto.randomUUID(),
    });
    const ajena = await llamarRpc(usuarios.propietario_b.cliente, "salir_de_organizacion", {
        p_organizacion_id: organizacionA,
    });

    comprobarRechazo(inexistente, rechazos.permiso_denegado);
    assert.deepEqual(inexistente, ajena);
    assert.deepEqual(await leerEstado(usuarios.propietario_a, organizacionA), antesA);
    assert.deepEqual(await leerEstado(usuarios.propietario_b, organizacionB), antesB);
});
