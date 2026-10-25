import {
    Ban,
    Building2,
    ChevronDown,
    CircleCheck,
    CornerDownRight,
    FileSearch,
    SearchX,
    TriangleAlert,
    UserPlus,
    Users,
    X,
    type LucideIcon,
} from "lucide-react";
import { useId, useState, type CSSProperties, type MouseEvent } from "react";
import { EtiquetaEstado, EtiquetaSenal } from "../componentes/etiqueta_estado.tsx";
import {
    estilosEstado,
    estilosSenal,
    formatearDuracion,
    formatearFecha,
    plural,
    type EstadoTarea,
    type TipoSenal,
} from "../componentes/estados.ts";
import { Pista } from "../componentes/pista.tsx";
import { actividadReciente, fechaReferencia, tareas, type EsperandoA } from "./datos_demostracion.ts";
import {
    bloqueadasPorEstado,
    esperasAgrupadas,
    estadosDelFlujo,
    filtrarPorSenales,
    haceCuanto,
    motivoSinResultados,
    recuentoPorEstado,
    recuentoSenales,
    resumenGeneral,
    resumenIntervencion,
    tareasConIntervencion,
    tiposSenal,
    vencimientosPorDia,
    type TareaConSenales,
} from "./derivados.ts";

// -----------------------------------------------------------------------------
// Datos derivados de la colección única (ver derivados.ts).
// -----------------------------------------------------------------------------

const ahora = new Date(fechaReferencia);
const intervencion = tareasConIntervencion(tareas, ahora);
const recuento = recuentoSenales(intervencion);
const resumen = resumenIntervencion(intervencion, recuento);
const general = resumenGeneral(tareas);

const idListaIntervencion = "lista-intervencion";

// Retraso de la entrada escalonada de cada sección (solo en el primer montaje).
const retraso = (milisegundos: number) => ({ "--retraso": `${milisegundos}ms` }) as CSSProperties;

const capitalizar = (texto: string) => texto.charAt(0).toUpperCase() + texto.slice(1);

const nombresFiltro: Record<TipoSenal, string> = {
    bloqueada: "Bloqueadas",
    vencida: "Vencidas",
    en_riesgo: "En riesgo",
};

const tonosSenal: Record<TipoSenal, string> = {
    bloqueada: "text-error",
    vencida: "text-atencion",
    en_riesgo: "text-atencion",
};

// -----------------------------------------------------------------------------
// Piezas comunes
// -----------------------------------------------------------------------------

function EncabezadoSeccion({ id, titulo, pregunta }: { id: string; titulo: string; pregunta: string }) {
    return (
        <div>
            <h2 id={id} className="text-xs font-semibold tracking-[0.08em] text-texto-2 uppercase">
                {titulo}
            </h2>
            <p className="mt-1 text-[15px] font-medium">{pregunta}</p>
        </div>
    );
}

export type PropiedadesFiltros = {
    filtros: TipoSenal[];
    alternarFiltro: (tipo: TipoSenal) => void;
};

// Botón de filtro por señal. Lo usan la zona de intervención y el contexto
// operativo, con el mismo estado.
function BotonSenal({
    tipo,
    activo,
    alPulsar,
}: {
    tipo: TipoSenal;
    activo: boolean;
    alPulsar: () => void;
}) {
    const { Icono } = estilosSenal[tipo];
    return (
        <button
            type="button"
            aria-pressed={activo}
            onClick={alPulsar}
            className={`transicion inline-flex min-h-10 items-center gap-2 rounded-lg border px-3 text-sm font-medium ${
                activo
                    ? "border-texto bg-texto text-fondo"
                    : "border-borde-fuerte bg-superficie text-texto hover:bg-elevada"
            }`}
        >
            <Icono size={16} aria-hidden="true" className={activo ? "" : tonosSenal[tipo]} />
            {nombresFiltro[tipo]}
            <span className="tabular-nums">{recuento[tipo]}</span>
        </button>
    );
}

function iniciales(nombre: string): string {
    return nombre
        .replace(/\./g, "")
        .split(/\s+/)
        .map((parte) => parte[0])
        .join("")
        .slice(0, 2)
        .toUpperCase();
}

