import {
    ArrowLeft,
    Building2,
    FolderKanban,
    Info,
    LayoutDashboard,
    ListChecks,
    Menu,
    Users,
    Workflow,
    X,
    Zap,
    type LucideIcon,
} from "lucide-react";
import { useCallback, useRef, useState, type CSSProperties } from "react";
import { SimboloNexo } from "../componentes/simbolo_nexo.tsx";
import { SelectorTema } from "../componentes/selector_tema.tsx";
import { enlacePortada } from "../ruta/ruta.ts";
import type { PreferenciaTema } from "../tema/tema.ts";
import { formatearFecha, type TipoSenal } from "../componentes/estados.ts";
import { fechaReferencia, organizacionDemostracion } from "./datos_demostracion.ts";
import {
    ActividadReciente,
    ContextoOperativo,
    EsperandoA,
    FlujoTareas,
    NecesitaIntervencion,
    ProximosVencimientos,
} from "./secciones_panel.tsx";

const formatoCorto = new Intl.DateTimeFormat("es", {
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
});

// Solo "Panel" existe en esta entrega. El resto se muestra como próximo y no
// navega: no se simulan páginas que todavía no están construidas.
const secciones: { etiqueta: string; Icono: LucideIcon; disponible: boolean }[] = [
    { etiqueta: "Panel", Icono: LayoutDashboard, disponible: true },
    { etiqueta: "Proyectos", Icono: FolderKanban, disponible: false },
    { etiqueta: "Tareas", Icono: ListChecks, disponible: false },
    { etiqueta: "Flujos", Icono: Workflow, disponible: false },
    { etiqueta: "Automatizaciones", Icono: Zap, disponible: false },
    { etiqueta: "Miembros", Icono: Users, disponible: false },
];

function Navegacion() {
    return (
        <nav aria-label="Secciones" className="flex flex-1 flex-col">
            <div className="flex items-center gap-2.5 px-2 py-1.5">
                <span className="inline-flex size-8 items-center justify-center rounded-lg border border-borde bg-elevada text-texto-2">
                    <Building2 size={16} aria-hidden="true" />
                </span>
                <span className="min-w-0">
                    <span className="block truncate text-sm font-medium">{organizacionDemostracion}</span>
                    <span className="block text-xs text-texto-2">Organización de ejemplo</span>
                </span>
            </div>

            <ul className="mt-5 flex flex-col gap-0.5">
                {secciones.map(({ etiqueta, Icono, disponible }) => (
                    <li key={etiqueta}>
                        {disponible ? (
                            <a
                                href="#/demostracion"
                                aria-current="page"
                                className="transicion flex items-center gap-3 rounded-lg bg-acento-suave px-2.5 py-2 text-sm font-medium text-texto"
                            >
                                <Icono size={18} aria-hidden="true" className="text-acento" />
                                {etiqueta}
                            </a>
                        ) : (
                            <span
                                aria-disabled="true"
                                className="flex cursor-not-allowed items-center gap-3 rounded-lg px-2.5 py-2 text-sm text-texto-2"
                            >
                                <Icono size={18} aria-hidden="true" className="shrink-0" />
                                <span className="min-w-0 truncate">{etiqueta}</span>
                                <span className="ml-auto shrink-0 rounded px-1.5 py-0.5 text-[11px] text-texto-2 ring-1 ring-borde">
                                    Pronto
                                </span>
                            </span>
                        )}
                    </li>
                ))}
            </ul>

            <a
                href={enlacePortada}
                className="transicion mt-auto flex items-center gap-2 rounded-lg px-2.5 py-2 text-sm text-texto-2 hover:bg-elevada hover:text-texto"
            >
                <ArrowLeft size={16} aria-hidden="true" />
                Volver a la portada
            </a>
        </nav>
    );
}

type Propiedades = {
    preferencia: PreferenciaTema;
    alElegirTema: (preferencia: PreferenciaTema) => void;
};

