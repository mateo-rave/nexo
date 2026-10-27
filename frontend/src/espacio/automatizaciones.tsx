import type { SupabaseClient } from "@supabase/supabase-js";
import {
    ArrowLeft,
    Ban,
    ChevronRight,
    CircleAlert,
    CircleCheck,
    CircleDashed,
    Clock,
    GitBranch,
    Info,
    Pause,
    Play,
    Plus,
    RefreshCw,
    Workflow,
    type LucideIcon,
} from "lucide-react";
import { useCallback, useState, type ReactNode } from "react";
import { estilosEstado, type EstadoTarea } from "../componentes/estados.ts";
import { mensajeDeError } from "../supabase/errores.ts";
import { useCarga } from "./carga.ts";
import {
    activarRegla,
    crearRegla,
    crearVersionBorradorRegla,
    guardarBorradorRegla,
    listarEjecuciones,
    listarMiembros,
    listarProyectos,
    listarReglas,
    pausarRegla,
    publicarVersionRegla,
    type Activador,
    type Condicion,
    type DefinicionRegla,
    type Destinatarios,
    type Ejecucion,
    type EstadoEjecucion,
    type Miembro,
    type Organizacion,
    type Proyecto,
    type Regla,
    type VersionRegla,
} from "./datos.ts";
import { textoInstante } from "./formato.ts";
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

// Reglas de automatización (ADR-0008). La pantalla solo ofrece el catálogo
// cerrado del backend y oculta la gestión a los miembros por comodidad: cada
// RPC vuelve a comprobar el rol y valida la definición completa.

type Propiedades = { cliente: SupabaseClient; organizacion: Organizacion };

type Vista = { tipo: "lista" } | { tipo: "nueva" } | { tipo: "detalle"; reglaId: string };

const ordenEstados: EstadoTarea[] = ["pendiente", "en_curso", "en_revision", "completada", "cancelada"];

const textosActivador: Record<Activador, string> = {
    tarea_estado_cambiado: "Cuando cambia el estado de una tarea",
    tarea_vencida: "Cuando una tarea supera su fecha límite",
};

const textosDestinatarios: Record<Destinatarios, string> = {
    responsable: "su responsable",
    propietarios_y_administradores: "propietarios y administradores",
};

const avisoProcesamiento = "Nexo procesa los eventos cada minuto: una regla actúa poco después de que ocurra el evento.";