function Responsable({ nombre }: { nombre: string }) {
    return (
        <span className="inline-flex items-center gap-2">
            <span
                aria-hidden="true"
                className="inline-flex size-7 shrink-0 items-center justify-center rounded-full border border-borde-fuerte bg-elevada text-[11px] font-semibold"
            >
                {iniciales(nombre)}
            </span>
            {nombre}
        </span>
    );
}

const esperas: Record<EsperandoA, { etiqueta: string; frase: string; Icono: LucideIcon }> = {
    cliente: { etiqueta: "Cliente", frase: "Espera al cliente", Icono: Building2 },
    equipo: { etiqueta: "Equipo", frase: "Espera al equipo", Icono: Users },
    informacion: { etiqueta: "Información", frase: "Espera información", Icono: FileSearch },
};

// -----------------------------------------------------------------------------
// 1. Necesita intervención
// -----------------------------------------------------------------------------

// Columnas de escritorio: tarea · señales · responsable · siguiente paso.
const columnas = "lg:grid-cols-[minmax(0,1.35fr)_minmax(0,1fr)_minmax(0,0.7fr)_minmax(0,1.15fr)]";

function NodoHilo({ elemento, primero, ultimo }: { elemento: TareaConSenales; primero: boolean; ultimo: boolean }) {
    const bloqueada = elemento.senales.some((senal) => senal.tipo === "bloqueada");
    const vencida = elemento.senales.some((senal) => senal.tipo === "vencida");
    // Hilo vertical a la izquierda, con el nodo a la altura de la primera línea
    // de la fila. Si la tarea está bloqueada, el hilo se corta alrededor del
    // nodo; el icono y el texto del bloqueo están solo en la señal de la fila.
    return (
        <span aria-hidden="true" className="absolute inset-y-0 left-0 w-10">
            {!primero && (
                <span
                    className={`absolute top-0 left-[19px] w-px bg-borde-fuerte ${bloqueada ? "h-[10px]" : "h-[23px]"}`}
                />
            )}
            {!ultimo && (
                <span
                    className={`absolute bottom-0 left-[19px] w-px bg-borde-fuerte ${bloqueada ? "top-[36px]" : "top-[23px]"}`}
                />
            )}
            <span
                className={`absolute top-[18px] left-[14px] size-[11px] rounded-full ring-4 ring-superficie ${
                    bloqueada ? "bg-error" : vencida ? "bg-atencion" : "border-2 border-atencion bg-superficie"
                }`}
            />
        </span>
    );
}

