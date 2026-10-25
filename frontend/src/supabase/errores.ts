// Mensajes de error para la interfaz, sin filtrar detalles internos
// (CLAUDE.md, sección 10).
// - Las RPC de Nexo devuelven códigos propios PTxyz con un mensaje en español
//   pensado para el usuario: se muestra tal cual.
// - Los errores de Supabase Auth llegan en inglés: se traducen los habituales.
// - Cualquier otro error (red, SQL, PostgREST) recibe un mensaje genérico.

const mensajesAuth: Record<string, string> = {
    invalid_credentials: "El correo o la contraseña no son correctos.",
    email_not_confirmed: "Confirma tu correo antes de iniciar sesión.",
    user_already_exists: "Ya existe una cuenta con ese correo.",
    email_exists: "Ya existe una cuenta con ese correo.",
    weak_password: "La contraseña es demasiado débil: usa al menos 8 caracteres.",
    over_request_rate_limit: "Demasiados intentos. Espera unos minutos e inténtalo de nuevo.",
    over_email_send_rate_limit: "Demasiados intentos. Espera unos minutos e inténtalo de nuevo.",
    signup_disabled: "El registro de cuentas está desactivado.",
};

export function mensajeDeError(error: unknown): string {
    if (error && typeof error === "object") {
        const { code, message } = error as { code?: unknown; message?: unknown };

        if (typeof code === "string" && /^PT\d{3}$/.test(code) && typeof message === "string") {
            return message;
        }
        if (typeof code === "string" && code in mensajesAuth) {
            return mensajesAuth[code];
        }
        if (typeof message === "string" && /fetch|network/i.test(message)) {
            return "No se pudo conectar con el servidor. Revisa tu conexión.";
        }
    }
    return "No se pudo completar la operación. Inténtalo de nuevo.";
}
