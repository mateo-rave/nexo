import type { SupabaseClient } from "@supabase/supabase-js";
import { Archive, ArrowLeft, CalendarX2, ListPlus, Trash2 } from "lucide-react";
import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { EtiquetaEstado } from "../componentes/etiqueta_estado.tsx";
import { estilosEstado, type EstadoTarea } from "../componentes/estados.ts";
import { useCarga } from "./carga.ts";
import { textoVencimiento } from "./formato.ts";
import {
    archivarProyecto,
    asignarResponsable,
    cambiarEstadoTarea,
    crearTarea,
    eliminarTarea,
    listarMiembros,
    listarTareas,
    listarTransiciones,
    tareasConHallazgoAbierto,
    type Miembro,
    type NuevaTarea as DatosNuevaTarea,
    type Organizacion,
    type Proyecto,
    type Tarea,
} from "./datos.ts";
import {
    Aviso,
    AvisoError,
    Campo,
    claseBotonFila,
    claseBotonPrincipal,
    claseBotonSecundario,
    claseCampo,
    EsqueletoLista,
} from "./ui.tsx";

type Propiedades = {
    cliente: SupabaseClient;
    organizacion: Organizacion;
    proyecto: Proyecto;
    usuarioId: string;
    // Tarea a la que se llega desde el panel: se resalta y se lleva a la vista.
    tareaDestacada?: string;
    alVolver: () => void;
    alCambiarProyecto: () => void;
};

export function TareasProyecto({
    cliente,
    organizacion,
    proyecto,
    usuarioId,
    tareaDestacada,
    alVolver,
    alCambiarProyecto,
}: Propiedades) {
    const cargar = useCallback(async () => {
        const [tareas, transiciones, miembros, vencidas] = await Promise.all([
            listarTareas(cliente, proyecto.id),
            listarTransiciones(cliente, proyecto.version_flujo_id),
            listarMiembros(cliente, organizacion.id),
            tareasConHallazgoAbierto(cliente, organizacion.id),
        ]);
        return { tareas, transiciones, miembros, vencidas };
    }, [cliente, proyecto.id, proyecto.version_flujo_id, organizacion.id]);
    const { carga, recargar } = useCarga(cargar);
    const [error, setError] = useState<unknown>(null);
    const [ocupado, setOcupado] = useState(false);

    const gestiona = organizacion.rol !== "miembro";
    const archivado = proyecto.archivado_en !== null;

    // Ejecuta una operación del backend, muestra su error si lo hay y recarga.
    async function ejecutar(operacion: () => Promise<void>, despues: () => void = recargar) {
        setOcupado(true);
        setError(null);
        try {
            await operacion();
            despues();
        } catch (fallo) {
            setError(fallo);
        }
        setOcupado(false);
    }

    return (
        <div className="flex flex-col gap-6">
            <div className="flex flex-wrap items-center gap-3">
                <button type="button" onClick={alVolver} className={claseBotonSecundario}>
                    <ArrowLeft size={16} aria-hidden="true" />
                    Proyectos
                </button>
                <h2 className="min-w-0 flex-1 truncate text-lg font-semibold tracking-tight">{proyecto.nombre}</h2>
                {gestiona && (
                    <button
                        type="button"
                        className={claseBotonSecundario}
                        disabled={ocupado}
                        onClick={() =>
                            ejecutar(() => archivarProyecto(cliente, proyecto.id, !archivado), alCambiarProyecto)
                        }
                    >
                        <Archive size={16} aria-hidden="true" />
                        {archivado ? "Desarchivar" : "Archivar"}
                    </button>
                )}
            </div>

            {archivado && (
                <Aviso tono="informacion">
                    Este proyecto está archivado: sus tareas no se pueden crear ni modificar.
                </Aviso>
            )}
            {error !== null && <AvisoError error={error} />}

            {carga.estado === "error" && <AvisoError error={carga.error} />}
            {carga.estado !== "error" && (
                <>
                    {!archivado && carga.estado === "listo" && (
                        <NuevaTarea
                            miembros={carga.datos.miembros}
                            ocupado={ocupado}
                            alCrear={(tarea, limpiar) =>
                                ejecutar(() => crearTarea(cliente, proyecto.id, tarea), () => {
                                    limpiar();
                                    recargar();
                                })
                            }
                        />
                    )}

                    <section aria-labelledby="titulo-tareas">
                        <h3 id="titulo-tareas" className="font-semibold">
                            Tareas
                        </h3>
                        {carga.estado === "cargando" && <EsqueletoLista texto="Cargando tareas…" />}
                        {carga.estado === "listo" &&
                            (carga.datos.tareas.length === 0 ? (
                                <p className="mt-3 rounded-lg border border-dashed border-borde-fuerte px-4 py-6 text-sm text-texto-2">
                                    Este proyecto todavía no tiene tareas.
                                    {!archivado && " Crea la primera con el formulario de arriba."}
                                </p>
                            ) : (
                                <ul className="mt-3 divide-y divide-borde rounded-xl border border-borde bg-superficie">
                                    {carga.datos.tareas.map((tarea) => (
                                        <FilaTarea
                                            key={tarea.id}
                                            tarea={tarea}
                                            zonaHoraria={organizacion.zona_horaria}
                                            miembros={carga.datos.miembros}
                                            siguientes={carga.datos.transiciones
                                                .filter((t) => t.estado_origen === tarea.estado)
                                                .map((t) => t.estado_destino)}
                                            vencida={carga.datos.vencidas.has(tarea.id)}
                                            destacada={tarea.id === tareaDestacada}
                                            // Comodidad de interfaz: el backend vuelve a comprobar
                                            // permisos y transiciones en cada RPC.
                                            puedeGestionar={
                                                gestiona ||
                                                tarea.creado_por === usuarioId ||
                                                tarea.responsable_id === usuarioId
                                            }
                                            puedeEliminar={gestiona}
                                            soloLectura={archivado}
                                            ocupado={ocupado}
                                            alAsignar={(responsableId) =>
                                                ejecutar(() => asignarResponsable(cliente, tarea.id, responsableId))
                                            }
                                            alCambiarEstado={(estado) =>
                                                ejecutar(() => cambiarEstadoTarea(cliente, tarea.id, estado))
                                            }
                                            alEliminar={() => ejecutar(() => eliminarTarea(cliente, tarea.id))}
                                        />
                                    ))}
                                </ul>
                            ))}
                    </section>
                </>
            )}
        </div>
    );
}

