# ADR-0005: Nombres del código en español

- Estado: Aceptada
- Fecha: 2026-10-23
- Responsables: propietario del producto

> **En pocas palabras:** todo lo que nosotros nombremos en el desarrollo de Nexo (tablas, columnas, funciones, roles, estados, archivos de prueba, variables propias) se escribe en español, en minúsculas, con guion bajo y sin tildes ni ñ. Solo queda en inglés lo que imponen PostgreSQL, Supabase u otras herramientas.

## Contexto
El propietario aprende desarrollo de software y quiere leer y entender el código en su idioma. Los documentos ya están en español, pero los nombres técnicos planificados estaban en inglés (`organizations`, `add_member`, `owner`...).

## Opciones consideradas
1. **Todo en inglés.** Es la convención más común en la industria y coincide con los ejemplos de la documentación. Para el propietario es más difícil de leer, y mezcla idiomas con la documentación.
2. **Todo en español, sin tildes ni ñ.** Se lee de forma natural y es coherente con la documentación. La desventaja es que convive con nombres en inglés que no podemos cambiar (`auth.uid()`, `select`).
3. **Español con tildes y ñ** (`membresías`, `añadir`). PostgreSQL obliga a escribir esos nombres siempre entre comillas dobles, lo que provoca errores frecuentes y difíciles de ver.

## Decisión
Opción 2.

### Reglas
- `snake_case` en minúsculas: palabras separadas por `_`, por ejemplo `agregar_miembro`. En TypeScript, funciones y variables van en `camelCase` y tipos en `PascalCase` (ver "Convenciones de código TypeScript").
- Sin tildes ni ñ: `membresias`, `auditoria`, `anadir` → mejor `agregar`.
- Tablas en plural (`organizaciones`); columnas en singular (`rol`); claves foráneas `<entidad>_id` (`organizacion_id`).
- Funciones con un verbo en infinitivo (`crear_organizacion`); funciones que responden sí/no empiezan por `es_` o `tiene_`.
- Estados como adjetivos o participios en femenino cuando se refieren a "ejecución" o "acción" (`exitosa`, `fallida`, `programada`).
- Acciones de auditoría con la forma `entidad.participio` (`miembro.agregado`).
- Archivos de prueba en español (`membresias.test.sql`); la extensión `.test.sql` la exige la herramienta.
- Variables de entorno propias en español (`ORIGENES_PERMITIDOS`).
- Mensajes de commit en español, conservando el prefijo estándar (`docs:`, `feat:`, `fix:`, `test:`).
- Los mensajes de error que vea el usuario, en español.

### Lo que sigue en inglés (no depende de nosotros)
- Palabras de SQL: `select`, `insert`, `create table`, `security definer`, `with check`…
- Elementos de Supabase y PostgreSQL: `auth.uid()`, `auth.users`, esquemas `public` y `auth`, roles `anon` y `authenticated`, la clave `service_role`, variables `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY` y `SUPABASE_DB_URL`.
- Nombres de herramientas y comandos: `supabase db push`, `deno test`, la rama `main` de Git.
- Funciones de librerías externas como pgTAP: `results_eq`, `throws_ok`…

## Glosario oficial
Si se necesita un nombre nuevo, se añade aquí antes de usarlo.

### Esquemas, tablas y módulos
| Antes | Nombre oficial |
|---|---|
| `private` (esquema) | `privado` |
| `profiles` | `perfiles` |
| `organizations` | `organizaciones` |
| `memberships` | `membresias` |
| `audit_log` | `auditoria` |
| `notifications` | `notificaciones` |
| `workflow_definitions` | `definiciones_flujo` |
| `workflow_versions` | `versiones_flujo` |
| `automation_rules` | `reglas_automatizacion` |
| `automation_runs` | `ejecuciones_automatizacion` |
| `automation_actions` | `acciones_automatizacion` |
| módulos `accounts`, `projects`, `tasks`, `workflows`, `automation`, `monitoring`, `audit`, `integrations` | `cuentas`, `proyectos`, `tareas`, `flujos`, `automatizacion`, `monitoreo`, `auditoria`, `integraciones` |

