import { useEffect, useState } from "react";

// Tres vistas: no hace falta un enrutador. El hash permite enlazarlas y que el
// botón "atrás" del navegador funcione.
// - portada;
// - demostracion: panel con datos ficticios, identificados como tales;
// - espacio: la aplicación conectada al backend real (requiere sesión).
export type Vista = "portada" | "demostracion" | "espacio";

export const enlaceDemostracion = "#/demostracion";
export const enlaceEspacio = "#/app";
export const enlacePortada = "#/";

function vistaActual(): Vista {
    const hash = window.location.hash;
    if (hash === enlaceDemostracion) return "demostracion";
    if (hash === enlaceEspacio || hash.startsWith(`${enlaceEspacio}/`)) return "espacio";
    return "portada";
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
