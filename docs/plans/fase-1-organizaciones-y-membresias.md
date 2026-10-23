# Fase 1 — Organizaciones, membresías y seguridad base

- Estado: plan con decisiones confirmadas; implementación no iniciada (aún no se ha escrito SQL).
- Fecha: 2026-10-23
- Referencias: [ADR-0002](../architecture/decisions/0002-autenticacion-y-autorizacion-multiempresa.md), [ADR-0004](../architecture/decisions/0004-entornos-migraciones-y-pruebas.md), [permisos](../security/permissions.md), [estrategia de pruebas](../qa/test-strategy.md).

## Objetivo
Construir la "puerta de entrada" de seguridad de Nexo: saber **quién** es cada usuario, **a qué organizaciones** pertenece y **con qué rol**, y conseguir que la base de datos impida ver o tocar datos de una organización ajena. Todas las tablas posteriores (proyectos, tareas, reglas…) reutilizarán esta misma protección.

## Qué entra y qué no
**Entra:**
- Estructura `supabase/`.
- Tablas `profiles`, `organizations`, `memberships` y `audit_log`.
- Funciones auxiliares de permisos.
- Políticas RLS.
- Funciones para crear una organización y gestionar miembros.
- Pruebas de seguridad.

**No entra:**
- Proyectos y tareas.
- Invitaciones por correo.
- Eliminación de organizaciones.
- Cualquier frontend.

## Requisitos previos (los hace el propietario)
| # | Paso | Notas |
|---|---|---|
| 1 | Crear cuenta de Supabase. | Manual. |
| 2 | Crear el proyecto `nexo-dev`, solo para desarrollo. | Elegir una región cercana. Guardar la contraseña de la base de datos en un gestor de contraseñas. |
| 3 | Copiar la URL y las claves a `.env` local. | Nunca compartirlas en el chat ni en Git. |
| 4 | Aprobar el método de instalación de la Supabase CLI. | Es una dependencia: se decide en su momento. |
| 5 | Confirmar qué comandos de la CLI funcionan sin Docker. | Ver ADR-0004. |

Sin los pasos 1 a 4 se puede **escribir y revisar** el SQL, pero **no aplicarlo ni probarlo**.

## Las tablas, explicadas

### `profiles` — datos visibles de cada persona
Supabase Auth guarda los usuarios en una tabla interna (`auth.users`) que **no** se expone al frontend, porque contiene datos sensibles. `profiles` es la "ficha pública" de cada usuario dentro de Nexo.

| Columna | Qué guarda | Por qué |
|---|---|---|
| `id` | El mismo identificador que el usuario en `auth.users`. | Une la ficha con su cuenta; una persona = un perfil. |
| `display_name` | Nombre para mostrar. | Para ver quién es miembro de un equipo sin exponer datos de la cuenta. |
| `created_at`, `updated_at` | Fechas de creación y última edición. | Trazabilidad. |

Se crea **automáticamente** con un trigger cuando alguien se registra, así nunca falta.

### `organizations` — cada empresa que usa Nexo
| Columna | Qué guarda | Por qué |
|---|---|---|
| `id` | Identificador único (UUID). | Un UUID es un código largo y aleatorio: no se puede adivinar como un 1, 2, 3. Aun así, **adivinarlo no da acceso**: lo que protege es RLS. |
| `name` | Nombre de la organización. | Obligatorio, con longitud limitada (restricción `check`). |
| `created_by` | Usuario que la creó. | Auditoría. |
| `created_at`, `updated_at` | Fechas. | Trazabilidad. |

### `memberships` — quién pertenece a qué organización y con qué rol
Es la tabla **más importante de la seguridad**: todas las políticas preguntan a esta tabla.

| Columna | Qué guarda | Por qué |
|---|---|---|
| `organization_id` | La organización. | Clave foránea a `organizations`. |
| `user_id` | El usuario. | Clave foránea al usuario. |
| `role` | `owner`, `admin` o `member`. | Tipo enumerado: la base de datos rechaza cualquier otro valor, por ejemplo `superadmin`. |
| `created_at`, `updated_at` | Fechas. | Trazabilidad. |

