import { useCallback, useEffect, useState } from "react";

// "sistema" sigue prefers-color-scheme; "claro" y "oscuro" son una elección
// explícita del usuario y se guardan en el navegador.
export type PreferenciaTema = "sistema" | "claro" | "oscuro";
export type Tema = "claro" | "oscuro";

// Debe coincidir con el script de index.html.
const claveAlmacen = "nexo-tema";
const consultaOscuro = "(prefers-color-scheme: dark)";

function leerPreferencia(): PreferenciaTema {
    try {
        const guardada = localStorage.getItem(claveAlmacen);
        if (guardada === "claro" || guardada === "oscuro") {
            return guardada;
        }
    } catch {
        // Sin acceso al almacenamiento (modo privado o bloqueado): se sigue al sistema.
    }
    return "sistema";
}

function temaDelSistema(): Tema {
    return window.matchMedia(consultaOscuro).matches ? "oscuro" : "claro";
}

function guardarPreferencia(preferencia: PreferenciaTema): void {
    try {
        if (preferencia === "sistema") {
            localStorage.removeItem(claveAlmacen);
        } else {
            localStorage.setItem(claveAlmacen, preferencia);
        }
    } catch {
        // Si no se puede guardar, la elección dura solo esta visita.
    }
}

// "use" lo exige React para reconocer los hooks (ADR-0005).
export function useTema() {
    const [preferencia, setPreferencia] = useState<PreferenciaTema>(leerPreferencia);
    const [sistema, setSistema] = useState<Tema>(temaDelSistema);

    useEffect(() => {
        const consulta = window.matchMedia(consultaOscuro);
        const alCambiar = () => setSistema(consulta.matches ? "oscuro" : "claro");
        consulta.addEventListener("change", alCambiar);
        return () => consulta.removeEventListener("change", alCambiar);
    }, []);

    const tema: Tema = preferencia === "sistema" ? sistema : preferencia;

    useEffect(() => {
        document.documentElement.dataset.tema = tema;
    }, [tema]);

    const elegirPreferencia = useCallback((nueva: PreferenciaTema) => {
        setPreferencia(nueva);
        guardarPreferencia(nueva);
    }, []);

    return { preferencia, tema, elegirPreferencia };
}
