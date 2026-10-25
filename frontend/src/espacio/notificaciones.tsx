import type { SupabaseClient } from "@supabase/supabase-js";
import { Bell, Check } from "lucide-react";
import { useCallback, useState } from "react";
import { useCarga } from "./carga.ts";
import { listarNotificaciones, marcarNotificacionLeida, type Organizacion } from "./datos.ts";
import { AvisoError, claseBotonFila, EsqueletoLista } from "./ui.tsx";

const formatoFecha = new Intl.DateTimeFormat("es", {
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
});

// Notificaciones internas de la persona que ha iniciado sesión en esta
// organización. RLS solo devuelve las propias; las crea la detección
// programada del backend.
export function Notificaciones({ cliente, organizacion }: { cliente: SupabaseClient; organizacion: Organizacion }) {
    const cargar = useCallback(() => listarNotificaciones(cliente, organizacion.id), [cliente, organizacion.id]);
    const { carga, recargar } = useCarga(cargar);
    const [error, setError] = useState<unknown>(null);

    async function marcar(id: string) {
        setError(null);
        try {
            await marcarNotificacionLeida(cliente, id);
            recargar();
        } catch (fallo) {
            setError(fallo);
        }
    }

    return (
        <section aria-labelledby="titulo-notificaciones" className="flex flex-col gap-3">
            <h2 id="titulo-notificaciones" className="text-lg font-semibold tracking-tight">
                Notificaciones
            </h2>
            {error !== null && <AvisoError error={error} />}
            {carga.estado === "cargando" && <EsqueletoLista texto="Cargando notificaciones…" filas={2} />}
            {carga.estado === "error" && <AvisoError error={carga.error} />}
            {carga.estado === "listo" &&
                (carga.datos.length === 0 ? (
                    <p className="rounded-lg border border-dashed border-borde-fuerte px-4 py-6 text-sm text-texto-2">
                        No tienes notificaciones. Aquí aparecerán, por ejemplo, las tareas vencidas de las que eres
                        responsable.
                    </p>
                ) : (
                    <ul className="divide-y divide-borde rounded-xl border border-borde bg-superficie">
                        {carga.datos.map((notificacion) => {
                            const leida = notificacion.leida_en !== null;
                            return (
                                <li key={notificacion.id} className="flex items-start gap-3 px-4 py-3">
                                    <Bell
                                        size={18}
                                        aria-hidden="true"
                                        className={`mt-0.5 shrink-0 ${leida ? "text-texto-2" : "text-acento"}`}
                                    />
                                    <div className="min-w-0 flex-1">
                                        <p className={leida ? "text-texto-2" : "font-semibold"}>
                                            {notificacion.titulo}
                                            {!leida && <span className="sr-only"> (sin leer)</span>}
                                        </p>
                                        <p className="text-sm text-texto-2">{notificacion.mensaje}</p>
                                        <p className="mt-0.5 text-xs text-texto-2 tabular-nums">
                                            {formatoFecha.format(new Date(notificacion.creado_en))}
                                        </p>
                                    </div>
                                    {!leida && (
                                        <button type="button" className={claseBotonFila} onClick={() => marcar(notificacion.id)}>
                                            <Check size={16} aria-hidden="true" />
                                            Marcar como leída
                                        </button>
                                    )}
                                </li>
                            );
                        })}
                    </ul>
                ))}
        </section>
    );
}
