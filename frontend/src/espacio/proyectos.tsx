import type { SupabaseClient } from "@supabase/supabase-js";
import { Archive, ChevronRight, FolderPlus } from "lucide-react";
import { useCallback, useState, type FormEvent } from "react";
import { useCarga, type Carga } from "./carga.ts";
import { crearProyecto, listarVersionesPublicadas, type Organizacion, type Proyecto } from "./datos.ts";
import { AvisoError, Campo, claseBotonPrincipal, claseCampo, EsqueletoLista } from "./ui.tsx";

type Propiedades = {
    cliente: SupabaseClient;
    organizacion: Organizacion;
    carga: Carga<Proyecto[]>;
    recargar: () => void;
    alAbrir: (proyecto: Proyecto) => void;
};

// Lista los proyectos de la organización y, para propietario y
// administrador, permite crear uno con el flujo elegido (por defecto, el
// predeterminado). Ocultar el formulario a los miembros es solo comodidad:
// crear_proyecto rechaza a quien no tiene permiso.
export function Proyectos({ cliente, organizacion, carga, recargar, alAbrir }: Propiedades) {
    const gestiona = organizacion.rol !== "miembro";

    return (
        <div className="flex flex-col gap-8">
            {gestiona && <NuevoProyecto cliente={cliente} organizacion={organizacion} alCrear={recargar} />}

            <section aria-labelledby="titulo-proyectos">
                <h2 id="titulo-proyectos" className="text-lg font-semibold tracking-tight">
                    Proyectos
                </h2>
                {carga.estado === "cargando" && <EsqueletoLista texto="Cargando proyectos…" />}
                {carga.estado === "error" && (
                    <div className="mt-3">
                        <AvisoError error={carga.error} />
                    </div>
                )}
                {carga.estado === "listo" &&
                    (carga.datos.length === 0 ? (
                        <p className="mt-3 rounded-lg border border-dashed border-borde-fuerte px-4 py-6 text-sm text-texto-2">
                            Todavía no hay proyectos.{" "}
                            {gestiona ? "Crea el primero con el formulario de arriba." : "Pide a un administrador que cree uno."}
                        </p>
                    ) : (
                        <ul className="mt-3 divide-y divide-borde rounded-xl border border-borde bg-superficie">
                            {carga.datos.map((proyecto) => (
                                <li key={proyecto.id}>
                                    <button
                                        type="button"
                                        onClick={() => alAbrir(proyecto)}
                                        className="transicion flex w-full items-center gap-3 px-4 py-3 text-left hover:bg-elevada"
                                    >
                                        <span className="min-w-0 flex-1">
                                            <span className="block truncate font-medium">{proyecto.nombre}</span>
                                            {proyecto.descripcion && (
                                                <span className="block truncate text-[13px] text-texto-2">
                                                    {proyecto.descripcion}
                                                </span>
                                            )}
                                        </span>
                                        {proyecto.archivado_en && (
                                            <span className="inline-flex items-center gap-1 rounded-md bg-elevada px-2 py-0.5 text-xs font-medium text-texto-2">
                                                <Archive size={14} aria-hidden="true" />
                                                Archivado
                                            </span>
                                        )}
                                        <ChevronRight size={16} aria-hidden="true" className="shrink-0 text-texto-2" />
                                    </button>
                                </li>
                            ))}
                        </ul>
                    ))}
            </section>
        </div>
    );
}

function NuevoProyecto({
    cliente,
    organizacion,
    alCrear,
}: {
    cliente: SupabaseClient;
    organizacion: Organizacion;
    alCrear: () => void;
}) {
    const cargarVersiones = useCallback(
        () => listarVersionesPublicadas(cliente, organizacion.id),
        [cliente, organizacion.id],
    );
    const { carga: versiones } = useCarga(cargarVersiones);
    const [nombre, setNombre] = useState("");
    const [descripcion, setDescripcion] = useState("");
    const [versionId, setVersionId] = useState("");
    const [enviando, setEnviando] = useState(false);
    const [error, setError] = useState<unknown>(null);

    async function enviar(evento: FormEvent) {
        evento.preventDefault();
        setEnviando(true);
        setError(null);
        try {
            await crearProyecto(cliente, organizacion.id, nombre, descripcion, versionId || null);
            setNombre("");
            setDescripcion("");
            setVersionId("");
            alCrear();
        } catch (fallo) {
            setError(fallo);
        }
        setEnviando(false);
    }

    return (
        <section aria-labelledby="titulo-nuevo-proyecto" className="rounded-xl border border-borde bg-superficie p-4 sm:p-5">
            <h2 id="titulo-nuevo-proyecto" className="flex items-center gap-2 font-semibold">
                <FolderPlus size={18} aria-hidden="true" className="text-acento" />
                Nuevo proyecto
            </h2>
            <form onSubmit={enviar} className="mt-4 grid gap-4 sm:grid-cols-2">
                <Campo etiqueta="Nombre">
                    <input
                        className={claseCampo}
                        value={nombre}
                        onChange={(e) => setNombre(e.target.value)}
                        required
                        maxLength={100}
                    />
                </Campo>
                <Campo etiqueta="Flujo">
                    <select className={claseCampo} value={versionId} onChange={(e) => setVersionId(e.target.value)}>
                        <option value="">Flujo predeterminado</option>
                        {versiones.estado === "listo" &&
                            versiones.datos
                                .filter((version) => !version.es_predeterminado)
                                .map((version) => (
                                    <option key={version.id} value={version.id}>
                                        {version.nombre} · versión {version.numero}
                                    </option>
                                ))}
                    </select>
                </Campo>
                <div className="sm:col-span-2">
                    <Campo etiqueta="Descripción (opcional)">
                        <textarea
                            className={`${claseCampo} min-h-20 py-2`}
                            value={descripcion}
                            onChange={(e) => setDescripcion(e.target.value)}
                            maxLength={2000}
                        />
                    </Campo>
                </div>
                {error !== null && (
                    <div className="sm:col-span-2">
                        <AvisoError error={error} />
                    </div>
                )}
                <div className="sm:col-span-2">
                    <button type="submit" className={claseBotonPrincipal} disabled={enviando}>
                        {enviando ? "Creando…" : "Crear proyecto"}
                    </button>
                </div>
            </form>
        </section>
    );
}
