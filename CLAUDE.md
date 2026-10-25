# Nexo — Instrucciones permanentes para Claude Code

## 1. Contexto del producto
Nexo es un SaaS multiempresa para pequeños negocios de servicios. Busca centralizar y coordinar solicitudes, tareas, responsables y procesos; detectar bloqueos; y automatizar tareas repetitivas mediante reglas explícitas, controladas y auditables.

El público inicial es una hipótesis: pequeñas agencias digitales y equipos de servicios que gestionan solicitudes de varios clientes. No afirmes que la demanda está validada ni que Nexo carece de competencia. La validación comercial está pendiente.

Ejemplo central: una agencia recibe una solicitud, valida si está completa, asigna trabajo, gestiona la entrega y aprobación, detecta esperas excesivas y registra qué ocurrió. Cuando un patrón se repite, Nexo podrá sugerir una mejora para que una persona autorizada la revise (posterior al MVP).

## 2. Alcance inicial del MVP
Prioriza un flujo funcional de punta a punta, no una gran cantidad de módulos incompletos:
1. Usuarios, autenticación y organizaciones.
2. Membresías y roles (`propietario`, `administrador`, `miembro`; permisos en `docs/security/permissions.md`).
3. Proyectos y tareas con estado, responsable y fecha límite.
4. Flujos de trabajo básicos con definición estructurada y versionada.
5. Reglas de automatización limitadas a condiciones y acciones permitidas.
6. Registro de ejecuciones, errores y reintentos controlados, sin acciones ni notificaciones duplicadas por un mismo evento.
7. Detección basada en reglas de tareas vencidas (procesos inactivos si el tiempo lo permite).
8. Notificaciones internas e historial de auditoría.
9. Métricas sencillas y API documentada.

Quedan para después del MVP: sugerencias inteligentes de nuevas automatizaciones, aprobaciones especializadas, integraciones externas (incluido el envío de correos de notificación) y actualizaciones en tiempo real.

La meta de tres meses es una estimación de planificación, no una garantía. No desarrolles integraciones complejas, IA autónoma, decenas de conectores ni facturación avanzada hasta demostrar que son necesarias.

## 3. Frontend propio (ADR-0006)
Claude Code construye y mantiene el frontend directamente en este repositorio, con Vite, React, TypeScript y Tailwind CSS; usa `@supabase/supabase-js` para hablar con Supabase y Lucide React para los iconos. Vercel es la opción prevista de despliegue: todavía no hay cuenta configurada ni ningún despliegue hecho. Las versiones se verifican y se fijan al crear la aplicación (sección 5).

El frontend avanza por entregas pequeñas y se conecta a las funcionalidades reales a medida que el backend las ofrece. Hoy están implementadas y probadas la autenticación, las organizaciones y las membresías; proyectos, tareas, flujos y automatizaciones están por desarrollar. No inventes datos que parezcan reales ni presentes como funcional una operación que todavía no existe: los datos de demostración se identifican claramente y nunca se simula que algo está guardado si no lo está.

Mantén un contrato de API coherente (Data API, RPC y Edge Functions), documentado con ejemplos de peticiones y respuestas, con CORS apropiado por entorno en Edge Functions y con pruebas de API. Cuando una pantalla necesite una operación que no existe, se añade primero en el backend, con sus permisos y pruebas.

No pongas reglas de negocio, permisos ni acciones sensibles en el frontend: deben estar protegidos por el backend y la base de datos. El frontend nunca sustituye las políticas RLS ni los controles de autorización; la validación de formularios es solo una ayuda de usabilidad. En Vite, solo las variables con prefijo `VITE_` llegan al navegador: ninguna clave secreta puede llevar ese prefijo (sección 7).

## 4. Identidad visual (decisión de diseño vigente, aprobada por el propietario)
Es de cumplimiento obligatorio en todo el frontend (ADR-0006).

**Dirección:** dark premium con turquesa equilibrado; profesional, tecnológica y reconocible. Debe transmitir claridad, conexión entre procesos y control operativo, y no parecer una plantilla genérica de SaaS ni un dashboard generado automáticamente. Su personalidad sale de la composición, la tipografía, la iconografía, el símbolo, la jerarquía de la información y el uso intencional del turquesa.

**Temas:** modo claro y oscuro, diseñados con el mismo cuidado. Comparten estructura y componentes; solo cambian los tokens de color y los ajustes necesarios para el contraste. El tema inicial sigue la preferencia del sistema operativo; el usuario puede elegirlo manualmente y su preferencia se conserva.