function FilaIntervencion({
    elemento,
    primero,
    ultimo,
}: {
    elemento: TareaConSenales;
    primero: boolean;
    ultimo: boolean;
}) {
    const { tarea, senales } = elemento;
    const [abierta, setAbierta] = useState(false);
    const idDetalle = useId();
    const espera = tarea.bloqueo ? esperas[tarea.bloqueo.esperandoA] : null;

    return (
        <li className="aparecer relative pr-5 pl-11 sm:pr-6">
            <NodoHilo elemento={elemento} primero={primero} ultimo={ultimo} />

            {/* Escritorio: una fila de dos líneas en cuatro columnas. Tablet y móvil:
                señales, título, proyecto y siguiente paso apilados, sin desplegar nada.
                El DOM conserva el orden de lectura (tarea, señales, responsable, paso). */}
            <div className={`grid gap-x-6 gap-y-1.5 py-3 lg:items-start ${columnas}`}>
                <div className="min-w-0">
                    <h3>
                        <button
                            type="button"
                            aria-expanded={abierta}
                            aria-controls={idDetalle}
                            onClick={() => setAbierta((valor) => !valor)}
                            className="transicion group -mx-1 inline-flex items-start gap-1.5 rounded-md px-1 text-left font-semibold hover:text-acento"
                        >
                            {tarea.titulo}
                            <ChevronDown
                                size={18}
                                aria-hidden="true"
                                className={`transicion mt-0.5 shrink-0 text-texto-2 group-hover:text-acento ${abierta ? "rotate-180" : ""}`}
                            />
                            <span className="sr-only">{abierta ? "(ocultar detalle)" : "(ver detalle)"}</span>
                        </button>
                    </h3>
                    {/* A quién se espera solo aparece si la tarea está bloqueada. */}
                    <p className="mt-0.5 text-[13px] text-texto-2">
                        {tarea.proyecto}
                        <span className="lg:hidden"> · {tarea.responsable}</span>
                        {espera && <> · {espera.frase}</>}
                    </p>
                </div>

                <div className="order-first flex min-w-0 flex-wrap gap-1.5 lg:order-none lg:pt-0.5">
                    {senales.map((senal) => (
                        <EtiquetaSenal key={senal.tipo} senal={senal} />
                    ))}
                </div>
                <div className="hidden min-w-0 text-sm lg:block">
                    <span className="sr-only">Responsable: </span>
                    <Responsable nombre={tarea.responsable} />
                </div>
                {tarea.accionSugerida && (
                    <p className="flex min-w-0 items-start gap-1.5 text-[13px] lg:pt-0.5 lg:text-sm">
                        <CornerDownRight size={16} aria-hidden="true" className="mt-px shrink-0 text-acento" />
                        <span>
                            <span className="sr-only">Siguiente paso sugerido: </span>
                            {tarea.accionSugerida}
                        </span>
                    </p>
                )}
            </div>

            {/* Despliegue: la altura se anima de 0fr a 1fr; cerrado queda inerte. */}
            <div
                id={idDetalle}
                inert={!abierta}
                className={`grid transition-[grid-template-rows] duration-200 ease-[var(--ease-nexo)] ${
                    abierta ? "grid-rows-[1fr]" : "grid-rows-[0fr]"
                }`}
            >
                <div className="overflow-hidden">
                    <dl className="mb-4 grid gap-x-6 gap-y-3 rounded-lg border border-borde bg-elevada/50 p-4 text-sm sm:grid-cols-2 lg:grid-cols-4">
                        <div>
                            <dt className="text-xs text-texto-2">Estado del flujo</dt>
                            <dd className="mt-1">
                                <EtiquetaEstado estado={tarea.estado} />
                            </dd>
                        </div>
                        <div>
                            <dt className="text-xs text-texto-2">Fecha límite</dt>
                            <dd className="mt-1 tabular-nums">
                                {tarea.fechaLimite ? (
                                    <time dateTime={tarea.fechaLimite}>{formatearFecha(tarea.fechaLimite)}</time>
                                ) : (
                                    "Sin fecha límite"
                                )}
                            </dd>
                        </div>
                        {tarea.bloqueo && (
                            <>
                                <div>
                                    <dt className="text-xs text-texto-2">Bloqueada desde</dt>
                                    <dd className="mt-1 tabular-nums">
                                        <time dateTime={tarea.bloqueo.desde}>{formatearFecha(tarea.bloqueo.desde)}</time>
                                    </dd>
                                </div>
                                <div>
                                    <dt className="text-xs text-texto-2">Motivo del bloqueo</dt>
                                    <dd className="mt-1">{tarea.bloqueo.motivo}</dd>
                                </div>
                            </>
                        )}
                    </dl>
                </div>
            </div>
        </li>
    );
}

