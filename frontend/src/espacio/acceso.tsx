import type { SupabaseClient } from "@supabase/supabase-js";
import {
    ArrowLeft,
    ArrowRight,
    CircleAlert,
    CircleCheck,
    Eye,
    EyeOff,
    LoaderCircle,
    LockKeyhole,
    Mail,
    UserRound,
    UserRoundPlus,
    type LucideIcon,
} from "lucide-react";
import {
    useEffect,
    useId,
    useState,
    type CSSProperties,
    type FormEvent,
    type InputHTMLAttributes,
    type ReactElement,
    type ReactNode,
} from "react";
import { MarcaNexo } from "../componentes/simbolo_nexo.tsx";
import { enlaceDemostracion, enlaceEspacio, enlacePortada, enlaceRegistro } from "../ruta/ruta.ts";
import { PanelAcceso } from "./panel_acceso.tsx";
import { Aviso, AvisoError } from "./ui.tsx";

type Modo = "entrar" | "registrarse";

type Errores = Partial<Record<"nombre" | "correo" | "contrasena", string>>;

const longitudMinima = 8;

function modoSegunEnlace(): Modo {
    return window.location.hash === enlaceRegistro ? "registrarse" : "entrar";
}

// Ayuda de usabilidad antes de enviar; las reglas reales las aplica Supabase
// Auth y su respuesta se muestra igualmente.
function validar(modo: Modo, nombre: string, correo: string, contrasena: string): Errores {
    const errores: Errores = {};
    if (modo === "registrarse" && nombre.trim() === "") errores.nombre = "Escribe cómo quieres que te vea tu equipo.";
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(correo.trim())) errores.correo = "Escribe un correo válido, como nombre@agencia.com.";
    if (modo === "registrarse" && contrasena.length < longitudMinima) {
        errores.contrasena = `La contraseña necesita al menos ${longitudMinima} caracteres.`;
    } else if (contrasena === "") {
        errores.contrasena = "Escribe tu contraseña.";
    }
    return errores;
}

