import type { SupabaseClient } from "@supabase/supabase-js";
import { Bell, CalendarX2, CheckCheck, ChevronRight, CircleCheck, FolderKanban } from "lucide-react";
import { useCallback, useState } from "react";
import { EtiquetaEstado } from "../componentes/etiqueta_estado.tsx";
import { estilosEstado, type EstadoTarea } from "../componentes/estados.ts";
import { useCarga } from "./carga.ts";
import {
    listarEstadosDeTareas,
    listarHallazgosAbiertos,
    listarMiembros,
    listarNotificaciones,
    listarProyectos,
    resolverHallazgo,
    type HallazgoAbierto,
    type Organizacion,
    type Prioridad,
} from "./datos.ts";
import { textoInstante, textoVencimiento } from "./formato.ts";
import { AvisoError, claseBotonFila, EsqueletoLista } from "./ui.tsx";

type Propiedades = {
    cliente: SupabaseClient;
    organizacion: Organizacion;
    usuarioId: string;
    alAbrirTarea: (proyectoId: string, tareaId?: string) => void;
    alVerNotificaciones: () => void;
};

const etiquetasPrioridad: Record<Prioridad, string> = {
    alta: "Prioridad alta",
    media: "Prioridad media",
    baja: "Prioridad baja",
};

// Orden de los estados en el resumen de cada proyecto (catálogo del backend).
const ordenEstados: EstadoTarea[] = ["pendiente", "en_curso", "en_revision", "completada", "cancelada"];

const visiblesPorBloque = 6;

// Panel operativo: responde primero a "¿qué necesita atención?". Todos los
// datos vienen del backend con RLS: los hallazgos los crea la detección
// programada; el panel no decide qué está vencido.
export function Panel({ cliente, organizacion, usuarioId, alAbrirTarea, alVerNotificaciones }: Propiedades) {
    const cargar = useCallback(async () => {
        const [hallazgos, notificaciones, proyectos, estados, miembros] = await Promise.all([
            listarHallazgosAbiertos(cliente, organizacion.id),
            listarNotificaciones(cliente, organizacion.id),
            listarProyectos(cliente, organizacion.id),
            listarEstadosDeTareas(cliente, organizacion.id),
            listarMiembros(cliente, organizacion.id),
        ]);
        return { hallazgos, notificaciones, proyectos, estados, miembros };
    }, [cliente, organizacion.id]);
    const { carga, recargar } = useCarga(cargar);
    const [error, setError] = useState<unknown>(null);
    const [resolviendo, setResolviendo] = useState<string | null>(null);
    const [verTodos, setVerTodos] = useState(false);

    async function resolver(hallazgoId: string) {
        setResolviendo(hallazgoId);
        setError(null);
        try {
            await resolverHallazgo(cliente, hallazgoId);
            recargar();
        } catch (fallo) {
            setError(fallo);
        }
        setResolviendo(null);
    }

    if (carga.estado === "cargando") {
        return (
            <div className="flex flex-col gap-8">
                <EsqueletoLista texto="Cargando el panel…" />
            </div>
        );
    }
    if (carga.estado === "error") {
        return <AvisoError error={carga.error} />;
    }

    const { hallazgos, notificaciones, proyectos, estados, miembros } = carga.datos;
    const nombres = new Map(miembros.map((m) => [m.usuario_id, m.nombre_visible]));
    const gestiona = organizacion.rol !== "miembro";
    const visibles = verTodos ? hallazgos : hallazgos.slice(0, visiblesPorBloque);

    return (
        <div className="flex flex-col gap-8">
            {/* 1. Lo que necesita atención (bloque principal) */}
            <section aria-labelledby="titulo-atencion" className="rounded-xl border border-borde bg-superficie">
                <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1 border-b border-borde px-4 py-4 sm:px-5">
                    <h2 id="titulo-atencion" className="text-lg font-semibold tracking-tight">
                        Necesita atención
                    </h2>
                    <p className="text-sm text-texto-2">
                        <span className="text-2xl font-semibold text-texto tabular-nums">{hallazgos.length}</span>{" "}
                        {hallazgos.length === 1 ? "tarea vencida sin resolver" : "tareas vencidas sin resolver"}
                    </p>
                </div>

                {error !== null && (
                    <div className="px-4 pt-4 sm:px-5">
                        <AvisoError error={error} />
                    </div>
                )}

                {hallazgos.length === 0 ? (
                    <p className="flex items-start gap-2 px-4 py-6 text-sm text-texto-2 sm:px-5">
                        <CircleCheck size={18} aria-hidden="true" className="mt-0.5 shrink-0 text-exito" />
                        Nada pendiente. La detección revisa los vencimientos periódicamente: cuando una tarea supere
                        su fecha límite, aparecerá aquí.
                    </p>
                ) : (
                    <>
                        <ul className="divide-y divide-borde">
                            {visibles.map((hallazgo) => (
                                <FilaHallazgo
                                    key={hallazgo.id}
                                    hallazgo={hallazgo}
                                    zonaHoraria={organizacion.zona_horaria}
                                    responsable={
                                        hallazgo.tarea.responsable_id
                                            ? (nombres.get(hallazgo.tarea.responsable_id) ?? null)
                                            : null
                                    }
                                    // Matriz: propietario y administrador, o el responsable de la
                                    // tarea. La RPC lo vuelve a comprobar.
                                    puedeResolver={gestiona || hallazgo.tarea.responsable_id === usuarioId}
                                    resolviendo={resolviendo === hallazgo.id}
                                    alAbrir={() => alAbrirTarea(hallazgo.tarea.proyecto_id, hallazgo.tarea.id)}
                                    alResolver={() => resolver(hallazgo.id)}
                                />
                            ))}
                        </ul>
                        {hallazgos.length > visiblesPorBloque && (
                            <div className="border-t border-borde px-4 py-3 sm:px-5">
                                <button
                                    type="button"
                                    className={claseBotonFila}
                                    onClick={() => setVerTodos(!verTodos)}
                                >
                                    {verTodos ? "Ver menos" : `Ver las ${hallazgos.length}`}
                                </button>
                            </div>
                        )}
                    </>
                )}
            </section>

            <div className="grid gap-8 lg:grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)]">
                {/* 2. Proyectos: tareas por estado y hallazgos abiertos */}
                <ResumenProyectos
                    proyectos={proyectos}
                    estados={estados}
                    hallazgos={hallazgos}
                    alAbrir={(proyectoId) => alAbrirTarea(proyectoId)}
                />

                {/* 3. Notificaciones de quien ha iniciado sesión */}
                <NotificacionesRecientes
                    notificaciones={notificaciones}
                    zonaHoraria={organizacion.zona_horaria}
                    alVerTodas={alVerNotificaciones}
                />
            </div>
        </div>
    );
}

