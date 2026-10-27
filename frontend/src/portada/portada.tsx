import {
    ArrowRight,
    Building2,
    CalendarClock,
    CalendarX2,
    Check,
    CircleCheck,
    Clock,
    GitBranch,
    History,
    Inbox,
    ListTree,
    Milestone,
    PlayCircle,
    ShieldCheck,
    Sparkles,
    Workflow,
    type LucideIcon,
} from "lucide-react";
import type { ReactNode } from "react";
import { MarcaNexo } from "../componentes/simbolo_nexo.tsx";
import { SelectorTema } from "../componentes/selector_tema.tsx";
import { enlaceDemostracion, enlaceEspacio, enlaceRegistro } from "../ruta/ruta.ts";
import type { PreferenciaTema } from "../tema/tema.ts";
import { MaquetaProducto } from "./maqueta_producto.tsx";

type Propiedades = {
    preferencia: PreferenciaTema;
    alElegirTema: (preferencia: PreferenciaTema) => void;
};

// Todo lo que dice la portada es cierto hoy: lo que ya funciona se marca
// "Disponible" y lo demás "En desarrollo" o "Próximamente". Sin métricas,
// clientes ni integraciones inventadas (CLAUDE.md, secciones 1, 2 y 4).

const claseBotonPrincipal =
    "transicion inline-flex items-center justify-center gap-2 rounded-lg bg-acento px-5 py-2.5 text-sm font-semibold text-sobre-acento hover:brightness-110 active:scale-[0.98]";
const claseBotonSecundario =
    "transicion inline-flex items-center justify-center gap-2 rounded-lg border border-borde bg-elevada px-5 py-2.5 text-sm font-medium hover:border-borde-fuerte active:scale-[0.98]";
const claseEtiquetaSeccion = "text-[11px] font-semibold tracking-[0.14em] text-acento uppercase";
const claseTituloSeccion = "text-[1.75rem] leading-tight font-semibold tracking-[-0.02em] text-balance sm:text-[2rem]";

type Disponibilidad = "disponible" | "en_desarrollo" | "planificado" | "proximamente";

const disponibilidades: Record<Disponibilidad, { etiqueta: string; Icono: LucideIcon; clase: string }> = {
    disponible: { etiqueta: "Disponible", Icono: CircleCheck, clase: "bg-exito-suave text-exito" },
    en_desarrollo: { etiqueta: "En desarrollo", Icono: Clock, clase: "bg-informacion-suave text-informacion" },
    planificado: { etiqueta: "Planificado", Icono: Milestone, clase: "bg-elevada text-texto-2" },
    proximamente: { etiqueta: "Próximamente", Icono: CalendarClock, clase: "bg-elevada text-texto-2" },
};

function EtiquetaDisponibilidad({ valor }: { valor: Disponibilidad }) {
    const { etiqueta, Icono, clase } = disponibilidades[valor];
    return (
        <span className={`inline-flex shrink-0 items-center gap-1.5 rounded-full px-2.5 py-0.5 text-[11px] font-semibold ${clase}`}>
            <Icono size={12} aria-hidden="true" />
            {etiqueta}
        </span>
    );
}

const datosProducto = [
    { valor: "3", texto: "Roles por organización" },
    { valor: "5", texto: "Estados de tarea, con flujos propios" },
    { valor: "1 min", texto: "Entre revisiones de vencimientos" },
    { valor: "RLS", texto: "Cada agencia aislada en la base de datos" },
];

const pasos: { Icono: LucideIcon; titulo: string; texto: string; estado: Disponibilidad }[] = [
    {
        Icono: Inbox,
        titulo: "Recibe la solicitud",
        texto: "Cada petición de un cliente entra en un solo lugar, con lo necesario para empezar.",
        estado: "proximamente",
    },
    {
        Icono: ListTree,
        titulo: "Conviértela en trabajo",
        texto: "Un proyecto con sus tareas, cada una con responsable, estado y fecha límite.",
        estado: "disponible",
    },
    {
        Icono: CalendarX2,
        titulo: "Detecta lo que se detiene",
        texto: "Las tareas vencidas salen a la vista y se avisa a quien corresponde, sin avisos repetidos.",
        estado: "disponible",
    },
    {
        Icono: History,
        titulo: "Registra lo que pasó",
        texto: "Cada cambio queda en un historial, para saber quién hizo qué y cuándo.",
        estado: "en_desarrollo",
    },
];