**Paleta de marca** (no cambiarla ni añadir otra sin aprobación expresa del propietario):

| Token | Modo oscuro | Modo claro |
|---|---|---|
| Fondo principal | `#0B1117` | `#F4F8F7` |
| Superficie principal | `#111C24` | `#FFFFFF` |
| Superficie elevada | `#17262F` | `#EAF2F1` |
| Acento de marca (turquesa) | `#35D6C3` | `#08776F` |
| Texto principal | `#F2F7F7` | `#15292C` |
| Texto secundario | `#A5B8BD` | `#536A6D` |

El turquesa destaca acciones, selección, progreso y datos importantes, sin invadir la interfaz.

**Colores semánticos** (expresan el estado de una operación o elemento; no sustituyen al turquesa):

| Estado | Modo oscuro | Modo claro |
|---|---|---|
| Éxito | `#5CDE9B` | `#177A50` |
| Atención | `#F4C66A` | `#8C5C00` |
| Error o bloqueo | `#FF8585` | `#B42318` |
| Información | `#7EB6FF` | `#235CA8` |

Un estado nunca se comunica solo con color: va acompañado de icono y etiqueta de texto.

**Tipografía y composición:**
- Geist como primera opción; si no está disponible, una alternativa de sistema apropiada.
- Jerarquía clara entre títulos, métricas, descripciones y metadatos.
- Espaciado en múltiplos de 4 px; bordes sutiles, radios moderados y sombras discretas.
- Cada información usa el patrón que le corresponde (tablas, espacios abiertos, paneles, gráficos, listas); no el mismo estilo de tarjeta en cada sección.

**Iconografía:**
- Lucide React como biblioteca inicial de iconos SVG (sección 3).
- Una sola familia visual, en tamaños de 16, 20 y 24 px.
- Los iconos representan acciones o información reconocibles. Nunca se usan emojis, stickers ni caracteres decorativos en su lugar.

**Portada:**
- Composición propia, con un recurso visual de flujos de trabajo y nodos conectados que muestre cómo una solicitud se conecta con un proyecto, sus tareas y el resultado final.
- Debe integrar una representación visual del producto, no ilustraciones genéricas desconectadas de su funcionamiento.
- Titular provisional para explorar: «Que nada se quede a mitad de camino». Es una propuesta de copy, no un texto definitivo, hasta que el propietario apruebe la portada final.

**Dashboard y visualización de datos:**
- Prioriza información operativa: proyectos activos, tareas por estado, tareas vencidas o bloqueadas, aprobaciones pendientes, actividad reciente e indicadores de avance con contexto comprensible.
- Cada indicador se muestra cuando el backend ofrezca esos datos; el diseño no adelanta funciones fuera del alcance del MVP (sección 2).
- Los gráficos responden preguntas concretas. Nada de gráficos decorativos ni de métricas inventadas que parezcan datos reales.
- Sin conexión con el backend, los datos de demostración se identifican claramente, y nunca se simula que una operación está guardada si no lo está (sección 3).

**Interactividad y accesibilidad:**
- Toda interacción visible tiene un comportamiento real y estados definidos: carga, éxito, error, vacío, deshabilitado y foco de teclado.
- Transiciones discretas, en general de 160 a 220 ms, sin animaciones innecesarias; se respeta `prefers-reduced-motion`.
- Navegación por teclado, etiquetas accesibles y contraste suficiente.
- Si una combinación concreta no alcanza el contraste necesario, se ajusta el token funcional afectado y se informa del cambio; no se sacrifica la accesibilidad ni se altera la identidad de forma arbitraria.

**Se evita expresamente:** plantillas genéricas de dashboards SaaS; emojis como iconos; degradados llamativos por defecto; glassmorphism en toda la interfaz; tarjetas para absolutamente todo; métricas y gráficos sin utilidad real; animaciones excesivas; componentes atractivos sin funcionalidad; y cambiar la paleta o tomar nuevas decisiones de identidad sin autorización.