export function NecesitaIntervencion({ filtros, alternarFiltro, quitarFiltros }: PropiedadesFiltros & { quitarFiltros: () => void }) {
    const visibles = filtrarPorSenales(intervencion, filtros);

    // Anuncio para lectores de pantalla: se escribe solo al usar los filtros,
    // con el resultado de la acción, y no al cargar la página.
    const [anuncio, setAnuncio] = useState("");
    const anunciar = (nuevos: TipoSenal[]) => {
        const total = intervencion.length;
        setAnuncio(
            nuevos.length > 0
                ? `Mostrando ${filtrarPorSenales(intervencion, nuevos).length} de ${plural(total, "tarea", "tareas")}.`
                : `Filtros quitados. Mostrando ${total === 1 ? "la única tarea" : `las ${total} tareas`}.`,
        );
    };
    const alternarYAnunciar = (tipo: TipoSenal) => {
        alternarFiltro(tipo);
        anunciar(filtros.includes(tipo) ? filtros.filter((filtro) => filtro !== tipo) : [...filtros, tipo]);
    };

    // Al quitar los filtros desaparece el botón pulsado: el foco pasa a la lista,
    // que está justo debajo, en vez de perderse. Con teclado (detail === 0) el
    // foco se marca visible; el navegador no lo hace solo si el botón ya no existe.
    const quitarYEnfocar = (evento: MouseEvent<HTMLButtonElement>) => {
        quitarFiltros();
        anunciar([]);
        document
            .getElementById(idListaIntervencion)
            ?.focus({ preventScroll: true, focusVisible: evento.detail === 0 });
    };

    return (
        <section
            aria-labelledby="titulo-intervencion"
            style={retraso(30)}
            className="entrada overflow-hidden rounded-2xl border border-borde-fuerte bg-superficie"
        >
            {/* En escritorio el espaciado es algo menor y el detalle va junto al titular,
                para que la franja de cifras quepa en la primera pantalla (1440 × 900). */}
            <div className="border-b border-borde bg-elevada px-5 py-5 sm:px-6 lg:py-4">
                <div className="lg:flex lg:flex-wrap lg:items-center lg:gap-x-4">
                    <h2
                        id="titulo-intervencion"
                        className="flex items-center gap-2.5 text-xl leading-snug font-semibold tracking-tight sm:text-2xl"
                    >
                        <TriangleAlert size={24} aria-hidden="true" className="shrink-0 text-atencion" />
                        {resumen.titular}
                    </h2>
                    {resumen.detalle && <p className="mt-1 text-sm text-texto-2 lg:mt-0">{resumen.detalle}</p>}
                </div>

                <div className="mt-5 flex flex-wrap items-center gap-2 lg:mt-4">
                    <fieldset aria-describedby="ayuda-filtros" className="flex flex-wrap gap-2">
                        <legend className="sr-only">Filtrar por señal</legend>
                        {tiposSenal.map((tipo) => (
                            <BotonSenal
                                key={tipo}
                                tipo={tipo}
                                activo={filtros.includes(tipo)}
                                alPulsar={() => alternarYAnunciar(tipo)}
                            />
                        ))}
                    </fieldset>
                    {/* Visible para todos: los filtros se combinan por intersección. */}
                    <p id="ayuda-filtros" className="text-[13px] text-texto-2">
                        Si eliges varios, deben cumplirse todos.
                    </p>
                    {filtros.length > 0 && (
                        <button
                            type="button"
                            onClick={quitarYEnfocar}
                            className="transicion inline-flex min-h-10 items-center gap-1.5 rounded-lg px-3 text-sm font-medium text-texto-2 hover:bg-superficie hover:text-texto"
                        >
                            <X size={16} aria-hidden="true" />
                            Quitar filtros
                        </button>
                    )}
                    {/* Estado visible; el anuncio va aparte para no repetirlo ni leer el orden como resultado. */}
                    <p className="text-[13px] text-texto-2 tabular-nums sm:ml-auto">
                        {filtros.length > 0
                            ? `Mostrando ${visibles.length} de ${plural(intervencion.length, "tarea", "tareas")}`
                            : "De la más grave a la menos grave"}
                    </p>
                </div>
                <p aria-live="polite" className="sr-only">
                    {anuncio}
                </p>
            </div>

            <div id={idListaIntervencion} tabIndex={-1} aria-label="Tareas que necesitan intervención" className="outline-none focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-acento focus-visible:outline-solid">
                {visibles.length > 0 ? (
                    <>
                        <div
                            aria-hidden="true"
                            className={`hidden gap-6 border-b border-borde py-2 pr-6 pl-11 text-xs font-medium text-texto-2 lg:grid ${columnas}`}
                        >
                            <span>Tarea</span>
                            <span>Señales</span>
                            <span>Responsable</span>
                            <span>Siguiente paso sugerido</span>
                        </div>
                        <ol>
                            {visibles.map((elemento, indice) => (
                                <FilaIntervencion
                                    key={elemento.tarea.id}
                                    elemento={elemento}
                                    primero={indice === 0}
                                    ultimo={indice === visibles.length - 1}
                                />
                            ))}
                        </ol>
                    </>
                ) : (
                    <div className="aparecer flex flex-col items-start gap-3 px-5 py-10 sm:px-6">
                        <SearchX size={24} aria-hidden="true" className="text-texto-2" />
                        <p className="font-semibold">Ninguna tarea cumple estos filtros.</p>
                        <p className="max-w-xl text-sm text-texto-2">{motivoSinResultados(filtros)}</p>
                        <button
                            type="button"
                            onClick={quitarYEnfocar}
                            className="transicion mt-1 inline-flex min-h-10 items-center gap-1.5 rounded-lg bg-acento px-4 text-sm font-semibold text-sobre-acento hover:opacity-90"
                        >
                            <X size={16} aria-hidden="true" />
                            Quitar filtros
                        </button>
                    </div>
                )}
            </div>

            {/* Única marca contextual de lo que todavía no existe en el backend (también cubre «Esperando a»). */}
            <p className="border-t border-borde px-5 py-3 text-xs text-texto-2 sm:px-6">
                Ilustrativo: los bloqueos, a quién se espera (aquí y en «Esperando a») y los siguientes pasos son
                ejemplos sin backend todavía. Los pasos son sugerencias en texto, no acciones.
            </p>
        </section>
    );
}