export function PanelDemostracion({ preferencia, alElegirTema }: Propiedades) {
    // Navegación en móvil: <dialog> nativo (Escape, foco retenido y fondo inerte).
    const menuMovil = useRef<HTMLDialogElement>(null);
    const abrirMenu = () => menuMovil.current?.showModal();
    const cerrarMenu = () => menuMovil.current?.close();

    // Filtros por señal de la zona de intervención, su única ubicación.
    // Se combinan por intersección (ver filtrarPorSenales).
    const [filtros, setFiltros] = useState<TipoSenal[]>([]);
    const alternarFiltro = useCallback((tipo: TipoSenal) => {
        setFiltros((actuales) =>
            actuales.includes(tipo) ? actuales.filter((filtro) => filtro !== tipo) : [...actuales, tipo],
        );
    }, []);
    const quitarFiltros = useCallback(() => setFiltros([]), []);

    return (
        <div className="min-h-dvh lg:grid lg:grid-cols-[248px_minmax(0,1fr)]">
            <aside className="sticky top-0 hidden h-dvh flex-col border-r border-borde bg-superficie px-3 py-4 lg:flex">
                <a href={enlacePortada} className="mb-6 flex items-center gap-2.5 rounded-md px-2" aria-label="Nexo, portada">
                    <SimboloNexo tamano={26} />
                    <span className="font-semibold tracking-tight">Nexo</span>
                </a>
                <Navegacion />
            </aside>

            <dialog
                ref={menuMovil}
                aria-label="Navegación"
                className="m-0 h-dvh max-h-none w-full max-w-none bg-transparent p-0 text-texto backdrop:bg-fondo/70"
            >
                <div className="flex h-full">
                    <div className="flex h-full w-72 max-w-[85vw] flex-col border-r border-borde bg-superficie px-3 py-4">
                        <div className="mb-6 flex items-center justify-between px-2">
                            <span className="flex items-center gap-2.5">
                                <SimboloNexo tamano={26} />
                                <span className="font-semibold tracking-tight">Nexo</span>
                            </span>
                            <button
                                type="button"
                                onClick={cerrarMenu}
                                className="transicion inline-flex size-9 items-center justify-center rounded-lg text-texto-2 hover:bg-elevada hover:text-texto"
                            >
                                <X size={20} aria-hidden="true" />
                                <span className="sr-only">Cerrar navegación</span>
                            </button>
                        </div>
                        <Navegacion />
                    </div>
                    {/* Zona exterior: un clic cierra el menú. Con teclado se usa Escape o el botón de cerrar. */}
                    <button
                        type="button"
                        tabIndex={-1}
                        aria-hidden="true"
                        onClick={cerrarMenu}
                        className="h-full flex-1 cursor-default"
                    />
                </div>
            </dialog>

            <div className="min-w-0">
                <header className="sticky top-0 z-10 border-b border-borde bg-fondo/85 backdrop-blur-sm">
                    <div className="flex items-center gap-3 px-4 py-3 sm:px-6">
                        <button
                            type="button"
                            onClick={abrirMenu}
                            className="transicion inline-flex size-9 items-center justify-center rounded-lg text-texto-2 hover:bg-elevada hover:text-texto lg:hidden"
                        >
                            <Menu size={20} aria-hidden="true" />
                            <span className="sr-only">Abrir navegación</span>
                        </button>
                        <div className="min-w-0 flex-1">
                            <h1 className="truncate text-lg font-semibold tracking-tight">Panel</h1>
                            <p className="truncate text-xs text-texto-2">
                                Hoy en la demostración:{" "}
                                <time dateTime={fechaReferencia} className="tabular-nums">
                                    {/* Formato corto en pantallas estrechas, para que no se corte. */}
                                    <span className="sm:hidden">{formatoCorto.format(new Date(fechaReferencia))}</span>
                                    <span className="hidden sm:inline">{formatearFecha(fechaReferencia)}</span>
                                </time>
                            </p>
                        </div>
                        <span className="hidden items-center gap-1.5 rounded-md bg-informacion-suave px-2 py-1 text-xs font-medium text-informacion sm:inline-flex">
                            <Info size={14} aria-hidden="true" />
                            Datos de demostración
                        </span>
                        <SelectorTema preferencia={preferencia} alElegir={alElegirTema} />
                    </div>
                </header>

                {/* lg: algo menos de aire arriba para que la franja de cifras quepa en 1440 × 900. */}
                <main id="contenido" tabIndex={-1} className="mx-auto outline-none flex max-w-[1240px] flex-col gap-8 px-4 py-6 sm:px-6 sm:py-8 lg:gap-6 lg:pt-6">
                    <p
                        role="note"
                        style={{ "--retraso": "0ms" } as CSSProperties}
                        className="entrada flex items-start gap-2.5 rounded-lg border border-informacion/30 bg-informacion-suave px-4 py-3 text-sm"
                    >
                        <Info size={16} aria-hidden="true" className="mt-0.5 shrink-0 text-informacion" />
                        {/* Texto principal, no secundario: el gris sobre el fondo informativo
                            quedaba en 4,46:1 en modo claro (mínimo 4,5:1). */}
                        <span>
                            <span className="font-semibold">Vista previa con datos ficticios.</span>{" "}
                            Todavía no está conectada al backend: las cifras, nombres, fechas y tareas son ejemplos y
                            nada de lo que hagas aquí se guarda.
                        </span>
                    </p>

                    {/* Primero lo que está detenido o corre riesgo; después, el contexto. */}
                    <div className="flex flex-col gap-5 lg:gap-4">
                        <NecesitaIntervencion
                            filtros={filtros}
                            alternarFiltro={alternarFiltro}
                            quitarFiltros={quitarFiltros}
                        />
                        <ContextoOperativo />
                    </div>

                    {/* Secciones secundarias sobre el fondo, sin tarjeta: dos columnas asimétricas en escritorio. */}
                    {/* El orden del DOM es el de lectura (vencimientos, esperas, flujo, actividad). En
                        escritorio, esperas y flujo ocupan dos filas para que ninguna columna deje huecos. */}
                    <div className="grid gap-x-12 gap-y-8 lg:grid-cols-[minmax(0,1.65fr)_minmax(0,1fr)] lg:grid-rows-[auto_auto_auto]">
                        <div className="lg:col-start-1 lg:row-start-1">
                            <ProximosVencimientos />
                        </div>
                        <div className="lg:col-start-2 lg:row-span-2 lg:row-start-1">
                            <EsperandoA />
                        </div>
                        <div className="lg:col-start-1 lg:row-span-2 lg:row-start-2">
                            <FlujoTareas />
                        </div>
                        <div className="lg:col-start-2 lg:row-start-3">
                            <ActividadReciente />
                        </div>
                    </div>
                </main>
            </div>
        </div>
    );
}
