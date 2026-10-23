# Modelo inicial de amenazas de Nexo

Estado: inicial, adaptado a la arquitectura provisional con Supabase ([ADR-0001](../architecture/decisions/0001-supabase-como-plataforma-backend.md), [ADR-0002](../architecture/decisions/0002-autenticacion-y-autorizacion-multiempresa.md)). Revisar al diseñar cada módulo y cada integración.

## Activos a proteger
- Credenciales, tokens, sesiones y claves de API de Supabase (especialmente claves secretas).
- Datos de organizaciones, proyectos, tareas y clientes.
- Definiciones de flujos y reglas.
- Historial de ejecuciones y auditoría.
- Archivos importados y exportados.
- Secretos de integraciones y webhooks.

## Actores y amenazas
- Usuario autenticado que manipula IDs para acceder a datos ajenos (BOLA/IDOR), llamando directamente a la Data API sin pasar por la interfaz.
- Usuario con rol limitado que intenta ejecutar acciones administrativas.
- Cliente anónimo que abusa de endpoints de autenticación.
- Archivo malformado o excesivamente grande que consume recursos.
- Regla de automatización que se repite, entra en ciclo o ejecuta acciones duplicadas.
- Secreto filtrado en Git, logs, respuestas de error o en el bundle del frontend.
- Evento/webhook falso, repetido o alterado.
- Dependencia externa comprometida o no disponible.

### Amenazas específicas de Supabase
- **Tabla expuesta sin RLS:** cualquier usuario con la clave publicable lee o escribe toda la tabla.
- **Política demasiado amplia:** `using (true)`, falta de `with check` en `insert`/`update`, o política para `anon` en datos de negocio.
- **Clave secreta en el cliente:** `sb_secret_...` (o `service_role` heredada) en Vercel como variable pública o en código del frontend; omite RLS por completo.
- **Edge Function con clave secreta** que no verifica membresía: convierte un endpoint en un bypass de RLS.
- **`security definer` sin `search_path` fijo** o sin comprobar membresía: escalada de privilegios.
- **Vistas que omiten RLS** por ejecutarse con permisos del propietario.
- **Autorización basada en `user_metadata`**, que el usuario puede modificar.
- **Claims desactualizados** si en el futuro se ponen roles en el JWT.
- **Cambio de `organization_id`** en un `update` para mover una fila a otra organización.
- **Relaciones cruzadas:** tarea de la organización B apuntando a proyecto de A.
- **Jobs de cron** que crean filas sin `organization_id` correcto o duplican efectos.
- **Realtime / Storage** habilitados sin políticas cuando se usen.
- **Cambios manuales en el dashboard** de producción no versionados que desactivan una política.
- **Mensajes de error de PostgREST** que exponen nombres de restricciones o detalles internos.

## Controles iniciales
- Autorización en base de datos y servidor para cada recurso: RLS en todas las tablas expuestas, restricciones (FK compuestas, `not null`), triggers de invariantes y validación en RPC.
- Funciones auxiliares de autorización en un esquema no expuesto, `security definer` con `search_path = ''`.
- `anon` sin permisos sobre datos de negocio.
- Vistas con `security_invoker = true`.
- Clave publicable en el frontend; claves secretas solo en secretos de Edge Functions o herramientas de servidor; búsqueda automática de secretos en CI.
- Edge Functions con el JWT del usuario por defecto; uso justificado y auditado de la clave secreta.
- Pruebas negativas de aislamiento entre organizaciones (pgTAP y API).
- Contraseñas y sesiones gestionadas por Supabase Auth; confirmación de correo; MFA a evaluar.
- Rate limiting: límites de Supabase Auth configurados por entorno; CAPTCHA a evaluar. La Data API no tiene límites por usuario equivalentes: riesgo a evaluar antes de producción.
- Validación estricta de payloads (`check`, tipos, validación de `jsonb`) y archivos.
- Consultas parametrizadas: supabase-js/PostgREST en el cliente; nunca concatenar entrada del usuario en SQL dinámico (`format()` con `%I`/`%L` si fuera imprescindible).
- Idempotencia, límites de intentos, timeouts y detección de ciclos en automatizaciones.
- Verificación de firma/secretos en webhooks cuando se implementen.
- Logs sin secretos y con IDs de correlación en Edge Functions.
- CORS explícito en Edge Functions; Site URL y redirecciones restringidas en Auth; HTTPS (proporcionado por Supabase y Vercel).
- Todos los cambios de seguridad versionados en migraciones; revisar Security Advisor antes de cada despliegue.
- Copias de seguridad con prueba de restauración.

## Reglas del motor de automatización
No ejecutar código, SQL, shell ni expresiones libres aportadas por usuarios. Las reglas se expresan con un esquema limitado, validado y versionado, con catálogo cerrado de condiciones y acciones. El SQL que evalúa reglas es código del proyecto en migraciones; nunca se construye a partir de texto del usuario. Las acciones de efectos externos deben ser explícitas, autorizadas y auditables.

## SQL, XSS y validación
No crear un sanitizador global indiscriminado. Usa consultas parametrizadas, validación con restricciones y tipos, escape contextual al renderizar en el frontend y políticas de contenido cuando corresponda. La validación de entrada no sustituye la autorización.

## RLS de PostgreSQL
Decisión: RLS es el mecanismo principal de aislamiento (ADR-0002). Requisitos:
- Documentar cada política junto a su migración.
- Políticas por operación y por rol.
- Probar con roles `authenticated` y `anon` simulando JWT, nunca solo con roles con bypass.
- Las funciones de sistema (cron) que operan sin usuario deben propagar el `organization_id` del recurso de origen y tener pruebas propias.

RLS no es la única defensa: se combina con restricciones, triggers y validación en RPC y Edge Functions.

## Riesgos residuales y asuntos pendientes
- Confirmar cómo gestionará la sesión el frontend de Stitch (cliente puro o renderizado en servidor).
- Rate limiting de la Data API frente a abuso por usuarios autenticados.
- Definir retención y eliminación de datos (incluido `auth.users` y auditoría).
- Revisar obligaciones legales aplicables en los mercados de operación y región de alojamiento del proyecto Supabase.
- Seleccionar planes y observabilidad.
- Definir límites de tamaño, duración y consumo para las automatizaciones.
- Dependencia del proveedor (lock-in) y plan de salida.