### Columnas
| Antes | Nombre oficial |
|---|---|
| `organization_id`, `org_id` | `organizacion_id` |
| `user_id` | `usuario_id` |
| `role` | `rol` |
| `name` | `nombre` |
| `display_name` | `nombre_visible` |
| `email` | `correo` |
| `created_by` | `creado_por` |
| `created_at` | `creado_en` |
| `updated_at` | `actualizado_en` |
| `actor_id` | `actor_id` (también es palabra española) |
| `action` | `accion` |
| `target_type`, `target_id` | `tipo_recurso`, `recurso_id` |
| `details` | `detalles` |
| `status` | `estado` |
| `rule_id`, `rule_version` | `regla_id`, `version_regla` |
| `trigger_event_id` | `evento_id` |
| `idempotency_key` | `clave_idempotencia` |
| `attempts`, `max_attempts` | `intentos`, `max_intentos` |
| `error_code` | `codigo_error` |
| `origin_run_id` | `ejecucion_origen_id` |
| `parent_id` | `padre_id` |

### Roles
| Antes | Nombre oficial |
|---|---|
| `owner` | `propietario` |
| `admin` | `administrador` |
| `member` | `miembro` |

### Estados
| Antes | Nombre oficial |
|---|---|
| `pending`, `running`, `succeeded`, `failed`, `skipped` | `pendiente`, `en_ejecucion`, `exitosa`, `fallida`, `omitida` |
| `scheduled`, `completed` | `programada`, `completada` |
| `draft`, `published` | `borrador`, `publicada` |

### Funciones
| Antes | Nombre oficial |
|---|---|
| `private.is_member(org_id)` | `privado.es_miembro(organizacion_id)` |
| `private.has_role(org_id, roles)` | `privado.tiene_rol(organizacion_id, roles)` |
| `create_organization` | `crear_organizacion` |
| `add_member` | `agregar_miembro` |
| `change_member_role` | `cambiar_rol_miembro` |
| `remove_member` | `quitar_miembro` |
| `leave_organization` | `salir_de_organizacion` |
| Edge Function `health` | `salud` |

### Acciones de auditoría
| Antes | Nombre oficial |
|---|---|
| `organization.created`, `organization.updated` | `organizacion.creada`, `organizacion.actualizada` |
| `membership.added`, `membership.role_changed` | `miembro.agregado`, `miembro.rol_cambiado` |
| `membership.removed`, `membership.left` | `miembro.quitado`, `miembro.salio` |

### Añadidos con la migración de esquema base (2026-10-24)
| Elemento | Nombre oficial |
|---|---|
| Tipo enumerado de roles | `rol_membresia` |
| Función: ¿comparto alguna organización con este usuario? | `privado.tiene_organizacion_en_comun(usuario_id)` |
| Trigger: actualizar `actualizado_en` | `privado.asignar_actualizado_en()` |
| Trigger: crear el perfil al registrarse | `privado.crear_perfil()` |
| Trigger: siempre al menos un propietario | `privado.exigir_propietario()` |
| Trigger: bloquear cambio de `organizacion_id` | `privado.impedir_cambio_organizacion_id()` |
| Trigger: auditoría de solo inserción | `privado.impedir_cambios_auditoria()` |
| Trigger: auditar el cambio de nombre | `privado.auditar_organizacion_actualizada()` |
| Valores de `tipo_recurso` | `organizacion`, `membresia` |
| Claves de `detalles` | `nombre`, `nombre_anterior`, `nombre_nuevo`, `rol` |
| Dato que envía el frontend al registrarse (`options.data`) | `nombre_visible` |
| Códigos de error propios (campo `details` de la respuesta) | `sesion_requerida`, `nombre_invalido`, `perfil_inexistente`, `ultimo_propietario`, `auditoria_inmutable`, `organizacion_inmutable` |
| Workflow de GitHub Actions para pgTAP | `.github/workflows/pruebas-base-datos.yml` (nombre visible "Pruebas de base de datos", job `pgtap`) |

### Añadidos con la migración de gestión de miembros (migración 2 de la fase 1, 2026-10-24)
Las cuatro RPC (`agregar_miembro`, `cambiar_rol_miembro`, `quitar_miembro`, `salir_de_organizacion`) y sus acciones de auditoría ya figuraban en el glosario.

