import { useEffect, useState } from "react";

// Dos vistas en esta entrega: no hace falta un enrutador. El hash permite
// enlazar la demostración y que el botón "atrás" del navegador funcione.
export type Vista = "portada" | "demostracion";

export const enlaceDemostracion = "#/demostracion";
export const enlacePortada = "#/";

function vistaActual(): Vista {
    return window.location.hash === enlaceDemostracion ? "demostracion" : "portada";
}

export function useVista(): Vista {
    const [vista, setVista] = useState<Vista>(vistaActual);

    useEffect(() => {
        const alCambiar = () => setVista(vistaActual());
        window.addEventListener("hashchange", alCambiar);
        return () => window.removeEventListener("hashchange", alCambiar);
    }, []);

    return vista;
}
