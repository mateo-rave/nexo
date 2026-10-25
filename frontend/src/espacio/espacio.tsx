import type { Session, SupabaseClient } from "@supabase/supabase-js";
import { ArrowLeft, Bell, Building2, FolderKanban, LogOut, Plus, type LucideIcon } from "lucide-react";
import { useCallback, useState, type FormEvent } from "react";
import { MarcaNexo } from "../componentes/simbolo_nexo.tsx";
import { SelectorTema } from "../componentes/selector_tema.tsx";
import { enlacePortada } from "../ruta/ruta.ts";
import { useSesion } from "../sesion/sesion.ts";
import { configuracion } from "../supabase/cliente.ts";
import type { PreferenciaTema } from "../tema/tema.ts";
import { Acceso } from "./acceso.tsx";
import { useCarga } from "./carga.ts";
import { crearOrganizacion, listarOrganizaciones, listarProyectos, type Organizacion } from "./datos.ts";
import { Notificaciones } from "./notificaciones.tsx";
import { Proyectos } from "./proyectos.tsx";
import { TareasProyecto } from "./tareas.tsx";
import { Aviso, AvisoError, Campo, Cargando, claseBotonPrincipal, claseCampo } from "./ui.tsx";

type PropiedadesTema = {
    preferencia: PreferenciaTema;
    alElegirTema: (preferencia: PreferenciaTema) => void;
};

// Espacio de trabajo conectado al backend real (ADR-0006). Sin configuración
// de Supabase no simula nada: explica qué falta.
export function Espacio(tema: PropiedadesTema) {
    if (!configuracion.lista) {
        return (
            <div className="flex min-h-dvh items-center justify-center px-4">
                <main id="contenido" tabIndex={-1} className="w-full max-w-md outline-none">
                    <MarcaNexo />
                    <h1 className="mt-8 text-2xl font-semibold tracking-tight">Falta configurar la conexión</h1>
                    <div className="mt-4">
                        <Aviso tono="informacion">{configuracion.motivo}</Aviso>
                    </div>
                    <a href={enlacePortada} className="mt-6 inline-flex text-sm font-medium text-acento hover:underline">
                        Volver a la portada
                    </a>
                </main>
            </div>
        );
    }
    return <EspacioConCliente cliente={configuracion.cliente} {...tema} />;
}

function EspacioConCliente({ cliente, ...tema }: { cliente: SupabaseClient } & PropiedadesTema) {
    const sesion = useSesion(cliente);
    if (sesion === undefined) {
        return (
            <div className="flex min-h-dvh items-center justify-center">
                <Cargando texto="Comprobando la sesión…" />
            </div>
        );
    }
    if (sesion === null) {
        return <Acceso cliente={cliente} />;
    }
    return <EspacioConSesion cliente={cliente} sesion={sesion} {...tema} />;
}

// La organización mostrada se recuerda en este navegador (comodidad: el
// acceso real lo decide RLS en cada consulta).
const claveOrganizacion = "nexo-organizacion";

function leerOrganizacionGuardada(): string | null {
    try {
        return localStorage.getItem(claveOrganizacion);
    } catch {
        return null;
    }
}

function guardarOrganizacion(id: string): void {
    try {
        localStorage.setItem(claveOrganizacion, id);
    } catch {
        // Sin almacenamiento, la elección dura solo esta visita.
    }
}

type Seccion = "proyectos" | "notificaciones";

const etiquetasRol: Record<Organizacion["rol"], string> = {
    propietario: "Propietario",
    administrador: "Administrador",
    miembro: "Miembro",
};

