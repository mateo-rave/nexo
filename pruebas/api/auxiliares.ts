// Auxiliares compartidos de las pruebas de integración de API.
//
// Las pruebas actúan como el frontend: usan solo la clave publicable y la
// sesión de cada usuario de prueba, y llaman a las RPC por la Data API
// (PostgREST). Se ejecutan contra el Supabase local y desechable del workflow
// de CI, nunca contra nexo-dev ni producción (ver docs/qa/test-strategy.md).
//
// Nombres en español (ADR-0005): funciones y variables en camelCase, tipos en
// PascalCase. Los nombres SQL (RPC, argumentos p_...) y los campos de datos
// de la API (usuario_id, nombre_visible...) se escriben tal como los define
// el contrato.

import assert from "node:assert/strict";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

// -----------------------------------------------------------------------------
// Configuración: solo la URL local y la clave publicable local
// -----------------------------------------------------------------------------

function leerVariable(nombre: string): string {
    const valor = Deno.env.get(nombre);
    if (!valor) {
        throw new Error(`Falta la variable de entorno ${nombre}.`);
    }
    return valor;
}

const urlSupabase = leerVariable("SUPABASE_URL");
const clavePublicable = leerVariable("SUPABASE_PUBLISHABLE_KEY");

// Defensa adicional al permiso --allow-net del workflow: si alguien apunta
// las pruebas a un proyecto remoto, fallan antes de enviar nada.
if (!["127.0.0.1", "localhost"].includes(new URL(urlSupabase).hostname)) {
    throw new Error(
        "Las pruebas de API solo se ejecutan contra el Supabase local (127.0.0.1 o localhost).",
    );
}

// Solo la clave publicable: ni la secreta (sb_secret_...) ni las heredadas
// (anon o service_role, que son JWT).
if (!clavePublicable.startsWith("sb_publishable_")) {
    throw new Error("SUPABASE_PUBLISHABLE_KEY debe ser una clave publicable (sb_publishable_...).");
}

// -----------------------------------------------------------------------------
// Clientes con captura del estado HTTP real
// -----------------------------------------------------------------------------

export type Cliente = {
    supabase: SupabaseClient;
    // Estado HTTP de la última respuesta de la Data API (/rest/v1/...), leído
    // del objeto Response, no deducido del cuerpo del error.
    registro: { estadoHttp: number | null };
};

export function crearCliente(): Cliente {
    const registro: Cliente["registro"] = { estadoHttp: null };

    const transporte: typeof fetch = async (entrada, opciones) => {
        const respuesta = await fetch(entrada, opciones);
        const direccion = entrada instanceof Request ? entrada.url : String(entrada);
        if (new URL(direccion).pathname.startsWith("/rest/v1/")) {
            registro.estadoHttp = respuesta.status;
        }
        return respuesta;
    };

    const supabase = createClient(urlSupabase, clavePublicable, {
        auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
        global: { fetch: transporte },
    });

    return { supabase, registro };
}

// -----------------------------------------------------------------------------
// Usuarios de prueba (glosario de ADR-0005)
// -----------------------------------------------------------------------------

export type Usuario = {
    etiqueta: string;
    id: string;
    correo: string;
    nombreVisible: string;
    cliente: Cliente;
};

// Las claves son los nombres oficiales de los usuarios de prueba (ADR-0005).
export type Usuarios = {
    propietario_a: Usuario;
    administrador_a: Usuario;
    miembro_a: Usuario;
    propietario_b: Usuario;
    sin_membresia: Usuario;
};

// Correos sintéticos de example.com, únicos en cada ejecución.
const sufijoEjecucion = crypto.randomUUID().slice(0, 8);

export function correoSintetico(etiqueta: string): string {
    return `${etiqueta}.${sufijoEjecucion}@example.com`;
}

async function registrarUsuario(etiqueta: string, nombreVisible: string): Promise<Usuario> {
    const cliente = crearCliente();
    const correo = correoSintetico(etiqueta);

    // En el Supabase local las confirmaciones de correo están desactivadas
    // (supabase/config.toml), así que signUp devuelve ya una sesión.
    // nombre_visible es el dato que lee el trigger crear_perfil.
    const { data, error } = await cliente.supabase.auth.signUp({
        email: correo,
        password: crypto.randomUUID(),
        options: { data: { nombre_visible: nombreVisible } },
    });
    if (error) {
        throw new Error(`No se pudo registrar a ${etiqueta}: ${error.message}`);
    }
    if (!data.user || !data.session) {
        throw new Error(`El registro de ${etiqueta} no devolvió una sesión.`);
    }

    return { etiqueta, id: data.user.id, correo, nombreVisible, cliente };
}

// Se registran una sola vez por módulo y en serie: el registro tiene un
// límite de peticiones por IP (auth.rate_limit.sign_in_sign_ups).
let usuariosPendientes: Promise<Usuarios> | undefined;

