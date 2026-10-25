import type { EstadoTarea } from "../componentes/estados.ts";

// DATOS FICTICIOS DE DEMOSTRACIÓN. No vienen del backend ni representan
// clientes, personas ni métricas reales. Se sustituirán por datos de la API
// a medida que existan las funcionalidades (ADR-0006).
//
// Es la única fuente de la demostración: todas las cifras del panel se
// calculan a partir de esta colección (ver derivados.ts).

export const organizacionDemostracion = "Agencia Ejemplo";

// "Hoy" en la demostración: viernes 23 de octubre de 2026, 09:00. Una fecha
// fija para que los tiempos relativos sean coherentes y no dependan del reloj.
export const fechaReferencia = "2026-10-23T09:00:00";

// A quién se espera para desbloquear. Ilustrativo: hoy no existe en el backend.
export type EsperandoA = "cliente" | "equipo" | "informacion";

export type TareaDemostracion = {
    id: string;
    titulo: string;
    proyecto: string;
    estado: EstadoTarea;
    responsable: string;
    // Sin fecha límite, la tarea no cuenta para vencimientos ni riesgos.
    fechaLimite?: string;
    bloqueo?: {
        desde: string;
        esperandoA: EsperandoA;
        motivo: string;
    };
    // Sugerencia de siguiente paso para las tareas que necesitan intervención.
    // Solo texto: no ejecuta nada.
    accionSugerida?: string;
};

