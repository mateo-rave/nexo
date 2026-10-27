import type { Tarea } from "./datos.ts";

// Vencimiento tal como lo eligió el usuario (ADR-0007): sin hora, el día; con
// hora, el instante en la zona de la organización, indicando la zona. Solo da
// formato: si una tarea está vencida lo decide la detección del backend.
export function textoVencimiento(
    tarea: Pick<Tarea, "fecha_limite" | "vence_en">,
    zonaHoraria: string,
): string | null {
    if (tarea.fecha_limite) {
        const dia = new Intl.DateTimeFormat("es", {
            weekday: "short",
            day: "numeric",
            month: "short",
            year: "numeric",
            timeZone: "UTC",
        }).format(new Date(`${tarea.fecha_limite}T00:00:00Z`));
        return `Vence el ${dia}`;
    }
    if (tarea.vence_en) {
        const instante = new Intl.DateTimeFormat("es", {
            weekday: "short",
            day: "numeric",
            month: "short",
            year: "numeric",
            hour: "2-digit",
            minute: "2-digit",
            timeZone: zonaHoraria,
            timeZoneName: "short",
        }).format(new Date(tarea.vence_en));
        return `Vence el ${instante}`;
    }
    return null;
}

// Fecha y hora de un instante (detección, notificación) en la zona de la
// organización.
export function textoInstante(instante: string, zonaHoraria: string): string {
    return new Intl.DateTimeFormat("es", {
        day: "numeric",
        month: "short",
        hour: "2-digit",
        minute: "2-digit",
        timeZone: zonaHoraria,
    }).format(new Date(instante));
}
