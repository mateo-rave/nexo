# Requisitos iniciales de Nexo

Estado: borrador para validar. Los requisitos no validados deben tratarse como hipótesis, no como contrato definitivo.

## Requisitos funcionales del MVP

### Identidad y organizaciones
- RF-001: una persona podrá registrarse e iniciar sesión.
- RF-002: un usuario podrá crear una organización.
- RF-003: un usuario podrá pertenecer a una o más organizaciones.
- RF-004: el sistema aplicará permisos por rol y organización.

### Proyectos y tareas
- RF-010: los miembros autorizados podrán crear proyectos.
- RF-011: los miembros autorizados podrán crear tareas asociadas a un proyecto.
- RF-012: una tarea podrá tener estado, responsable, fecha límite y descripción.
- RF-013: las transiciones de estado se validarán en el backend.

### Flujos y automatización
- RF-020: un usuario autorizado podrá definir un flujo básico estructurado.
- RF-021: una definición de flujo publicada deberá estar versionada.
- RF-022: las reglas podrán combinar activadores, condiciones y acciones permitidas.
- RF-023: el motor registrará estado, resultado y errores de cada ejecución.
- RF-024: los eventos repetidos no deberán provocar efectos duplicados cuando se requiera idempotencia.
- RF-025: el sistema deberá limitar reintentos y evitar ciclos infinitos.

### Detección y notificaciones
- RF-030: el sistema detectará tareas vencidas según la hora y las reglas configuradas.
- RF-031: el sistema podrá detectar tareas o procesos sin actividad durante un periodo configurable.
- RF-032: un hallazgo incluirá evidencia, fecha, prioridad y referencia al proceso afectado.
- RF-033: se podrán enviar notificaciones internas a usuarios autorizados.
- RF-034: las notificaciones y ejecuciones relevantes quedarán registradas.
- RF-035 (pospuesto, fuera del MVP): el sistema podrá detectar aprobaciones demoradas. Requiere decidir primero cómo se modela una aprobación especializada.
- RF-036: las operaciones importantes (lista en `docs/security/permissions.md`) quedarán en un historial de auditoría no editable por los usuarios.
- RF-037: los usuarios autorizados podrán consultar métricas sencillas de su organización, por ejemplo tareas por estado, tareas vencidas y ejecuciones fallidas. Las métricas concretas se definirán al llegar a esa fase.

### Roles y permisos
- RF-005: los roles iniciales serán `owner`, `admin` y `member`; sus permisos están en `docs/security/permissions.md` y todo lo no permitido está denegado.
- RF-006: una organización siempre tendrá al menos un `owner`.

### API y operación
- RF-040: los recursos del MVP se expondrán mediante una API documentada, compuesta por la Data API de Supabase, funciones RPC y Edge Functions (ver `docs/architecture/overview.md`).
- RF-041: los listados que puedan crecer tendrán paginación y filtros apropiados.
- RF-042: habrá comprobaciones de salud adecuadas para el entorno (p. ej. una Edge Function de salud).

## Requisitos no funcionales
- RNF-001 Seguridad: autorización en el servidor y en la base de datos (RLS, restricciones y validación en funciones) para cada recurso y operación; nunca solo en el frontend.
- RNF-002 Aislamiento: ninguna organización podrá acceder a los datos de otra.
- RNF-003 Mantenibilidad: módulos con límites claros y responsabilidades explícitas.
- RNF-004 Testabilidad: reglas críticas cubiertas por pruebas automatizadas.
- RNF-005 Observabilidad: errores con contexto y sin filtrar secretos.
- RNF-006 Integridad: operaciones relacionadas usarán transacciones cuando deban ser atómicas.
- RNF-007 Rendimiento: tareas largas no bloquearán solicitudes web; usar procesamiento programado (Supabase Cron) o Edge Functions cuando esté justificado.
- RNF-008 Recuperación: documentar respaldos y probar restauración.
- RNF-009 API: contratos y errores consistentes.
- RNF-010 Privacidad: almacenar solo los datos necesarios y definir retención/eliminación.
- RNF-011 Gestión de claves: el frontend solo usa la clave publicable; las claves secretas nunca llegan al navegador, a Git ni a variables públicas de despliegue.

## Fuera del alcance inicial
- Integración completa con WhatsApp.
- Decenas de integraciones de terceros.
- Agentes de IA con autonomía amplia.
- Microservicios y Kubernetes sin necesidad demostrada.
- Facturación compleja antes de validar el modelo comercial.
- Analítica predictiva que requiera datos que todavía no existen.
- Sugerencias inteligentes de nuevas automatizaciones.
- Aprobaciones especializadas y su detección de demoras (RF-035).
- Integraciones externas, incluido el envío de correos de notificación.
- Actualizaciones en tiempo real (Supabase Realtime).

## Criterios de aceptación del MVP
1. Un usuario puede crear una organización y un proyecto.
2. Puede crear y asignar una tarea con fecha límite.
3. Puede configurar una regla segura y limitada.
4. La regla se ejecuta y su resultado queda trazado.
5. El sistema detecta al menos un tipo de bloqueo con una regla verificable.
6. Se notifica al usuario correspondiente.
7. Un usuario de otra organización no puede leer, modificar, borrar ni ejecutar acciones sobre esos datos, ni siquiera llamando directamente a la API.
8. Las pruebas críticas (incluidas las de políticas RLS) pasan en un entorno reproducible: Supabase local o CI.
9. La API está documentada y puede ser consumida por el frontend creado en Stitch usando solo la clave publicable.

## Hipótesis por validar
- El público objetivo priorizado sufre estos problemas con frecuencia.
- Puede entregar información suficiente para coordinar procesos.
- El producto es más útil que sus herramientas actuales.
- Tiene disposición a pagar por la solución.