// -----------------------------------------------------------------------------
// 2. Contexto operativo
// -----------------------------------------------------------------------------

// Solo cifras: los filtros por señal viven únicamente en "Necesita intervención".
export function ContextoOperativo() {
    const cifras = [
        { valor: general.abiertas, texto: "tareas abiertas", contexto: `de ${general.total}` },
        { valor: general.completadas, texto: "completadas", contexto: null },
        {
            valor: general.proyectosConTrabajoAbierto,
            texto: "proyectos con trabajo abierto",
            contexto: `de ${general.proyectos}`,
        },
    ];

    return (
        <section aria-labelledby="titulo-contexto" style={retraso(60)} className="entrada">
            <h2 id="titulo-contexto" className="sr-only">
                Contexto operativo
            </h2>
            <dl className="flex flex-wrap gap-x-8 gap-y-3 px-1">
                {cifras.map(({ valor, texto, contexto }) => (
                    <div key={texto} className="flex flex-row-reverse items-baseline justify-end gap-2">
                        <dt className="text-sm text-texto-2">
                            {texto}
                            {contexto && <span className="tabular-nums"> {contexto}</span>}
                        </dt>
                        <dd className="text-2xl font-semibold tracking-tight tabular-nums">{valor}</dd>
                    </div>
                ))}
            </dl>
        </section>
    );
}

// -----------------------------------------------------------------------------
// 3. Próximos siete días
// -----------------------------------------------------------------------------

const dias = vencimientosPorDia(tareas, ahora);
const formatoDiaCorto = new Intl.DateTimeFormat("es", { weekday: "short", day: "numeric" });
const formatoDiaLargo = new Intl.DateTimeFormat("es", { weekday: "long", day: "numeric", month: "long" });

function DetalleDia({ tareasDia }: { tareasDia: TareaConSenales[] }) {
    return (
        <ul className="mt-1.5 space-y-1.5">
            {tareasDia.map(({ tarea, senales }) => (
                <li key={tarea.id}>
                    <span className="font-medium">{tarea.titulo}</span>
                    <span className="text-texto-2"> · {tarea.proyecto}</span>
                    {senales.length > 0 && (
                        <span className="mt-1 flex flex-wrap gap-1">
                            {senales.map((senal) => (
                                <EtiquetaSenal key={senal.tipo} senal={senal} />
                            ))}
                        </span>
                    )}
                </li>
            ))}
        </ul>
    );
}

const tieneRiesgo = (tareasDia: TareaConSenales[]) =>
    tareasDia.some(({ senales }) => senales.some((senal) => senal.tipo === "en_riesgo"));

