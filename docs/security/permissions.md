# Roles y permisos de Nexo

Estado: aceptado para el MVP (ver [ADR-0002](../architecture/decisions/0002-autenticacion-y-autorizacion-multiempresa.md)). Este es el **único** lugar donde se mantiene la matriz de permisos; los demás documentos la enlazan. Cualquier cambio de la matriz requiere actualizar las políticas RLS, las funciones afectadas y sus pruebas en el mismo cambio.

## Principios
- **Denegar por defecto:** si una acción no aparece permitida en esta matriz, está prohibida.
- **Por organización:** un rol solo vale dentro de la organización de la membresía. Ser `propietario` en A no da ningún permiso en B.
- **Sin membresía, sin acceso:** un usuario autenticado sin membresía en una organización no ve que esa organización existe.
- **Sin acceso anónimo:** el rol `anon` no lee ni escribe datos de negocio.
- **El identificador no autoriza:** conocer o enviar el ID de un recurso (organización, proyecto, tarea, regla) nunca concede acceso; se verifica la membresía del usuario autenticado.
- **La base de datos lo hace cumplir:** cada fila de esta matriz se traduce en políticas RLS, restricciones o validaciones en funciones SQL, no en el frontend.

## Roles iniciales
| Rol | Para quién | Resumen |
|---|---|---|
| `propietario` | Quien crea la organización o recibe la propiedad. | Control total de la organización, incluida la gestión de administradores. Siempre debe existir al menos uno. |
| `administrador` | Coordinadores del equipo. | Gestiona proyectos, flujos, reglas y miembros con rol `miembro`. |
| `miembro` | Personas que ejecutan el trabajo. | Trabaja con tareas y consulta la información de la organización. |

## Matriz de permisos
✅ permitido · ❌ denegado · *condición* = permitido solo si se cumple.

### Organización y miembros
| Acción | propietario | administrador | miembro |
|---|---|---|---|
| Ver la organización | ✅ | ✅ | ✅ |
| Editar nombre y datos de la organización | ✅ | ✅ | ❌ |
| Eliminar la organización | ✅ | ❌ | ❌ |
| Ver la lista de miembros y sus roles | ✅ | ✅ | ✅ |
| Añadir un miembro con rol `miembro` | ✅ | ✅ | ❌ |
| Añadir un miembro con rol `administrador` u `propietario` | ✅ | ❌ | ❌ |
| Cambiar el rol de un miembro | ✅ | ❌ | ❌ |
| Quitar a un `miembro` | ✅ | ✅ | ❌ |
| Quitar a un `administrador` u `propietario` | ✅ | ❌ | ❌ |
| Salir de la organización | *si no es el último propietario* | ✅ | ✅ |

Regla adicional: ninguna operación puede dejar a la organización sin `propietario`.

### Proyectos y tareas
| Acción | propietario | administrador | miembro |
|---|---|---|---|
| Ver proyectos | ✅ | ✅ | ✅ |
| Crear, editar y archivar proyectos | ✅ | ✅ | ❌ |
| Eliminar proyectos | ✅ | ✅ | ❌ |
| Ver tareas | ✅ | ✅ | ✅ |
| Crear tareas | ✅ | ✅ | ✅ |
| Editar título, descripción y fecha límite | ✅ | ✅ | *si es responsable o creador de la tarea* |
| Asignar responsable (solo a miembros de la misma organización) | ✅ | ✅ | ✅ |
| Cambiar estado (solo transiciones permitidas) | ✅ | ✅ | *si es responsable o creador de la tarea* |
| Eliminar tareas | ✅ | ✅ | ❌ |

### Flujos, reglas y ejecuciones
| Acción | propietario | administrador | miembro |
|---|---|---|---|
| Ver flujos y reglas | ✅ | ✅ | ✅ |
| Crear y editar borradores de flujos y reglas | ✅ | ✅ | ❌ |
| Publicar una versión (queda inmutable) | ✅ | ✅ | ❌ |
| Activar o desactivar una regla | ✅ | ✅ | ❌ |
| Modificar una versión ya publicada | ❌ | ❌ | ❌ |
| Ver ejecuciones y sus errores | ✅ | ✅ | ✅ |
| Reintentar manualmente una ejecución fallida | ✅ | ✅ | ❌ |

### Detección, notificaciones, métricas y auditoría
| Acción | propietario | administrador | miembro |
|---|---|---|---|
| Ver hallazgos (tareas vencidas) | ✅ | ✅ | ✅ |
| Marcar un hallazgo como resuelto | ✅ | ✅ | *si es responsable de la tarea afectada* |
| Ver y marcar como leídas **sus propias** notificaciones | ✅ | ✅ | ✅ |
| Ver notificaciones de otras personas | ❌ | ❌ | ❌ |
| Ver métricas sencillas de la organización | ✅ | ✅ | ✅ |
| Ver el historial de auditoría | ✅ | ✅ | ❌ |
| Editar o borrar registros de auditoría | ❌ | ❌ | ❌ |

Las ejecuciones, hallazgos, notificaciones y registros de auditoría los crea el sistema (funciones SQL y tareas programadas), no los usuarios directamente.

## Operaciones que quedan en auditoría
Se registran como mínimo: quién (usuario o "sistema"), qué acción, sobre qué recurso, en qué organización, cuándo y, si aplica, valores anteriores y nuevos (sin secretos ni contenido privado innecesario).

- Creación y eliminación de organizaciones.
- Altas, bajas y cambios de rol de miembros.
- Creación, archivado y eliminación de proyectos.
- Creación, cambio de estado, reasignación y eliminación de tareas.
- Publicación de versiones de flujos y reglas; activación y desactivación de reglas.
- Inicio, resultado y reintentos de ejecuciones de automatización.
- Creación y resolución de hallazgos.
- Intentos rechazados en funciones sensibles (cambio de rol, publicación), cuando sea posible registrarlos sin exponer datos de otra organización.

## Cómo se prueba
Por cada fila de la matriz debe existir al menos una prueba del caso **permitido** y una del caso **denegado** (rol insuficiente, otra organización, sin membresía o anónimo). Detalle en [test-strategy.md](../qa/test-strategy.md).

## Revisión
La matriz es inicial y se ajustará con el uso real. Ampliar permisos de `miembro` o crear roles nuevos (p. ej. solo lectura) requiere actualizar este documento y la ADR-0002.
