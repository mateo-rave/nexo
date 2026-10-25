import {
    Ban,
    CircleCheck,
    Clock,
    FolderKanban,
    Inbox,
    PackageCheck,
    type LucideIcon,
} from "lucide-react";

// Ejemplo ilustrativo (no son datos reales): una solicitud se convierte en un
// proyecto con tres tareas; una está bloqueada y retiene el resultado.

type Nodo = {
    x: number;
    y: number;
    titulo: string;
    detalle: string;
    Icono: LucideIcon;
    tono: "neutro" | "acento" | "exito" | "informacion" | "error";
};

const ancho = 132;
const alto = 58;

const nodos = {
    solicitud: {
        x: 8,
        y: 151,
        titulo: "Solicitud",
        detalle: "Rediseño web",
        Icono: Inbox,
        tono: "neutro",
    },
    proyecto: {
        x: 178,
        y: 151,
        titulo: "Proyecto",
        detalle: "3 tareas",
        Icono: FolderKanban,
        tono: "acento",
    },
    diseno: { x: 348, y: 44, titulo: "Diseño", detalle: "Completada", Icono: CircleCheck, tono: "exito" },
    contenido: { x: 348, y: 151, titulo: "Contenido", detalle: "Bloqueada", Icono: Ban, tono: "error" },
    desarrollo: {
        x: 348,
        y: 258,
        titulo: "Desarrollo",
        detalle: "En curso",
        Icono: Clock,
        tono: "informacion",
    },
    resultado: {
        x: 518,
        y: 151,
        titulo: "Resultado",
        detalle: "Entrega",
        Icono: PackageCheck,
        tono: "neutro",
    },
} satisfies Record<string, Nodo>;

const tonos: Record<Nodo["tono"], { icono: string; borde: string }> = {
    neutro: { icono: "text-texto-2", borde: "stroke-borde-fuerte" },
    acento: { icono: "text-acento", borde: "stroke-acento" },
    exito: { icono: "text-exito", borde: "stroke-borde-fuerte" },
    informacion: { icono: "text-informacion", borde: "stroke-borde-fuerte" },
    error: { icono: "text-error", borde: "stroke-error" },
};

// Curva horizontal entre el borde derecho de un nodo y el izquierdo de otro.
function conexion(desde: Nodo, hasta: Nodo): string {
    const x1 = desde.x + ancho;
    const y1 = desde.y + alto / 2;
    const x2 = hasta.x;
    const y2 = hasta.y + alto / 2;
    const medio = (x1 + x2) / 2;
    return `M ${x1} ${y1} C ${medio} ${y1}, ${medio} ${y2}, ${x2} ${y2}`;
}

function NodoFlujo({ nodo }: { nodo: Nodo }) {
    const { icono, borde } = tonos[nodo.tono];
    const { Icono } = nodo;
    return (
        <g>
            <rect
                x={nodo.x}
                y={nodo.y}
                width={ancho}
                height={alto}
                rx={10}
                className={`fill-superficie ${borde}`}
                strokeWidth={1.25}
            />
            <Icono x={nodo.x + 12} y={nodo.y + 19} width={20} height={20} className={icono} aria-hidden="true" />
            <text x={nodo.x + 42} y={nodo.y + 25} className="fill-texto text-[13px] font-semibold">
                {nodo.titulo}
            </text>
            <text x={nodo.x + 42} y={nodo.y + 42} className="fill-texto-2 text-[11.5px]">
                {nodo.detalle}
            </text>
        </g>
    );
}

export function DiagramaFlujo() {
    const { solicitud, proyecto, diseno, contenido, desarrollo, resultado } = nodos;
    return (
        <figure className="relative">
            {/* El dibujo es decorativo para lectores de pantalla; este texto lo describe. */}
            <p className="sr-only">
                Ejemplo de flujo de trabajo en Nexo: una solicitud de rediseño web se convierte en un proyecto
                con tres tareas: diseño, completada; contenido, bloqueada a la espera del cliente; y
                desarrollo, en curso. El resultado se entrega cuando las tres terminan.
            </p>
            <svg viewBox="0 0 658 360" className="h-auto w-full" aria-hidden="true">

                {/* Retícula de puntos, muy sutil, como plano de fondo. */}
                <defs>
                    <pattern id="reticula" width="22" height="22" patternUnits="userSpaceOnUse">
                        <circle cx="1" cy="1" r="1" className="fill-borde-fuerte" />
                    </pattern>
                </defs>
                <rect width="658" height="360" fill="url(#reticula)" opacity="0.6" />

                <g fill="none" strokeWidth={1.75} strokeLinecap="round">
                    {/* Tramo ya recorrido: sólido. */}
                    <path d={conexion(solicitud, proyecto)} className="stroke-acento" />
                    <path d={conexion(proyecto, diseno)} className="stroke-acento" />
                    <path d={conexion(diseno, resultado)} className="stroke-borde-fuerte" />
                    {/* Trabajo en marcha: trazo animado (se detiene con prefers-reduced-motion). */}
                    <path d={conexion(proyecto, desarrollo)} className="linea-activa stroke-acento" />
                    <path d={conexion(desarrollo, resultado)} className="stroke-borde-fuerte" strokeDasharray="6 4" />
                    {/* Tramo detenido por el bloqueo. */}
                    <path d={conexion(proyecto, contenido)} className="stroke-error" strokeDasharray="2 5" />
                    <path d={conexion(contenido, resultado)} className="stroke-borde-fuerte" strokeDasharray="2 5" />
                </g>

                {Object.values(nodos).map((nodo) => (
                    <NodoFlujo key={nodo.titulo} nodo={nodo} />
                ))}

                {/* Aviso sobre el tramo bloqueado. */}
                <g>
                    <rect
                        x={contenido.x + 6}
                        y={contenido.y + alto + 10}
                        width={120}
                        height={24}
                        rx={6}
                        className="fill-error-suave"
                    />
                    <text
                        x={contenido.x + 66}
                        y={contenido.y + alto + 26}
                        textAnchor="middle"
                        className="fill-error text-[11px] font-medium"
                    >
                        Esperando al cliente
                    </text>
                </g>
            </svg>
            <figcaption className="mt-3 text-xs text-texto-2">
                Ejemplo ilustrativo: el resultado no se entrega mientras una tarea siga bloqueada.
            </figcaption>
        </figure>
    );
}