export function ProximosVencimientos() {
    const total = dias.reduce((suma, { tareas: delDia }) => suma + delDia.length, 0);
    return (
        <section aria-labelledby="titulo-vencimientos" style={retraso(90)} className="entrada border-t border-borde pt-6">
            <EncabezadoSeccion
                id="titulo-vencimientos"
                titulo="Próximos siete días"
                pregunta={`${plural(total, "tarea vence", "tareas vencen")} antes del ${formatoDiaLargo.format(
                    new Date(dias[dias.length - 1].fecha.getTime() + 24 * 60 * 60 * 1000),
                )}`}
            />

            {/* Escritorio y tablet: línea temporal horizontal con nodos. */}
            <ol className="relative mt-6 hidden grid-cols-7 md:grid">
                <span aria-hidden="true" className="absolute top-[42px] right-[7%] left-[7%] h-px bg-borde-fuerte" />
                {dias.map(({ fecha, tareas: delDia }, indice) => {
                    const etiqueta = formatoDiaCorto.format(fecha);
                    const esHoy = indice === 0;
                    const riesgo = tieneRiesgo(delDia);
                    return (
                        <li key={fecha.toISOString()} className="relative flex flex-col items-center gap-2 text-center">
                            <span className={`text-xs tabular-nums ${esHoy ? "font-semibold text-texto" : "text-texto-2"}`}>
                                {esHoy ? "Hoy" : etiqueta}
                            </span>
                            {delDia.length > 0 ? (
                                <Pista
                                    alinear={indice < 2 ? "inicio" : indice > 4 ? "fin" : "centro"}
                                    contenido={
                                        <>
                                            <span className="font-semibold">
                                                {capitalizar(formatoDiaLargo.format(fecha))}:{" "}
                                                {plural(delDia.length, "vencimiento", "vencimientos")}
                                            </span>
                                            <DetalleDia tareasDia={delDia} />
                                        </>
                                    }
                                >
                                    {(atributos) => (
                                        <button
                                            type="button"
                                            {...atributos}
                                            className={`transicion relative z-10 inline-flex size-9 items-center justify-center rounded-full border-2 text-sm font-semibold tabular-nums hover:scale-105 ${
                                                riesgo
                                                    ? "border-atencion bg-atencion-suave text-atencion"
                                                    : "border-acento bg-superficie text-texto"
                                            }`}
                                        >
                                            {delDia.length}
                                            <span className="sr-only">
                                                {" "}
                                                {plural(delDia.length, "vencimiento", "vencimientos")} el {formatoDiaLargo.format(fecha)}
                                            </span>
                                        </button>
                                    )}
                                </Pista>
                            ) : (
                                <span className="relative z-10 inline-flex size-9 items-center justify-center">
                                    <span aria-hidden="true" className="size-2.5 rounded-full border border-borde-fuerte bg-fondo" />
                                    <span className="sr-only">Sin vencimientos el {formatoDiaLargo.format(fecha)}</span>
                                </span>
                            )}
                            <span className={`text-xs ${riesgo ? "font-medium text-atencion" : "text-texto-2"}`}>
                                {delDia.length === 0 ? "—" : riesgo ? "En riesgo" : plural(delDia.length, "tarea", "tareas")}
                            </span>
                        </li>
                    );
                })}
            </ol>

            {/* Móvil: lista vertical sobre el hilo, con las tareas a la vista. */}
            <ol className="mt-5 md:hidden">
                {dias.map(({ fecha, tareas: delDia }, indice) => (
                    <li key={fecha.toISOString()} className="relative pb-4 pl-8 last:pb-0">
                        {indice < dias.length - 1 && (
                            <span aria-hidden="true" className="absolute top-5 bottom-0 left-[9px] w-px bg-borde-fuerte" />
                        )}
                        <span
                            aria-hidden="true"
                            className={`absolute top-1.5 left-1 size-[11px] rounded-full ${
                                delDia.length === 0
                                    ? "border border-borde-fuerte bg-fondo"
                                    : tieneRiesgo(delDia)
                                      ? "border-2 border-atencion bg-atencion-suave"
                                      : "border-2 border-acento bg-fondo"
                            }`}
                        />
                        <p className="text-sm">
                            <span className="font-semibold">
                                {indice === 0 ? `Hoy, ${formatoDiaLargo.format(fecha)}` : capitalizar(formatoDiaLargo.format(fecha))}
                            </span>
                            <span className="text-texto-2 tabular-nums">
                                {" "}
                                · {delDia.length === 0 ? "sin vencimientos" : plural(delDia.length, "tarea", "tareas")}
                            </span>
                        </p>
                        {delDia.length > 0 && (
                            <div className="text-[13px]">
                                <DetalleDia tareasDia={delDia} />
                            </div>
                        )}
                    </li>
                ))}
            </ol>
        </section>
    );
}

// -----------------------------------------------------------------------------
// 4. Esperando a
// -----------------------------------------------------------------------------

const grupos = esperasAgrupadas(intervencion);