**Restricciones:**
- **Una persona aparece una sola vez por organización** (`unique(organization_id, user_id)`). Así no puede tener dos roles a la vez en el mismo sitio.
- **Siempre al menos un `owner`.** Se comprueba en las funciones y, además, con un trigger de respaldo. Así ni siquiera un error en una función deja una organización sin dueño.
- **Índice por `user_id`.** Las políticas buscan "¿este usuario es miembro?" en cada consulta, y el índice hace que esa búsqueda sea rápida.

### `audit_log` — historial de operaciones importantes
| Columna | Qué guarda |
|---|---|
| `id` | Identificador del registro. |
| `organization_id` | Organización afectada. |
| `actor_id` | Quién lo hizo (o vacío si fue el sistema). |
| `action` | Qué pasó, por ejemplo `membership.role_changed`. |
| `target_type`, `target_id` | Sobre qué recurso. |
| `details` | Datos útiles en JSON (rol anterior y nuevo, por ejemplo), sin secretos. |
| `created_at` | Cuándo. |

Es de **solo inserción**: solo la escriben las funciones y los triggers del sistema, y nadie puede editarla ni borrarla.

## Funciones auxiliares de permisos (esquema `private`)
| Función | Responde a | Para qué |
|---|---|---|
| `private.is_member(org_id)` | "¿El usuario actual pertenece a esta organización?" | Base de casi todas las políticas de lectura. |
| `private.has_role(org_id, roles)` | "¿El usuario actual tiene alguno de estos roles aquí?" | Políticas y funciones de escritura. |

**Por qué van en un esquema `private`:**
- **No forman parte de la API.** La Data API solo expone el esquema `public`, así que el frontend no puede llamarlas directamente.
- **Evitan una recursión infinita.** Si la política de `memberships` consultara `memberships` directamente, PostgreSQL volvería a aplicar la misma política una y otra vez. Estas funciones son `security definer`: leen la tabla con permisos propios, sin pasar por RLS. Por eso se declaran con `search_path` fijo y solo devuelven verdadero o falso.

## Políticas RLS, explicadas
RLS (*Row Level Security*, seguridad a nivel de fila) añade a cada consulta un filtro invisible que el usuario no puede quitar. Si `owner_b` pide "todas las organizaciones", PostgreSQL le devuelve solo las suyas, aunque la petición no lo diga.

Reglas generales:
- RLS se activa en **las cuatro** tablas.
- `anon` (visitante sin sesión) no recibe ningún permiso.
- Cada política se escribe por operación: leer (`select`), crear (`insert`), modificar (`update`) y borrar (`delete`).

| Tabla | Operación | Quién puede | Para qué sirve esta política |
|---|---|---|---|
| `profiles` | Leer | El propio usuario y quienes compartan alguna organización con él. | Ver los nombres de tus compañeros sin ver a todos los usuarios de Nexo. |
| `profiles` | Modificar | Solo el propio usuario, y solo su fila. | Nadie cambia el nombre de otra persona. |
| `profiles` | Crear / borrar | Nadie directamente. | Los crea el trigger de registro; se borran junto con la cuenta. |
| `organizations` | Leer | Miembros de esa organización. | Aislamiento: no ves que existan organizaciones ajenas. |
| `organizations` | Crear | Nadie directamente; solo con la función `create_organization`. | Crear la organización y su `owner` debe ser **una sola operación**: no puede existir una organización sin dueño. |
| `organizations` | Modificar | `owner` y `admin` de esa organización. | Cumple la matriz. `with check` impide que el cambio la saque de su ámbito. |
| `organizations` | Borrar | Nadie en esta fase. | La eliminación de organizaciones se pospone. |
| `memberships` | Leer | Miembros de la misma organización. | Ver quién está en tu equipo, nunca en otro. |
| `memberships` | Crear / modificar / borrar | Nadie directamente; solo con funciones. | Las reglas (un admin no puede nombrar admins, siempre un owner) son demasiado complejas para una política simple. Las funciones las comprueban dentro de una transacción. |
| `audit_log` | Leer | `owner` y `admin` de esa organización. | Revisar qué pasó; `member` no lo ve, según la matriz. |
| `audit_log` | Crear / modificar / borrar | Nadie directamente. | Un historial que se puede editar no sirve como prueba. |