## 5. Stack (provisional, ver ADR-0001 a ADR-0006)
- Supabase como plataforma de backend administrada.
- PostgreSQL de Supabase para persistencia; esquema, políticas y funciones en migraciones SQL versionadas (`supabase/migrations/`).
- Supabase Auth para autenticación.
- Row Level Security (RLS) para el aislamiento entre organizaciones.
- Data API (PostgREST) para CRUD simple protegido por RLS.
- Funciones SQL (RPC) y triggers para operaciones atómicas cerca de los datos, cuando estén justificadas.
- Supabase Edge Functions en TypeScript/Deno para operaciones que requieran endpoints específicos, secretos o efectos externos.
- Supabase Cron para comprobaciones programadas.
- Supabase Realtime solo si una funcionalidad concreta lo necesita.
- Frontend: Vite, React, TypeScript y Tailwind CSS, con `@supabase/supabase-js` y Lucide React (ADR-0006); despliegue previsto en Vercel.
- Pruebas: pgTAP (`supabase test db`), `deno test`, pruebas de API con `supabase-js`, Playwright cuando exista frontend.
- GitHub Actions para CI.

En el MVP **no** uses Django, Django REST Framework, Celery ni Redis, y no mantengas dos implementaciones paralelas de autenticación o API. Esta arquitectura es provisional hasta verificarla con el despliegue elegido.

No presupongas que Docker, Supabase CLI, Deno u otras herramientas locales están instaladas: compruébalo. Verifica las versiones estables y su compatibilidad antes de fijarlas. No asumas versiones ni instales dependencias sin justificar su necesidad.

## 6. Arquitectura y diseño
Un único backend administrado, sin microservicios. Mantén responsabilidades y límites claros entre módulos lógicos (grupos de tablas, funciones y migraciones): cuentas, organizaciones, proyectos, tareas, flujos, automatizacion, monitoreo, notificaciones, auditoria e integraciones. La facturación queda pospuesta hasta validar el modelo comercial.

Reparte la lógica según `docs/architecture/decisions/0003-separacion-api-datos-sql-edge-functions.md`, justificando cada ubicación por seguridad, transacciones, rendimiento y mantenibilidad, no por preferencia. Evita abstracciones ceremoniales, duplicación de lógica y que un módulo escriba directamente en tablas internas de otro. Usa transacciones (funciones SQL) cuando varias escrituras deban ser atómicas. Documenta las decisiones relevantes en `docs/architecture/decisions/`.

**Nombres en español (ADR-0005):** todo lo que nombremos en el desarrollo se escribe en español: tablas, columnas, funciones, roles, estados, archivos de prueba, variables de entorno propias, mensajes de error al usuario y mensajes de commit (conservando prefijos como `docs:` o `feat:`). Sin tildes ni ñ, y con el estilo de cada lenguaje: objetos SQL, archivos y variables de entorno propias en `snake_case` y minúsculas; en TypeScript, funciones y variables en `camelCase`, y tipos, interfaces y componentes de React en `PascalCase` (JSX exige que los componentes empiecen por mayúscula). Los campos de respuesta de la API y los nombres de los argumentos de las RPC conservan exactamente el contrato existente (`usuario_id`, `nombre_visible`, `p_organizacion_id`). Usa el glosario de `docs/architecture/decisions/0005-nombres-en-espanol.md` y añade allí los nombres nuevos antes de usarlos. Solo queda en inglés lo que imponen SQL, PostgreSQL, Supabase y las herramientas (`select`, `auth.uid()`, `anon`, `SUPABASE_URL`...).

## 7. Seguridad obligatoria
- No subas secretos, credenciales ni archivos `.env` reales al repositorio.
- Mantén `.env.example` sin secretos reales.
- El frontend solo usa la clave publicable de Supabase. Las claves secretas (`sb_secret_...` o `service_role` heredada) nunca se exponen en el navegador, ni se suben a Git, ni se incluyen en código cliente o variables públicas de Vercel.
- No confíes en un `organizacion_id` enviado por el cliente: verifica siempre la membresía del usuario autenticado (`auth.uid()`). No autorices con `user_metadata`.
- RLS habilitado en todas las tablas expuestas, con políticas por operación y `with check` en escrituras; `anon` sin acceso a datos de negocio; vistas con `security_invoker`; funciones `security definer` solo justificadas y con `search_path` fijo.
- Cada consulta, RPC, Edge Function, job programado y exportación debe comprobar pertenencia y permisos. Una Edge Function que use la clave secreta debe verificar membresía explícitamente.
- Prueba explícitamente que usuarios de una organización no puedan leer, modificar, borrar ni ejecutar acciones sobre otra.
- Usa consultas parametrizadas (nunca SQL dinámico con entrada del usuario sin `format()` seguro); validación con restricciones, tipos y esquemas; escape de salida según contexto.
- No crees un sanitizador universal que modifique indiscriminadamente los datos.
- No ejecutes código arbitrario enviado por los usuarios dentro de las reglas.
- Valida archivos, limita tamaño y procesa datos importados como contenido no confiable.
- Configura CORS de Edge Functions solo para orígenes autorizados, restringe Site URL y redirecciones de Auth, y usa HTTPS en producción.
- No registres contraseñas, tokens ni contenido privado innecesario.
- RLS es el mecanismo principal de aislamiento, pero no la única defensa: combínalo con restricciones (FK compuestas por organización), triggers y validación en funciones.
- No hagas cambios manuales en el dashboard de producción, despliegues destructivos, `db reset` ni operaciones de producción sin autorización explícita.