// Inicio de sesión y registro con Supabase Auth (correo y contraseña,
// ADR-0002). nombre_visible viaja en los datos del registro y lo lee el
// trigger crear_perfil; solo se usa para mostrar, nunca para autorizar.
export function Acceso({ cliente }: { cliente: SupabaseClient }) {
    const [modo, setModo] = useState<Modo>(modoSegunEnlace);
    const [correo, setCorreo] = useState("");
    const [contrasena, setContrasena] = useState("");
    const [nombreVisible, setNombreVisible] = useState("");
    const [enviando, setEnviando] = useState(false);
    const [error, setError] = useState<unknown>(null);
    const [errores, setErrores] = useState<Errores>({});
    const [confirmacionPendiente, setConfirmacionPendiente] = useState(false);

    const registro = modo === "registrarse";

    // Si la dirección cambia con el formulario ya abierto (por ejemplo, al
    // volver a #/app tras cerrar la sesión), el formulario la sigue.
    useEffect(() => {
        const alCambiar = () => setModo(modoSegunEnlace());
        window.addEventListener("hashchange", alCambiar);
        return () => window.removeEventListener("hashchange", alCambiar);
    }, []);

    async function enviar(evento: FormEvent) {
        evento.preventDefault();
        if (enviando) return;
        const encontrados = validar(modo, nombreVisible, correo, contrasena);
        setErrores(encontrados);
        if (Object.keys(encontrados).length > 0) {
            const primero = (["nombre", "correo", "contrasena"] as const).find((campo) => encontrados[campo]);
            document.getElementById(`acceso-${primero}`)?.focus();
            return;
        }

        setEnviando(true);
        setError(null);
        setConfirmacionPendiente(false);

        if (modo === "entrar") {
            const { error: fallo } = await cliente.auth.signInWithPassword({ email: correo, password: contrasena });
            if (fallo) setError(fallo);
        } else {
            const { data, error: fallo } = await cliente.auth.signUp({
                email: correo,
                password: contrasena,
                options: {
                    data: { nombre_visible: nombreVisible },
                    emailRedirectTo: `${window.location.origin}/`,
                },
            });
            if (fallo) {
                setError(fallo);
            } else if (!data.session) {
                // Con la confirmación de correo activada no hay sesión hasta
                // confirmar: no se simula que la cuenta ya está lista.
                setConfirmacionPendiente(true);
            }
        }
        setEnviando(false);
    }

    function cambiarModo() {
        const siguiente = registro ? "entrar" : "registrarse";
        setModo(siguiente);
        setError(null);
        setErrores({});
        setConfirmacionPendiente(false);
        // El enlace refleja el formulario visible sin crear entradas de historial.
        window.history.replaceState(null, "", siguiente === "registrarse" ? enlaceRegistro : enlaceEspacio);
    }

    // Al corregir un campo, su aviso desaparece.
    function limpiar(campo: keyof Errores) {
        if (errores[campo]) setErrores({ ...errores, [campo]: undefined });
    }

    return (
        <div className="min-h-dvh lg:grid lg:grid-cols-[minmax(0,1fr)_minmax(0,1.05fr)]">
            <div className="flex min-h-dvh flex-col px-5 py-6 sm:px-10 sm:py-8 xl:px-14">
                <div className="entrada flex items-center justify-between gap-4">
                    <a href={enlacePortada} className="rounded-md" aria-label="Nexo, portada">
                        <MarcaNexo />
                    </a>
                    <a
                        href={enlacePortada}
                        className="transicion inline-flex items-center gap-1.5 rounded-md px-2 py-1 text-[13px] text-texto-2 hover:text-texto"
                    >
                        <ArrowLeft size={14} aria-hidden="true" />
                        Portada
                    </a>
                </div>

                <main id="contenido" tabIndex={-1} className="my-auto w-full max-w-[400px] self-center py-10 outline-none">
                    <div className="entrada" style={{ "--retraso": "40ms" } as CSSProperties}>
                        <h1 className="text-[1.75rem] leading-tight font-semibold tracking-[-0.02em]">
                            {registro ? "Crea tu cuenta" : "Inicia sesión"}
                        </h1>
                        <p className="mt-2 text-[15px] text-pretty text-texto-2">
                            {registro
                                ? "Con tu cuenta podrás crear una organización o unirte a una."
                                : "Entra para ver los proyectos y tareas de tu organización."}
                        </p>
                    </div>

                    <form onSubmit={enviar} noValidate className="mt-8 flex flex-col gap-5" aria-busy={enviando}>
                        {registro && (
                            <CampoAcceso
                                id="acceso-nombre"
                                etiqueta="Nombre visible"
                                Icono={UserRound}
                                error={errores.nombre}
                                retraso={80}
                                entrada={
                                    <input
                                        value={nombreVisible}
                                        onChange={(e) => {
                                            setNombreVisible(e.target.value);
                                            limpiar("nombre");
                                        }}
                                        placeholder="Ej.: Carlos Méndez"
                                        maxLength={100}
                                        autoComplete="name"
                                    />
                                }
                            />
                        )}
                        <CampoAcceso
                            id="acceso-correo"
                            etiqueta="Correo"
                            Icono={Mail}
                            error={errores.correo}
                            retraso={registro ? 120 : 80}
                            entrada={
                                <input
                                    type="email"
                                    value={correo}
                                    onChange={(e) => {
                                        setCorreo(e.target.value);
                                        limpiar("correo");
                                    }}
                                    placeholder="nombre@agencia.com"
                                    autoComplete="email"
                                    inputMode="email"
                                />
                            }
                        />
                        <CampoContrasena
                            valor={contrasena}
                            alCambiar={(valor) => {
                                setContrasena(valor);
                                limpiar("contrasena");
                            }}
                            registro={registro}
                            error={errores.contrasena}
                            retraso={registro ? 160 : 120}
                        />

                        {error !== null && (
                            <div className="aparecer">
                                <AvisoError error={error} />
                            </div>
                        )}
                        {confirmacionPendiente && (
                            <div className="aparecer">
                                <Aviso tono="informacion">
                                    Te enviamos un correo para confirmar la cuenta. Cuando lo confirmes, podrás iniciar
                                    sesión.
                                </Aviso>
                            </div>
                        )}

                        <div className="entrada" style={{ "--retraso": `${registro ? 200 : 160}ms` } as CSSProperties}>
                            <button
                                type="submit"
                                disabled={enviando}
                                className="transicion group inline-flex min-h-11 w-full items-center justify-center gap-2 rounded-lg bg-acento px-4 text-sm font-semibold text-sobre-acento shadow-[0_8px_24px_-12px_var(--acento)] hover:brightness-110 hover:shadow-[0_10px_28px_-10px_var(--acento)] active:scale-[0.985] disabled:cursor-wait disabled:opacity-70 disabled:hover:brightness-100"
                            >
                                {enviando ? (
                                    <LoaderCircle size={16} aria-hidden="true" className="animate-spin" />
                                ) : registro ? (
                                    <UserRoundPlus size={16} aria-hidden="true" />
                                ) : null}
                                {enviando ? (registro ? "Creando la cuenta…" : "Entrando…") : registro ? "Crear cuenta" : "Entrar"}
                                {!enviando && !registro && (
                                    <ArrowRight size={16} aria-hidden="true" className="transicion group-hover:translate-x-0.5" />
                                )}
                            </button>
                        </div>
                    </form>

                    <p
                        className="entrada mt-6 text-center text-sm text-texto-2"
                        style={{ "--retraso": `${registro ? 240 : 200}ms` } as CSSProperties}
                    >
                        <button
                            type="button"
                            onClick={cambiarModo}
                            className="transicion rounded font-medium text-acento hover:underline"
                        >
                            {registro ? "¿Ya tienes cuenta? Inicia sesión" : "¿No tienes cuenta? Créala"}
                        </button>
                    </p>
                </main>

                <div className="entrada flex flex-wrap items-center justify-between gap-3 border-t border-borde pt-5 text-xs text-texto-2" style={{ "--retraso": "260ms" } as CSSProperties}>
                    <span>Los datos de cada organización están aislados del resto.</span>
                    <a href={enlaceDemostracion} className="transicion rounded hover:text-texto">
                        Ver la demostración
                    </a>
                </div>
            </div>

            {/* El panel visual acompaña al formulario en pantallas anchas; en
                móvil se omite para dejar todo el espacio al formulario. */}
            <aside aria-label="Cómo funciona Nexo" className="hidden border-l border-borde bg-superficie lg:block">
                <div className="sticky top-0 h-dvh">
                    <PanelAcceso />
                </div>
            </aside>
        </div>
    );
}