function FilaHallazgo({
    hallazgo,
    zonaHoraria,
    responsable,
    puedeResolver,
    resolviendo,
    alAbrir,
    alResolver,
}: {
    hallazgo: HallazgoAbierto;
    zonaHoraria: string;
    responsable: string | null;
    puedeResolver: boolean;
    resolviendo: boolean;
    alAbrir: () => void;
    alResolver: () => void;
}) {
    const vencimiento = textoVencimiento(hallazgo.tarea, zonaHoraria);
    return (
        <li className="grid gap-3 px-4 py-3.5 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center sm:px-5">
            <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                    <EtiquetaEstado estado={hallazgo.tarea.estado} />
                    <span className="inline-flex items-center gap-1.5 rounded-md bg-atencion-suave px-2 py-0.5 text-xs font-semibold text-atencion">
                        <CalendarX2 size={14} aria-hidden="true" />
                        Vencida
                    </span>
                    <span className="text-xs text-texto-2">{etiquetasPrioridad[hallazgo.prioridad]}</span>
                </div>
                <p className="mt-1.5 font-semibold">{hallazgo.tarea.titulo}</p>
                <p className="mt-0.5 text-[13px] text-texto-2">
                    {hallazgo.tarea.proyecto} · {responsable ?? "Sin responsable"}
                    {vencimiento && <> · {vencimiento}</>}
                </p>
                <p className="mt-0.5 text-xs text-texto-2 tabular-nums">
                    Detectada el {textoInstante(hallazgo.detectado_en, zonaHoraria)}
                </p>
            </div>
            <div className="flex flex-wrap gap-2 sm:justify-end">
                <button type="button" className={claseBotonFila} onClick={alAbrir}>
                    Abrir tarea
                    <span className="sr-only"> {hallazgo.tarea.titulo}</span>
                    <ChevronRight size={14} aria-hidden="true" />
                </button>
                {puedeResolver && (
                    <button type="button" className={claseBotonFila} onClick={alResolver} disabled={resolviendo}>
                        <CheckCheck size={14} aria-hidden="true" />
                        {resolviendo ? "Resolviendo…" : "Resolver"}
                        <span className="sr-only"> el hallazgo de {hallazgo.tarea.titulo}</span>
                    </button>
                )}
            </div>
        </li>
    );
}