| Elemento | Nombre oficial |
|---|---|
| Función: buscar la única cuenta elegible para un correo | `privado.buscar_usuario_confirmado(correo)` |
| Función: rechazar niveles de aislamiento distintos de `read committed` | `privado.exigir_read_committed()` |
| Claves de `detalles` en `miembro.rol_cambiado` | `rol_anterior`, `rol_nuevo` |
| Códigos de error nuevos (campo `details` de la respuesta) | `permiso_denegado`, `rol_no_permitido`, `rol_invalido`, `correo_invalido`, `usuario_no_disponible`, `ya_es_miembro`, `miembro_no_encontrado`, `rol_sin_cambios`, `accion_no_permitida`, `aislamiento_no_soportado` |
| Archivos de prueba | `agregar_miembro.test.sql`, `cambiar_rol_miembro.test.sql`, `quitar_miembro.test.sql`, `salir_de_organizacion.test.sql`, `aislamiento_rpc.test.sql` |

### Añadidos con las pruebas de integración de API (2026-10-24)
| Elemento | Nombre oficial |
|---|---|
| Carpeta de las pruebas de integración de API | `pruebas/api/` (`api` es un término técnico aceptado) |
| Archivos de prueba (Deno exige el sufijo `.test.ts`) | `agregar_miembro.test.ts`, `cambiar_rol_miembro.test.ts`, `quitar_miembro.test.ts`, `salir_de_organizacion.test.ts` |
| Módulo de auxiliares compartidos | `auxiliares.ts` |
| Job del workflow `pruebas-base-datos.yml` | id `pgtap` sin cambios; nombre visible "pgTAP y API en Supabase local" |
| Variables de entorno de las pruebas | `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` (nombres de Supabase, ya en la lista de excepciones) |

**Convenciones de código TypeScript** (decisión del 2026-10-24): los nombres siguen en español, pero cada lenguaje conserva su estilo habitual.
- Funciones, variables y propiedades propias en `camelCase`: `prepararEscenario`, `llamarRpc`, `estadoHttp`, `organizacionA`.
- Tipos, interfaces y clases en `PascalCase`: `ResultadoRpc`, `RechazoEsperado`, `FotoEstado`.
- Los objetos SQL siguen en `snake_case`, y desde TypeScript se escriben exactamente igual: nombres de RPC (`agregar_miembro`), argumentos (`p_organizacion_id`), tablas y columnas (`membresias`, `organizacion_id`).
- Los campos de datos de la API (respuestas, filas y metadatos que se envían) conservan los nombres del contrato: `usuario_id`, `nombre_visible`, `actor_id`, `recurso_id`, `detalles`; también los códigos de error que llegan en `details` (`permiso_denegado`), que se usan como claves del catálogo de rechazos esperados.
- Los nombres oficiales de los usuarios de prueba (`propietario_a`, `sin_membresia`...) se mantienen como en este glosario, también como claves en TypeScript.
- Se mantienen en inglés las APIs de librerías y del entorno (`createClient`, `Deno.test`, `Response.status`) y los campos de error de PostgREST (`code`, `message`, `details`, `hint`).
- Las descripciones de los casos de prueba van en español y empiezan por el nombre de la RPC: `"quitar_miembro: un miembro no puede quitar a nadie"`.
- La regla general de `snake_case` de este ADR se aplica a SQL, archivos, variables de entorno y valores del contrato; en TypeScript prevalece esta lista.

**Convenciones de código SQL:**
- Parámetros de función con prefijo `p_` (`p_nombre`) y variables con `v_` (`v_usuario_id`), para no confundirlos con columnas del mismo nombre.
- Triggers: `<tabla>_<que_hace>` (`membresias_exigir_propietario`).
- Índices: `<tabla>_<columnas>_indice`. Restricciones `check`: `<tabla>_<columna>_valido`.
- Los nombres automáticos de PostgreSQL para claves primarias y foráneas (`_pkey`, `_fkey`) se aceptan como impuestos por la herramienta.

### Usuarios de prueba
`propietario_a`, `administrador_a`, `miembro_a`, `propietario_b`, `sin_membresia` y el visitante anónimo (`anon`).

## Consecuencias
- Hay que tener cuidado al copiar ejemplos de la documentación de Supabase, que están en inglés: se adaptan los nombres propios al glosario.
- Un desarrollador que no hable español necesitará este glosario. Es aceptable para el contexto actual del proyecto.
- Los documentos existentes se actualizaron con estos nombres el 2026-10-23. Los commits anteriores conservan los nombres en inglés.

## Cómo se verificará
- En cada revisión de una migración, una función o una prueba, se buscan nombres propios en inglés que no estén en la lista de excepciones.
