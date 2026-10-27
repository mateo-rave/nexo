import type { SupabaseClient } from "@supabase/supabase-js";
import type { EstadoTarea } from "../componentes/estados.ts";

// Acceso a datos del espacio de trabajo. Solo usa lo que ya existe en el
// backend: lecturas por la Data API (protegidas por RLS) y escrituras por las
// RPC (que comprueban permisos y auditan). El frontend no decide permisos:
// oculta acciones por comodidad, pero quien manda es el backend (ADR-0006).
// Los nombres de columnas y argumentos son los del contrato de la API.

export type Rol = "propietario" | "administrador" | "miembro";

export type Organizacion = { id: string; nombre: string; zona_horaria: string; rol: Rol };

export type Proyecto = {
    id: string;
    nombre: string;
    descripcion: string | null;
    archivado_en: string | null;
    version_flujo_id: string;
};

export type VersionPublicada = { id: string; numero: number; nombre: string; es_predeterminado: boolean };

export type Tarea = {
    id: string;
    titulo: string;
    descripcion: string | null;
    estado: EstadoTarea;
    responsable_id: string | null;
    creado_por: string | null;
    fecha_limite: string | null;
    vence_en: string | null;
};

export type Transicion = { estado_origen: EstadoTarea; estado_destino: EstadoTarea };

export type Miembro = { usuario_id: string; rol: Rol; nombre_visible: string };

export type Notificacion = {
    id: string;
    titulo: string;
    mensaje: string;
    leida_en: string | null;
    creado_en: string;
};

// Lanza el error del backend tal cual; la interfaz lo traduce con
// mensajeDeError.
function exigir<T>(respuesta: { data: T | null; error: unknown }): T {
    if (respuesta.error) {
        throw respuesta.error;
    }
    return respuesta.data as T;
}

// -----------------------------------------------------------------------------
// Organizaciones
// -----------------------------------------------------------------------------

export async function listarOrganizaciones(
    cliente: SupabaseClient,
    usuarioId: string,
): Promise<Organizacion[]> {
    const filas = exigir(
        await cliente
            .from("membresias")
            .select("rol, organizaciones(id, nombre, zona_horaria)")
            .eq("usuario_id", usuarioId),
    ) as unknown as { rol: Rol; organizaciones: Omit<Organizacion, "rol"> }[];
    return filas
        .map((fila) => ({ ...fila.organizaciones, rol: fila.rol }))
        .sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));
}

export async function crearOrganizacion(cliente: SupabaseClient, nombre: string): Promise<void> {
    exigir(await cliente.rpc("crear_organizacion", { p_nombre: nombre }));
}

export async function listarMiembros(cliente: SupabaseClient, organizacionId: string): Promise<Miembro[]> {
    const filas = exigir(
        await cliente
            .from("membresias")
            .select("usuario_id, rol, perfiles(nombre_visible)")
            .eq("organizacion_id", organizacionId),
    ) as unknown as { usuario_id: string; rol: Rol; perfiles: { nombre_visible: string } }[];
    return filas
        .map((fila) => ({ usuario_id: fila.usuario_id, rol: fila.rol, nombre_visible: fila.perfiles.nombre_visible }))
        .sort((a, b) => a.nombre_visible.localeCompare(b.nombre_visible, "es"));
}

// -----------------------------------------------------------------------------
// Proyectos y flujos
// -----------------------------------------------------------------------------

export async function listarProyectos(cliente: SupabaseClient, organizacionId: string): Promise<Proyecto[]> {
    return exigir(
        await cliente
            .from("proyectos")
            .select("id, nombre, descripcion, archivado_en, version_flujo_id")
            .eq("organizacion_id", organizacionId)
            .order("creado_en"),
    ) as Proyecto[];
}

export async function listarVersionesPublicadas(
    cliente: SupabaseClient,
    organizacionId: string,
): Promise<VersionPublicada[]> {
    const filas = exigir(
        await cliente
            .from("versiones_flujo")
            .select("id, numero, definiciones_flujo(nombre, es_predeterminado)")
            .eq("organizacion_id", organizacionId)
            .eq("estado", "publicada")
            .order("numero"),
    ) as unknown as {
        id: string;
        numero: number;
        definiciones_flujo: { nombre: string; es_predeterminado: boolean };
    }[];
    return filas.map((fila) => ({
        id: fila.id,
        numero: fila.numero,
        nombre: fila.definiciones_flujo.nombre,
        es_predeterminado: fila.definiciones_flujo.es_predeterminado,
    }));
}

export async function crearProyecto(
    cliente: SupabaseClient,
    organizacionId: string,
    nombre: string,
    descripcion: string,
    versionFlujoId: string | null,
): Promise<Proyecto> {
    return exigir(
        await cliente.rpc("crear_proyecto", {
            p_organizacion_id: organizacionId,
            p_nombre: nombre,
            p_descripcion: descripcion || null,
            p_version_flujo_id: versionFlujoId,
        }),
    ) as Proyecto;
}

export async function archivarProyecto(
    cliente: SupabaseClient,
    proyectoId: string,
    archivado: boolean,
): Promise<void> {
    exigir(await cliente.rpc("archivar_proyecto", { p_proyecto_id: proyectoId, p_archivado: archivado }));
}

// -----------------------------------------------------------------------------
// Tareas
// -----------------------------------------------------------------------------

