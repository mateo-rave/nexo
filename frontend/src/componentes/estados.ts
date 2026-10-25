import {
    Ban,
    CalendarClock,
    CalendarX2,
    CircleCheck,
    CircleDashed,
    CircleX,
    Clock,
    Eye,
    type LucideIcon,
} from "lucide-react";

// -----------------------------------------------------------------------------
// Estado del flujo: uno solo por tarea.
// -----------------------------------------------------------------------------

// Catálogo del backend (tipo estado_tarea, ADR-0007). La demostración no usa
// cancelada.
export type EstadoTarea = "pendiente" | "en_curso" | "en_revision" | "completada" | "cancelada";

// Un estado nunca se comunica solo con color: siempre icono y texto (CLAUDE.md, sección 4).
export const estilosEstado: Record<
    EstadoTarea,
    { etiqueta: string; Icono: LucideIcon; clases: string; barra: string }
> = {
    pendiente: {
        etiqueta: "Pendiente",
        Icono: CircleDashed,
        clases: "bg-elevada text-texto-2",
        barra: "bg-texto-2/45",
    },
    en_curso: {
        etiqueta: "En curso",
        Icono: Clock,
        clases: "bg-informacion-suave text-informacion",
        barra: "bg-informacion",
    },
    // Neutro: el turquesa se reserva para el avance y la acción principal.
    en_revision: {
        etiqueta: "En revisión",
        Icono: Eye,
        clases: "bg-elevada text-texto",
        barra: "bg-texto-2",
    },
    completada: {
        etiqueta: "Completada",
        Icono: CircleCheck,
        clases: "bg-exito-suave text-exito",
        barra: "bg-exito",
    },
    cancelada: {
        etiqueta: "Cancelada",
        Icono: CircleX,
        clases: "bg-elevada text-texto-2",
        barra: "bg-texto-2/45",
    },
};

// -----------------------------------------------------------------------------
// Señales: hechos que se superponen al estado (una tarea puede estar bloqueada
// y vencida a la vez). En la demostración se calculan aquí a partir de las
// fechas; en el producto vendrán del backend (hallazgos, RF-030).
// -----------------------------------------------------------------------------

export type TipoSenal = "bloqueada" | "vencida" | "en_riesgo";

export type Senal = {
    tipo: TipoSenal;
    // Momento de referencia: inicio del bloqueo o fecha límite.
    fecha: string;
    // Tiempo transcurrido (bloqueada, vencida) o restante (en_riesgo), en milisegundos.
    duracion: number;
};

export const estilosSenal: Record<
    TipoSenal,
    { etiqueta: string; Icono: LucideIcon; clases: string; texto: (tiempo: string) => string }
> = {
    bloqueada: {
        etiqueta: "Bloqueada",
        Icono: Ban,
        clases: "bg-error-suave text-error",
        texto: (tiempo) => `Bloqueada · ${tiempo}`,
    },
    vencida: {
        etiqueta: "Vencida",
        Icono: CalendarX2,
        clases: "bg-atencion-suave text-atencion",
        texto: (tiempo) => `Vencida · hace ${tiempo}`,
    },
    // Con borde y sin relleno: misma familia de color que "vencida", menos peso.
    en_riesgo: {
        etiqueta: "En riesgo",
        Icono: CalendarClock,
        clases: "border border-atencion/70 text-atencion",
        texto: (tiempo) => `En riesgo · vence en ${tiempo}`,
    },
};

const hora = 60 * 60 * 1000;
export const umbralRiesgo = 48 * hora;

type DatosSenales = {
    fechaLimite: string;
    bloqueadaDesde?: string;
};

export function calcularSenales(tarea: DatosSenales, ahora: Date): Senal[] {
    const senales: Senal[] = [];
    if (tarea.bloqueadaDesde) {
        senales.push({
            tipo: "bloqueada",
            fecha: tarea.bloqueadaDesde,
            duracion: ahora.getTime() - new Date(tarea.bloqueadaDesde).getTime(),
        });
    }
    const restante = new Date(tarea.fechaLimite).getTime() - ahora.getTime();
    if (restante < 0) {
        senales.push({ tipo: "vencida", fecha: tarea.fechaLimite, duracion: -restante });
    } else if (restante <= umbralRiesgo) {
        // Solo si aún no ha vencido: una tarea vencida no está además "en riesgo".
        senales.push({ tipo: "en_riesgo", fecha: tarea.fechaLimite, duracion: restante });
    }
    return senales;
}

// Bloqueada y vencida > bloqueada > vencida > en riesgo.
export function gravedad(senales: Senal[]): number {
    const tiene = (tipo: TipoSenal) => senales.some((senal) => senal.tipo === tipo);
    if (tiene("bloqueada") && tiene("vencida")) return 4;
    if (tiene("bloqueada")) return 3;
    if (tiene("vencida")) return 2;
    if (tiene("en_riesgo")) return 1;
    return 0;
}

// Formato compacto para etiquetas ("45 min", "25 h", "3 d") y largo para frases.
export function formatearDuracion(milisegundos: number, largo = false): string {
    const minutos = Math.floor(milisegundos / 60000);
    if (minutos < 60) {
        return largo ? plural(minutos, "minuto", "minutos") : `${minutos} min`;
    }
    const horas = Math.floor(minutos / 60);
    // Hasta 48 h (el umbral de riesgo) en horas, para que "vence en 48 h" se lea igual que el umbral.
    if (horas <= 48) {
        return largo ? plural(horas, "hora", "horas") : `${horas} h`;
    }
    const dias = Math.floor(horas / 24);
    return largo ? plural(dias, "día", "días") : `${dias} d`;
}

export function plural(cantidad: number, singular: string, varios: string): string {
    return `${cantidad} ${cantidad === 1 ? singular : varios}`;
}

const formatoFecha = new Intl.DateTimeFormat("es", {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
});

export function formatearFecha(fecha: string | Date): string {
    return formatoFecha.format(typeof fecha === "string" ? new Date(fecha) : fecha);
}