function ResumenProyectos({
    proyectos,
    estados,
    hallazgos,
    alAbrir,
}: {
    proyectos: { id: string; nombre: string; archivado_en: string | null }[];
    estados: { proyecto_id: string; estado: EstadoTarea }[];
    hallazgos: HallazgoAbierto[];
    alAbrir: (proyectoId: string) => void;
}) {
    const activos = proyectos.filter((p) => p.archivado_en === null);
    const archivados = proyectos.length - activos.length;

    // Recuentos de datos reales; no se interpreta nada (ni "abiertas" ni
    // "en riesgo"): solo cuántas tareas hay en cada estado.
    const recuento = new Map<string, Map<EstadoTarea, number>>();
    for (const { proyecto_id, estado } of estados) {
        const delProyecto = recuento.get(proyecto_id) ?? new Map<EstadoTarea, number>();
        delProyecto.set(estado, (delProyecto.get(estado) ?? 0) + 1);
        recuento.set(proyecto_id, delProyecto);
    }
    const conHallazgo = new Map<string, number>();
    for (const { tarea } of hallazgos) {
        conHallazgo.set(tarea.proyecto_id, (conHallazgo.get(tarea.proyecto_id) ?? 0) + 1);
    }

    return (
        <section aria-labelledby="titulo-resumen-proyectos">
            <div className="flex flex-wrap items-baseline gap-x-3">
                <h2 id="titulo-resumen-proyectos" className="font-semibold">
                    Proyectos activos
                </h2>
                <p className="text-sm text-texto-2 tabular-nums">
                    {activos.length}
                    {archivados > 0 && ` · ${archivados} archivado${archivados === 1 ? "" : "s"}`}
                </p>
            </div>
            {activos.length === 0 ? (
                <p className="mt-3 rounded-lg border border-dashed border-borde-fuerte px-4 py-6 text-sm text-texto-2">
                    No hay proyectos activos. Créalos desde la sección Proyectos.
                </p>
            ) : (
                <ul className="mt-3 divide-y divide-borde rounded-xl border border-borde bg-superficie">
                    {activos.map((proyecto) => {
                        const porEstado = recuento.get(proyecto.id);
                        const vencidas = conHallazgo.get(proyecto.id) ?? 0;
                        return (
                            <li key={proyecto.id}>
                                <button
                                    type="button"
                                    onClick={() => alAbrir(proyecto.id)}
                                    className="transicion flex w-full items-start gap-3 px-4 py-3 text-left hover:bg-elevada"
                                >
                                    <FolderKanban size={18} aria-hidden="true" className="mt-0.5 shrink-0 text-texto-2" />
                                    <span className="min-w-0 flex-1">
                                        <span className="block truncate font-medium">{proyecto.nombre}</span>
                                        <span className="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-[13px] text-texto-2 tabular-nums">
                                            {porEstado === undefined ? (
                                                <span>Sin tareas</span>
                                            ) : (
                                                ordenEstados
                                                    .filter((estado) => porEstado.has(estado))
                                                    .map((estado) => {
                                                        const { etiqueta, Icono } = estilosEstado[estado];
                                                        return (
                                                            <span key={estado} className="inline-flex items-center gap-1">
                                                                <Icono size={13} aria-hidden="true" />
                                                                {etiqueta}: {porEstado.get(estado)}
                                                            </span>
                                                        );
                                                    })
                                            )}
                                        </span>
                                    </span>
                                    {vencidas > 0 && (
                                        <span className="inline-flex shrink-0 items-center gap-1 rounded-md bg-atencion-suave px-2 py-0.5 text-xs font-semibold text-atencion tabular-nums">
                                            <CalendarX2 size={14} aria-hidden="true" />
                                            {vencidas} vencida{vencidas === 1 ? "" : "s"}
                                        </span>
                                    )}
                                    <ChevronRight size={16} aria-hidden="true" className="mt-0.5 shrink-0 text-texto-2" />
                                </button>
                            </li>
                        );
                    })}
                </ul>
            )}
        </section>
    );
}

function NotificacionesRecientes({
    notificaciones,
    zonaHoraria,
    alVerTodas,
}: {
    notificaciones: { id: string; titulo: string; mensaje: string; leida_en: string | null; creado_en: string }[];
    zonaHoraria: string;
    alVerTodas: () => void;
}) {
    const sinLeer = notificaciones.filter((n) => n.leida_en === null).length;
    const recientes = notificaciones.slice(0, 5);

    return (
        <section aria-labelledby="titulo-notificaciones-recientes">
            <div className="flex flex-wrap items-baseline justify-between gap-x-3">
                <div className="flex items-baseline gap-x-3">
                    <h2 id="titulo-notificaciones-recientes" className="font-semibold">
                        Tus notificaciones
                    </h2>
                    <p className="text-sm text-texto-2 tabular-nums">{sinLeer} sin leer</p>
                </div>
                {notificaciones.length > 0 && (
                    <button type="button" onClick={alVerTodas} className="transicion rounded text-sm font-medium text-acento hover:underline">
                        Ver todas
                    </button>
                )}
            </div>
            {recientes.length === 0 ? (
                <p className="mt-3 rounded-lg border border-dashed border-borde-fuerte px-4 py-6 text-sm text-texto-2">
                    No tienes notificaciones.
                </p>
            ) : (
                <ul className="mt-3 divide-y divide-borde rounded-xl border border-borde bg-superficie">
                    {recientes.map((notificacion) => {
                        const leida = notificacion.leida_en !== null;
                        return (
                            <li key={notificacion.id} className="flex items-start gap-3 px-4 py-3">
                                <Bell
                                    size={16}
                                    aria-hidden="true"
                                    className={`mt-0.5 shrink-0 ${leida ? "text-texto-2" : "text-acento"}`}
                                />
                                <div className="min-w-0">
                                    <p className={`text-sm ${leida ? "text-texto-2" : "font-semibold"}`}>
                                        {notificacion.mensaje}
                                    </p>
                                    <p className="mt-0.5 text-xs text-texto-2 tabular-nums">
                                        {leida ? "Leída" : "Sin leer"} · {textoInstante(notificacion.creado_en, zonaHoraria)}
                                    </p>
                                </div>
                            </li>
                        );
                    })}
                </ul>
            )}
        </section>
    );
}