function EspacioConSesion({
    cliente,
    sesion,
    preferencia,
    alElegirTema,
}: { cliente: SupabaseClient; sesion: Session } & PropiedadesTema) {
    const usuarioId = sesion.user.id;
    const cargarOrganizaciones = useCallback(() => listarOrganizaciones(cliente, usuarioId), [cliente, usuarioId]);
    const { carga, recargar } = useCarga(cargarOrganizaciones);
    const [elegida, setElegida] = useState<string | null>(leerOrganizacionGuardada);
    const [seccion, setSeccion] = useState<Seccion>("proyectos");
    const [creandoOrganizacion, setCreandoOrganizacion] = useState(false);

    if (carga.estado === "cargando") {
        return (
            <div className="flex min-h-dvh items-center justify-center">
                <Cargando texto="Cargando tus organizaciones…" />
            </div>
        );
    }
    if (carga.estado === "error") {
        return (
            <div className="flex min-h-dvh items-center justify-center px-4">
                <div className="w-full max-w-md">
                    <AvisoError error={carga.error} />
                </div>
            </div>
        );
    }

    const organizaciones = carga.datos;
    const organizacion = organizaciones.find((o) => o.id === elegida) ?? organizaciones[0];

    if (!organizacion || creandoOrganizacion) {
        return (
            <div className="flex min-h-dvh items-center justify-center px-4 py-10">
                <main id="contenido" tabIndex={-1} className="w-full max-w-md outline-none">
                    <MarcaNexo />
                    <NuevaOrganizacion
                        cliente={cliente}
                        primera={!organizacion}
                        alCrear={() => {
                            setCreandoOrganizacion(false);
                            recargar();
                        }}
                        alCancelar={organizacion ? () => setCreandoOrganizacion(false) : undefined}
                    />
                    {!organizacion && (
                        <button
                            type="button"
                            onClick={() => cliente.auth.signOut()}
                            className="transicion mt-6 inline-flex items-center gap-2 rounded text-sm text-texto-2 hover:text-texto"
                        >
                            <LogOut size={16} aria-hidden="true" />
                            Cerrar sesión
                        </button>
                    )}
                </main>
            </div>
        );
    }

    const elegir = (id: string) => {
        setElegida(id);
        guardarOrganizacion(id);
    };

    return (
        <div className="min-h-dvh lg:grid lg:grid-cols-[248px_minmax(0,1fr)]">
            {/* En móvil, una barra compacta (marca, organización y secciones); en
                escritorio, la barra lateral completa. */}
            <aside className="border-b border-borde bg-superficie px-4 py-3 lg:sticky lg:top-0 lg:flex lg:h-dvh lg:flex-col lg:border-r lg:border-b-0 lg:px-3 lg:py-4">
                <div className="flex items-end gap-3 lg:block">
                    <a
                        href={enlacePortada}
                        className="flex shrink-0 items-center self-center rounded-md lg:mb-5 lg:px-2"
                        aria-label="Nexo, portada"
                    >
                        <MarcaNexo />
                    </a>

                    <label className="flex min-w-0 flex-1 flex-col gap-1.5 text-xs text-texto-2 lg:px-2">
                        <span className="sr-only flex items-center gap-1.5 lg:not-sr-only">
                            <Building2 size={14} aria-hidden="true" />
                            Organización
                        </span>
                        <select
                            className={claseCampo}
                            value={organizacion.id}
                            onChange={(e) => elegir(e.target.value)}
                        >
                            {organizaciones.map((o) => (
                                <option key={o.id} value={o.id}>
                                    {o.nombre}
                                </option>
                            ))}
                        </select>
                    </label>
                    <button
                        type="button"
                        onClick={() => setCreandoOrganizacion(true)}
                        className="transicion inline-flex size-10 shrink-0 items-center justify-center gap-1.5 rounded-lg border border-borde-fuerte text-xs font-medium text-acento hover:bg-elevada lg:mt-2 lg:ml-2 lg:size-auto lg:border-0 lg:hover:bg-transparent lg:hover:underline"
                    >
                        <Plus size={14} aria-hidden="true" />
                        <span className="sr-only lg:not-sr-only">Nueva organización</span>
                    </button>
                </div>

                <nav aria-label="Secciones" className="mt-3 flex gap-1 lg:mt-5 lg:flex-col">
                    <EnlaceSeccion
                        etiqueta="Proyectos"
                        Icono={FolderKanban}
                        activa={seccion === "proyectos"}
                        alPulsar={() => setSeccion("proyectos")}
                    />
                    <EnlaceSeccion
                        etiqueta="Notificaciones"
                        Icono={Bell}
                        activa={seccion === "notificaciones"}
                        alPulsar={() => setSeccion("notificaciones")}
                    />
                </nav>

                <div className="mt-auto hidden flex-col gap-1 lg:flex">
                    <p className="truncate px-2.5 text-xs text-texto-2">{sesion.user.email}</p>
                    <button
                        type="button"
                        onClick={() => cliente.auth.signOut()}
                        className="transicion flex items-center gap-2 rounded-lg px-2.5 py-2 text-sm text-texto-2 hover:bg-elevada hover:text-texto"
                    >
                        <LogOut size={16} aria-hidden="true" />
                        Cerrar sesión
                    </button>
                </div>
            </aside>

            <div className="min-w-0">
                <header className="flex items-center gap-3 border-b border-borde px-4 py-3 sm:px-6">
                    <div className="min-w-0 flex-1">
                        <h1 className="truncate text-lg font-semibold tracking-tight">{organizacion.nombre}</h1>
                        <p className="truncate text-xs text-texto-2">
                            {etiquetasRol[organizacion.rol]} · Zona horaria: {organizacion.zona_horaria}
                        </p>
                    </div>
                    <SelectorTema preferencia={preferencia} alElegir={alElegirTema} />
                    <button
                        type="button"
                        onClick={() => cliente.auth.signOut()}
                        title="Cerrar sesión"
                        className="transicion inline-flex size-9 items-center justify-center rounded-lg text-texto-2 hover:bg-elevada hover:text-texto lg:hidden"
                    >
                        <LogOut size={18} aria-hidden="true" />
                        <span className="sr-only">Cerrar sesión</span>
                    </button>
                </header>
                <main id="contenido" tabIndex={-1} className="mx-auto max-w-[1100px] px-4 py-6 outline-none sm:px-6 sm:py-8">
                    {seccion === "proyectos" ? (
                        <SeccionProyectos
                            key={organizacion.id}
                            cliente={cliente}
                            organizacion={organizacion}
                            usuarioId={usuarioId}
                        />
                    ) : (
                        <Notificaciones key={organizacion.id} cliente={cliente} organizacion={organizacion} />
                    )}
                </main>
            </div>
        </div>
    );
}