// Una fila: los datos a la izquierda, con sus acciones debajo, y el
// responsable en una columna de ancho fijo para que todas las filas terminen
// en el mismo borde.
function FilaTarea({
    tarea,
    zonaHoraria,
    miembros,
    siguientes,
    vencida,
    destacada,
    puedeGestionar,
    puedeEliminar,
    soloLectura,
    ocupado,
    alAsignar,
    alCambiarEstado,
    alEliminar,
}: {
    tarea: Tarea;
    zonaHoraria: string;
    miembros: Miembro[];
    siguientes: EstadoTarea[];
    vencida: boolean;
    destacada: boolean;
    puedeGestionar: boolean;
    puedeEliminar: boolean;
    soloLectura: boolean;
    ocupado: boolean;
    alAsignar: (responsableId: string | null) => void;
    alCambiarEstado: (estado: EstadoTarea) => void;
    alEliminar: () => void;
}) {
    const vencimiento = textoVencimiento(tarea, zonaHoraria);
    const acciones = !soloLectura && ((puedeGestionar && siguientes.length > 0) || puedeEliminar);
    const fila = useRef<HTMLLIElement>(null);

    // Al llegar desde el panel, la fila recibe el foco (también para teclado y
    // lectores de pantalla) y se desplaza hasta ella sin animación.
    useEffect(() => {
        if (destacada) {
            fila.current?.focus({ preventScroll: true });
            fila.current?.scrollIntoView({ block: "center" });
        }
    }, [destacada]);

    return (
        <li
            ref={fila}
            id={`tarea-${tarea.id}`}
            tabIndex={destacada ? -1 : undefined}
            aria-current={destacada ? "true" : undefined}
            className={`grid gap-3 px-4 py-3.5 outline-none sm:grid-cols-[minmax(0,1fr)_13rem] sm:gap-6 ${
                destacada ? "bg-acento-suave/60 ring-2 ring-acento ring-inset first:rounded-t-xl last:rounded-b-xl" : ""
            }`}
        >
            <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                    <EtiquetaEstado estado={tarea.estado} />
                    {vencida && (
                        <span className="inline-flex items-center gap-1.5 rounded-md bg-atencion-suave px-2 py-0.5 text-xs font-semibold text-atencion">
                            <CalendarX2 size={14} aria-hidden="true" />
                            Vencida
                        </span>
                    )}
                </div>
                <p className="mt-1.5 font-semibold">{tarea.titulo}</p>
                {tarea.descripcion && <p className="mt-0.5 text-sm text-texto-2">{tarea.descripcion}</p>}
                {vencimiento && <p className="mt-1 text-[13px] text-texto-2 tabular-nums">{vencimiento}</p>}

                {acciones && (
                    <div className="mt-3 flex flex-wrap items-center gap-2">
                        {puedeGestionar &&
                            siguientes.map((estado) => {
                                const { etiqueta, Icono } = estilosEstado[estado];
                                return (
                                    <button
                                        key={estado}
                                        type="button"
                                        className={claseBotonFila}
                                        disabled={ocupado}
                                        onClick={() => alCambiarEstado(estado)}
                                    >
                                        <Icono size={14} aria-hidden="true" />
                                        <span className="sr-only">Pasar a </span>
                                        {etiqueta}
                                    </button>
                                );
                            })}
                        {puedeEliminar && (
                            <button
                                type="button"
                                className={`${claseBotonFila} text-texto-2 hover:text-error`}
                                disabled={ocupado}
                                title="Eliminar tarea"
                                onClick={() => {
                                    if (window.confirm(`¿Eliminar la tarea «${tarea.titulo}»?`)) {
                                        alEliminar();
                                    }
                                }}
                            >
                                <Trash2 size={14} aria-hidden="true" />
                                <span className="sr-only">Eliminar {tarea.titulo}</span>
                            </button>
                        )}
                    </div>
                )}
            </div>

            <label className="flex flex-col gap-1 text-xs text-texto-2">
                Responsable
                <select
                    className={claseCampo}
                    value={tarea.responsable_id ?? ""}
                    disabled={ocupado || soloLectura}
                    onChange={(e) => alAsignar(e.target.value || null)}
                >
                    <option value="">Sin responsable</option>
                    {miembros.map((miembro) => (
                        <option key={miembro.usuario_id} value={miembro.usuario_id}>
                            {miembro.nombre_visible}
                        </option>
                    ))}
                </select>
            </label>
        </li>
    );
}

