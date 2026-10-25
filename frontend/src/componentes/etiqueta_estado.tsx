import {
    estilosEstado,
    estilosSenal,
    formatearDuracion,
    formatearFecha,
    type EstadoTarea,
    type Senal,
} from "./estados.ts";

export function EtiquetaEstado({ estado }: { estado: EstadoTarea }) {
    const { etiqueta, Icono, clases } = estilosEstado[estado];
    return (
        <span
            className={`inline-flex items-center gap-1.5 rounded-md px-2 py-0.5 text-xs font-medium whitespace-nowrap ${clases}`}
        >
            <Icono size={14} aria-hidden="true" />
            {etiqueta}
        </span>
    );
}

// Señal con icono, texto y tiempo; la fecha exacta queda en <time> y en el título.
export function EtiquetaSenal({ senal }: { senal: Senal }) {
    const { Icono, clases, texto } = estilosSenal[senal.tipo];
    const fecha = formatearFecha(senal.fecha);
    const referencia = senal.tipo === "bloqueada" ? `Bloqueada desde: ${fecha}` : `Fecha límite: ${fecha}`;
    return (
        <span
            title={referencia}
            className={`inline-flex items-center gap-1.5 rounded-md px-2 py-0.5 text-xs font-semibold whitespace-nowrap tabular-nums ${clases}`}
        >
            <Icono size={14} aria-hidden="true" />
            <time dateTime={senal.fecha}>{texto(formatearDuracion(senal.duracion))}</time>
            <span className="sr-only">({referencia})</span>
        </span>
    );
}
