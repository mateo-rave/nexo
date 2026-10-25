import { createClient, type SupabaseClient } from "@supabase/supabase-js";

// Cliente de Supabase del navegador (ADR-0006). Solo usa la URL del proyecto y
// la clave publicable: la seguridad la aplican RLS y las RPC del backend.
// Vite solo envía al navegador las variables con prefijo VITE_; ninguna clave
// secreta puede llevarlo (CLAUDE.md, sección 7).

export type Configuracion =
    | { lista: true; cliente: SupabaseClient }
    | { lista: false; motivo: string };

function crearConfiguracion(): Configuracion {
    const url: string | undefined = import.meta.env.VITE_SUPABASE_URL;
    const clave: string | undefined = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

    if (!url || !clave) {
        return {
            lista: false,
            motivo:
                "Faltan VITE_SUPABASE_URL y VITE_SUPABASE_PUBLISHABLE_KEY. Crea frontend/.env.local con la URL del proyecto de Supabase y su clave publicable.",
        };
    }

    // Defensa adicional: una clave secreta (sb_secret_...) o una clave heredada
    // con formato JWT nunca debe llegar al navegador.
    if (!clave.startsWith("sb_publishable_")) {
        return {
            lista: false,
            motivo:
                "VITE_SUPABASE_PUBLISHABLE_KEY debe ser la clave publicable (sb_publishable_...). Nunca uses una clave secreta en el frontend.",
        };
    }

    return {
        lista: true,
        cliente: createClient(url, clave, {
            auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: "pkce" },
        }),
    };
}

export const configuracion = crearConfiguracion();
