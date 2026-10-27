import { CalendarX2, Check, Inbox, PackageCheck, Timer, UserRoundCheck, type LucideIcon } from "lucide-react";
import type { CSSProperties } from "react";

// Panel visual de las pantallas de acceso. Es un ejemplo ilustrativo de cómo
// Nexo sigue el trabajo (no son datos del usuario) y lo dice en pantalla. Todo
// el movimiento es decorativo y se detiene con prefers-reduced-motion.

type EstadoEtapa = "completada" | "activa" | "pendiente";

const etapas: { titulo: string; detalle: string; Icono: LucideIcon; estado: EstadoEtapa }[] = [
    { titulo: "Solicitud", detalle: "Recibida", Icono: Inbox, estado: "completada" },
    { titulo: "Asignación", detalle: "Ana P., responsable", Icono: UserRoundCheck, estado: "completada" },
    { titulo: "Ejecución", detalle: "En curso", Icono: Timer, estado: "activa" },
    { titulo: "Entrega", detalle: "Pendiente", Icono: PackageCheck, estado: "pendiente" },
];

const estilosEtapa: Record<EstadoEtapa, { nodo: string; titulo: string }> = {
    completada: { nodo: "border-acento/40 bg-acento-suave text-acento", titulo: "text-texto" },
    activa: { nodo: "pulso-acento border-acento bg-superficie text-acento", titulo: "text-acento" },
    pendiente: { nodo: "border-borde-fuerte bg-superficie text-texto-2", titulo: "text-texto-2" },
};

const beneficios = [
    "Cada proyecto con sus tareas, su responsable y su fecha límite.",
    "Un aviso cuando una tarea se vence, sin perseguir a nadie.",
    "Un historial de quién cambió qué y cuándo.",
];

// Tramo entre dos etapas: sólido si ya se recorrió, en marcha si lleva a la
// etapa activa y punteado si todavía no se ha llegado.
function Tramo({ hacia }: { hacia: EstadoEtapa }) {
    if (hacia === "completada") return <span className="h-px flex-1 bg-acento/60" />;
    if (hacia === "activa") return <span className="trazo-activo h-px flex-1" />;
    return <span className="h-px flex-1 border-t border-dashed border-borde-fuerte" />;
}

export function PanelAcceso() {
    return (
        <div className="entrada-lateral relative flex h-full flex-col overflow-hidden px-10 py-10 xl:px-14">
            <div aria-hidden="true" className="reticula-puntos pointer-events-none absolute inset-0 opacity-50" />
            <div
                aria-hidden="true"
                className="pointer-events-none absolute -right-24 -bottom-24 size-[420px] rounded-full bg-acento/[0.07] blur-[120px]"
            />

            <div className="relative flex items-center justify-between gap-4">
                <p className="inline-flex items-center gap-2 rounded-full border border-borde bg-fondo/60 px-3 py-1 text-[13px] text-texto-2">
                    <span className="latido size-1.5 rounded-full bg-acento" aria-hidden="true" />
                    Así sigue Nexo el trabajo de tu equipo
                </p>
            </div>

            <div className="relative my-auto py-10">
                <figure className="rounded-2xl border border-borde bg-fondo/80 p-6 shadow-[0_24px_64px_-32px_rgb(0_0_0/0.6)]">
                    <figcaption className="flex flex-wrap items-center justify-between gap-2 border-b border-borde pb-4">
                        <span className="text-sm font-medium">Proyecto «Rediseño web»</span>
                        <span className="rounded-md bg-elevada px-2 py-0.5 font-mono text-[11px] text-texto-2">
                            Ejemplo ilustrativo
                        </span>
                    </figcaption>

                    <ol className="mt-6 flex items-start">
                        {etapas.map(({ titulo, detalle, Icono, estado }, indice) => {
                            const estilo = estilosEtapa[estado];
                            return (
                                <li
                                    key={titulo}
                                    className="encender flex flex-1 flex-col items-center text-center"
                                    style={{ "--retraso": `${300 + indice * 220}ms` } as CSSProperties}
                                >
                                    <div className="flex w-full items-center">
                                        {indice === 0 ? <span className="flex-1" /> : <Tramo hacia={estado} />}
                                        <span
                                            className={`inline-flex size-11 shrink-0 items-center justify-center rounded-xl border ${estilo.nodo}`}
                                        >
                                            {estado === "completada" ? (
                                                <Check size={18} aria-hidden="true" />
                                            ) : (
                                                <Icono size={18} aria-hidden="true" />
                                            )}
                                        </span>
                                        {indice === etapas.length - 1 ? (
                                            <span className="flex-1" />
                                        ) : (
                                            <Tramo hacia={etapas[indice + 1].estado} />
                                        )}
                                    </div>
                                    <span className={`mt-3 text-[13px] font-semibold ${estilo.titulo}`}>{titulo}</span>
                                    <span className="mt-0.5 px-1 text-xs text-texto-2">{detalle}</span>
                                    <span className="sr-only">
                                        {estado === "completada" ? "Completada" : estado === "activa" ? "En curso" : "Pendiente"}
                                    </span>
                                </li>
                            );
                        })}
                    </ol>

                    <div className="mt-6 flex flex-wrap items-center justify-between gap-2 rounded-lg bg-atencion-suave px-3.5 py-2.5">
                        <span className="flex items-center gap-2 text-[13px] font-medium text-atencion">
                            <CalendarX2 size={16} aria-hidden="true" />
                            «Contenido» superó su fecha límite
                        </span>
                        <span className="text-xs text-texto-2">Nexo avisó a su responsable</span>
                    </div>
                </figure>

                <p className="mt-10 max-w-lg text-[1.375rem] leading-snug font-medium tracking-[-0.015em] text-balance">
                    Cada solicitud, conectada con su proyecto, sus tareas y su resultado.
                </p>
                <ul className="mt-6 flex flex-col gap-3">
                    {beneficios.map((texto) => (
                        <li key={texto} className="flex items-start gap-3 text-sm text-texto-2">
                            <span className="mt-0.5 inline-flex size-5 shrink-0 items-center justify-center rounded-md border border-acento/40 bg-acento-suave text-acento">
                                <Check size={12} aria-hidden="true" />
                            </span>
                            {texto}
                        </li>
                    ))}
                </ul>
            </div>

            <p className="relative border-t border-borde pt-5 text-xs text-texto-2">
                Los datos de este panel son un ejemplo: tu espacio de trabajo muestra los tuyos.
            </p>
        </div>
    );
}