## Funciones de negocio (RPC)
Son operaciones que el frontend puede llamar. Cada una comprueba permisos, hace todos sus cambios en una transacción ("todo o nada") y escribe en `audit_log`.

| Función | Qué hace | Quién puede |
|---|---|---|
| `create_organization(name)` | Crea la organización y la membresía `owner` del usuario actual. | Cualquier usuario con sesión. |
| `add_member(org_id, email, role)` | Añade a un usuario **ya registrado**. | `owner` (cualquier rol); `admin` (solo `member`). |
| `change_member_role(org_id, user_id, role)` | Cambia un rol. | Solo `owner`; nunca puede dejar la organización sin owner. |
| `remove_member(org_id, user_id)` | Quita a alguien. | `owner` (a cualquiera); `admin` (solo a `member`). |
| `leave_organization(org_id)` | El usuario sale de la organización. | Cualquiera, salvo el último owner. |

En todas, el `org_id` que llega del frontend **se verifica** contra la membresía del usuario autenticado. Si alguien envía el ID de otra organización, recibe un error. El mensaje es genérico, para no revelar si esa organización existe.

### Diseño de `add_member` (decisión confirmada)
Solo añade usuarios que **ya tienen una cuenta registrada y confirmada**. Las invitaciones por correo quedan fuera del MVP.

**Cómo se identifica al usuario:**
- El frontend envía el **correo electrónico**, nunca un `user_id`. Así nadie puede añadir a una persona adivinando o copiando su identificador interno.
- El correo se normaliza (sin espacios, comparación sin distinguir mayúsculas) y se busca en `auth.users` con una función auxiliar del esquema `private`. El frontend no puede llamarla ni leer `auth.users`.
- Solo cuentan cuentas con el correo **confirmado**. Una cuenta sin confirmar podría haberla creado alguien con un correo ajeno.

**Cómo se evita que alguien añada miembros sin permiso.** La función comprueba, en este orden y dentro de una transacción:
1. **Hay sesión.** Sin `auth.uid()`, error.
2. **Quien llama es `owner` o `admin` de esa organización.** Se comprueba *antes* de buscar el correo, para que un usuario sin permiso no pueda usar la función para averiguar qué correos están registrados.
3. **El rol pedido está permitido para quien llama.** `admin` solo puede añadir `member`; `owner` puede añadir cualquier rol.
4. **La cuenta existe y está confirmada.**
5. **La persona no es ya miembro.** Además, la restricción `unique` lo garantiza aunque dos peticiones lleguen a la vez.
6. **Se crea la membresía y se registra `membership.added` en `audit_log`.** Ambas cosas ocurren juntas o no ocurre ninguna.

**Mensajes de error:**
- "Correo no registrado" y "correo sin confirmar" devuelven **el mismo** mensaje genérico ("No se pudo añadir a esta persona"). Así no se revela quién tiene cuenta en Nexo.
- Los fallos de los pasos 1 a 3 devuelven un error de permisos que tampoco confirma si la organización existe.

**Qué devuelve:** el `user_id`, el `display_name` y el rol del nuevo miembro. No devuelve el correo ni otros datos de la cuenta.

**Riesgos que aceptamos en el MVP:**
- Un `owner` o `admin` puede probar correos para saber si están registrados. Lo limita que solo ellos pueden llamar a la función y que cada alta queda auditada. Se añadirá un límite de intentos si hace falta.
- La persona añadida no da su consentimiento previo: queda dentro de la organización y puede salir con `leave_organization`. Las invitaciones con aceptación quedan para después del MVP.

## Alcance sencillo de `profiles` y `audit_log`
- **`profiles`:** solo `id`, `display_name` y fechas. Sin foto, teléfono ni preferencias. No guarda el correo, que sigue en `auth.users`.
- **`audit_log`:** solo registra las acciones de esta fase:
  - `organization.created`;
  - `organization.updated`;
  - `membership.added`;
  - `membership.role_changed`;
  - `membership.removed`;
  - `membership.left`.

  Sin pantallas de búsqueda avanzada, exportaciones ni retención automática.

