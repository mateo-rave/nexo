import type { Session, SupabaseClient } from "@supabase/supabase-js";
import { useEffect, useState } from "react";

// Sesión de Supabase Auth. undefined mientras se lee la sesión guardada; null
// si no hay sesión. La sesión vive en el navegador (ADR-0006).
// "use" lo exige React para reconocer los hooks (ADR-0005).
export function useSesion(cliente: SupabaseClient): Session | null | undefined {
    const [sesion, setSesion] = useState<Session | null | undefined>(undefined);

    useEffect(() => {
        let vigente = true;
        cliente.auth.getSession().then(({ data }) => {
            if (vigente) setSesion(data.session);
        });
        const { data } = cliente.auth.onAuthStateChange((_evento, nueva) => setSesion(nueva));
        return () => {
            vigente = false;
            data.subscription.unsubscribe();
        };
    }, [cliente]);

    return sesion;
}