function CampoAcceso({
    id,
    etiqueta,
    Icono,
    error,
    retraso,
    entrada,
    extra,
    ayuda,
}: {
    id: string;
    etiqueta: string;
    Icono: LucideIcon;
    error?: string;
    retraso: number;
    entrada: ReactElement<InputHTMLAttributes<HTMLInputElement>>;
    extra?: ReactNode;
    ayuda?: ReactNode;
}) {
    const base = useId();
    const idError = `${base}-error`;
    const idAyuda = `${base}-ayuda`;
    const descritoPor = [ayuda ? idAyuda : null, error ? idError : null].filter(Boolean).join(" ") || undefined;
    const props = entrada.props;

    return (
        <div className="entrada flex flex-col gap-2" style={{ "--retraso": `${retraso}ms` } as CSSProperties}>
            <label htmlFor={id} className="text-sm font-medium">
                {etiqueta}
            </label>
            <div
                className={`transicion group flex min-h-11 items-center gap-2.5 rounded-lg border bg-superficie px-3 focus-within:shadow-[0_0_0_3px_var(--acento-suave)] ${
                    error ? "border-error" : "border-borde-fuerte hover:border-texto-2/50 focus-within:border-acento"
                }`}
            >
                <Icono
                    size={16}
                    aria-hidden="true"
                    className={`transicion shrink-0 ${error ? "text-error" : "text-texto-2 group-focus-within:text-acento"}`}
                />
                <input
                    {...props}
                    id={id}
                    aria-invalid={error ? true : undefined}
                    aria-describedby={descritoPor}
                    className="min-w-0 flex-1 bg-transparent py-2.5 text-[15px] text-texto outline-none placeholder:text-texto-2/70 focus-visible:outline-none"
                />
                {extra}
            </div>
            {ayuda && <div id={idAyuda}>{ayuda}</div>}
            {error && (
                <p id={idError} className="aparecer flex items-start gap-1.5 text-[13px] text-error">
                    <CircleAlert size={14} aria-hidden="true" className="mt-0.5 shrink-0" />
                    {error}
                </p>
            )}
        </div>
    );
}

function CampoContrasena({
    valor,
    alCambiar,
    registro,
    error,
    retraso,
}: {
    valor: string;
    alCambiar: (valor: string) => void;
    registro: boolean;
    error?: string;
    retraso: number;
}) {
    const [visible, setVisible] = useState(false);
    const cumple = valor.length >= longitudMinima;
    const progreso = Math.min(valor.length / longitudMinima, 1);

    return (
        <CampoAcceso
            id="acceso-contrasena"
            etiqueta="Contraseña"
            Icono={LockKeyhole}
            error={error}
            retraso={retraso}
            entrada={
                <input
                    type={visible ? "text" : "password"}
                    value={valor}
                    onChange={(e) => alCambiar(e.target.value)}
                    autoComplete={registro ? "new-password" : "current-password"}
                />
            }
            extra={
                <button
                    type="button"
                    onClick={() => setVisible(!visible)}
                    aria-pressed={visible}
                    title={visible ? "Ocultar contraseña" : "Mostrar contraseña"}
                    className="transicion -mr-1.5 inline-flex size-8 shrink-0 items-center justify-center rounded-md text-texto-2 hover:bg-elevada hover:text-texto"
                >
                    {visible ? <EyeOff size={16} aria-hidden="true" /> : <Eye size={16} aria-hidden="true" />}
                    <span className="sr-only">{visible ? "Ocultar contraseña" : "Mostrar contraseña"}</span>
                </button>
            }
            ayuda={
                registro && (
                    <div className="flex flex-col gap-1.5">
                        <div className="h-1 overflow-hidden rounded-full bg-elevada" aria-hidden="true">
                            <div
                                className={`h-full rounded-full transition-[width,background-color] duration-200 ease-[var(--ease-nexo)] ${cumple ? "bg-exito" : "bg-acento"}`}
                                style={{ width: `${progreso * 100}%` }}
                            />
                        </div>
                        <p className={`flex items-center gap-1.5 text-xs ${cumple ? "text-exito" : "text-texto-2"}`}>
                            {cumple && <CircleCheck size={13} aria-hidden="true" />}
                            Al menos {longitudMinima} caracteres
                            {!cumple && valor.length > 0 && (
                                <span className="tabular-nums">
                                    {" "}
                                    ({valor.length} de {longitudMinima})
                                </span>
                            )}
                        </p>
                    </div>
                )
            }
        />
    );
}
