import { ArrowRight, CalendarClock, History, Inbox, ListTree } from "lucide-react";
import { MarcaNexo } from "../componentes/simbolo_nexo.tsx";
import { SelectorTema } from "../componentes/selector_tema.tsx";
import { enlaceDemostracion, enlaceEspacio } from "../ruta/ruta.ts";
import type { PreferenciaTema } from "../tema/tema.ts";
import { DiagramaFlujo } from "./diagrama_flujo.tsx";

type Propiedades = {
    preferencia: PreferenciaTema;
    alElegirTema: (preferencia: PreferenciaTema) => void;
};

const pasos = [
    {
        Icono: Inbox,
        titulo: "Recibe la solicitud",
        texto: "Cada petición de un cliente entra en un solo lugar, con lo necesario para empezar.",
    },
    {
        Icono: ListTree,
        titulo: "Conviértela en trabajo",
        texto: "Un proyecto con sus tareas, cada una con responsable, estado y fecha límite.",
    },
    {
        Icono: CalendarClock,
        titulo: "Detecta lo que se detiene",
        texto: "Tareas vencidas, bloqueos y esperas largas salen a la vista antes de que sea tarde.",
    },
    {
        Icono: History,
        titulo: "Registra lo que pasó",
        texto: "Cada cambio queda en un historial, para saber quién hizo qué y cuándo.",
    },
];

export function Portada({ preferencia, alElegirTema }: Propiedades) {
    return (
        <div className="min-h-dvh">
            <header className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-5 sm:px-6">
                <a href="#/" className="rounded-md" aria-label="Nexo, inicio">
                    <MarcaNexo />
                </a>
                <div className="flex items-center gap-3">
                    <SelectorTema preferencia={preferencia} alElegir={alElegirTema} />
                    <a
                        href={enlaceDemostracion}
                        className="transicion hidden rounded-lg px-3 py-2 text-sm font-medium text-texto-2 hover:bg-elevada hover:text-texto sm:inline-flex"
                    >
                        Demostración
                    </a>
                    <a
                        href={enlaceEspacio}
                        className="transicion inline-flex rounded-lg border border-borde-fuerte px-3 py-2 text-sm font-medium text-texto hover:bg-elevada"
                    >
                        Entrar
                    </a>
                </div>
            </header>

            <main id="contenido" tabIndex={-1} className="outline-none">
                <section className="mx-auto grid max-w-6xl items-center gap-12 px-4 pt-10 pb-20 sm:px-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.15fr)] lg:gap-16 lg:pt-20 lg:pb-28">
                    <div>
                        <p className="inline-flex items-center gap-2 rounded-full border border-borde px-3 py-1 text-xs font-medium text-texto-2">
                            <span className="size-1.5 rounded-full bg-acento" aria-hidden="true" />
                            Vista previa · Nexo está en desarrollo
                        </p>
                        <h1 className="mt-6 text-[2.6rem] leading-[1.04] font-semibold tracking-[-0.035em] text-balance sm:text-6xl lg:text-[4.1rem]">
                            Que nada se quede <span className="text-acento">a mitad de camino</span>.
                        </h1>
                        <p className="mt-6 max-w-xl text-lg leading-relaxed text-pretty text-texto-2">
                            Nexo conecta cada solicitud con su proyecto, sus tareas y su resultado, y te avisa
                            cuando algo se detiene antes de llegar al final.
                        </p>
                        <div className="mt-9 flex flex-wrap items-center gap-3">
                            <a
                                href={enlaceDemostracion}
                                className="transicion group inline-flex items-center gap-2 rounded-lg bg-acento px-5 py-3 text-sm font-semibold text-sobre-acento hover:opacity-90"
                            >
                                Ver la demostración
                                <ArrowRight
                                    size={16}
                                    aria-hidden="true"
                                    className="transicion group-hover:translate-x-0.5"
                                />
                            </a>
                            <a
                                href="#como-funciona"
                                className="transicion inline-flex items-center rounded-lg border border-borde-fuerte px-5 py-3 text-sm font-medium hover:bg-elevada"
                            >
                                Cómo funciona
                            </a>
                        </div>
                    </div>

                    <div className="rounded-2xl border border-borde bg-elevada/50 p-4 sm:p-6">
                        <DiagramaFlujo />
                    </div>
                </section>

                <section id="como-funciona" className="border-t border-borde">
                    <div className="mx-auto max-w-6xl px-4 py-20 sm:px-6">
                        <div className="max-w-2xl">
                            <h2 className="text-3xl font-semibold tracking-[-0.025em] sm:text-4xl">
                                Del primer correo a la entrega, sin perder el hilo
                            </h2>
                            <p className="mt-4 text-texto-2">
                                Así es como Nexo quiere ordenar el trabajo de un equipo de servicios.
                            </p>
                        </div>

                        <ol className="mt-12 grid gap-10 sm:grid-cols-2 lg:grid-cols-4 lg:gap-8">
                            {pasos.map(({ Icono, titulo, texto }, indice) => (
                                <li key={titulo} className="relative">
                                    <div className="flex items-center gap-3">
                                        <span className="inline-flex size-10 items-center justify-center rounded-full border border-borde-fuerte bg-superficie text-acento">
                                            <Icono size={20} aria-hidden="true" />
                                        </span>
                                        <span className="text-xs font-medium text-texto-2 tabular-nums">
                                            0{indice + 1}
                                        </span>
                                        {indice < pasos.length - 1 && (
                                            <span
                                                className="hidden h-px flex-1 bg-borde-fuerte lg:block"
                                                aria-hidden="true"
                                            />
                                        )}
                                    </div>
                                    <h3 className="mt-5 font-semibold">{titulo}</h3>
                                    <p className="mt-2 text-sm leading-relaxed text-texto-2">{texto}</p>
                                </li>
                            ))}
                        </ol>

                        <p className="mt-14 border-l-2 border-acento pl-4 text-sm text-texto-2">
                            Nexo está en construcción: la base de cuentas, organizaciones y miembros ya está lista en
                            el servidor; proyectos, tareas y automatizaciones están en desarrollo.
                        </p>
                    </div>
                </section>
            </main>

            <footer className="border-t border-borde">
                <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 px-4 py-6 text-xs text-texto-2 sm:px-6">
                    <span>Nexo · vista previa en desarrollo</span>
                    <a href={enlaceDemostracion} className="transicion rounded hover:text-texto">
                        Ver la demostración
                    </a>
                </div>
            </footer>
        </div>
    );
}