function NuevaTarea({
    miembros,
    ocupado,
    alCrear,
}: {
    miembros: Miembro[];
    ocupado: boolean;
    alCrear: (tarea: DatosNuevaTarea, limpiar: () => void) => void;
}) {
    const [titulo, setTitulo] = useState("");
    const [descripcion, setDescripcion] = useState("");
    const [responsableId, setResponsableId] = useState("");
    const [fecha, setFecha] = useState("");
    const [hora, setHora] = useState("");
    const campoTitulo = useRef<HTMLInputElement>(null);

    function enviar(evento: FormEvent) {
        evento.preventDefault();
        alCrear(
            {
                titulo,
                descripcion,
                responsableId: responsableId || null,
                fechaLimite: fecha || null,
                horaLimite: hora || null,
            },
            () => {
                setTitulo("");
                setDescripcion("");
                setResponsableId("");
                setFecha("");
                setHora("");
                // Para crear varias tareas seguidas sin volver al ratón.
                campoTitulo.current?.focus();
            },
        );
    }

    return (
        <section aria-labelledby="titulo-nueva-tarea" className="rounded-xl border border-borde bg-superficie p-4 sm:p-5">
            <h3 id="titulo-nueva-tarea" className="flex items-center gap-2 font-semibold">
                <ListPlus size={18} aria-hidden="true" className="text-acento" />
                Nueva tarea
            </h3>
            <form
                onSubmit={enviar}
                className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)_10.5rem_8rem]"
            >
                <div className="sm:col-span-2 lg:col-span-1">
                    <Campo etiqueta="Título">
                        <input
                            ref={campoTitulo}
                            className={claseCampo}
                            value={titulo}
                            onChange={(e) => setTitulo(e.target.value)}
                            required
                            maxLength={200}
                        />
                    </Campo>
                </div>
                <div className="sm:col-span-2 lg:col-span-1">
                    <Campo etiqueta="Responsable">
                        <select className={claseCampo} value={responsableId} onChange={(e) => setResponsableId(e.target.value)}>
                            <option value="">Sin responsable</option>
                            {miembros.map((miembro) => (
                                <option key={miembro.usuario_id} value={miembro.usuario_id}>
                                    {miembro.nombre_visible}
                                </option>
                            ))}
                        </select>
                    </Campo>
                </div>
                <Campo etiqueta="Fecha límite">
                    <input className={claseCampo} type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} />
                </Campo>
                <Campo etiqueta="Hora (opcional)">
                    <input
                        className={claseCampo}
                        type="time"
                        value={hora}
                        onChange={(e) => setHora(e.target.value)}
                        disabled={!fecha}
                    />
                </Campo>
                <div className="sm:col-span-2 lg:col-span-4">
                    <Campo etiqueta="Descripción (opcional)">
                        <textarea
                            className={`${claseCampo} min-h-16 py-2`}
                            value={descripcion}
                            onChange={(e) => setDescripcion(e.target.value)}
                            maxLength={5000}
                        />
                    </Campo>
                </div>
                <div className="sm:col-span-2 lg:col-span-4">
                    <button type="submit" className={claseBotonPrincipal} disabled={ocupado}>
                        {ocupado ? "Guardando…" : "Crear tarea"}
                    </button>
                </div>
            </form>
        </section>
    );
}