export async function listarTareas(cliente: SupabaseClient, proyectoId: string): Promise<Tarea[]> {
    return exigir(
        await cliente
            .from("tareas")
            .select("id, titulo, descripcion, estado, responsable_id, creado_por, fecha_limite, vence_en")
            .eq("proyecto_id", proyectoId)
            .order("creado_en"),
    ) as Tarea[];
}

export async function listarTransiciones(cliente: SupabaseClient, versionFlujoId: string): Promise<Transicion[]> {
    return exigir(
        await cliente
            .from("transiciones_version_flujo")
            .select("estado_origen, estado_destino")
            .eq("version_flujo_id", versionFlujoId),
    ) as Transicion[];
}

// Tareas con un hallazgo de vencimiento sin resolver: lo decide la detección
// del backend, no el reloj del navegador.
export async function tareasConHallazgoAbierto(
    cliente: SupabaseClient,
    organizacionId: string,
): Promise<Set<string>> {
    const filas = exigir(
        await cliente
            .from("hallazgos")
            .select("tarea_id")
            .eq("organizacion_id", organizacionId)
            .is("resuelto_en", null),
    ) as { tarea_id: string }[];
    return new Set(filas.map((fila) => fila.tarea_id));
}

export type NuevaTarea = {
    titulo: string;
    descripcion: string;
    responsableId: string | null;
    fechaLimite: string | null;
    horaLimite: string | null;
};

export async function crearTarea(
    cliente: SupabaseClient,
    proyectoId: string,
    tarea: NuevaTarea,
): Promise<void> {
    exigir(
        await cliente.rpc("crear_tarea", {
            p_proyecto_id: proyectoId,
            p_titulo: tarea.titulo,
            p_descripcion: tarea.descripcion || null,
            p_responsable_id: tarea.responsableId,
            p_fecha_limite: tarea.fechaLimite,
            p_hora_limite: tarea.horaLimite,
        }),
    );
}

export async function cambiarEstadoTarea(
    cliente: SupabaseClient,
    tareaId: string,
    estado: EstadoTarea,
): Promise<void> {
    exigir(await cliente.rpc("cambiar_estado_tarea", { p_tarea_id: tareaId, p_estado: estado }));
}

export async function asignarResponsable(
    cliente: SupabaseClient,
    tareaId: string,
    responsableId: string | null,
): Promise<void> {
    exigir(await cliente.rpc("asignar_responsable", { p_tarea_id: tareaId, p_responsable_id: responsableId }));
}

export async function eliminarTarea(cliente: SupabaseClient, tareaId: string): Promise<void> {
    exigir(await cliente.rpc("eliminar_tarea", { p_tarea_id: tareaId }));
}

// -----------------------------------------------------------------------------
// Panel operativo
// -----------------------------------------------------------------------------

export type Prioridad = "baja" | "media" | "alta";

// Hallazgo sin resolver con la tarea y el proyecto afectados. Lo crea la
// detección programada del backend; el frontend no calcula vencimientos.
export type HallazgoAbierto = {
    id: string;
    prioridad: Prioridad;
    detectado_en: string;
    tarea: Pick<Tarea, "id" | "titulo" | "estado" | "responsable_id" | "fecha_limite" | "vence_en"> & {
        proyecto_id: string;
        proyecto: string;
    };
};

export async function listarHallazgosAbiertos(
    cliente: SupabaseClient,
    organizacionId: string,
): Promise<HallazgoAbierto[]> {
    const filas = exigir(
        await cliente
            .from("hallazgos")
            .select(
                "id, prioridad, detectado_en, tareas(id, titulo, estado, responsable_id, proyecto_id, fecha_limite, vence_en, proyectos(nombre))",
            )
            .eq("organizacion_id", organizacionId)
            .is("resuelto_en", null)
            .order("detectado_en"),
    ) as unknown as {
        id: string;
        prioridad: Prioridad;
        detectado_en: string;
        tareas: Omit<HallazgoAbierto["tarea"], "proyecto"> & { proyectos: { nombre: string } };
    }[];
    return filas.map(({ tareas: { proyectos, ...tarea }, ...hallazgo }) => ({
        ...hallazgo,
        tarea: { ...tarea, proyecto: proyectos.nombre },
    }));
}

export async function resolverHallazgo(cliente: SupabaseClient, hallazgoId: string): Promise<void> {
    exigir(await cliente.rpc("resolver_hallazgo", { p_hallazgo_id: hallazgoId }));
}

// Estado de cada tarea de la organización, para el resumen por proyecto.
export async function listarEstadosDeTareas(
    cliente: SupabaseClient,
    organizacionId: string,
): Promise<{ proyecto_id: string; estado: EstadoTarea }[]> {
    return exigir(
        await cliente.from("tareas").select("proyecto_id, estado").eq("organizacion_id", organizacionId),
    ) as { proyecto_id: string; estado: EstadoTarea }[];
}

// -----------------------------------------------------------------------------
// Notificaciones (RLS: cada persona solo ve las suyas)
// -----------------------------------------------------------------------------

export async function listarNotificaciones(
    cliente: SupabaseClient,
    organizacionId: string,
): Promise<Notificacion[]> {
    return exigir(
        await cliente
            .from("notificaciones")
            .select("id, titulo, mensaje, leida_en, creado_en")
            .eq("organizacion_id", organizacionId)
            .order("creado_en", { ascending: false })
            .limit(50),
    ) as Notificacion[];
}

export async function marcarNotificacionLeida(cliente: SupabaseClient, notificacionId: string): Promise<void> {
    exigir(await cliente.rpc("marcar_notificacion_leida", { p_notificacion_id: notificacionId }));
}
