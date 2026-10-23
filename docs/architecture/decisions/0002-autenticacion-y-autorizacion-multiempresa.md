# ADR-0002: Autenticación y autorización multiempresa

- Estado: Aceptada
- Fecha: 2026-10-23 (propuesta y aceptación)
- Responsables: propietario del producto

## Contexto
Un usuario puede pertenecer a una o más organizaciones con roles distintos en cada una. El frontend (Stitch, desplegado en Vercel) accederá a Supabase con la clave publicable, de modo que cualquier usuario autenticado puede enviar peticiones directas a la Data API saltándose la interfaz. El aislamiento debe garantizarse en el servidor y en la base de datos, nunca en React.

## Opciones consideradas
1. **Roles en claims del JWT (Custom Access Token Hook).** Evita consultas en cada política. Los claims quedan desactualizados hasta que se renueva el token (un rol revocado sigue activo minutos u horas) y el token crece con el número de organizaciones.
2. **Consulta de membresía en cada política mediante funciones auxiliares `security definer`.** Siempre refleja el estado actual de las membresías. Coste de rendimiento controlable con índices y `(select auth.uid())`.
3. **Organización activa enviada por el frontend (cabecera o parámetro) como fuente de verdad.** Simple, pero inseguro: el cliente controla el valor.

## Decisión
Opción 2.

### Autenticación
- Supabase Auth, inicialmente email + contraseña con confirmación de correo. Proveedores OAuth y MFA quedan pendientes.
- El frontend usa solo la URL del proyecto y la **clave publicable** (`sb_publishable_...`). Las **claves secretas** (`sb_secret_...`) y cualquier clave `service_role` heredada solo existen en Edge Functions o herramientas de servidor, nunca en el navegador, en Git ni en variables de Vercel expuestas al cliente.
- La identidad en SQL se obtiene de `auth.uid()`. No se usa `user_metadata` para autorizar, porque el propio usuario puede modificarlo.
- Configurar en Auth la Site URL y la lista de redirecciones permitidas por entorno (dominios de Vercel de preview/producción).

### Modelo de datos de autorización
- `organizations(id, name, created_by, created_at)`.
- `memberships(organization_id, user_id, role, created_at)` con `unique (organization_id, user_id)`.
- Roles iniciales: `owner`, `admin`, `member`. La matriz de permisos se mantiene en [docs/security/permissions.md](../../security/permissions.md); lo no permitido allí está denegado.
- Todas las tablas de negocio llevan `organization_id uuid not null`.
- Las tablas hijas referencian al padre con clave foránea compuesta `(organization_id, parent_id) → parent(organization_id, id)`, de modo que la base de datos impide enlazar una tarea a un proyecto de otra organización aunque el cliente envíe IDs manipulados.
- Un trigger impide modificar `organization_id` después de la creación.
- Una organización no puede quedarse sin `owner` (comprobado en la función que cambia roles o elimina membresías).

### Políticas RLS
- RLS habilitado en **todas** las tablas de esquemas expuestos. Una prueba verifica que ninguna tabla expuesta lo tenga deshabilitado.
- Funciones auxiliares en un esquema no expuesto (p. ej. `private`): `private.is_member(org_id)` y `private.has_role(org_id, roles[])`, declaradas `security definer`, `stable`, con `set search_path = ''`.
- Políticas separadas por operación (`select`, `insert`, `update`, `delete`), dirigidas al rol `authenticated`. `insert` y `update` usan `with check` para impedir escribir en otra organización.
- El rol `anon` no recibe permisos sobre tablas de negocio.
- Las vistas expuestas se crean con `security_invoker = true` para no saltarse RLS.
- Las operaciones de varias escrituras o con reglas de rol (crear organización + membresía owner, invitar, cambiar rol) se hacen por funciones RPC que validan el rol dentro de la transacción.

### Organización activa
El frontend puede recordar qué organización está mostrando, pero es solo una preferencia de interfaz. Cada fila se autoriza por su propio `organization_id` contra `memberships`. Un `organization_id` recibido en una RPC o Edge Function se verifica siempre contra la membresía del usuario autenticado.

### Edge Functions
- Por defecto crean el cliente Supabase con el JWT del usuario que llama, para que RLS se aplique.
- Solo usan la clave secreta cuando la operación lo exige (p. ej. tareas de sistema). En ese caso, la función comprueba explícitamente la membresía y el rol y lo registra en auditoría.

## Consecuencias
- Cada política consulta `memberships`; se necesita índice `(user_id, organization_id)` y revisar planes de consulta con datos de prueba.
- La seguridad depende de pruebas negativas exhaustivas (ver `docs/qa/test-strategy.md`).
- Si el rendimiento lo exige, los claims en JWT podrán añadirse como optimización con una nueva ADR, sin dejar de comprobar membresía para acciones sensibles.

### Auditoría
Las operaciones importantes (lista en `docs/security/permissions.md`) se registran en una tabla de solo inserción, escrita por triggers o funciones SQL. Ningún rol puede editar ni borrar registros de auditoría.

## Cómo se verificará
- Por cada permiso de la matriz, una prueba del caso permitido y otra del caso denegado.
- Pruebas pgTAP por tabla: un usuario de la organización B no puede leer, insertar, actualizar ni borrar filas de A, y las filas de A quedan intactas tras el intento.
- Pruebas de API con supabase-js usando dos usuarios reales de prueba.
- Prueba de que `anon` no accede a ninguna tabla de negocio.
- Prueba de que RLS está habilitado en todas las tablas expuestas.
- Revisión del Security Advisor de Supabase sin avisos críticos abiertos.