const roles = [
    { nombre: "Propietario", texto: "Control total de la organización, incluidos los administradores." },
    { nombre: "Administrador", texto: "Coordina proyectos, flujos y tareas, y gestiona a los miembros." },
    { nombre: "Miembro", texto: "Crea tareas y trabaja las suyas; consulta todo lo de su agencia." },
];

const estadoProducto: { grupo: Disponibilidad; elementos: string[] }[] = [
    {
        grupo: "disponible",
        elementos: [
            "Cuentas, organizaciones y roles",
            "Proyectos y tareas con responsable y fecha límite",
            "Flujos versionados por organización",
            "Detección de tareas vencidas y notificaciones",
            "Panel operativo",
        ],
    },
    {
        grupo: "en_desarrollo",
        elementos: ["Historial de auditoría en pantalla"],
    },
    {
        grupo: "planificado",
        elementos: ["Gestión de miembros desde la aplicación", "Reglas de automatización", "Métricas sencillas"],
    },
    {
        grupo: "proximamente",
        elementos: ["Entrada de solicitudes", "Integraciones externas, como el correo", "Sugerencias de nuevas automatizaciones"],
    },
];

const enlacesNavegacion = [
    { href: "#capacidades", texto: "Capacidades" },
    { href: "#como-funciona", texto: "Cómo funciona" },
    { href: "#estado", texto: "Estado del producto" },
    { href: enlaceDemostracion, texto: "Demostración" },
];