export function Automatizaciones({ cliente, organizacion }: Propiedades) {
    const cargar = useCallback(async () => {
        const [reglas, proyectos, miembros] = await Promise.all([
            listarReglas(cliente, organizacion.id),
            listarProyectos(cliente, organizacion.id),
            listarMiembros(cliente, organizacion.id),
        ]);
        return { reglas, proyectos, miembros };
    }, [cliente, organizacion.id]);
    const { carga, recargar } = useCarga(cargar);
    const [vista, setVista] = useState<Vista>({ tipo: "lista" });
    const gestiona = organizacion.rol !== "miembro";

    if (carga.estado === "cargando") {
        return <EsqueletoLista texto="Cargando las reglas…" />;
    }
    if (carga.estado === "error") {
        return <AvisoError error={carga.error} />;
    }

    const { reglas, proyectos, miembros } = carga.datos;

    if (vista.tipo === "nueva" && gestiona) {
        return (
            <NuevaRegla
                cliente={cliente}
                organizacion={organizacion}
                proyectos={proyectos}
                alCrear={(reglaId) => {
                    recargar();
                    setVista({ tipo: "detalle", reglaId });
                }}
                alCancelar={() => setVista({ tipo: "lista" })}
            />
        );
    }

    if (vista.tipo === "detalle") {
        const regla = reglas.find((r) => r.id === vista.reglaId);
        // Tras crear una regla, la lista se está recargando.
        if (!regla) {
            return <EsqueletoLista texto="Cargando la regla…" filas={2} />;
        }
        return (
            <DetalleRegla
                key={regla.id}
                cliente={cliente}
                organizacion={organizacion}
                regla={regla}
                proyectos={proyectos}
                miembros={miembros}
                gestiona={gestiona}
                alVolver={() => setVista({ tipo: "lista" })}
                alCambiar={recargar}
            />
        );
    }

    return (
        <section aria-labelledby="titulo-reglas" className="flex flex-col gap-4">
            <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="max-w-2xl">
                    <h2 id="titulo-reglas" className="text-lg font-semibold tracking-tight">
                        Reglas de automatización
                    </h2>
                    <p className="mt-1 text-sm text-texto-2">
                        Una regla avisa a las personas adecuadas cuando ocurre algo en una tarea. Solo admite las
                        condiciones y acciones del catálogo de Nexo.
                    </p>
                </div>
                {gestiona && (
                    <button type="button" className={claseBotonPrincipal} onClick={() => setVista({ tipo: "nueva" })}>
                        <Plus size={16} aria-hidden="true" />
                        Nueva regla
                    </button>
                )}
            </div>

            {reglas.length === 0 ? (
                <p className="rounded-lg border border-dashed border-borde-fuerte px-4 py-6 text-sm text-texto-2">
                    Todavía no hay reglas.{" "}
                    {gestiona ? "Crea la primera con «Nueva regla»." : "Las crean el propietario y los administradores."}
                </p>
            ) : (
                <ul className="divide-y divide-borde rounded-xl border border-borde bg-superficie">
                    {reglas.map((regla) => {
                        const vigente = versionPublicada(regla) ?? versionBorrador(regla);
                        return (
                            <li key={regla.id}>
                                <button
                                    type="button"
                                    onClick={() => setVista({ tipo: "detalle", reglaId: regla.id })}
                                    className="transicion flex w-full items-start gap-3 px-4 py-3 text-left hover:bg-elevada"
                                >
                                    <Workflow size={18} aria-hidden="true" className="mt-0.5 shrink-0 text-texto-2" />
                                    <span className="min-w-0 flex-1">
                                        <span className="block truncate font-medium">{regla.nombre}</span>
                                        {vigente && (
                                            <span className="mt-0.5 block text-[13px] text-texto-2">
                                                {resumenDefinicion(vigente, proyectos)}
                                            </span>
                                        )}
                                    </span>
                                    <EtiquetaEstadoRegla regla={regla} />
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

// -----------------------------------------------------------------------------
// Estado de una regla y descripción de su definición
// -----------------------------------------------------------------------------

function versionPublicada(regla: Regla): VersionRegla | undefined {
    return [...regla.versiones].reverse().find((version) => version.estado === "publicada");
}

function versionBorrador(regla: Regla): VersionRegla | undefined {
    return regla.versiones.find((version) => version.estado === "borrador");
}

type EstadoRegla = "activa" | "pausada" | "sin_activar";

function estadoDeRegla(regla: Regla): EstadoRegla {
    if (regla.periodos.some((periodo) => periodo.desactivada_en === null)) return "activa";
    return regla.periodos.length > 0 ? "pausada" : "sin_activar";
}

const estilosEstadoRegla: Record<EstadoRegla, { etiqueta: string; Icono: LucideIcon; clases: string }> = {
    activa: { etiqueta: "Activa", Icono: CircleCheck, clases: "bg-exito-suave text-exito" },
    pausada: { etiqueta: "Pausada", Icono: Pause, clases: "bg-elevada text-texto-2" },
    sin_activar: { etiqueta: "Sin activar", Icono: CircleDashed, clases: "bg-elevada text-texto-2" },
};

function EtiquetaEstadoRegla({ regla }: { regla: Regla }) {
    const { etiqueta, Icono, clases } = estilosEstadoRegla[estadoDeRegla(regla)];
    return (
        <span className={`inline-flex shrink-0 items-center gap-1.5 rounded-md px-2 py-0.5 text-xs font-semibold ${clases}`}>
            <Icono size={14} aria-hidden="true" />
            {etiqueta}
        </span>
    );
}

// "Pendiente", "Pendiente o En curso", "Pendiente, En curso o En revisión".
function listaConO(elementos: string[]): string {
    return elementos.length <= 1
        ? elementos.join("")
        : `${elementos.slice(0, -1).join(", ")} o ${elementos[elementos.length - 1]}`;
}

// Por ejemplo: «Cuando una tarea pasa a En revisión en el proyecto «Web», si
// tiene responsable, avisar a su responsable.»
function resumenDefinicion(definicion: DefinicionRegla, proyectos: Proyecto[]): string {
    const condicion = <T extends Condicion["tipo"]>(tipo: T) =>
        definicion.condiciones.find((c): c is Extract<Condicion, { tipo: T }> => c.tipo === tipo);
    const estados = condicion("estado_destino");
    const proyecto = condicion("proyecto");
    const responsable = condicion("con_responsable");

    let texto =
        definicion.activador === "tarea_vencida"
            ? "Cuando una tarea supera su fecha límite"
            : estados
              ? `Cuando una tarea pasa a ${listaConO(estados.estados.map((e) => estilosEstado[e].etiqueta))}`
              : "Cuando una tarea cambia de estado";
    if (proyecto) {
        const nombre = proyectos.find((p) => p.id.toLowerCase() === proyecto.proyecto_id.toLowerCase())?.nombre;
        texto += nombre ? ` en el proyecto «${nombre}»` : " en un proyecto concreto";
    }
    if (responsable) {
        texto += responsable.valor ? ", si tiene responsable" : ", si no tiene responsable";
    }
    const destinatarios = definicion.acciones.map((accion) => textosDestinatarios[accion.destinatarios]);
    return `${texto}, avisar a ${destinatarios.join(" y a ")}.`;
}

// -----------------------------------------------------------------------------
// Crear una regla
// -----------------------------------------------------------------------------

function NuevaRegla({
    cliente,
    organizacion,
    proyectos,
    alCrear,
    alCancelar,
}: {
    cliente: SupabaseClient;
    organizacion: Organizacion;
    proyectos: Proyecto[];
    alCrear: (reglaId: string) => void;
    alCancelar: () => void;
}) {
    const [enviando, setEnviando] = useState(false);
    const [error, setError] = useState<unknown>(null);

    async function crear(nombre: string, definicion: DefinicionRegla) {
        setEnviando(true);
        setError(null);
        try {
            const version = await crearRegla(cliente, organizacion.id, nombre, definicion);
            alCrear(version.regla_id);
        } catch (fallo) {
            setError(fallo);
            setEnviando(false);
        }
    }

    return (
        <section aria-labelledby="titulo-nueva-regla" className="flex flex-col gap-4">
            <div className="flex flex-wrap items-center gap-3">
                <button type="button" onClick={alCancelar} className={claseBotonSecundario}>
                    <ArrowLeft size={16} aria-hidden="true" />
                    Reglas
                </button>
                <h2 id="titulo-nueva-regla" className="text-lg font-semibold tracking-tight">
                    Nueva regla
                </h2>
            </div>
            <p className="max-w-2xl text-sm text-texto-2">
                Se crea como borrador: no actúa hasta que publiques una versión y la actives.
            </p>
            <EditorRegla
                proyectos={proyectos}
                conNombre
                ocupado={enviando}
                error={error}
                botones={[{ accion: "crear", etiqueta: enviando ? "Creando…" : "Crear borrador", principal: true }]}
                alEnviar={(_accion, nombre, definicion) => crear(nombre, definicion)}
            />
        </section>
    );
}

// -----------------------------------------------------------------------------
// Detalle de una regla: versiones, activación y ejecuciones
// -----------------------------------------------------------------------------

function DetalleRegla({
    cliente,
    organizacion,
    regla,
    proyectos,
    miembros,
    gestiona,
    alVolver,
    alCambiar,
}: {
    cliente: SupabaseClient;
    organizacion: Organizacion;
    regla: Regla;
    proyectos: Proyecto[];
    miembros: Miembro[];
    gestiona: boolean;
    alVolver: () => void;
    alCambiar: () => void;
}) {
    const [operacion, setOperacion] = useState<Operacion | null>(null);
    const [fallo, setFallo] = useState<{ lugar: "cabecera" | "editor"; texto: string } | null>(null);
    const [guardado, setGuardado] = useState(false);
    const ocupado = operacion !== null;
    const publicada = versionPublicada(regla);
    const borrador = versionBorrador(regla);
    const estado = estadoDeRegla(regla);
    const zona = organizacion.zona_horaria;

    function empezar(nueva: Operacion) {
        setOperacion(nueva);
        setFallo(null);
        setGuardado(false);
    }

    // Activar, pausar y crear un borrador: el error se muestra en la cabecera.
    async function ejecutar(nueva: Operacion, accion: () => Promise<void>) {
        empezar(nueva);
        try {
            await accion();
            alCambiar();
        } catch (error) {
            setFallo({ lugar: "cabecera", texto: mensajeDeError(error) });
        }
        setOperacion(null);
    }

    function activar() {
        if (
            window.confirm(
                `¿Activar la regla «${regla.nombre}»? Actuará sobre los eventos que ocurran desde ahora, no sobre los anteriores.`,
            )
        ) {
            void ejecutar("activando", () => activarRegla(cliente, regla.id));
        }
    }

    function pausar() {
        if (
            window.confirm(
                `¿Pausar la regla «${regla.nombre}»? Dejará de actuar sobre los eventos que ocurran desde ahora. ` +
                    "Los eventos que ya ocurrieron mientras estaba activa se seguirán procesando.",
            )
        ) {
            void ejecutar("pausando", () => pausarRegla(cliente, regla.id));
        }
    }

    // Publicar guarda antes el borrador: son dos RPC, así que si la segunda
    // falla el borrador ya está guardado. Se recarga para mostrar lo que hay en
    // el backend y se dice qué paso falló.
    async function guardar(version: VersionRegla, definicion: DefinicionRegla, publicar: boolean) {
        if (
            publicar &&
            !window.confirm(
                `¿Publicar la versión ${version.numero}? Una versión publicada no se puede modificar: para cambiarla ` +
                    "tendrás que crear un borrador nuevo. Se aplicará a los eventos que ocurran desde su publicación.",
            )
        ) {
            return;
        }
        empezar(publicar ? "publicando" : "guardando");
        try {
            await guardarBorradorRegla(cliente, version.id, definicion);
        } catch (error) {
            setFallo({ lugar: "editor", texto: `No se pudo guardar el borrador. ${mensajeDeError(error)}` });
            setOperacion(null);
            return;
        }
        if (publicar) {
            try {
                await publicarVersionRegla(cliente, version.id);
            } catch (error) {
                setFallo({
                    lugar: "editor",
                    texto: `El borrador se guardó, pero no se pudo publicar la versión ${version.numero}. ${mensajeDeError(error)}`,
                });
            }
        } else {
            setGuardado(true);
        }
        alCambiar();
        setOperacion(null);
    }

    return (
        <div className="flex flex-col gap-6">
            <div className="flex flex-wrap items-center gap-3">
                <button type="button" onClick={alVolver} className={claseBotonSecundario}>
                    <ArrowLeft size={16} aria-hidden="true" />
                    Reglas
                </button>
                <h2 className="min-w-0 flex-1 truncate text-lg font-semibold tracking-tight">{regla.nombre}</h2>
                <EtiquetaEstadoRegla regla={regla} />
                {gestiona &&
                    (estado === "activa" ? (
                        <button type="button" className={claseBotonSecundario} disabled={ocupado} onClick={pausar}>
                            <Pause size={16} aria-hidden="true" />
                            {operacion === "pausando" ? "Pausando…" : "Pausar"}
                        </button>
                    ) : (
                        <button
                            type="button"
                            className={claseBotonPrincipal}
                            disabled={ocupado || !publicada}
                            title={publicada ? undefined : "Publica una versión para poder activarla"}
                            onClick={activar}
                        >
                            <Play size={16} aria-hidden="true" />
                            {operacion === "activando" ? "Activando…" : estado === "pausada" ? "Reactivar" : "Activar"}
                        </button>
                    ))}
            </div>

            {/* Sin borrador tras recargar, el error del editor también va aquí. */}
            {fallo && (fallo.lugar === "cabecera" || !borrador) && <Aviso tono="error">{fallo.texto}</Aviso>}

            {estado === "activa" && (
                <Aviso tono="informacion">
                    {avisoProcesamiento} Pausarla no cancela lo que ya ocurrió: los eventos ocurridos mientras estaba
                    activa se procesan igualmente.
                </Aviso>
            )}
            {estado === "pausada" && (
                <Aviso tono="informacion">
                    La regla está pausada: no actúa sobre los eventos nuevos. Los que ocurrieron mientras estaba activa
                    se procesaron o se procesarán igualmente; al reactivarla, solo actuará sobre los eventos que ocurran
                    desde ese momento.
                </Aviso>
            )}
            {estado === "sin_activar" && gestiona && !publicada && (
                <Aviso tono="informacion">Publica una versión para poder activar la regla.</Aviso>
            )}

            <section aria-labelledby="titulo-version-publicada" className="rounded-xl border border-borde bg-superficie p-4 sm:p-5">
                <h3 id="titulo-version-publicada" className="flex items-center gap-2 font-semibold">
                    <GitBranch size={18} aria-hidden="true" className="text-acento" />
                    Versión publicada
                </h3>
                {publicada ? (
                    <>
                        <p className="mt-2 text-sm">
                            <span className="font-medium">Versión {publicada.numero} publicada</span>
                            {publicada.publicada_en && (
                                <span className="text-texto-2 tabular-nums"> · {textoInstante(publicada.publicada_en, zona)}</span>
                            )}
                        </p>
                        <p className="mt-1 text-sm text-texto-2">{resumenDefinicion(publicada, proyectos)}</p>
                        <p className="mt-2 text-xs text-texto-2">
                            Una versión publicada no se modifica. Cada evento usa la versión publicada en el momento en
                            que ocurrió.
                        </p>
                        {gestiona && !borrador && (
                            <button
                                type="button"
                                className={`${claseBotonFila} mt-3`}
                                disabled={ocupado}
                                onClick={() =>
                                    void ejecutar("creando_borrador", () => crearVersionBorradorRegla(cliente, publicada.id))
                                }
                            >
                                <Plus size={14} aria-hidden="true" />
                                {operacion === "creando_borrador"
                                    ? "Creando el borrador…"
                                    : `Crear un borrador a partir de la versión ${publicada.numero}`}
                            </button>
                        )}
                    </>
                ) : (
                    <p className="mt-2 text-sm text-texto-2">Todavía no hay ninguna versión publicada.</p>
                )}
            </section>

            {borrador && (
                <section aria-labelledby="titulo-borrador" className="flex flex-col gap-3">
                    <h3 id="titulo-borrador" className="font-semibold">
                        Borrador · versión {borrador.numero}
                    </h3>
                    {gestiona ? (
                        <EditorRegla
                            key={borrador.id}
                            proyectos={proyectos}
                            inicial={borrador}
                            conNombre={false}
                            ocupado={ocupado}
                            error={null}
                            avisos={
                                <>
                                    {guardado && (
                                        <Aviso tono="exito">
                                            Borrador guardado. No actúa hasta que publiques esta versión.
                                        </Aviso>
                                    )}
                                    {fallo?.lugar === "editor" && <Aviso tono="error">{fallo.texto}</Aviso>}
                                </>
                            }
                            alModificar={() => setGuardado(false)}
                            botones={[
                                {
                                    accion: "guardar",
                                    etiqueta: operacion === "guardando" ? "Guardando…" : "Guardar borrador",
                                },
                                {
                                    accion: "publicar",
                                    etiqueta: operacion === "publicando" ? "Publicando…" : `Publicar versión ${borrador.numero}`,
                                    principal: true,
                                },
                            ]}
                            alEnviar={(accion, _nombre, definicion) =>
                                void guardar(borrador, definicion, accion === "publicar")
                            }
                        />
                    ) : (
                        <p className="text-sm text-texto-2">{resumenDefinicion(borrador, proyectos)}</p>
                    )}
                </section>
            )}

            <EjecucionesRegla
                cliente={cliente}
                regla={regla}
                miembros={miembros}
                zonaHoraria={zona}
            />
        </div>
    );
}

// -----------------------------------------------------------------------------
// Editor de la definición (catálogo cerrado de ADR-0008)
// -----------------------------------------------------------------------------

type Operacion = "guardando" | "publicando" | "activando" | "pausando" | "creando_borrador";

type FiltroResponsable = "cualquiera" | "con" | "sin";

type Boton = { accion: string; etiqueta: string; principal?: boolean };

function EditorRegla({
    proyectos,
    inicial,
    conNombre,
    ocupado,
    error,
    avisos,
    alModificar,
    botones,
    alEnviar,
}: {
    proyectos: Proyecto[];
    inicial?: DefinicionRegla;
    conNombre: boolean;
    ocupado: boolean;
    error: unknown;
    // Resultado de la última operación, junto a los botones que la lanzaron.
    avisos?: ReactNode;
    alModificar?: () => void;
    botones: Boton[];
    alEnviar: (accion: string, nombre: string, definicion: DefinicionRegla) => void;
}) {
    const condicion = <T extends Condicion["tipo"]>(tipo: T) =>
        inicial?.condiciones.find((c): c is Extract<Condicion, { tipo: T }> => c.tipo === tipo);
    const estadoInicial = condicion("estado_destino");
    const proyectoInicial = condicion("proyecto");
    const responsableInicial = condicion("con_responsable");

    const [nombre, setNombre] = useState("");
    const [activador, setActivador] = useState<Activador>(inicial?.activador ?? "tarea_estado_cambiado");
    const [usarEstados, setUsarEstados] = useState(estadoInicial !== undefined);
    const [estados, setEstados] = useState<EstadoTarea[]>(estadoInicial?.estados ?? []);
    const [usarProyecto, setUsarProyecto] = useState(proyectoInicial !== undefined);
    const [proyectoId, setProyectoId] = useState(proyectoInicial?.proyecto_id.toLowerCase() ?? "");
    const [responsable, setResponsable] = useState<FiltroResponsable>(
        responsableInicial === undefined ? "cualquiera" : responsableInicial.valor ? "con" : "sin",
    );
    const destinatariosIniciales = inicial?.acciones.map((a) => a.destinatarios) ?? ["propietarios_y_administradores"];
    const [avisarResponsable, setAvisarResponsable] = useState(destinatariosIniciales.includes("responsable"));
    const [avisarAdministracion, setAvisarAdministracion] = useState(
        destinatariosIniciales.includes("propietarios_y_administradores"),
    );
    const [aviso, setAviso] = useState<string | null>(null);

    // Ayuda de usabilidad: el backend valida la definición completa.
    function definicion(): DefinicionRegla | string {
        if (conNombre && nombre.trim() === "") return "Escribe un nombre para la regla.";
        const condiciones: Condicion[] = [];
        if (activador === "tarea_estado_cambiado" && usarEstados) {
            if (estados.length === 0) return "Elige al menos un estado o desmarca esa condición.";
            condiciones.push({ tipo: "estado_destino", estados: ordenEstados.filter((e) => estados.includes(e)) });
        }
        if (usarProyecto) {
            if (proyectoId === "") return "Elige un proyecto o desmarca esa condición.";
            condiciones.push({ tipo: "proyecto", proyecto_id: proyectoId });
        }
        if (responsable !== "cualquiera") {
            condiciones.push({ tipo: "con_responsable", valor: responsable === "con" });
        }
        const destinatarios: Destinatarios[] = [];
        if (avisarResponsable) destinatarios.push("responsable");
        if (avisarAdministracion) destinatarios.push("propietarios_y_administradores");
        if (destinatarios.length === 0) return "Elige al menos a quién avisar.";
        return {
            activador,
            condiciones,
            acciones: destinatarios.map((d) => ({ tipo: "notificar" as const, destinatarios: d })),
        };
    }

    function enviar(accion: string) {
        const resultado = definicion();
        if (typeof resultado === "string") {
            setAviso(resultado);
            return;
        }
        setAviso(null);
        alEnviar(accion, nombre.trim(), resultado);
    }

    return (
        <form
            noValidate
            onSubmit={(evento) => {
                evento.preventDefault();
                const principal = botones.find((b) => b.principal) ?? botones[0];
                enviar(principal.accion);
            }}
            onChange={alModificar}
            aria-busy={ocupado}
            className="rounded-xl border border-borde bg-superficie p-4 sm:p-5"
        >
            {/* Mientras se guarda, ningún campo cambia lo que se está enviando. */}
            <fieldset disabled={ocupado} className="flex min-w-0 flex-col gap-5">
                {conNombre && (
                    <div className="max-w-md">
                        <Campo etiqueta="Nombre de la regla">
                            <input
                                className={claseCampo}
                                value={nombre}
                                onChange={(e) => setNombre(e.target.value)}
                                maxLength={100}
                                required
                            />
                        </Campo>
                    </div>
                )}

                <Grupo titulo="Cuándo actúa">
                    {(Object.keys(textosActivador) as Activador[]).map((valor) => (
                        <Opcion
                            key={valor}
                            tipo="radio"
                            nombre="activador"
                            marcada={activador === valor}
                            alCambiar={() => setActivador(valor)}
                        >
                            {textosActivador[valor]}
                        </Opcion>
                    ))}
                </Grupo>

                <Grupo titulo="Condiciones (opcionales; deben cumplirse todas)">
                    {activador === "tarea_estado_cambiado" && (
                        <div className="flex flex-col gap-2">
                            <Opcion tipo="checkbox" marcada={usarEstados} alCambiar={() => setUsarEstados(!usarEstados)}>
                                Solo si la tarea pasa a uno de estos estados
                            </Opcion>
                            {usarEstados && (
                                <fieldset className="ml-6 flex flex-wrap gap-x-4 gap-y-2" aria-label="Estados de destino">
                                    {ordenEstados.map((estado) => (
                                        <Opcion
                                            key={estado}
                                            tipo="checkbox"
                                            marcada={estados.includes(estado)}
                                            alCambiar={() =>
                                                setEstados(
                                                    estados.includes(estado)
                                                        ? estados.filter((e) => e !== estado)
                                                        : [...estados, estado],
                                                )
                                            }
                                        >
                                            {estilosEstado[estado].etiqueta}
                                        </Opcion>
                                    ))}
                                </fieldset>
                            )}
                        </div>
                    )}
                    <div className="flex flex-col gap-2">
                        <Opcion tipo="checkbox" marcada={usarProyecto} alCambiar={() => setUsarProyecto(!usarProyecto)}>
                            Solo en un proyecto
                        </Opcion>
                        {usarProyecto && (
                            <div className="ml-6 max-w-sm">
                                <Campo etiqueta="Proyecto">
                                    <select className={claseCampo} value={proyectoId} onChange={(e) => setProyectoId(e.target.value)}>
                                        <option value="">Elige un proyecto</option>
                                        {proyectos.map((proyecto) => (
                                            <option key={proyecto.id} value={proyecto.id}>
                                                {proyecto.nombre}
                                                {proyecto.archivado_en ? " (archivado)" : ""}
                                            </option>
                                        ))}
                                    </select>
                                </Campo>
                            </div>
                        )}
                    </div>
                    <div className="max-w-sm">
                        <Campo etiqueta="Responsable de la tarea">
                            <select
                                className={claseCampo}
                                value={responsable}
                                onChange={(e) => setResponsable(e.target.value as FiltroResponsable)}
                            >
                                <option value="cualquiera">Con o sin responsable</option>
                                <option value="con">Solo si tiene responsable</option>
                                <option value="sin">Solo si no tiene responsable</option>
                            </select>
                        </Campo>
                    </div>
                </Grupo>

                <Grupo titulo="Qué hace: avisar a">
                    <Opcion tipo="checkbox" marcada={avisarResponsable} alCambiar={() => setAvisarResponsable(!avisarResponsable)}>
                        El responsable de la tarea
                    </Opcion>
                    <Opcion
                        tipo="checkbox"
                        marcada={avisarAdministracion}
                        alCambiar={() => setAvisarAdministracion(!avisarAdministracion)}
                    >
                        Propietarios y administradores
                    </Opcion>
                    <p className="text-xs text-texto-2">
                        Nexo redacta el aviso. Una persona recibe como máximo un aviso por evento, aunque varias reglas
                        actúen sobre él.
                    </p>
                </Grupo>

                {aviso && <Aviso tono="error">{aviso}</Aviso>}
                {error !== null && <AvisoError error={error} />}
                {avisos}

                <div className="flex flex-wrap gap-3">
                    {botones.map((boton) =>
                        boton.principal ? (
                            <button key={boton.accion} type="submit" className={claseBotonPrincipal} disabled={ocupado}>
                                {boton.etiqueta}
                            </button>
                        ) : (
                            <button
                                key={boton.accion}
                                type="button"
                                className={claseBotonSecundario}
                                disabled={ocupado}
                                onClick={() => enviar(boton.accion)}
                            >
                                {boton.etiqueta}
                            </button>
                        ),
                    )}
                </div>
            </fieldset>
        </form>
    );
}

function Grupo({ titulo, children }: { titulo: string; children: ReactNode }) {
    return (
        <fieldset className="flex flex-col gap-3">
            <legend className="mb-2 text-sm font-semibold">{titulo}</legend>
            {children}
        </fieldset>
    );
}

function Opcion({
    tipo,
    nombre,
    marcada,
    alCambiar,
    children,
}: {
    tipo: "radio" | "checkbox";
    nombre?: string;
    marcada: boolean;
    alCambiar: () => void;
    children: ReactNode;
}) {
    return (
        <label className="flex w-fit cursor-pointer items-center gap-2 text-sm">
            <input type={tipo} name={nombre} checked={marcada} onChange={alCambiar} className="size-4 accent-acento" />
            {children}
        </label>
    );
}

// -----------------------------------------------------------------------------
// Ejecuciones
// -----------------------------------------------------------------------------

const estilosEjecucion: Record<EstadoEjecucion, { etiqueta: string; Icono: LucideIcon; clases: string }> = {
    pendiente: { etiqueta: "Pendiente", Icono: Clock, clases: "bg-informacion-suave text-informacion" },
    exitosa: { etiqueta: "Exitosa", Icono: CircleCheck, clases: "bg-exito-suave text-exito" },
    fallida: { etiqueta: "Fallida", Icono: CircleAlert, clases: "bg-error-suave text-error" },
    omitida: { etiqueta: "Omitida", Icono: Ban, clases: "bg-elevada text-texto-2" },
};

function EjecucionesRegla({
    cliente,
    regla,
    miembros,
    zonaHoraria,
}: {
    cliente: SupabaseClient;
    regla: Regla;
    miembros: Miembro[];
    zonaHoraria: string;
}) {
    const cargar = useCallback(() => listarEjecuciones(cliente, regla.id), [cliente, regla.id]);
    const { carga, recargar } = useCarga(cargar);
    const nombres = new Map(miembros.map((m) => [m.usuario_id, m.nombre_visible]));
    const nombreDe = (id: string) => nombres.get(id) ?? "una persona que ya no es miembro";
    const numeroDe = (versionId: string) => regla.versiones.find((v) => v.id === versionId)?.numero;

    return (
        <section aria-labelledby="titulo-ejecuciones" className="flex flex-col gap-3">
            <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                    <h3 id="titulo-ejecuciones" className="font-semibold">
                        Ejecuciones
                    </h3>
                    <p className="text-xs text-texto-2">{avisoProcesamiento}</p>
                </div>
                <button type="button" className={claseBotonFila} onClick={recargar}>
                    <RefreshCw size={14} aria-hidden="true" />
                    Actualizar
                </button>
            </div>

            {carga.estado === "cargando" && <EsqueletoLista texto="Cargando las ejecuciones…" filas={2} />}
            {carga.estado === "error" && <AvisoError error={carga.error} />}
            {carga.estado === "listo" &&
                (carga.datos.length === 0 ? (
                    <p className="rounded-lg border border-dashed border-borde-fuerte px-4 py-6 text-sm text-texto-2">
                        Todavía no hay ejecuciones. Aparecerán aquí cuando ocurra un evento que la regla reciba mientras
                        está activa.
                    </p>
                ) : (
                    <ul className="divide-y divide-borde rounded-xl border border-borde bg-superficie" aria-label="Ejecuciones de la regla">
                        {carga.datos.map((ejecucion) => (
                            <FilaEjecucion
                                key={ejecucion.id}
                                ejecucion={ejecucion}
                                numeroVersion={numeroDe(ejecucion.version_regla_id)}
                                nombreDe={nombreDe}
                                zonaHoraria={zonaHoraria}
                            />
                        ))}
                    </ul>
                ))}
        </section>
    );
}

function FilaEjecucion({
    ejecucion,
    numeroVersion,
    nombreDe,
    zonaHoraria,
}: {
    ejecucion: Ejecucion;
    numeroVersion: number | undefined;
    nombreDe: (id: string) => string;
    zonaHoraria: string;
}) {
    const { etiqueta, Icono, clases } = estilosEjecucion[ejecucion.estado];
    const notificados = ejecucion.acciones.flatMap((a) => a.resultado.notificados ?? []);
    const omitidos = ejecucion.acciones.flatMap((a) => a.resultado.omitidos ?? []);
    const fecha = ejecucion.terminada_en ?? ejecucion.creado_en;
    // Solo se afirma si el backend registró cada acción como completada con
    // sus dos listas vacías (por ejemplo, avisar al responsable de una tarea
    // sin responsable).
    const sinDestinatarios =
        ejecucion.estado === "exitosa" &&
        ejecucion.acciones.length > 0 &&
        ejecucion.acciones.every(
            (a) =>
                a.estado === "completada" &&
                Array.isArray(a.resultado.notificados) &&
                a.resultado.notificados.length === 0 &&
                Array.isArray(a.resultado.omitidos) &&
                a.resultado.omitidos.length === 0,
        );

    return (
        <li className="flex flex-col gap-1.5 px-4 py-3">
            <div className="flex flex-wrap items-center gap-2">
                <span className={`inline-flex items-center gap-1.5 rounded-md px-2 py-0.5 text-xs font-semibold ${clases}`}>
                    <Icono size={14} aria-hidden="true" />
                    {etiqueta}
                </span>
                <span className="text-xs text-texto-2 tabular-nums">
                    {textoInstante(fecha, zonaHoraria)}
                    {numeroVersion !== undefined && ` · versión ${numeroVersion}`}
                    {ejecucion.estado === "pendiente" && ejecucion.intentos === 0
                        ? " · aún sin intentar"
                        : ` · intento ${ejecucion.intentos} de ${ejecucion.max_intentos}`}
                </span>
            </div>
            {ejecucion.mensaje_error && <p className="text-sm text-texto-2">{ejecucion.mensaje_error}</p>}
            {ejecucion.estado === "pendiente" && ejecucion.intentos > 0 && (
                <p className="text-xs text-texto-2 tabular-nums">
                    Próximo intento: {textoInstante(ejecucion.proximo_intento_en, zonaHoraria)}
                </p>
            )}
            {notificados.length > 0 && (
                <p className="text-sm">Avisó a {notificados.map(nombreDe).join(", ")}.</p>
            )}
            {sinDestinatarios && <p className="text-sm text-texto-2">No había a quién avisar.</p>}
            {omitidos.length > 0 && (
                <p className="flex items-start gap-1.5 text-xs text-texto-2">
                    <Info size={14} aria-hidden="true" className="mt-px shrink-0" />
                    No volvió a avisar a {omitidos.map((o) => nombreDe(o.destinatario_id)).join(", ")}: ya tenía un aviso
                    de este evento.
                </p>
            )}
        </li>
    );
}
