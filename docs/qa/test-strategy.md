# Estrategia de QA y testing

Estado: adaptada a la arquitectura provisional con Supabase (ver [ADR-0004](../architecture/decisions/0004-entornos-migraciones-y-pruebas.md)).

## Objetivo
Probar reglas de negocio, políticas RLS, contratos de API, aislamiento multiempresa, integridad de datos y flujos críticos desde el comienzo.

## Pirámide de pruebas

### 1. Unitarias
Prueban unidades pequeñas sin infraestructura externa cuando sea posible.
- **SQL:** funciones puras (cálculo de vencimiento, evaluación de condiciones, validación de definiciones) con pgTAP.
- **Edge Functions:** módulos TypeScript sin red con `deno test`.

Usa mocks para dependencias externas (proveedor de correo); no los uses donde importe verificar consultas reales, restricciones o políticas.

### 2. Base de datos y módulo
Comprueban tablas, restricciones, triggers, políticas RLS y funciones RPC de un módulo contra un PostgreSQL de Supabase real (local o CI) con pgTAP. Cada módulo prueba entradas válidas, inválidas y permisos por rol.

### 3. Integración de API
Pruebas TypeScript con `supabase-js` que actúan como el frontend: inician sesión con usuarios de prueba y llaman a la Data API, RPC y Edge Functions. Demuestran que lo probado en SQL también se cumple a través de la API pública con la clave publicable. CI usa una base efímera; nunca datos locales ni producción.

### 4. E2E
Cuando el frontend de Stitch esté integrado, Playwright probará los flujos principales desde la interfaz. Antes de eso, el recorrido completo se prueba con pruebas de integración de API.

## Pruebas de permisos (obligatorias)
Cada permiso de [docs/security/permissions.md](../security/permissions.md) necesita **dos** pruebas: una que demuestre que el rol autorizado **sí** puede hacerlo y otra que demuestre que un rol no autorizado **no** puede. Probar solo los rechazos no basta: una política que lo deniega todo también los pasaría.

Ejemplos de casos permitidos que deben pasar:
- `owner_a`, `admin_a` y `member_a` ven los proyectos y tareas de A.
- `admin_a` crea un proyecto en A; `member_a` crea una tarea en A.
- `member_a` cambia el estado de una tarea de la que es responsable.
- `owner_a` cambia el rol de `member_a` a `admin`.
- Cada usuario ve y marca como leídas sus propias notificaciones.
- `admin_a` consulta el historial de auditoría de A.

## Pruebas de aislamiento multiempresa (obligatorias)
Datos base: organizaciones A y B; usuarios `owner_a`, `admin_a`, `member_a`, `owner_b`, `sin_membresia` y anónimo. Para **cada** tabla de negocio expuesta y **cada** RPC/Edge Function:

| Caso | Resultado esperado |
|---|---|
| `owner_b` lista filas de A | Resultado vacío. |
| `owner_b` lee una fila de A por ID | Sin filas. |
| `owner_b` inserta una fila con `organization_id` de A | Error de RLS (`42501`) o rechazo de la RPC. |
| `owner_b` inserta en B una fila hija que apunta a un padre de A (FK compuesta) | Error de restricción. |
| `owner_b` actualiza una fila de A | 0 filas afectadas **y** la fila de A queda intacta (verificado como `owner_a`). |
| `owner_b` cambia el `organization_id` de su fila a A | Rechazado por trigger/política. |
| `owner_b` borra una fila de A | 0 filas afectadas **y** la fila sigue existiendo. |
| `owner_b` llama a una RPC/Edge Function con un ID de A (organización, proyecto, tarea, regla) | Error de autorización; sin efectos ni auditoría a nombre de A. |
| `owner_b` ejecuta o publica una regla/flujo de A | Rechazado; sin ejecución creada. |
| `sin_membresia` hace cualquiera de lo anterior | Igual que `owner_b`. |
| `anon` lee o escribe cualquier tabla de negocio | Error de permisos. |
| `member_a` ejecuta una acción reservada a `admin`/`owner` | Rechazado. |
| `admin_a` asciende a alguien a `admin` u `owner` | Rechazado. |
| `member_a` lee notificaciones de otro usuario de A | Sin filas. |
| `member_a` lee el historial de auditoría | Sin filas o error de permisos. |
| Cualquier rol edita o borra un registro de auditoría | Rechazado. |
| `owner_a` intenta quedarse sin owner en A | Rechazado. |
| Membresía revocada | El usuario pierde acceso en la siguiente petición. |