export function Portada({ preferencia, alElegirTema }: Propiedades) {
    return (
        <div className="min-h-dvh">
            <header className="fixed inset-x-0 top-0 z-40 border-b border-borde bg-fondo/80 backdrop-blur-md">
                <div className="mx-auto flex h-16 max-w-7xl items-center justify-between gap-4 px-4 sm:px-8 lg:px-12">
                    <a href="#/" className="rounded-md" aria-label="Nexo, inicio">
                        <MarcaNexo />
                    </a>
                    <nav aria-label="Secciones de la portada" className="hidden items-center gap-6 lg:flex">
                        {enlacesNavegacion.map(({ href, texto }) => (
                            <a key={href} href={href} className="transicion rounded text-[13px] font-medium text-texto-2 hover:text-texto">
                                {texto}
                            </a>
                        ))}
                    </nav>
                    <div className="flex items-center gap-2 sm:gap-3">
                        <span className="hidden sm:inline-flex">
                            <SelectorTema preferencia={preferencia} alElegir={alElegirTema} />
                        </span>
                        <a
                            href={enlaceEspacio}
                            className="transicion rounded-lg px-2.5 py-2 text-[13px] font-medium text-texto-2 hover:text-texto"
                        >
                            Iniciar sesión
                        </a>
                        <a href={enlaceRegistro} className={`${claseBotonPrincipal} px-3.5 py-2 text-[13px]`}>
                            Crear cuenta
                        </a>
                    </div>
                </div>
            </header>

            <main id="contenido" tabIndex={-1} className="pt-16 outline-none">
                {/* Hero */}
                <section className="relative overflow-hidden px-4 pt-14 pb-16 sm:px-8 sm:pt-20 lg:px-12">
                    {/* Resplandor de fondo, discreto y sin animación. */}
                    <div
                        aria-hidden="true"
                        className="pointer-events-none absolute -top-48 left-1/2 h-[380px] w-[720px] -translate-x-1/2 rounded-full bg-acento/10 blur-[130px]"
                    />
                    <div
                        aria-hidden="true"
                        className="pointer-events-none absolute top-80 -left-32 h-[360px] w-[360px] rounded-full bg-acento/[0.06] blur-[110px]"
                    />

                    <div className="relative mx-auto flex max-w-7xl flex-col items-center text-center">
                        <p className="inline-flex items-center gap-2 rounded-full bg-acento-suave px-3.5 py-1">
                            <Sparkles size={14} aria-hidden="true" className="text-acento" />
                            <span className={claseEtiquetaSeccion}>
                                Vista previa<span className="hidden sm:inline"> · Para agencias y equipos de servicios</span>
                            </span>
                        </p>
                        <h1 className="mt-6 max-w-4xl text-[2.375rem] leading-[1.08] font-semibold tracking-[-0.03em] text-balance sm:text-[3.5rem] sm:leading-[1.1]">
                            Que nada se quede <span className="text-acento">a mitad de camino.</span>
                        </h1>
                        <p className="mt-5 max-w-2xl text-base leading-relaxed text-pretty text-texto-2 sm:text-lg">
                            Nexo conecta cada solicitud con su proyecto, sus tareas y su resultado, y avisa cuando algo
                            se detiene antes de llegar al final.
                        </p>
                        <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
                            <a href={enlaceRegistro} className={`${claseBotonPrincipal} group`}>
                                Crear cuenta
                                <ArrowRight size={16} aria-hidden="true" className="transicion group-hover:translate-x-0.5" />
                            </a>
                            <a href={enlaceDemostracion} className={claseBotonSecundario}>
                                <PlayCircle size={16} aria-hidden="true" className="text-acento" />
                                Ver la demostración
                            </a>
                        </div>

                        {/* Datos del producto (no son métricas de uso). */}
                        <div className="mt-14 w-full max-w-3xl">
                            <p className="text-[11px] font-semibold tracking-[0.14em] text-texto-2 uppercase">
                                Cómo está construido
                            </p>
                            <dl className="mt-4 grid grid-cols-2 gap-3 md:grid-cols-4">
                                {datosProducto.map(({ valor, texto }) => (
                                    <div key={texto} className="flex flex-col items-center rounded-lg bg-superficie px-3 py-3">
                                        <dt className="sr-only">{texto}</dt>
                                        <dd className="text-2xl font-semibold text-acento tabular-nums">{valor}</dd>
                                        <dd className="mt-0.5 text-xs leading-snug text-texto-2">{texto}</dd>
                                    </div>
                                ))}
                            </dl>
                        </div>

                        <div className="mt-14 w-full max-w-6xl">
                            <MaquetaProducto />
                        </div>
                    </div>
                </section>

                {/* Capacidades */}
                <section id="capacidades" className="scroll-mt-16 border-t border-borde bg-superficie/50 px-4 py-20 sm:px-8 lg:px-12">
                    <div className="mx-auto max-w-7xl">
                        <div className="max-w-2xl">
                            <p className={claseEtiquetaSeccion}>Capacidades</p>
                            <h2 className={`mt-2 ${claseTituloSeccion}`}>Control operativo sin complejidad innecesaria.</h2>
                            <p className="mt-3 text-texto-2">
                                Pensado para el día a día de los equipos que gestionan solicitudes de varios clientes.
                            </p>
                        </div>

                        <div className="mt-12 grid gap-5 lg:grid-cols-12">
                            <Tarjeta
                                className="lg:col-span-8"
                                Icono={CalendarX2}
                                titulo="Detección de tareas vencidas"
                                estado="disponible"
                                texto="Nexo revisa los vencimientos por su cuenta. Cuando una tarea supera su fecha límite, crea un aviso una sola vez y notifica a su responsable o, si no tiene, a propietarios y administradores."
                            >
                                <div className="flex flex-col gap-3 rounded-lg bg-fondo/70 p-4 text-[13px]">
                                    <p className="font-medium">Cómo decide Nexo</p>
                                    <div className="flex flex-wrap items-center gap-2">
                                        <Pieza tono="acento">SI</Pieza>
                                        una tarea
                                        <Pieza>sin completar ni cancelar</Pieza>
                                        supera
                                        <Pieza>su fecha límite</Pieza>
                                    </div>
                                    <div className="flex flex-wrap items-center gap-2">
                                        <Pieza tono="atencion">ENTONCES</Pieza>
                                        marca la tarea como
                                        <Pieza tono="atencion">Vencida</Pieza>y avisa a
                                        <Pieza>su responsable</Pieza>
                                    </div>
                                    <p className="flex items-center gap-2 border-t border-borde pt-3 text-xs text-texto-2">
                                        <Check size={14} aria-hidden="true" className="text-exito" />
                                        Repetir la revisión no duplica avisos ni notificaciones.
                                    </p>
                                </div>
                            </Tarjeta>

                            <Tarjeta
                                className="lg:col-span-4"
                                Icono={GitBranch}
                                titulo="Flujos versionados"
                                estado="disponible"
                                texto="Cada organización define qué cambios de estado se permiten. Una versión publicada no se modifica."
                            >
                                <div className="flex flex-col gap-3 rounded-lg bg-fondo/70 p-4 text-[13px]">
                                    <ol className="flex flex-wrap items-center gap-x-2 gap-y-1.5">
                                        {["Pendiente", "En curso", "En revisión", "Completada"].map((estado, indice, lista) => (
                                            <li key={estado} className="flex items-center gap-2">
                                                <span className={indice === lista.length - 1 ? "font-medium text-exito" : ""}>{estado}</span>
                                                {indice < lista.length - 1 && (
                                                    <ArrowRight size={13} aria-hidden="true" className="text-texto-2" />
                                                )}
                                            </li>
                                        ))}
                                    </ol>
                                    <div className="h-1.5 overflow-hidden rounded-full bg-elevada" aria-hidden="true">
                                        <div className="h-full w-2/3 rounded-full bg-acento" />
                                    </div>
                                    <p className="text-xs text-texto-2">Los saltos no permitidos se rechazan en el servidor.</p>
                                </div>
                            </Tarjeta>

                            <Tarjeta
                                className="lg:col-span-4"
                                Icono={Workflow}
                                titulo="Reglas de automatización"
                                estado="planificado"
                                texto="Condiciones y acciones permitidas, definidas como datos, nunca como código arbitrario."
                            >
                                <ul className="flex flex-col gap-2 rounded-lg bg-fondo/70 p-4 text-[13px]">
                                    {[
                                        "Sin acciones duplicadas por un mismo evento",
                                        "Reintentos limitados y controlados",
                                        "Registro de cada ejecución y su resultado",
                                    ].map((texto) => (
                                        <li key={texto} className="flex items-start gap-2">
                                            <Check size={14} aria-hidden="true" className="mt-0.5 shrink-0 text-acento" />
                                            {texto}
                                        </li>
                                    ))}
                                </ul>
                            </Tarjeta>

                            <Tarjeta
                                className="lg:col-span-8"
                                Icono={ShieldCheck}
                                titulo="Cada agencia, aislada. Cada rol, con sus permisos."
                                estado="disponible"
                                texto="Los datos de una organización nunca se ven desde otra. Los permisos los comprueba la base de datos en cada operación, no la pantalla."
                            >
                                <ul className="grid gap-3 sm:grid-cols-3">
                                    {roles.map(({ nombre, texto }) => (
                                        <li key={nombre} className="rounded-lg bg-fondo/70 p-4">
                                            <p className="text-[11px] font-semibold tracking-[0.1em] text-acento uppercase">{nombre}</p>
                                            <p className="mt-1.5 text-[13px] leading-snug text-texto-2">{texto}</p>
                                        </li>
                                    ))}
                                </ul>
                            </Tarjeta>
                        </div>
                    </div>
                </section>

                {/* Cómo funciona */}
                <section id="como-funciona" className="scroll-mt-16 border-t border-borde px-4 py-20 sm:px-8 lg:px-12">
                    <div className="mx-auto max-w-7xl">
                        <div className="mx-auto max-w-3xl text-center">
                            <p className={claseEtiquetaSeccion}>Cómo funciona</p>
                            <h2 className={`mt-2 ${claseTituloSeccion}`}>Del primer correo a la entrega, sin perder el hilo.</h2>
                            <p className="mt-3 text-texto-2">Así ordena Nexo el trabajo de un equipo de servicios.</p>
                        </div>
                        <ol className="mt-12 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
                            {pasos.map(({ Icono, titulo, texto, estado }, indice) => (
                                <li
                                    key={titulo}
                                    className="transicion flex flex-col rounded-xl border border-borde bg-superficie p-6 hover:-translate-y-0.5 hover:border-borde-fuerte"
                                >
                                    <div className="flex items-center justify-between">
                                        <span className="text-xl font-semibold text-acento tabular-nums">0{indice + 1}</span>
                                        <span className="inline-flex size-9 items-center justify-center rounded-full bg-elevada">
                                            <Icono size={16} aria-hidden="true" />
                                        </span>
                                    </div>
                                    <h3 className="mt-5 font-semibold">{titulo}</h3>
                                    <p className="mt-2 text-sm leading-relaxed text-texto-2">{texto}</p>
                                    <div className="mt-auto pt-6">
                                        <EtiquetaDisponibilidad valor={estado} />
                                    </div>
                                </li>
                            ))}
                        </ol>
                    </div>
                </section>

                {/* Estado del producto */}
                <section id="estado" className="scroll-mt-16 border-t border-borde bg-superficie/50 px-4 py-20 sm:px-8 lg:px-12">
                    <div className="mx-auto grid max-w-7xl items-start gap-10 rounded-2xl border border-borde bg-fondo p-6 sm:p-10 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)] lg:gap-16">
                        <div>
                            <p className={claseEtiquetaSeccion}>Estado del producto</p>
                            <h2 className={`mt-2 ${claseTituloSeccion}`}>Construido paso a paso, sobre una base sólida.</h2>
                            <p className="mt-4 leading-relaxed text-texto-2">
                                Nexo está en desarrollo. Cada parte se publica cuando funciona de punta a punta y está
                                probada: permisos, aislamiento entre organizaciones y casos de error incluidos.
                            </p>
                            <ul className="mt-6 flex flex-wrap gap-2">
                                {["React y TypeScript", "PostgreSQL con RLS", "Supabase", "Pruebas automáticas en cada cambio"].map(
                                    (texto) => (
                                        <li key={texto} className="rounded-md bg-elevada px-2.5 py-1 text-xs font-medium">
                                            {texto}
                                        </li>
                                    ),
                                )}
                            </ul>
                            <dl className="mt-8 grid gap-5 border-t border-borde pt-6 sm:grid-cols-2">
                                <div>
                                    <dt className="flex items-center gap-2 text-sm font-semibold">
                                        <ShieldCheck size={16} aria-hidden="true" className="text-acento" />
                                        Permisos en la base de datos
                                    </dt>
                                    <dd className="mt-1 text-sm text-texto-2">
                                        Aunque alguien se salte la pantalla, el servidor rechaza lo que su rol no permite.
                                    </dd>
                                </div>
                                <div>
                                    <dt className="flex items-center gap-2 text-sm font-semibold">
                                        <Building2 size={16} aria-hidden="true" className="text-acento" />
                                        Una agencia, sus datos
                                    </dt>
                                    <dd className="mt-1 text-sm text-texto-2">
                                        Se prueba que nadie de otra organización pueda leer, cambiar ni borrar nada.
                                    </dd>
                                </div>
                            </dl>
                        </div>

                        <div className="flex flex-col gap-4">
                            {estadoProducto.map(({ grupo, elementos }) => (
                                <div key={grupo} className="rounded-xl border border-borde bg-superficie p-5">
                                    <EtiquetaDisponibilidad valor={grupo} />
                                    <ul className="mt-3 grid gap-x-6 gap-y-2 text-sm sm:grid-cols-2">
                                        {elementos.map((texto) => (
                                            <li key={texto} className="flex items-start gap-2">
                                                <span className="mt-2 size-1 shrink-0 rounded-full bg-texto-2" aria-hidden="true" />
                                                {texto}
                                            </li>
                                        ))}
                                    </ul>
                                </div>
                            ))}
                        </div>
                    </div>
                </section>

                {/* Llamada final */}
                <section className="relative overflow-hidden border-t border-borde px-4 py-20 sm:px-8 lg:px-12">
                    <div
                        aria-hidden="true"
                        className="pointer-events-none absolute bottom-0 left-1/2 h-[300px] w-[600px] -translate-x-1/2 rounded-full bg-acento/10 blur-[140px]"
                    />
                    <div className="relative mx-auto flex max-w-5xl flex-col items-center gap-4 rounded-2xl border border-borde bg-superficie px-6 py-14 text-center sm:px-12">
                        <p className={claseEtiquetaSeccion}>Vista previa abierta</p>
                        <h2 className="max-w-2xl text-[2rem] leading-tight font-semibold tracking-[-0.025em] text-balance sm:text-[3rem]">
                            Ordena el trabajo de tu equipo desde hoy.
                        </h2>
                        <p className="max-w-xl text-texto-2">
                            Crea tu organización, tus proyectos y tus tareas, y deja que Nexo te avise de lo que se queda
                            atrás.
                        </p>
                        <div className="mt-4 flex flex-wrap items-center justify-center gap-3">
                            <a href={enlaceRegistro} className={`${claseBotonPrincipal} group`}>
                                Crear cuenta
                                <ArrowRight size={16} aria-hidden="true" className="transicion group-hover:translate-x-0.5" />
                            </a>
                            <a href={enlaceDemostracion} className={claseBotonSecundario}>
                                Ver la demostración
                            </a>
                        </div>
                        <ul className="mt-3 flex flex-wrap items-center justify-center gap-x-5 gap-y-2 text-xs text-texto-2">
                            {["Datos aislados por organización", "Tres roles con permisos claros", "Tema claro y oscuro"].map(
                                (texto) => (
                                    <li key={texto} className="flex items-center gap-1.5">
                                        <Check size={14} aria-hidden="true" className="text-acento" />
                                        {texto}
                                    </li>
                                ),
                            )}
                        </ul>
                    </div>
                </section>
            </main>

            <footer className="border-t border-borde bg-superficie/50 px-4 py-12 sm:px-8 lg:px-12">
                <div className="mx-auto max-w-7xl">
                    <div className="flex flex-col items-start justify-between gap-4 border-b border-borde pb-8 sm:flex-row sm:items-center">
                        <MarcaNexo />
                        <p className="inline-flex items-center gap-2 rounded-full border border-borde bg-superficie px-3 py-1 text-xs text-texto-2">
                            <span className="size-1.5 rounded-full bg-acento" aria-hidden="true" />
                            Vista previa en desarrollo
                        </p>
                    </div>
                    <div className="grid grid-cols-2 gap-8 py-8 sm:grid-cols-3">
                        <ColumnaPie
                            titulo="Producto"
                            enlaces={[
                                { href: "#capacidades", texto: "Capacidades" },
                                { href: "#como-funciona", texto: "Cómo funciona" },
                                { href: "#estado", texto: "Estado del producto" },
                            ]}
                        />
                        <ColumnaPie
                            titulo="Probar Nexo"
                            enlaces={[
                                { href: enlaceDemostracion, texto: "Demostración" },
                                { href: enlaceRegistro, texto: "Crear cuenta" },
                                { href: enlaceEspacio, texto: "Iniciar sesión" },
                            ]}
                        />
                        <div className="col-span-2 sm:col-span-1 sm:hidden">
                            <SelectorTema preferencia={preferencia} alElegir={alElegirTema} />
                        </div>
                    </div>
                    <p className="border-t border-borde pt-6 text-xs text-texto-2">
                        Nexo · vista previa. La demostración usa datos ficticios.
                    </p>
                </div>
            </footer>
        </div>
    );
}

