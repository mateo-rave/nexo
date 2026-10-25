import { Monitor, Moon, Sun, type LucideIcon } from "lucide-react";
import type { PreferenciaTema } from "../tema/tema.ts";

const opciones: { valor: PreferenciaTema; etiqueta: string; Icono: LucideIcon }[] = [
    { valor: "sistema", etiqueta: "Sistema", Icono: Monitor },
    { valor: "claro", etiqueta: "Claro", Icono: Sun },
    { valor: "oscuro", etiqueta: "Oscuro", Icono: Moon },
];

type Propiedades = {
    preferencia: PreferenciaTema;
    alElegir: (preferencia: PreferenciaTema) => void;
};

// Grupo de opciones nativo: se maneja con el teclado (Tab y flechas) sin código extra.
export function SelectorTema({ preferencia, alElegir }: Propiedades) {
    return (
        <fieldset className="inline-flex items-center rounded-lg border border-borde bg-superficie p-0.5">
            <legend className="sr-only">Tema de la interfaz</legend>
            {opciones.map(({ valor, etiqueta, Icono }) => (
                <label
                    key={valor}
                    title={`Tema: ${etiqueta.toLowerCase()}`}
                    className="transicion relative inline-flex size-8 cursor-pointer items-center justify-center rounded-md text-texto-2 hover:text-texto has-checked:bg-elevada has-checked:text-texto has-focus-visible:outline-2 has-focus-visible:outline-acento"
                >
                    <input
                        type="radio"
                        name="tema"
                        value={valor}
                        checked={preferencia === valor}
                        onChange={() => alElegir(valor)}
                        className="sr-only"
                    />
                    <Icono size={16} aria-hidden="true" />
                    <span className="sr-only">{etiqueta}</span>
                </label>
            ))}
        </fieldset>
    );
}
