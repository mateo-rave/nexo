// Cálculos de la demostración: funciones puras sobre la colección de tareas.
// Ningún componente inventa cifras; todas salen de aquí. Cuando exista la API,
// basta con cambiar la fuente de datos.

import {
    calcularSenales,
    formatearDuracion,
    gravedad,
    plural,
    type EstadoTarea,
    type Senal,
    type TipoSenal,
} from "../componentes/estados.ts";
import type { EsperandoA, TareaDemostracion } from "./datos_demostracion.ts";

export type TareaConSenales = { tarea: TareaDemostracion; senales: Senal[]; gravedad: number };

export const estadosDelFlujo: EstadoTarea[] = ["pendiente", "en_curso", "en_revision", "completada"];
export const tiposSenal: TipoSenal[] = ["bloqueada", "vencida", "en_riesgo"];
export const motivosEspera: EsperandoA[] = ["cliente", "equipo", "informacion"];

const dia = 24 * 60 * 60 * 1000;

export const esAbierta = (tarea: TareaDemostracion) => tarea.estado !== "completada";

export const tieneSenal = (senales: Senal[], tipo: TipoSenal) => senales.some((senal) => senal.tipo === tipo);

const duracionDe = (senales: Senal[], tipo: TipoSenal) =>
    senales.find((senal) => senal.tipo === tipo)?.duracion ?? 0;

// Señales de una tarea abierta. Las completadas no tienen señales. Sin fecha
// límite, una tarea no puede vencer ni estar en riesgo: solo puede estar bloqueada.
export function senalesDe(tarea: TareaDemostracion, ahora: Date): Senal[] {
    if (!esAbierta(tarea)) return [];
    if (tarea.fechaLimite) {
        return calcularSenales({ fechaLimite: tarea.fechaLimite, bloqueadaDesde: tarea.bloqueo?.desde }, ahora);
    }
    if (tarea.bloqueo) {
        return [
            {
                tipo: "bloqueada",
                fecha: tarea.bloqueo.desde,
                duracion: ahora.getTime() - new Date(tarea.bloqueo.desde).getTime(),
            },
        ];
    }
    return [];
}

// Tareas que necesitan intervención (al menos una señal), de la más grave a la
// menos grave. A igual gravedad: lo que lleva más tiempo bloqueado o vencido;
// si solo está en riesgo, lo que vence antes.
export function tareasConIntervencion(tareas: TareaDemostracion[], ahora: Date): TareaConSenales[] {
    return tareas
        .map((tarea) => {
            const senales = senalesDe(tarea, ahora);
            return { tarea, senales, gravedad: gravedad(senales) };
        })
        .filter(({ senales }) => senales.length > 0)
        .sort((a, b) => {
            if (a.gravedad !== b.gravedad) return b.gravedad - a.gravedad;
            if (a.gravedad === 1) return duracionDe(a.senales, "en_riesgo") - duracionDe(b.senales, "en_riesgo");
            const peso = (senales: Senal[]) => Math.max(duracionDe(senales, "bloqueada"), duracionDe(senales, "vencida"));
            return peso(b.senales) - peso(a.senales);
        });
}

// Intersección: una tarea debe tener todas las señales de los filtros activos.
export function filtrarPorSenales(lista: TareaConSenales[], filtros: TipoSenal[]): TareaConSenales[] {
    return lista.filter(({ senales }) => filtros.every((tipo) => tieneSenal(senales, tipo)));
}

export type RecuentoSenales = Record<TipoSenal, number> & { bloqueoMasAntiguo: number };

export function recuentoSenales(lista: TareaConSenales[]): RecuentoSenales {
    const cuantas = (tipo: TipoSenal) => lista.filter(({ senales }) => tieneSenal(senales, tipo)).length;
    return {
        bloqueada: cuantas("bloqueada"),
        vencida: cuantas("vencida"),
        en_riesgo: cuantas("en_riesgo"),
        bloqueoMasAntiguo: Math.max(0, ...lista.map(({ senales }) => duracionDe(senales, "bloqueada"))),
    };
}

// Titular y frase secundaria de la zona de intervención. El desglose por
// señal no se repite aquí: ya lo muestran los botones de filtro.
export function resumenIntervencion(lista: TareaConSenales[], recuento: RecuentoSenales) {
    if (lista.length === 0) {
        return { titular: "Ninguna tarea necesita intervención", detalle: null };
    }
    return {
        titular: plural(lista.length, "tarea necesita intervención", "tareas necesitan intervención"),
        detalle:
            recuento.bloqueoMasAntiguo > 0
                ? `El bloqueo más antiguo lleva ${formatearDuracion(recuento.bloqueoMasAntiguo, true)}.`
                : null,
    };
}

