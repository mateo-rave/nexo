// Símbolo de Nexo: tres nodos conectados; el último, en turquesa, es el
// trabajo que llega a su resultado.
export function SimboloNexo({ tamano = 28 }: { tamano?: number }) {
    return (
        <svg
            width={tamano}
            height={tamano}
            viewBox="0 0 32 32"
            fill="none"
            aria-hidden="true"
            className="shrink-0"
        >
            <rect width="32" height="32" rx="8" className="fill-elevada" />
            <path
                d="M8 22 L16 10 L24 22"
                className="stroke-texto-2"
                strokeWidth="2.25"
                strokeLinecap="round"
                strokeLinejoin="round"
            />
            <circle cx="8" cy="22" r="3" className="fill-elevada stroke-texto" strokeWidth="2" />
            <circle cx="16" cy="10" r="3" className="fill-elevada stroke-texto" strokeWidth="2" />
            <circle cx="24" cy="22" r="3.25" className="fill-acento" />
        </svg>
    );
}

export function MarcaNexo() {
    return (
        <span className="inline-flex items-center gap-2.5">
            <SimboloNexo />
            <span className="text-[17px] font-semibold tracking-tight">Nexo</span>
        </span>
    );
}