## 8. Motor de automatización
Las definiciones de reglas deben ser datos estructurados validados, no código ejecutable arbitrario. Cada ejecución debe tener estado, timestamps, versión de regla, resultado y errores seguros. Diseña idempotencia cuando un evento pueda repetirse, límites de reintentos, timeouts y prevención de ciclos infinitos. Diferencia entre acción programada y acción completada. No marques como exitosa una ejecución que falló.

Versiones de flujos y reglas publicadas son inmutables. La evaluación de reglas con acciones internas se hace en SQL dentro de una transacción; las acciones con efectos externos se registran como programadas y las procesa una Edge Function (ADR-0003). Las comprobaciones programadas deben poder ejecutarse repetidamente sin duplicar hallazgos, notificaciones ni efectos (restricciones `unique` y claves de deduplicación).

## 9. Calidad y pruebas
Usa la pirámide de testing (detalle en `docs/qa/test-strategy.md`):
- Unitarias para reglas de negocio aisladas (pgTAP para funciones SQL, `deno test` para Edge Functions).
- Pruebas de base de datos: políticas RLS, restricciones, triggers y RPC con pgTAP.
- Integración de API con `supabase-js` y usuarios de prueba.
- E2E de flujos críticos con Playwright cuando exista el frontend.

Si una prueba necesita Docker, Supabase CLI u otra herramienta no disponible, indica el requisito y la alternativa (CI o proyecto de desarrollo). Nunca ejecutes pruebas contra producción.

Incluye casos positivos, entradas inválidas, falta de permisos, aislamiento entre organizaciones, duplicados, reintentos y fallos de dependencias. No declares las pruebas aprobadas si no se ejecutaron. Si no pueden ejecutarse, indica el bloqueo concreto.

Flujo crítico objetivo: registro → organización → proyecto → tarea/flujo → regla → ejecución → detección de bloqueo → notificación → historial.

## 10. Errores, operaciones y documentación
Usa respuestas de error consistentes sin filtrar trazas internas, secretos, consultas SQL ni nombres de restricciones (códigos de error propios en RPC; `{ "error": { "code", "message", "request_id" } }` en Edge Functions). Añade logs estructurados y un identificador de solicitud cuando sea razonable. Documenta configuración local, pruebas, API, respaldos/restauración y riesgos. Los respaldos deben poder probarse mediante una restauración, no solo generarse.

## 11. Forma de trabajar
1. Lee este archivo y los documentos relevantes antes de cambiar código.
2. Trabaja por entregas pequeñas con criterios de aceptación.
3. Antes de cambios relevantes, inspecciona el estado existente.
4. Explica las decisiones con lenguaje claro y directo.
5. No construyas todos los módulos de una sola vez.
6. No borres ni sobrescribas trabajo existente sin razón documentada.
7. Mantén documentación coherente con las decisiones reales.
8. Al terminar una tarea, informa archivos modificados, comandos ejecutados, pruebas aprobadas/fallidas y pendientes.
9. Nunca inventes resultados de pruebas, disponibilidad de servicios ni validación comercial.
10. Para decisiones importantes, propone opciones y recomienda una con sus razones; registra las decisiones aceptadas.

## 12. Primera instrucción en un repositorio nuevo
Primero inspecciona el repositorio y el entorno. Lee `docs/product/vision.md`, `docs/product/requirements.md`, `docs/product/mvp-scope.md`, `docs/architecture/overview.md`, las ADR de `docs/architecture/decisions/`, `docs/qa/test-strategy.md`, `docs/security/threat-model.md`, `docs/security/permissions.md` y `docs/operations/development-and-backups.md`. Compara los documentos con este archivo, informa contradicciones y propone el siguiente paso más pequeño. No empieces construyendo toda la aplicación.