export function prepararUsuarios(): Promise<Usuarios> {
    usuariosPendientes ??= (async () => ({
        propietario_a: await registrarUsuario("propietario_a", "Propietario A"),
        administrador_a: await registrarUsuario("administrador_a", "Administrador A"),
        miembro_a: await registrarUsuario("miembro_a", "Miembro A"),
        propietario_b: await registrarUsuario("propietario_b", "Propietario B"),
        sin_membresia: await registrarUsuario("sin_membresia", "Persona sin membresía"),
    }))();
    return usuariosPendientes;
}

// -----------------------------------------------------------------------------
// Llamadas a RPC
// -----------------------------------------------------------------------------

// Campos del cuerpo de error de PostgREST, con sus nombres originales.
export type ErrorApi = {
    code: string | null;
    message: string | null;
    details: string | null;
    hint: string | null;
};

export type ResultadoRpc = {
    estadoHttp: number;
    datos: unknown;
    error: ErrorApi | null;
};

export async function llamarRpc(
    cliente: Cliente,
    funcion: string,
    argumentos: Record<string, unknown>,
): Promise<ResultadoRpc> {
    cliente.registro.estadoHttp = null;
    const { data, error, status } = await cliente.supabase.rpc(funcion, argumentos);

    const estadoHttp = cliente.registro.estadoHttp;
    if (estadoHttp === null) {
        throw new Error(`No se capturó el estado HTTP de la llamada a ${funcion}.`);
    }
    // postgrest-js también informa el estado; si no coincide con el capturado,
    // algo entre medias lo alteró.
    assert.equal(status, estadoHttp, `Estado HTTP inconsistente en ${funcion}.`);

    return {
        estadoHttp,
        datos: data,
        error: error
            ? {
                code: error.code ?? null,
                message: error.message ?? null,
                details: error.details ?? null,
                hint: error.hint ?? null,
            }
            : null,
    };
}

// -----------------------------------------------------------------------------
// Respuestas esperadas
// -----------------------------------------------------------------------------

export type RechazoEsperado = {
    estadoHttp: number;
    code: string;
    message: string;
    details: string | null;
};

// Errores propios de las RPC: PostgREST traduce PTxyz al estado HTTP xyz y
// devuelve el SQLSTATE en code, el mensaje en message y el código propio de
// Nexo (detail en el SQL) en details.
function rechazoPropio(estadoHttp: number, details: string, message: string): RechazoEsperado {
    return { estadoHttp, code: `PT${estadoHttp}`, message, details };
}

// Las claves son los códigos de error del contrato (campo details).
export const rechazos = {
    permiso_denegado: rechazoPropio(
        403,
        "permiso_denegado",
        "No tienes permiso para realizar esta acción en esta organización.",
    ),
    rol_no_permitido: rechazoPropio(
        403,
        "rol_no_permitido",
        "Tu rol no permite asignar o gestionar ese rol.",
    ),
    rol_invalido: rechazoPropio(400, "rol_invalido", "Debes indicar un rol válido."),
    correo_invalido: rechazoPropio(400, "correo_invalido", "Debes indicar un correo válido."),
    usuario_no_disponible: rechazoPropio(
        400,
        "usuario_no_disponible",
        "No se pudo añadir a esta persona.",
    ),
    ya_es_miembro: rechazoPropio(
        409,
        "ya_es_miembro",
        "Esta persona ya es miembro de la organización.",
    ),
    miembro_no_encontrado: rechazoPropio(
        404,
        "miembro_no_encontrado",
        "Esa persona no es miembro de la organización.",
    ),
    rol_sin_cambios: rechazoPropio(409, "rol_sin_cambios", "La persona ya tiene ese rol."),
    ultimo_propietario: rechazoPropio(
        409,
        "ultimo_propietario",
        "La organización debe tener al menos un propietario.",
    ),
    accion_no_permitida: rechazoPropio(
        400,
        "accion_no_permitida",
        "Para salir de la organización usa salir_de_organizacion.",
    ),
};

// anon no tiene execute sobre las RPC: PostgreSQL rechaza la llamada con
// 42501 antes de entrar en la función (no llega a PT401 sesion_requerida),
// y PostgREST responde 401 porque la petición no está autenticada.
export function rechazoSinPermisoExecute(funcion: string): RechazoEsperado {
    return {
        estadoHttp: 401,
        code: "42501",
        message: `permission denied for function ${funcion}`,
        details: null,
    };
}

