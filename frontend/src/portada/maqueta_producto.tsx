import { CalendarX2, ChevronDown, FolderKanban, History, type LucideIcon } from "lucide-react";
import type { ReactNode } from "react";
import { DiagramaFlujo } from "./diagrama_flujo.tsx";

// Maqueta del producto para la portada. Ejemplo ilustrativo, no son datos
// reales: muestra cómo Nexo enseña un proyecto, la tarea que se ha detenido y
// el historial de lo que pasó. Se identifica como ejemplo dentro de la propia
// ventana.

type Tono = "atencion" | "exito" | "informacion" | "neutro";

const tonos: Record<Tono, string> = {
    atencion: "text-atencion",
    exito: "text-exito",
    informacion: "text-informacion",
    neutro: "text-texto-2",
};

const actividad: { tipo: string; tono: Tono; cuando: string; texto: string }[] = [
    { tipo: "Vencimiento", tono: "atencion", cuando: "Hoy, 09:01", texto: "«Contenido» superó su fecha límite" },
    { tipo: "Estado", tono: "exito", cuando: "Ayer, 17:40", texto: "Ana P. pasó «Diseño» a Completada" },
    { tipo: "Responsable", tono: "informacion", cuando: "Ayer, 11:12", texto: "Carlos V. es responsable de «Desarrollo»" },
    { tipo: "Proyecto", tono: "neutro", cuando: "Lun, 10:03", texto: "Laura G. creó «Rediseño web»" },
];

function Cabecera({ Icono, titulo, children }: { Icono: LucideIcon; titulo: string; children?: ReactNode }) {
    return (
        <div className="flex flex-wrap items-center justify-between gap-2">
            <span className="flex items-center gap-2 text-sm font-semibold">
                <Icono size={16} aria-hidden="true" className="text-acento" />
                {titulo}
            </span>
            {children}
        </div>
    );
}

export function MaquetaProducto() {
    return (
        <div className="rounded-2xl border border-borde bg-superficie/70 p-1.5 shadow-[0_24px_64px_-32px_rgb(0_0_0/0.55)] sm:p-2">
            <div className="flex flex-col gap-3 rounded-xl bg-fondo p-3 text-left sm:gap-4 sm:p-4">
                {/* Barra superior de la aplicación */}
                <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg bg-superficie px-3 py-2">
                    <div className="flex min-w-0 items-center gap-3">
                        <span className="inline-flex items-center gap-2 rounded-md bg-elevada px-2.5 py-1 text-[13px] font-medium">
                            <span className="size-1.5 rounded-full bg-acento" aria-hidden="true" />
                            Agencia Ejemplo
                            <ChevronDown size={14} aria-hidden="true" className="text-texto-2" />
                        </span>
                        <span className="hidden truncate text-xs text-texto-2 sm:inline">Propietario · America/Bogota</span>
                    </div>
                    <span className="rounded-full bg-acento-suave px-2.5 py-0.5 text-[11px] font-semibold tracking-wide text-acento uppercase">
                        Ejemplo ilustrativo
                    </span>
                </div>

                {/* Aviso de la detección */}
                <div className="flex items-center justify-between gap-3 rounded-lg bg-atencion-suave px-3 py-2.5">
                    <div className="flex min-w-0 items-center gap-3">
                        <span className="inline-flex size-8 shrink-0 items-center justify-center rounded-md bg-atencion-suave text-atencion">
                            <CalendarX2 size={16} aria-hidden="true" />
                        </span>
                        <div className="min-w-0">
                            <p className="truncate text-[13px] font-semibold text-atencion">
                                Tarea vencida: «Contenido», esperando al cliente
                            </p>
                            <p className="truncate text-xs text-texto-2">
                                Nexo lo detectó solo y avisó a su responsable, Ana P.
                            </p>
                        </div>
                    </div>
                    <span className="hidden shrink-0 rounded-md bg-atencion-suave px-2 py-1 text-xs font-medium text-atencion tabular-nums md:inline">
                        Vencida hace 2 días
                    </span>
                </div>

                <div className="grid gap-3 sm:gap-4 lg:grid-cols-12">
                    {/* Proyecto con su flujo */}
                    <div className="flex flex-col gap-3 rounded-lg bg-superficie p-3 sm:p-4 lg:col-span-8">
                        <Cabecera Icono={FolderKanban} titulo="Rediseño web">
                            <span className="rounded-md bg-acento-suave px-2 py-0.5 text-xs font-medium text-acento tabular-nums">
                                3 tareas
                            </span>
                        </Cabecera>
                        <div className="rounded-lg bg-fondo/60 p-2 sm:p-3">
                            <DiagramaFlujo />
                        </div>
                    </div>

                    {/* Historial y avance */}
                    <div className="flex flex-col gap-3 rounded-lg bg-superficie p-3 sm:p-4 lg:col-span-4">
                        <Cabecera Icono={History} titulo="Actividad reciente" />
                        <ul className="flex flex-col gap-1.5">
                            {actividad.map(({ tipo, tono, cuando, texto }) => (
                                <li key={texto} className="rounded-md bg-fondo/60 px-2.5 py-2">
                                    <div className="flex items-center justify-between gap-2 text-[11px] font-medium tabular-nums">
                                        <span className={tonos[tono]}>{tipo}</span>
                                        <span className="text-texto-2">{cuando}</span>
                                    </div>
                                    <p className="mt-0.5 truncate text-xs">{texto}</p>
                                </li>
                            ))}
                        </ul>
                        <div className="mt-auto rounded-md bg-elevada px-3 py-2.5">
                            <p className="text-[11px] font-semibold tracking-wide text-texto-2 uppercase">
                                Avance del proyecto
                            </p>
                            <div className="mt-1 flex items-baseline justify-between gap-2">
                                <span className="text-lg font-semibold text-acento tabular-nums">1 de 3</span>
                                <span className="text-xs text-texto-2">tareas completadas</span>
                            </div>
                            {/* El texto de arriba ya da el dato; la barra es solo visual. */}
                            <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-fondo" aria-hidden="true">
                                <div className="h-full w-1/3 rounded-full bg-acento" />
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
}