export function EsperandoA() {
    return (
        <section aria-labelledby="titulo-esperas" style={retraso(120)} className="entrada border-t border-borde pt-6">
            <EncabezadoSeccion id="titulo-esperas" titulo="Esperando a" pregunta="¿De quién depende desbloquear?" />
            <ul className="mt-4 divide-y divide-borde">
                {grupos.map(({ motivo, tareas: delGrupo, esperaMasLarga }) => {
                    const { etiqueta, Icono } = esperas[motivo];
                    return (
                        <li key={motivo} className="flex items-start gap-3 py-3">
                            <Icono size={20} aria-hidden="true" className="mt-0.5 shrink-0 text-texto-2" />
                            <div className="min-w-0 flex-1">
                                <p className="flex flex-wrap items-baseline justify-between gap-x-3">
                                    <span className="font-medium">{etiqueta}</span>
                                    <span className="text-sm text-texto-2 tabular-nums">
                                        {delGrupo.length === 0
                                            ? "Nada pendiente"
                                            : `${plural(delGrupo.length, "tarea", "tareas")} · la más antigua, ${formatearDuracion(esperaMasLarga, true)}`}
                                    </span>
                                </p>
                                {delGrupo.length > 0 && (
                                    <p className="mt-0.5 truncate text-[13px] text-texto-2">
                                        {delGrupo.map((tarea) => tarea.titulo).join(" · ")}
                                    </p>
                                )}
                            </div>
                        </li>
                    );
                })}
            </ul>
        </section>
    );
}

// -----------------------------------------------------------------------------
// 5. Flujo de tareas: los cuatro estados reales, con cortes donde hay bloqueos.
// -----------------------------------------------------------------------------

const porEstado = recuentoPorEstado(tareas);
const bloqueadas = bloqueadasPorEstado(intervencion);

// Tramo entre un estado y el siguiente: cortado si hay tareas bloqueadas en el
// estado de origen; con pulso si hay trabajo que puede avanzar sin bloqueos.
function Tramo({ estado, vertical }: { estado: EstadoTarea; vertical: boolean }) {
    const cortado = bloqueadas[estado].length > 0;
    const activo = !cortado && porEstado[estado] > 0;
    const trazo = cortado ? "stroke-borde-fuerte" : "stroke-acento";
    if (vertical) {
        return (
            <svg aria-hidden="true" viewBox="0 0 2 40" preserveAspectRatio="none" className="ml-[23px] h-8 w-0.5 overflow-visible">
                {cortado ? (
                    <>
                        <line x1="1" y1="0" x2="1" y2="13" className={trazo} strokeWidth="1.5" />
                        <line x1="1" y1="27" x2="1" y2="40" className={trazo} strokeWidth="1.5" />
                    </>
                ) : (
                    <line x1="1" y1="0" x2="1" y2="40" className={`${trazo} ${activo ? "linea-activa" : ""}`} strokeWidth="1.5" />
                )}
            </svg>
        );
    }
    return (
        <span aria-hidden="true" className="relative mx-2 mt-6 flex h-px min-w-6 flex-1 items-center">
            {cortado ? (
                <>
                    <span className="h-px flex-1 bg-borde-fuerte" />
                    <span className="mx-1.5 inline-flex size-5 items-center justify-center rounded-full bg-error-suave text-error">
                        <Ban size={12} strokeWidth={2.5} />
                    </span>
                    <span className="h-px flex-1 bg-borde-fuerte" />
                </>
            ) : (
                <svg viewBox="0 0 100 2" preserveAspectRatio="none" className="h-0.5 w-full overflow-visible">
                    <line x1="0" y1="1" x2="100" y2="1" className={`${trazo} ${activo ? "linea-activa" : ""}`} strokeWidth="1.5" vectorEffect="non-scaling-stroke" />
                </svg>
            )}
        </span>
    );
}

