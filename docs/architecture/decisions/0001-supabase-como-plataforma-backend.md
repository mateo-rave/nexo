# ADR-0001: Supabase como plataforma de backend

- Estado: Aceptada. Las menciones al frontend en Stitch están superadas por [ADR-0006](0006-frontend-propio-con-react.md); la decisión sobre el backend no cambia.
- Fecha: 2026-10-23 (propuesta y aceptación)

Nota: la decisión de plataforma es firme para el MVP. Al tomarla no existían todavía las cuentas. Actualización del 2026-10-24: ya existen la cuenta de Supabase (con el proyecto de desarrollo `nexo-dev`) y la de GitHub, con el repositorio privado como remoto `origin`. El frontend ya no se hará en Stitch: lo construye Claude Code en el repositorio (ADR-0006). Siguen sin verificar los planes; si esa verificación obliga a cambiar la decisión, se hará con una nueva ADR.
- Responsables: propietario del producto

## Contexto
La primera versión de `CLAUDE.md` proponía Django, Django REST Framework, Celery/Redis y Docker Compose. Aún no había código ni alojamiento contratado. El propietario desarrollaría el frontend en Stitch y preveía publicarlo en Vercel (historia: desde el 2026-10-24 el frontend se construye en el repositorio, ADR-0006). Se necesita un backend que:

- ofrezca autenticación, PostgreSQL y aislamiento multiempresa sin operar servidores propios;
- permita a una persona o equipo pequeño entregar el MVP en el plazo estimado;
- mantenga las reglas de negocio, permisos y acciones sensibles fuera del navegador.

No hay alojamiento contratado; esta decisión es un escenario objetivo, no una contratación.

## Opciones consideradas
1. **Django + DRF alojado aparte (plan original).** Control total de la capa de aplicación, ecosistema maduro de pruebas (pytest). Requiere alojar y operar un servidor web, cola (Celery/Redis) y base de datos; la autenticación con un frontend en otro dominio exige decidir sesiones vs tokens y CORS.
2. **Supabase (PostgreSQL administrado, Auth, Data API, Edge Functions, Cron).** Menos infraestructura que operar; autenticación integrada; aislamiento aplicado en la base de datos con RLS. Obliga a diseñar la seguridad en SQL con rigor, crea dependencia de un proveedor y reparte la lógica entre SQL y TypeScript/Deno.
3. **Híbrido: Supabase para Auth/DB + Django para la lógica.** Dos runtimes, dos lugares de autorización y dos despliegues. Mayor coste sin beneficio demostrado en el MVP.

## Decisión
Opción 2, de forma provisional. Supabase es la plataforma de backend del MVP:

- PostgreSQL de Supabase para persistencia.
- Supabase Auth para identidad y sesiones.
- Data API (PostgREST) para CRUD simple protegido por RLS.
- Funciones SQL (RPC) y triggers para operaciones atómicas cerca de los datos.
- Edge Functions (TypeScript/Deno) para operaciones que requieran secretos, efectos externos u orquestación.
- Supabase Cron (pg_cron) para comprobaciones programadas.
- Realtime solo si una funcionalidad concreta lo necesita.

Durante el MVP **no** se usarán Django, DRF, Celery ni Redis, y no se mantendrán dos implementaciones de autenticación o API.

## Consecuencias
- La autorización se concentra en RLS, restricciones y funciones SQL; los errores de diseño en políticas son el riesgo principal (ver ADR-0002).
- Las pruebas pasan de pytest a pgTAP (SQL) y pruebas TypeScript (ver ADR-0004).
- Existe dependencia del proveedor (lock-in). Se mitiga manteniendo el esquema en migraciones SQL estándar de PostgreSQL y aislando el código específico de Supabase en las Edge Functions.
- Límites de plan (backups, número de proyectos, tiempos de ejecución de Edge Functions, cuotas) deben verificarse al elegir plan; no se asumen.
- El entorno local completo de Supabase CLI requiere Docker, que hoy no está instalado (ver ADR-0004).
- Se reemplaza la sección de stack de `CLAUDE.md`. Como el repositorio aún no tiene historial Git, la propuesta anterior (Django) queda registrada en esta ADR como opción 1.

## Cómo se verificará
- El flujo crítico del MVP funciona de punta a punta en un proyecto Supabase de desarrollo.
- Las pruebas de aislamiento entre organizaciones pasan (pgTAP y API).
- El frontend (ADR-0006) puede consumir Auth, Data API y Edge Functions sin claves secretas en el cliente.
- Revisión de esta ADR cuando se elija plan/alojamiento. Si la lógica de negocio se vuelve difícil de mantener en SQL/Edge Functions, se reevaluará la opción 1 o 3 en una nueva ADR.