// 41 tareas en 8 proyectos: 9 pendientes, 12 en curso, 4 en revisión y 16
// completadas. 2 proyectos (Catálogo de verano y Auditoría SEO) ya no tienen
// trabajo abierto.
export const tareas: TareaDemostracion[] = [
    // --- Abiertas con alguna señal respecto a la fecha de referencia ---
    {
        id: "t1",
        titulo: "Textos de la página de servicios",
        proyecto: "Rediseño web",
        estado: "en_curso",
        responsable: "Laura M.",
        fechaLimite: "2026-10-22T18:00:00",
        bloqueo: {
            desde: "2026-10-20T08:00:00",
            esperandoA: "cliente",
            motivo: "Falta el contenido que debe enviar el cliente",
        },
        accionSugerida: "Pedir el contenido al cliente",
    },
    {
        id: "t2",
        titulo: "Ajustes del logotipo",
        proyecto: "Identidad de marca",
        estado: "en_curso",
        responsable: "Diego R.",
        fechaLimite: "2026-10-21T18:00:00",
        bloqueo: {
            desde: "2026-10-22T15:00:00",
            esperandoA: "equipo",
            motivo: "Espera la revisión interna de Ana P.",
        },
        accionSugerida: "Pedir a Ana P. que revise los ajustes",
    },
    {
        id: "t3",
        titulo: "Accesos al servidor",
        proyecto: "Migración de tienda",
        estado: "pendiente",
        responsable: "Carlos V.",
        fechaLimite: "2026-10-28T18:00:00",
        bloqueo: {
            desde: "2026-10-22T08:00:00",
            esperandoA: "informacion",
            motivo: "Faltan las credenciales de acceso",
        },
        accionSugerida: "Solicitar las credenciales de acceso",
    },
    {
        id: "t4",
        titulo: "Informe mensual",
        proyecto: "Mantenimiento web",
        estado: "en_curso",
        responsable: "Laura M.",
        fechaLimite: "2026-10-19T18:00:00",
        accionSugerida: "Entregar el informe o acordar una nueva fecha",
    },
    {
        id: "t5",
        titulo: "Calendario de publicaciones",
        proyecto: "Campaña de otoño",
        estado: "en_curso",
        responsable: "Ana P.",
        fechaLimite: "2026-10-22T09:00:00",
        accionSugerida: "Revisar con Ana P. una nueva fecha",
    },
    {
        id: "t6",
        titulo: "Banners de campaña",
        proyecto: "Campaña de otoño",
        estado: "en_curso",
        responsable: "Carlos V.",
        fechaLimite: "2026-10-24T17:00:00",
        accionSugerida: "Confirmar con Carlos V. que llega a tiempo",
    },
    {
        id: "t7",
        titulo: "Propuesta de contenidos",
        proyecto: "Rediseño web",
        estado: "pendiente",
        responsable: "Diego R.",
        fechaLimite: "2026-10-25T09:00:00",
        accionSugerida: "Empezarla hoy para llegar a la fecha",
    },

    // --- Abiertas sin señales: pendientes ---
    { id: "t8", titulo: "Arquitectura de la información", proyecto: "Rediseño web", estado: "pendiente", responsable: "Marta S.", fechaLimite: "2026-10-26T18:00:00" },
    { id: "t9", titulo: "Guía de estilo de marca", proyecto: "Identidad de marca", estado: "pendiente", responsable: "Diego R.", fechaLimite: "2026-11-04T18:00:00" },
    { id: "t10", titulo: "Plan de redirecciones", proyecto: "Migración de tienda", estado: "pendiente", responsable: "Carlos V." },
    { id: "t11", titulo: "Copia de seguridad previa", proyecto: "Migración de tienda", estado: "pendiente", responsable: "Carlos V.", fechaLimite: "2026-10-28T12:00:00" },
    { id: "t12", titulo: "Selección de imágenes", proyecto: "Boletín de noviembre", estado: "pendiente", responsable: "Ana P." },
    { id: "t13", titulo: "Revisión de enlaces rotos", proyecto: "Mantenimiento web", estado: "pendiente", responsable: "Laura M." },
    { id: "t14", titulo: "Textos del boletín", proyecto: "Boletín de noviembre", estado: "pendiente", responsable: "Marta S.", fechaLimite: "2026-11-06T18:00:00" },

    // --- Abiertas sin señales: en curso ---
    { id: "t15", titulo: "Maquetación de la portada", proyecto: "Rediseño web", estado: "en_curso", responsable: "Diego R.", fechaLimite: "2026-10-27T18:00:00" },
    { id: "t16", titulo: "Prototipo de navegación", proyecto: "Rediseño web", estado: "en_curso", responsable: "Marta S.", fechaLimite: "2026-11-02T18:00:00" },
    { id: "t17", titulo: "Aplicaciones del logotipo", proyecto: "Identidad de marca", estado: "en_curso", responsable: "Diego R.", fechaLimite: "2026-10-26T12:00:00" },
    { id: "t18", titulo: "Importación de productos", proyecto: "Migración de tienda", estado: "en_curso", responsable: "Carlos V.", fechaLimite: "2026-11-10T18:00:00" },
    { id: "t19", titulo: "Actualización de plugins", proyecto: "Mantenimiento web", estado: "en_curso", responsable: "Laura M." },
    { id: "t20", titulo: "Anuncios para redes", proyecto: "Campaña de otoño", estado: "en_curso", responsable: "Ana P.", fechaLimite: "2026-11-03T18:00:00" },
    { id: "t21", titulo: "Plantilla del boletín", proyecto: "Boletín de noviembre", estado: "en_curso", responsable: "Marta S." },

    // --- Abiertas sin señales: en revisión ---
    { id: "t22", titulo: "Mapa del sitio", proyecto: "Rediseño web", estado: "en_revision", responsable: "Laura M.", fechaLimite: "2026-11-05T18:00:00" },
    { id: "t23", titulo: "Tipografías corporativas", proyecto: "Identidad de marca", estado: "en_revision", responsable: "Diego R." },
    { id: "t24", titulo: "Textos de los anuncios", proyecto: "Campaña de otoño", estado: "en_revision", responsable: "Ana P.", fechaLimite: "2026-11-01T18:00:00" },
    { id: "t25", titulo: "Informe de rendimiento de septiembre", proyecto: "Mantenimiento web", estado: "en_revision", responsable: "Laura M." },

    // --- Completadas ---
    { id: "t26", titulo: "Brief del proyecto", proyecto: "Rediseño web", estado: "completada", responsable: "Laura M." },
    { id: "t27", titulo: "Análisis de la competencia", proyecto: "Rediseño web", estado: "completada", responsable: "Marta S." },
    { id: "t28", titulo: "Paleta de colores", proyecto: "Identidad de marca", estado: "completada", responsable: "Diego R." },
    { id: "t29", titulo: "Bocetos del logotipo", proyecto: "Identidad de marca", estado: "completada", responsable: "Diego R." },
    { id: "t30", titulo: "Inventario de productos", proyecto: "Migración de tienda", estado: "completada", responsable: "Carlos V." },
    { id: "t31", titulo: "Informe de agosto", proyecto: "Mantenimiento web", estado: "completada", responsable: "Laura M." },
    { id: "t32", titulo: "Renovación del certificado SSL", proyecto: "Mantenimiento web", estado: "completada", responsable: "Carlos V." },
    { id: "t33", titulo: "Concepto creativo", proyecto: "Campaña de otoño", estado: "completada", responsable: "Ana P." },
    { id: "t34", titulo: "Público objetivo", proyecto: "Campaña de otoño", estado: "completada", responsable: "Ana P." },
    { id: "t35", titulo: "Lista de suscriptores", proyecto: "Boletín de noviembre", estado: "completada", responsable: "Marta S." },
    { id: "t36", titulo: "Fotografía de producto", proyecto: "Catálogo de verano", estado: "completada", responsable: "Ana P." },
    { id: "t37", titulo: "Maquetación del catálogo", proyecto: "Catálogo de verano", estado: "completada", responsable: "Diego R." },
    { id: "t38", titulo: "Entrega del catálogo", proyecto: "Catálogo de verano", estado: "completada", responsable: "Laura M." },
    { id: "t39", titulo: "Análisis técnico", proyecto: "Auditoría SEO", estado: "completada", responsable: "Carlos V." },
    { id: "t40", titulo: "Informe de palabras clave", proyecto: "Auditoría SEO", estado: "completada", responsable: "Marta S." },
    { id: "t41", titulo: "Presentación de resultados", proyecto: "Auditoría SEO", estado: "completada", responsable: "Laura M." },
];

export type Actividad = {
    id: string;
    tipo: "completada" | "bloqueo" | "asignacion";
    texto: string;
    // Siempre anterior a la fecha de referencia.
    fecha: string;
};

// Coherente con fechaReferencia y con las tareas de arriba.
export const actividadReciente: Actividad[] = [
    { id: "a1", tipo: "completada", texto: "Diego R. completó «Paleta de colores»", fecha: "2026-10-23T08:48:00" },
    { id: "a2", tipo: "asignacion", texto: "Ana P. asignó «Banners de campaña» a Carlos V.", fecha: "2026-10-23T07:00:00" },
    { id: "a3", tipo: "bloqueo", texto: "Diego R. marcó como bloqueada «Ajustes del logotipo»", fecha: "2026-10-22T15:00:00" },
    { id: "a4", tipo: "bloqueo", texto: "Carlos V. marcó como bloqueada «Accesos al servidor»", fecha: "2026-10-22T08:00:00" },
    { id: "a5", tipo: "bloqueo", texto: "Laura M. marcó como bloqueada «Textos de la página de servicios»", fecha: "2026-10-20T08:00:00" },
];