## Pruebas de seguridad planificadas
Datos de prueba sintéticos:
- Organizaciones A y B.
- Usuarios `owner_a`, `admin_a`, `member_a`, `owner_b`, `sin_membresia` y el visitante anónimo.

Todo con correos `@example.com`.

| Archivo (pgTAP) | Casos permitidos (deben funcionar) | Casos denegados (deben fallar) |
|---|---|---|
| `rls_enabled.test.sql` | — | Ninguna tabla de `public` sin RLS; `anon` sin permisos. |
| `profiles.test.sql` | Ver tu perfil y los de tu organización; editar el tuyo. | Ver perfiles de B; editar el perfil de otro. |
| `organizations.test.sql` | Los miembros de A ven A; `owner_a` y `admin_a` la renombran. | `owner_b` ve, edita o borra A; `member_a` la renombra; insertar directamente sin la función. |
| `memberships.test.sql` | Los miembros de A ven los miembros de A. | `owner_b` ve los miembros de A; cualquiera inserta, edita o borra directamente. |
| `create_organization.test.sql` | Se crea la organización con su owner y queda en auditoría. | Sin sesión; nombre vacío o demasiado largo. |
| `member_management.test.sql` | `owner_a` añade un admin; `admin_a` añade y quita un member; `owner_a` cambia roles; `member_a` sale; el correo funciona con mayúsculas o espacios. | `admin_a` nombra admin u owner; `member_a` añade miembros; `owner_b` gestiona miembros de A; el último owner sale o se degrada; añadir a alguien que ya es miembro; correo no registrado y correo sin confirmar devuelven el mismo mensaje; sin permisos, el error aparece antes de buscar el correo. |
| `audit_log.test.sql` | `owner_a` y `admin_a` leen la auditoría de A. | `member_a` la lee; `owner_b` lee la de A; cualquiera edita o borra un registro. |

Regla: en cada escritura denegada se comprueba, además, que la fila objetivo **sigue intacta**.

## Pasos de implementación (cuando se apruebe)
1. **Estructura:** `supabase init` crea `supabase/config.toml` y las carpetas `migrations/` y `tests/`. Requiere la CLI.
2. **Migración 1 — esquema base:**
   - esquema `private`;
   - tipo de rol;
   - las cuatro tablas con sus restricciones e índices;
   - RLS activado;
   - permisos revocados a `anon`.
3. **Migración 2 — permisos:** funciones auxiliares y políticas RLS.
4. **Migración 3 — operaciones:**
   - trigger de perfiles;
   - trigger de "siempre un owner";
   - funciones RPC;
   - auditoría.
5. **Pruebas:** los archivos pgTAP de la tabla anterior.
6. **Aplicar y verificar en `nexo-dev`:**
   - `db push --dry-run` y luego `db push`;
   - ejecutar las pruebas;
   - revisar el Security Advisor.
7. **Commit en Git** con las migraciones y las pruebas.

Cada paso se revisa antes de pasar al siguiente.

## Criterios de aceptación
- Las migraciones se aplican sin errores en `nexo-dev`.
- Todas las pruebas pgTAP pasan y se anota dónde se ejecutaron.
- Un usuario de B no puede leer, crear, modificar ni borrar nada de A, ni con llamadas directas ni con funciones.
- Cada permiso de la matriz que toca esta fase tiene su prueba permitida y su prueba denegada.
- Las operaciones de membresía quedan en `audit_log`.
- El Security Advisor no muestra avisos críticos en estas tablas.

## Decisiones
**Confirmadas por el propietario (2026-10-23):**
1. `add_member` solo añade usuarios ya registrados; las invitaciones por correo quedan fuera del MVP (diseño arriba).
2. `profiles` y `audit_log` forman parte de esta fase, con el alcance sencillo descrito arriba.

**Pospuesta:**
3. Qué pasa con la auditoría si en el futuro se borra una organización. Como la eliminación de organizaciones se pospone, esta decisión también.
