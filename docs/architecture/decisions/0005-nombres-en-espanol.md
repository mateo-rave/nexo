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
- `snake_case` en minúsculas: palabras separadas por `_`, por ejemplo `agregar_miembro`.
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

### Usuarios de prueba
`propietario_a`, `administrador_a`, `miembro_a`, `propietario_b`, `sin_membresia` y el visitante anónimo (`anon`).

## Consecuencias
- Hay que tener cuidado al copiar ejemplos de la documentación de Supabase, que están en inglés: se adaptan los nombres propios al glosario.
- Un desarrollador que no hable español necesitará este glosario. Es aceptable para el contexto actual del proyecto.
- Los documentos existentes se actualizaron con estos nombres el 2026-10-23. Los commits anteriores conservan los nombres en inglés.

## Cómo se verificará
- En cada revisión de una migración, una función o una prueba, se buscan nombres propios en inglés que no estén en la lista de excepciones.
