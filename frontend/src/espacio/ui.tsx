import { CircleAlert, CircleCheck, Info, LoaderCircle, type LucideIcon } from "lucide-react";
import type { ReactNode } from "react";
import { mensajeDeError } from "../supabase/errores.ts";

// Piezas comunes del espacio de trabajo, con los tokens de estilos.css.
// Un estado nunca se comunica solo con color: siempre icono y texto.

export const claseBotonPrincipal =
    "transicion inline-flex min-h-10 items-center justify-center gap-2 rounded-lg bg-acento px-4 text-sm font-semibold text-sobre-acento hover:opacity-90 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-50";

export const claseBotonSecundario =
    "transicion inline-flex min-h-10 items-center justify-center gap-2 rounded-lg border border-borde-fuerte bg-superficie px-3 text-sm font-medium text-texto hover:bg-elevada active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-50";

// Acciones dentro de una fila: misma forma que el botón secundario, más
// compactas para no pesar más que los datos.
export const claseBotonFila =
    "transicion inline-flex min-h-8 items-center justify-center gap-1.5 rounded-md border border-borde-fuerte bg-superficie px-2.5 text-[13px] font-medium text-texto hover:bg-elevada active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-50";

export const claseCampo =
    "transicion min-h-10 w-full rounded-lg border border-borde-fuerte bg-superficie px-3 text-sm text-texto placeholder:text-texto-2 focus:border-acento";

const tonos: Record<"error" | "exito" | "informacion", { Icono: LucideIcon; clases: string }> = {
    error: { Icono: CircleAlert, clases: "border-error/30 bg-error-suave text-error" },
    exito: { Icono: CircleCheck, clases: "border-exito/30 bg-exito-suave text-exito" },
    informacion: { Icono: Info, clases: "border-informacion/30 bg-informacion-suave text-informacion" },
};

export function Aviso({ tono, children }: { tono: keyof typeof tonos; children: ReactNode }) {
    const { Icono, clases } = tonos[tono];
    return (
        <p
            role={tono === "error" ? "alert" : "status"}
            className={`flex items-start gap-2 rounded-lg border px-3 py-2 text-sm ${clases}`}
        >
            <Icono size={16} aria-hidden="true" className="mt-0.5 shrink-0" />
            <span className="text-texto">{children}</span>
        </p>
    );
}

export function AvisoError({ error }: { error: unknown }) {
    return <Aviso tono="error">{mensajeDeError(error)}</Aviso>;
}

export function Cargando({ texto }: { texto: string }) {
    return (
        <output className="flex items-center gap-2 py-6 text-sm text-texto-2">
            <LoaderCircle size={16} aria-hidden="true" className="animate-spin motion-reduce:animate-none" />
            {texto}
        </output>
    );
}

// Carga de una lista: la forma final con barras planas, sin brillo ni
// animación, para que la pantalla no salte cuando llegan los datos.
export function EsqueletoLista({ texto, filas = 3 }: { texto: string; filas?: number }) {
    return (
        <output className="mt-3 block rounded-xl border border-borde bg-superficie">
            <span className="sr-only">{texto}</span>
            <span aria-hidden="true" className="block divide-y divide-borde">
                {Array.from({ length: filas }, (_, indice) => (
                    <span key={indice} className="flex flex-col gap-2 px-4 py-3.5">
                        <span className="h-4 w-2/5 rounded bg-elevada" />
                        <span className="h-3 w-1/4 rounded bg-elevada" />
                    </span>
                ))}
            </span>
        </output>
    );
}

export function Campo({ etiqueta, children }: { etiqueta: string; children: ReactNode }) {
    return (
        <label className="flex flex-col gap-1.5 text-sm font-medium">
            {etiqueta}
            {children}
        </label>
    );
}