function EnlaceSeccion({
    etiqueta,
    Icono,
    activa,
    alPulsar,
}: {
    etiqueta: string;
    Icono: LucideIcon;
    activa: boolean;
    alPulsar: () => void;
}) {
    return (
        <button
            type="button"
            onClick={alPulsar}
            aria-current={activa ? "page" : undefined}
            className={`transicion flex items-center gap-3 rounded-lg px-2.5 py-2 text-sm ${
                activa ? "bg-acento-suave font-medium text-texto" : "text-texto-2 hover:bg-elevada hover:text-texto"
            }`}
        >
            <Icono size={18} aria-hidden="true" className={activa ? "text-acento" : undefined} />
            {etiqueta}
        </button>
    );
}

// Lista de proyectos o tareas de un proyecto. La lista se carga aquí para que
// la vista de tareas reciba siempre el proyecto actualizado (por ejemplo, tras
// archivarlo).
function SeccionProyectos({
    cliente,
    organizacion,
    usuarioId,
}: {
    cliente: SupabaseClient;
    organizacion: Organizacion;
    usuarioId: string;
}) {
    const cargar = useCallback(() => listarProyectos(cliente, organizacion.id), [cliente, organizacion.id]);
    const { carga, recargar } = useCarga(cargar);
    const [abiertoId, setAbiertoId] = useState<string | null>(null);

    const abierto = carga.estado === "listo" ? carga.datos.find((p) => p.id === abiertoId) : undefined;

    if (abierto) {
        return (
            <TareasProyecto
                key={`${abierto.id}-${abierto.archivado_en ?? "activo"}`}
                cliente={cliente}
                organizacion={organizacion}
                proyecto={abierto}
                usuarioId={usuarioId}
                alVolver={() => setAbiertoId(null)}
                alCambiarProyecto={recargar}
            />
        );
    }
    return (
        <Proyectos
            cliente={cliente}
            organizacion={organizacion}
            carga={carga}
            recargar={recargar}
            alAbrir={(proyecto) => setAbiertoId(proyecto.id)}
        />
    );
}

function NuevaOrganizacion({
    cliente,
    primera,
    alCrear,
    alCancelar,
}: {
    cliente: SupabaseClient;
    primera: boolean;
    alCrear: () => void;
    alCancelar?: () => void;
}) {
    const [nombre, setNombre] = useState("");
    const [enviando, setEnviando] = useState(false);
    const [error, setError] = useState<unknown>(null);

    async function enviar(evento: FormEvent) {
        evento.preventDefault();
        setEnviando(true);
        setError(null);
        try {
            await crearOrganizacion(cliente, nombre);
            alCrear();
        } catch (fallo) {
            setError(fallo);
        }
        setEnviando(false);
    }

    return (
        <>
            <h1 className="mt-8 text-2xl font-semibold tracking-tight">
                {primera ? "Crea tu organización" : "Nueva organización"}
            </h1>
            <p className="mt-1 text-sm text-texto-2">
                {primera
                    ? "Todavía no perteneces a ninguna. Crea una para empezar; también pueden añadirte a una existente."
                    : "Serás su propietario. Su zona horaria será America/Bogota hasta que la cambies."}
            </p>
            <form onSubmit={enviar} className="mt-6 flex flex-col gap-4">
                <Campo etiqueta="Nombre de la organización">
                    <input
                        className={claseCampo}
                        value={nombre}
                        onChange={(e) => setNombre(e.target.value)}
                        required
                        maxLength={100}
                    />
                </Campo>
                {error !== null && <AvisoError error={error} />}
                <div className="flex flex-wrap gap-3">
                    <button type="submit" className={claseBotonPrincipal} disabled={enviando}>
                        {enviando ? "Creando…" : "Crear organización"}
                    </button>
                    {alCancelar && (
                        <button
                            type="button"
                            onClick={alCancelar}
                            className="transicion inline-flex items-center gap-2 rounded-lg px-3 text-sm text-texto-2 hover:text-texto"
                        >
                            <ArrowLeft size={16} aria-hidden="true" />
                            Volver
                        </button>
                    )}
                </div>
            </form>
        </>
    );
}