function Tarjeta({
    className,
    Icono,
    titulo,
    estado,
    texto,
    children,
}: {
    className: string;
    Icono: LucideIcon;
    titulo: string;
    estado: Disponibilidad;
    texto: string;
    children: ReactNode;
}) {
    return (
        <article
            className={`transicion flex flex-col justify-between gap-6 rounded-2xl border border-borde bg-fondo p-6 hover:border-borde-fuerte ${className}`}
        >
            <div>
                <div className="flex items-center justify-between gap-3">
                    <span className="inline-flex size-10 items-center justify-center rounded-lg bg-elevada text-acento">
                        <Icono size={20} aria-hidden="true" />
                    </span>
                    <EtiquetaDisponibilidad valor={estado} />
                </div>
                <h3 className="mt-5 text-xl font-semibold tracking-[-0.01em]">{titulo}</h3>
                <p className="mt-2 max-w-xl text-sm leading-relaxed text-texto-2">{texto}</p>
            </div>
            {children}
        </article>
    );
}

function Pieza({ tono, children }: { tono?: "acento" | "atencion"; children: ReactNode }) {
    const clase =
        tono === "acento"
            ? "bg-acento-suave font-semibold text-acento"
            : tono === "atencion"
              ? "bg-atencion-suave font-semibold text-atencion"
              : "bg-elevada";
    return <span className={`rounded px-2 py-0.5 ${clase}`}>{children}</span>;
}

function ColumnaPie({ titulo, enlaces }: { titulo: string; enlaces: { href: string; texto: string }[] }) {
    return (
        <div>
            <p className="text-[11px] font-semibold tracking-[0.1em] uppercase">{titulo}</p>
            <ul className="mt-3 flex flex-col gap-2">
                {enlaces.map(({ href, texto }) => (
                    <li key={texto}>
                        <a href={href} className="transicion rounded text-sm text-texto-2 hover:text-texto">
                            {texto}
                        </a>
                    </li>
                ))}
            </ul>
        </div>
    );
}
