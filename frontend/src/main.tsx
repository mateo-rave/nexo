import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { Aplicacion } from "./aplicacion.tsx";
import "./estilos.css";

const raiz = document.getElementById("raiz");
if (!raiz) {
    throw new Error("Falta el elemento #raiz en index.html.");
}

createRoot(raiz).render(
    <StrictMode>
        <Aplicacion />
    </StrictMode>,
);