Comprobaciones globales:
- Ninguna tabla de esquemas expuestos tiene RLS deshabilitado.
- Las vistas expuestas usan `security_invoker`.
- Las funciones `security definer` fijan `search_path`.
- Ninguna clave secreta aparece en el bundle del frontend ni en el repositorio (búsqueda automática en CI).

## Pruebas del motor de automatización
- Una regla válida se ejecuta y queda una ejecución `succeeded` con versión de regla, timestamps y resultado.
- Una definición con condición o acción no permitida se rechaza al guardar.
- Una versión publicada no puede modificarse.
- El mismo evento procesado dos veces produce una sola ejecución y un solo efecto.
- La detección programada ejecutada dos veces seguidas no duplica hallazgos ni notificaciones.
- Dos procesos concurrentes no toman la misma ejecución pendiente.
- Un fallo transitorio se reintenta hasta el límite y termina `failed` con error seguro.
- Si una acción falla, la ejecución no queda `succeeded` y no persisten efectos parciales.
- Una acción externa queda `scheduled` hasta que la Edge Function la confirma.
- Una cadena de reglas que se dispararían mutuamente se detiene en la profundidad máxima.
- Proveedor externo caído: la acción queda `failed`/reintentable, no `completed`.

## Flujos críticos
- Registrar usuario y crear organización (con membresía owner atómica).
- Crear proyecto y tarea con responsable y fecha límite.
- Definir y publicar una regla permitida.
- Procesar el evento sin duplicar sus efectos.
- Detectar un bloqueo y crear notificación.
- Consultar la ejecución y la auditoría.
- Intentar leer, modificar, borrar o ejecutar acciones sobre otra organización y recibir denegación.

## Casos negativos obligatorios
- Sin autenticación.
- JWT caducado o manipulado.
- Rol insuficiente.
- Identificador de recurso manipulado.
- Acceso cruzado entre organizaciones.
- Campos ausentes o inválidos.
- Evento repetido.
- Reintento tras fallo.
- Acción no permitida.
- Ciclo de automatización detectado o limitado.
- Dependencia externa caída.

## Herramientas
| Uso | Herramienta | Requiere |
|---|---|---|
| SQL, RLS, triggers, RPC | pgTAP vía `supabase test db` (`supabase/tests/`); opcional `supabase-test-helpers`. | Supabase local (Docker) o CI. |
| Edge Functions | `deno test`. | Deno; integración además Supabase local/CI/desarrollo. |
| Integración de API | `deno test` + `supabase-js` (un solo runtime con las Edge Functions; alternativa: Vitest en Node). | Supabase local, CI o desarrollo. |
| E2E | Playwright. | Frontend integrado. |
| Lint/formato | `deno fmt`, `deno lint`, `supabase db lint`, Security/Performance Advisors. | Deno, Supabase CLI. |
| CI | GitHub Actions con Supabase CLI (los runners Linux incluyen Docker). | Repositorio en GitHub. |

Las versiones se fijarán al instalar cada herramienta, verificando compatibilidad.

### Sin Docker local (situación vigente)
- Las pruebas pgTAP y de integración se ejecutan contra el proyecto Supabase **de desarrollo**, nunca producción, y en CI cuando exista GitHub.
- Las pruebas pgTAP se envuelven en `begin; ... rollback;` para no dejar datos.
- Si la CLI no permite ejecutar `supabase test db` contra el proyecto remoto sin Docker, los archivos se ejecutan en el SQL Editor del proyecto de desarrollo y el resultado se anota indicando dónde se ejecutó.
- Las pruebas unitarias de Edge Functions solo necesitan Deno.

## Reglas de calidad
- No afirmar que pasó una prueba si no fue ejecutada; indicar dónde se ejecutó.
- No desactivar una prueba que falla solo para dejar CI verde sin investigar la causa.
- Un "0 filas afectadas" no basta para probar una denegación de escritura: verificar que la fila objetivo sigue intacta.
- Los cálculos (vencimiento, inactividad) se verifican con datos de referencia y tiempo controlado.
- Fixtures pequeños y sintéticos; sin datos personales reales.
- Probar permisos en SQL (pgTAP) **y** a través de la API.
- Informar pruebas pasadas, fallidas y no ejecutadas por separado.

## Umbral inicial
Primero cobertura de caminos críticos y riesgos de seguridad: toda tabla expuesta debe tener su archivo de pruebas RLS antes de considerarse terminada. Un porcentaje de cobertura por sí solo no demuestra calidad; la meta cuantitativa se decidirá después.
