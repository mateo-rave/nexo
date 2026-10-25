import { useEffect } from "react";
import { PanelDemostracion } from "./demostracion/panel_demostracion.tsx";
import { Portada } from "./portada/portada.tsx";
import { useVista } from "./ruta/ruta.ts";
import { useTema } from "./tema/tema.ts";

const titulos = {
    portada: "Nexo · Que nada se quede a mitad de camino",
    demostracion: "Panel (demostración) · Nexo",
} as const;

export function Aplicacion() {
    const { preferencia, elegirPreferencia } = useTema();
    const vista = useVista();

    useEffect(() => {
        document.title = titulos[vista];
        window.scrollTo({ top: 0 });
    }, [vista]);

    return (
        <>
            {/* Mueve el foco sin tocar el hash: el hash decide la vista. */}
            <a
                href="#contenido"
                onClick={(evento) => {
                    evento.preventDefault();
                    document.getElementById("contenido")?.focus();
                }}
                className="sr-only rounded-md bg-acento px-3 py-2 text-sm font-medium text-sobre-acento focus:not-sr-only focus:fixed focus:top-3 focus:left-3 focus:z-50"
            >
                Saltar al contenido
            </a>
            {vista === "demostracion" ? (
                <PanelDemostracion preferencia={preferencia} alElegirTema={elegirPreferencia} />
            ) : (
                <Portada preferencia={preferencia} alElegirTema={elegirPreferencia} />
            )}
        </>
    );
}
