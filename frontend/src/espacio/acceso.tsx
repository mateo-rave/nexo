import type { SupabaseClient } from "@supabase/supabase-js";
import { LogIn, UserPlus } from "lucide-react";
import { useState, type FormEvent } from "react";
import { MarcaNexo } from "../componentes/simbolo_nexo.tsx";
import { Aviso, AvisoError, Campo, claseBotonPrincipal, claseCampo } from "./ui.tsx";

type Modo = "entrar" | "registrarse";

// Inicio de sesión y registro con Supabase Auth (correo y contraseña,
// ADR-0002). nombre_visible viaja en los datos del registro y lo lee el
// trigger crear_perfil; solo se usa para mostrar, nunca para autorizar.
export function Acceso({ cliente }: { cliente: SupabaseClient }) {
    const [modo, setModo] = useState<Modo>("entrar");
    const [correo, setCorreo] = useState("");
    const [contrasena, setContrasena] = useState("");
    const [nombreVisible, setNombreVisible] = useState("");
    const [enviando, setEnviando] = useState(false);
    const [error, setError] = useState<unknown>(null);
    const [confirmacionPendiente, setConfirmacionPendiente] = useState(false);

    async function enviar(evento: FormEvent) {
        evento.preventDefault();
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

    return (
        <div className="flex min-h-dvh items-center justify-center px-4 py-10">
            <main id="contenido" tabIndex={-1} className="w-full max-w-sm outline-none">
                <a href="#/" className="inline-flex rounded-md" aria-label="Nexo, portada">
                    <MarcaNexo />
                </a>
                <h1 className="mt-8 text-2xl font-semibold tracking-tight">
                    {modo === "entrar" ? "Inicia sesión" : "Crea tu cuenta"}
                </h1>
                <p className="mt-1 text-sm text-texto-2">
                    {modo === "entrar"
                        ? "Entra para ver los proyectos y tareas de tu organización."
                        : "Con tu cuenta podrás crear una organización o unirte a una."}
                </p>

                <form onSubmit={enviar} className="mt-6 flex flex-col gap-4">
                    {modo === "registrarse" && (
                        <Campo etiqueta="Nombre visible">
                            <input
                                className={claseCampo}
                                value={nombreVisible}
                                onChange={(e) => setNombreVisible(e.target.value)}
                                required
                                maxLength={100}
                                autoComplete="name"
                            />
                        </Campo>
                    )}
                    <Campo etiqueta="Correo">
                        <input
                            className={claseCampo}
                            type="email"
                            value={correo}
                            onChange={(e) => setCorreo(e.target.value)}
                            required
                            autoComplete="email"
                        />
                    </Campo>
                    <div className="flex flex-col gap-1.5">
                        <Campo etiqueta="Contraseña">
                            <input
                                className={claseCampo}
                                type="password"
                                value={contrasena}
                                onChange={(e) => setContrasena(e.target.value)}
                                required
                                minLength={8}
                                aria-describedby={modo === "registrarse" ? "ayuda-contrasena" : undefined}
                                autoComplete={modo === "entrar" ? "current-password" : "new-password"}
                            />
                        </Campo>
                        {/* El límite se ve junto al campo, no solo al fallar. */}
                        {modo === "registrarse" && (
                            <p id="ayuda-contrasena" className="text-xs text-texto-2">
                                Al menos 8 caracteres.
                            </p>
                        )}
                    </div>

                    {error !== null && <AvisoError error={error} />}
                    {confirmacionPendiente && (
                        <Aviso tono="informacion">
                            Te enviamos un correo para confirmar la cuenta. Cuando lo confirmes, podrás iniciar sesión.
                        </Aviso>
                    )}

                    <button type="submit" className={claseBotonPrincipal} disabled={enviando}>
                        {modo === "entrar" ? <LogIn size={16} aria-hidden="true" /> : <UserPlus size={16} aria-hidden="true" />}
                        {enviando ? "Enviando…" : modo === "entrar" ? "Entrar" : "Crear cuenta"}
                    </button>
                </form>

                <button
                    type="button"
                    onClick={() => {
                        setModo(modo === "entrar" ? "registrarse" : "entrar");
                        setError(null);
                        setConfirmacionPendiente(false);
                    }}
                    className="transicion mt-4 rounded text-sm font-medium text-acento hover:underline"
                >
                    {modo === "entrar" ? "¿No tienes cuenta? Créala" : "¿Ya tienes cuenta? Inicia sesión"}
                </button>
            </main>
        </div>
    );
}