export function FlujoTareas() {
    return (
        <section aria-labelledby="titulo-flujo" style={retraso(150)} className="entrada border-t border-borde pt-6">
            <EncabezadoSeccion
                id="titulo-flujo"
                titulo="Flujo de tareas"
                pregunta={`¿Dónde se detiene el trabajo? ${plural(general.total, "tarea", "tareas")} por estado`}
            />

            <ol className="mt-6 flex flex-col md:flex-row md:items-start">
                {estadosDelFlujo.map((estado, indice) => {
                    const { etiqueta, Icono } = estilosEstado[estado];
                    const cantidad = porEstado[estado];
                    const bloqueadasEstado = bloqueadas[estado];
                    const esCompletada = estado === "completada";
                    const ultimo = indice === estadosDelFlujo.length - 1;
                    return (
                        <li key={estado} className={`flex flex-col md:flex-row ${ultimo ? "" : "md:flex-1"}`}>
                            <div className="flex items-center gap-3 md:flex-col md:items-start">
                                <Pista
                                    alinear={indice === 0 ? "inicio" : ultimo ? "fin" : "centro"}
                                    contenido={
                                        <>
                                            <span className="font-semibold">
                                                {etiqueta}: {plural(cantidad, "tarea", "tareas")}
                                            </span>
                                            {bloqueadasEstado.length > 0 ? (
                                                <span className="mt-1 block">
                                                    {plural(bloqueadasEstado.length, "bloqueada", "bloqueadas")}:{" "}
                                                    {bloqueadasEstado.map((tarea) => `«${tarea.titulo}»`).join(", ")}
                                                </span>
                                            ) : (
                                                <span className="mt-1 block text-texto-2">Ninguna bloqueada.</span>
                                            )}
                                        </>
                                    }
                                >
                                    {(atributos) => (
                                        <button
                                            type="button"
                                            {...atributos}
                                            className={`transicion inline-flex size-12 shrink-0 items-center justify-center rounded-full border-2 hover:scale-105 ${
                                                esCompletada
                                                    ? "border-acento bg-acento text-sobre-acento"
                                                    : "border-borde-fuerte bg-superficie text-texto"
                                            }`}
                                        >
                                            <Icono size={20} aria-hidden="true" />
                                            <span className="sr-only">
                                                {etiqueta}: {plural(cantidad, "tarea", "tareas")}
                                            </span>
                                        </button>
                                    )}
                                </Pista>
                                <div className="md:mt-1">
                                    <p className="flex items-baseline gap-2">
                                        <span className="text-2xl font-semibold tracking-tight tabular-nums">{cantidad}</span>
                                        <span className="text-sm text-texto-2">{etiqueta}</span>
                                    </p>
                                    {bloqueadasEstado.length > 0 && (
                                        <p className="mt-1 inline-flex items-center gap-1 text-xs font-semibold text-error">
                                            <Ban size={14} aria-hidden="true" />
                                            {plural(bloqueadasEstado.length, "bloqueada", "bloqueadas")}
                                        </p>
                                    )}
                                </div>
                            </div>
                            {!ultimo && (
                                <>
                                    <span className="md:hidden">
                                        <Tramo estado={estado} vertical />
                                    </span>
                                    <span className="hidden flex-1 md:flex">
                                        <Tramo estado={estado} vertical={false} />
                                    </span>
                                </>
                            )}
                        </li>
                    );
                })}
            </ol>
            <p className="mt-5 text-xs text-texto-2">
                Un corte en el hilo marca un estado con tareas bloqueadas, que no pueden pasar al siguiente.
            </p>
        </section>
    );
}

// -----------------------------------------------------------------------------
// 6. Actividad reciente
// -----------------------------------------------------------------------------

const iconosActividad: Record<(typeof actividadReciente)[number]["tipo"], { Icono: LucideIcon; tono: string }> = {
    completada: { Icono: CircleCheck, tono: "text-exito" },
    bloqueo: { Icono: Ban, tono: "text-error" },
    asignacion: { Icono: UserPlus, tono: "text-informacion" },
};

export function ActividadReciente() {
    return (
        <section aria-labelledby="titulo-actividad" style={retraso(180)} className="entrada border-t border-borde pt-6">
            <EncabezadoSeccion id="titulo-actividad" titulo="Actividad reciente" pregunta="¿Qué ha cambiado?" />
            <ol className="mt-4">
                {actividadReciente.map(({ id, tipo, texto, fecha }, indice) => {
                    const { Icono, tono } = iconosActividad[tipo];
                    const momento = haceCuanto(fecha, ahora);
                    return (
                        <li key={id} className="relative flex gap-3 pb-4 last:pb-0">
                            {indice < actividadReciente.length - 1 && (
                                <span aria-hidden="true" className="absolute top-8 bottom-0 left-[13px] w-px bg-borde-fuerte" />
                            )}
                            <span className="inline-flex size-7 shrink-0 items-center justify-center rounded-full border border-borde-fuerte bg-superficie">
                                <Icono size={14} aria-hidden="true" className={tono} />
                            </span>
                            <div className="min-w-0 pt-0.5">
                                <p className="text-sm leading-snug">{texto}</p>
                                <p className="mt-0.5 text-xs text-texto-2 tabular-nums">
                                    <time dateTime={fecha} title={formatearFecha(fecha)}>
                                        {capitalizar(momento)}
                                    </time>
                                </p>
                            </div>
                        </li>
                    );
                })}
            </ol>
        </section>
    );
}
