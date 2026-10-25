import { useCallback, useEffect, useState } from "react";

// Estado de una lectura del backend: cargando, lista o con error. Al recargar
// se conservan los datos anteriores hasta que llegan los nuevos, para que la
// pantalla no salte.
export type Carga<T> =
    | { estado: "cargando" }
    | { estado: "listo"; datos: T }
    | { estado: "error"; error: unknown };

// "cargar" debe venir de useCallback: la lectura se repite cuando cambia.
export function useCarga<T>(cargar: () => Promise<T>) {
    const [carga, setCarga] = useState<Carga<T>>({ estado: "cargando" });
    const [version, setVersion] = useState(0);

    useEffect(() => {
        let vigente = true;
        cargar().then(
            (datos) => {
                if (vigente) setCarga({ estado: "listo", datos });
            },
            (error: unknown) => {
                if (vigente) setCarga({ estado: "error", error });
            },
        );
        return () => {
            vigente = false;
        };
    }, [cargar, version]);

    const recargar = useCallback(() => setVersion((actual) => actual + 1), []);

    return { carga, recargar };
}
