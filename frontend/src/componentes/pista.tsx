import { useEffect, useId, useState, type ReactNode } from "react";

// Pista contextual accesible (WCAG 1.4.13):
// - se abre al pasar el cursor, al enfocar con el teclado o al tocar;
// - se mantiene mientras el cursor está sobre el disparador o sobre la pista;
// - se cierra con Escape, al perder el foco o al salir el cursor.
// El disparador debe ser un elemento interactivo nativo (normalmente <button>).

export type AtributosDisparador = {
    "aria-describedby": string;
    onFocus: () => void;
    onBlur: () => void;
    onClick: () => void;
};

type Propiedades = {
    contenido: ReactNode;
    // Alineación horizontal respecto al disparador, para no salirse por los bordes.
    alinear?: "centro" | "inicio" | "fin";
    className?: string;
    children: (atributos: AtributosDisparador) => ReactNode;
};

const alineaciones = {
    centro: "left-1/2 -translate-x-1/2",
    inicio: "left-0",
    fin: "right-0",
};

export function Pista({ contenido, alinear = "centro", className = "", children }: Propiedades) {
    const id = useId();
    const [abierta, setAbierta] = useState(false);

    useEffect(() => {
        if (!abierta) return;
        const alPulsar = (evento: KeyboardEvent) => {
            if (evento.key === "Escape") setAbierta(false);
        };
        document.addEventListener("keydown", alPulsar);
        return () => document.removeEventListener("keydown", alPulsar);
    }, [abierta]);

    return (
        <span
            className={`relative inline-flex ${className}`}
            onMouseEnter={() => setAbierta(true)}
            onMouseLeave={() => setAbierta(false)}
        >
            {children({
                // Siempre enlazada: la descripción existe aunque la pista esté oculta.
                "aria-describedby": id,
                onFocus: () => setAbierta(true),
                onBlur: () => setAbierta(false),
                // Al tocar en pantallas táctiles: abre (no alterna, porque el foco ya la abrió).
                onClick: () => setAbierta(true),
            })}
            <span
                role="tooltip"
                id={id}
                hidden={!abierta}
                className={`aparecer absolute bottom-full z-20 mb-2 w-max max-w-[260px] rounded-lg border border-borde-fuerte bg-superficie px-3 py-2 text-left text-xs leading-relaxed text-texto shadow-md ${alineaciones[alinear]}`}
            >
                {contenido}
            </span>
        </span>
    );
}