export function comprobarRechazo(resultado: ResultadoRpc, esperado: RechazoEsperado): void {
    assert.equal(resultado.estadoHttp, esperado.estadoHttp, "estado HTTP");
    assert.ok(resultado.error, "se esperaba un error");
    assert.equal(resultado.error.code, esperado.code, "code");
    assert.equal(resultado.error.message, esperado.message, "message");
    assert.equal(resultado.error.details, esperado.details, "details");
    assert.equal(resultado.error.hint, null, "hint");
    assert.equal(resultado.datos, null, "un rechazo no devuelve datos");
}

export function comprobarExito(resultado: ResultadoRpc, estadoHttp: number): void {
    assert.equal(resultado.error, null, `error inesperado: ${JSON.stringify(resultado.error)}`);
    assert.equal(resultado.estadoHttp, estadoHttp, "estado HTTP");
}

// -----------------------------------------------------------------------------
// Escenario: organizaciones A y B nuevas en cada prueba
// -----------------------------------------------------------------------------

export type Escenario = {
    usuarios: Usuarios;
    organizacionA: string;
    organizacionB: string;
};

async function crearOrganizacion(dueno: Usuario, nombre: string): Promise<string> {
    const resultado = await llamarRpc(dueno.cliente, "crear_organizacion", { p_nombre: nombre });
    comprobarExito(resultado, 200);
    const organizacion = resultado.datos as { id: string };
    return organizacion.id;
}

export async function agregar(
    quien: Usuario,
    organizacionId: string,
    persona: Usuario,
    rol: string,
): Promise<void> {
    const resultado = await llamarRpc(quien.cliente, "agregar_miembro", {
        p_organizacion_id: organizacionId,
        p_correo: persona.correo,
        p_rol: rol,
    });
    comprobarExito(resultado, 200);
}

export async function cambiarRol(
    quien: Usuario,
    organizacionId: string,
    persona: Usuario,
    rol: string,
): Promise<void> {
    const resultado = await llamarRpc(quien.cliente, "cambiar_rol_miembro", {
        p_organizacion_id: organizacionId,
        p_usuario_id: persona.id,
        p_rol: rol,
    });
    comprobarExito(resultado, 204);
}

// A: propietario_a (propietario), administrador_a (administrador) y
// miembro_a (miembro). B: propietario_b. sin_membresia no está en ninguna.
export async function prepararEscenario(): Promise<Escenario> {
    const usuarios = await prepararUsuarios();
    const organizacionA = await crearOrganizacion(usuarios.propietario_a, "Organización A");
    await agregar(
        usuarios.propietario_a,
        organizacionA,
        usuarios.administrador_a,
        "administrador",
    );
    await agregar(usuarios.propietario_a, organizacionA, usuarios.miembro_a, "miembro");
    const organizacionB = await crearOrganizacion(usuarios.propietario_b, "Organización B");
    return { usuarios, organizacionA, organizacionB };
}

// -----------------------------------------------------------------------------
// Estado de membresías y auditoría
// -----------------------------------------------------------------------------

// Filas tal como las devuelve la Data API (nombres de columna del contrato).
export type Membresia = { usuario_id: string; rol: string };

export type RegistroAuditoria = {
    id: number;
    accion: string;
    actor_id: string | null;
    recurso_id: string | null;
    detalles: Record<string, unknown>;
};

export type FotoEstado = {
    membresias: Membresia[];
    auditoria: RegistroAuditoria[];
};

// Lee el estado tal como lo ve "lector" por la Data API (RLS incluida). Para
// ver la auditoría, el lector debe ser propietario o administrador.
export async function leerEstado(lector: Usuario, organizacionId: string): Promise<FotoEstado> {
    const membresias = await lector.cliente.supabase
        .from("membresias")
        .select("usuario_id, rol")
        .eq("organizacion_id", organizacionId)
        .order("usuario_id");
    if (membresias.error) {
        throw new Error(`No se pudieron leer las membresías: ${membresias.error.message}`);
    }

    const auditoria = await lector.cliente.supabase
        .from("auditoria")
        .select("id, accion, actor_id, recurso_id, detalles")
        .eq("organizacion_id", organizacionId)
        .order("id");
    if (auditoria.error) {
        throw new Error(`No se pudo leer la auditoría: ${auditoria.error.message}`);
    }

    return {
        membresias: membresias.data as Membresia[],
        auditoria: auditoria.data as RegistroAuditoria[],
    };
}

export function rolDe(estado: FotoEstado, persona: Usuario): string | undefined {
    return estado.membresias.find((m) => m.usuario_id === persona.id)?.rol;
}

// La operación añadió exactamente un registro de auditoría y es este.
export function comprobarNuevaAuditoria(
    antes: FotoEstado,
    despues: FotoEstado,
    esperado: Omit<RegistroAuditoria, "id">,
): void {
    assert.equal(despues.auditoria.length, antes.auditoria.length + 1, "registros de auditoría");
    const { id: _id, ...ultimo } = despues.auditoria[despues.auditoria.length - 1];
    assert.deepEqual(ultimo, esperado);
}