// Explica por qué una combinación de filtros no tiene resultados.
export function motivoSinResultados(filtros: TipoSenal[]): string {
    if (filtros.includes("vencida") && filtros.includes("en_riesgo")) {
        return "Una tarea vencida no se considera en riesgo, así que estas dos señales nunca coinciden.";
    }
    return "Ninguna tarea tiene a la vez todas las señales seleccionadas.";
}

export function recuentoPorEstado(tareas: TareaDemostracion[]): Record<EstadoTarea, number> {
    const recuento: Record<EstadoTarea, number> = { pendiente: 0, en_curso: 0, en_revision: 0, completada: 0 };
    for (const tarea of tareas) recuento[tarea.estado] += 1;
    return recuento;
}

export function bloqueadasPorEstado(lista: TareaConSenales[]): Record<EstadoTarea, TareaDemostracion[]> {
    const grupos: Record<EstadoTarea, TareaDemostracion[]> = {
        pendiente: [],
        en_curso: [],
        en_revision: [],
        completada: [],
    };
    for (const { tarea, senales } of lista) {
        if (tieneSenal(senales, "bloqueada")) grupos[tarea.estado].push(tarea);
    }
    return grupos;
}

export type DiaVencimientos = {
    // Inicio del día (00:00).
    fecha: Date;
    tareas: TareaConSenales[];
};

// Los 7 días desde la fecha de referencia (incluida) y las tareas abiertas cuya
// fecha límite cae en cada uno y aún no ha pasado. Las tareas sin fecha límite
// quedan fuera; las ya vencidas se muestran en "Necesita intervención".
export function vencimientosPorDia(tareas: TareaDemostracion[], ahora: Date, dias = 7): DiaVencimientos[] {
    const hoy = new Date(ahora.getFullYear(), ahora.getMonth(), ahora.getDate());
    return Array.from({ length: dias }, (_, indice) => {
        const inicio = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate() + indice);
        const fin = new Date(inicio.getTime() + dia);
        const delDia = tareas
            .filter((tarea) => {
                if (!esAbierta(tarea) || !tarea.fechaLimite) return false;
                const limite = new Date(tarea.fechaLimite);
                return limite >= inicio && limite < fin && limite >= ahora;
            })
            .map((tarea) => {
                const senales = senalesDe(tarea, ahora);
                return { tarea, senales, gravedad: gravedad(senales) };
            })
            .sort((a, b) => (a.tarea.fechaLimite ?? "").localeCompare(b.tarea.fechaLimite ?? ""));
        return { fecha: inicio, tareas: delDia };
    });
}

export type GrupoEspera = {
    motivo: EsperandoA;
    tareas: TareaDemostracion[];
    // Espera más larga del grupo, en milisegundos (0 si no hay tareas).
    esperaMasLarga: number;
};

export function esperasAgrupadas(lista: TareaConSenales[]): GrupoEspera[] {
    return motivosEspera.map((motivo) => {
        const delGrupo = lista.filter(({ tarea, senales }) => tarea.bloqueo?.esperandoA === motivo && tieneSenal(senales, "bloqueada"));
        return {
            motivo,
            tareas: delGrupo.map(({ tarea }) => tarea),
            esperaMasLarga: Math.max(0, ...delGrupo.map(({ senales }) => duracionDe(senales, "bloqueada"))),
        };
    });
}

export function resumenGeneral(tareas: TareaDemostracion[]) {
    const abiertas = tareas.filter(esAbierta);
    const proyectos = new Set(tareas.map((tarea) => tarea.proyecto));
    const proyectosConTrabajoAbierto = new Set(abiertas.map((tarea) => tarea.proyecto));
    return {
        total: tareas.length,
        abiertas: abiertas.length,
        completadas: tareas.length - abiertas.length,
        proyectos: proyectos.size,
        proyectosConTrabajoAbierto: proyectosConTrabajoAbierto.size,
    };
}

// "hace 12 min", "hace 18 h", "hace 3 d" respecto a la fecha de referencia.
export function haceCuanto(fecha: string, ahora: Date): string {
    return `hace ${formatearDuracion(ahora.getTime() - new Date(fecha).getTime())}`;
}
