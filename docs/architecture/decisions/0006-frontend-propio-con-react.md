# ADR-0006: Frontend propio con React en el repositorio

- Estado: Aceptada
- Fecha: 2026-10-24 (decisión del propietario)
- Responsables: propietario del producto

> **En pocas palabras:** el propietario ya no diseñará ni construirá el frontend en Stitch. Claude Code lo construye y lo mantiene directamente en este repositorio, con Vite, React, TypeScript y Tailwind CSS, y se conecta a Supabase con `supabase-js`. La identidad visual de `CLAUDE.md` es obligatoria. La seguridad sigue viviendo en el backend: el frontend solo muestra datos y envía peticiones.

## Contexto
Hasta ahora, `CLAUDE.md` y la documentación decían que el propietario desarrollaría el frontend en Stitch y lo integraría después. Por eso se prohibía crear una interfaz propia en React, el framework no se fijaba hasta ver el código que generara Stitch y la etapa inicial se limitaba al backend y a los contratos de API.

El 2026-10-24 el propietario decidió abandonar Stitch. Situación en ese momento:
- **Backend:** están implementadas y probadas la infraestructura, la autenticación (Supabase Auth), las organizaciones y las membresías. Son las migraciones 1 y 2, aplicadas en `nexo-dev`, con 199 pruebas pgTAP y 40 pruebas de API aprobadas en CI.
- **Pendiente:** las funcionalidades centrales de negocio, que son proyectos, tareas, flujos y automatizaciones, todavía no existen.
- **Identidad visual:** está aprobada y registrada en `CLAUDE.md`.
- **Despliegue:** no hay cuenta de Vercel ni ningún despliegue configurado.

## Opciones consideradas
1. **Mantener Stitch** como herramienta de diseño e implementación. Permite un diseño visual rápido, pero el código generado no está en el repositorio, su estructura y framework son desconocidos, y aplicar la identidad visual, la accesibilidad y las pruebas exige adaptar después un código ajeno. El propietario la descarta.
2. **Vite + React + TypeScript como aplicación de una sola página (SPA)**, construida en el repositorio. Encaja con un backend totalmente administrado: el navegador habla directamente con Supabase usando la clave publicable y el JWT del usuario, igual que las pruebas de API que ya pasan. No hay servidor propio que operar ni proteger, y se despliega como sitio estático. A cambio, la sesión vive en el navegador y la portada no tiene renderizado en servidor.
3. **Next.js** (renderizado en servidor y rutas de servidor). Mejor posicionamiento en buscadores para la portada y la posibilidad de ejecutar código en el servidor. Añade un runtime de servidor, gestión de sesión con cookies y una segunda superficie donde podría acabar lógica de negocio, sin una necesidad demostrada en el MVP.
4. **Otro framework** (Vue, Svelte…). Sin ventaja clara frente a React para este proyecto; se pierde la coherencia con la identidad aprobada, que prevé Lucide React.

## Decisión
Opción 2. Claude Code construye y mantiene el frontend directamente en el repositorio:
- **Vite, React y TypeScript**, con **Tailwind CSS** para los estilos.
- **`@supabase/supabase-js`** para Auth, Data API, RPC y, cuando existan, Edge Functions. Solo con la clave publicable.
- **Lucide React** para la iconografía.
- **Vercel** como opción prevista de despliegue. Todavía no está contratado ni configurado, y no hay ningún despliegue realizado.
- **La identidad visual aprobada en `CLAUDE.md` es de cumplimiento obligatorio:** paleta, temas claro y oscuro, tipografía, iconografía, portada, dashboard, accesibilidad e interacciones.
- **La seguridad se queda en el backend.** El frontend nunca sustituye las políticas RLS, las restricciones ni los controles de autorización de las RPC y Edge Functions. La validación en formularios es solo una ayuda de usabilidad.
- **El frontend avanza por entregas pequeñas** y se conecta a las funcionalidades reales a medida que el backend las ofrece. No inventa datos que parezcan reales ni presenta como funcionales operaciones que aún no existen; los datos de demostración se identifican claramente.

Las versiones exactas de Vite, React, TypeScript, Tailwind CSS, `supabase-js` y Lucide React se verifican y se fijan al crear la aplicación, como el resto de dependencias (ADR-0004).

## Ventajas
- Un solo repositorio para el backend, el frontend, las pruebas y la documentación: los cambios del contrato de API y de la interfaz se revisan juntos.
- La identidad visual, la accesibilidad y los estados de interacción se aplican desde el principio, sin adaptar código generado por otra herramienta.
- Sin servidor propio: menos infraestructura que operar y proteger, coherente con ADR-0001.
- Reutiliza lo ya probado: `supabase-js`, la clave publicable y el JWT del usuario.
- El frontend se puede probar con Playwright en CI contra el mismo Supabase local y desechable.

## Desventajas
- Más trabajo para Claude Code: el frontend deja de ser una pieza externa.
- La sesión de Supabase se guarda en el navegador, así que un fallo de XSS podría exponer el token del usuario. Hay que evitar inyectar HTML sin escapar y valorar una política de seguridad de contenido (CSP).
- Una SPA no ofrece renderizado en servidor: el posicionamiento de la portada en buscadores es más limitado. Se acepta para el MVP.

## Consecuencias
- Se eliminan de `CLAUDE.md` la prohibición de crear una interfaz propia en React y las instrucciones que atribuían el frontend a Stitch.
- Quedan superadas las referencias a Stitch de ADR-0001 a ADR-0004 y de la documentación: se conservan como historia y se marcan como superadas por esta ADR.
- El framework deja de ser una decisión pendiente: la sesión se gestiona en el cliente con `supabase-js`, sin renderizado en servidor.
- Las variables públicas del frontend usan el prefijo `VITE_`. Vite solo envía al navegador las variables con ese prefijo, así que **ninguna clave secreta puede llevarlo**. Los nombres concretos se añaden al glosario de ADR-0005 al crear la aplicación.
- Las convenciones de ADR-0005 se aplican al código del frontend: `camelCase` en funciones y variables, `PascalCase` en tipos y componentes, y los nombres del contrato tal como los define la API.
- Las pruebas de extremo a extremo con Playwright pasan a ser posibles en cuanto exista la aplicación (ADR-0004 y `docs/qa/test-strategy.md`).

## Cómo se verificará
- La aplicación se crea en el repositorio con las versiones verificadas y fijadas, y su compilación y comprobación de tipos pasan en CI.
- El código del frontend no contiene claves secretas: solo la URL y la clave publicable, con prefijo `VITE_`.
- Cada pantalla usa datos reales del backend o datos de demostración identificados como tales.
- Las pruebas de aislamiento de la API siguen pasando: el frontend no añade ninguna vía de acceso que salte RLS.
- La interfaz cumple la identidad visual de `CLAUDE.md` en modo claro y oscuro, con navegación por teclado y contraste suficiente.
