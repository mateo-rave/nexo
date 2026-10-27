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
- `snake_case` en minúsculas: palabras separadas por `_`, por ejemplo `agregar_miembro`. En TypeScript, funciones y variables van en `camelCase`, y tipos y componentes de React en `PascalCase` (ver "Convenciones de código TypeScript").
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

### Añadidos con la primera entrega del frontend (ADR-0006, 2026-10-24)
| Elemento | Nombre oficial |
|---|---|
| Carpeta de la aplicación | `frontend/`, con su propio `package.json` y `package-lock.json` |
| Variables públicas del frontend | `VITE_SUPABASE_URL` y `VITE_SUPABASE_PUBLISHABLE_KEY`. **El prefijo `VITE_` lo impone Vite y hace que el valor se incluya en el código que llega al navegador**: cualquiera puede leerlo. Solo admite la URL de Supabase y su clave publicable; nunca claves `sb_secret_`, `service_role`, contraseñas ni otros secretos. Aún no se usan en el código: el frontend no está conectado al backend. |
| Archivos de código | `snake_case`: `aplicacion.tsx`, `estilos.css`, `tema/tema.ts`, `ruta/ruta.ts`, `componentes/` (`simbolo_nexo.tsx`, `selector_tema.tsx`, `etiqueta_estado.tsx`, `estados.ts`, `pista.tsx`), `portada/` (`portada.tsx`, `diagrama_flujo.tsx`) y `demostracion/` (`panel_demostracion.tsx`, `secciones_panel.tsx`, `datos_demostracion.ts`, `derivados.ts`). `main.tsx`, `index.html`, `vite.config.ts`, `tsconfig*.json` y `.oxlintrc.json` conservan el nombre que esperan las herramientas. |
| Hooks de React | Prefijo `use` obligatorio, porque React y su lint solo reconocen así los hooks: `useTema`, `useVista`. El resto del nombre, en español. |
| Tokens de color (variables CSS) | En español y con guiones, como exige CSS: `--fondo`, `--superficie`, `--superficie-elevada`, `--acento`, `--texto`, `--texto-secundario`, `--exito`, `--atencion`, `--error`, `--informacion`, `--sobre-acento` y los derivados `--borde`, `--borde-fuerte` y `--<color>-suave`. En Tailwind se usan como `bg-fondo`, `text-texto-2`, `border-borde`… |
| Tema | Atributo `data-tema` en `<html>`, con valores `claro` y `oscuro`; preferencia `sistema`, `claro` u `oscuro`, guardada en `localStorage` con la clave `nexo-tema` (ausente = seguir al sistema). |
| Vistas (hash de la URL) | `#/` (portada) y `#/demostracion` (panel de demostración). |
| Señales de una tarea en el panel de demostración (se superponen al estado del flujo) | `bloqueada`, `vencida` y `en_riesgo` (tipo `TipoSenal`). «En riesgo»: vence en 48 horas o menos y aún no ha vencido. Solo existen en la demostración: el bloqueo manual y «en riesgo» quedan fuera del MVP (ADR-0007). |
| Motivos de espera (ilustrativos, no existen en el backend) | `cliente`, `equipo` e `informacion` (tipo `EsperandoA`). |
| Componentes del panel de demostración | `NecesitaIntervencion`, `ContextoOperativo`, `ProximosVencimientos`, `EsperandoA`, `FlujoTareas`, `ActividadReciente`, `EtiquetaSenal` y `Pista` (pista contextual accesible). |
| Utilidades CSS de movimiento | `transicion`, `linea-activa`, `entrada` (entrada escalonada, con la variable `--retraso`) y `aparecer`. |
| Scripts de npm del frontend | `dev`, `build`, `typecheck`, `lint` y `preview`: nombres estándar que esperan las herramientas y Vercel. |

### Añadidos con la integración del frontend (fase 3, 2026-10-25)
| Elemento | Nombre oficial |
|---|---|
| Archivos | `supabase/cliente.ts` y `supabase/errores.ts` (cliente y mensajes de error), `sesion/sesion.ts` y `espacio/` (`espacio.tsx`, `acceso.tsx`, `proyectos.tsx`, `tareas.tsx`, `notificaciones.tsx`, `datos.ts`, `carga.ts`, `ui.tsx`) |
| Hooks | `useSesion` y `useCarga` |
| Vista y almacenamiento | Vista `espacio` en `#/app` (aplicación conectada al backend); la organización mostrada se recuerda en `localStorage` con la clave `nexo-organizacion` |
| Componentes | `Espacio`, `Acceso`, `Proyectos`, `TareasProyecto`, `FilaTarea`, `Notificaciones`, `Aviso`, `AvisoError`, `Cargando`, `EsqueletoLista` y `Campo`; clases compartidas `claseBotonPrincipal`, `claseBotonSecundario`, `claseBotonFila` y `claseCampo` |
| Pruebas E2E | `frontend/e2e/recorrido.spec.ts` (Playwright, configuración en `frontend/playwright.config.ts`) y script de npm `e2e`; en CI, job `frontend` (tipos, lint, build y comprobación de claves en el bundle) y pasos E2E en el job `pgtap` |

### Añadidos con el panel operativo (fase 3, 2026-10-25)
| Elemento | Nombre oficial |
|---|---|
| Archivos | `espacio/panel.tsx` (panel operativo) y `espacio/formato.ts` (formato de fechas: `textoVencimiento` y `textoInstante`) |
| Datos | Tipos `Prioridad` y `HallazgoAbierto`; funciones `listarHallazgosAbiertos`, `resolverHallazgo` (RPC `resolver_hallazgo`) y `listarEstadosDeTareas` |
| Secciones del espacio | `panel` (inicial), `proyectos` y `notificaciones`; tipo `Abierto` (`proyectoId` y `tareaId` opcional) para abrir una tarea desde el panel, que se resalta con `tareaDestacada` |
| Componentes | `Panel`, `FilaHallazgo`, `ResumenProyectos` y `NotificacionesRecientes` |
| Pruebas E2E | `frontend/e2e/panel.spec.ts` (espera a la detección programada, abre la tarea y resuelve el hallazgo) |

### Añadidos con el rediseño de la portada (2026-10-25)
| Elemento | Nombre oficial |
|---|---|
| Archivos | `portada/maqueta_producto.tsx` (maqueta ilustrativa del producto) |
| Componentes | `MaquetaProducto`, `Tarjeta`, `Pieza`, `EtiquetaDisponibilidad` y `ColumnaPie`; tipo `Disponibilidad` (`disponible`, `en_desarrollo`, `planificado`, `proximamente`) |
| Rutas | `enlaceRegistro` (`#/app/registro`): abre el espacio con el formulario de registro |

### Añadidos con el rediseño de las pantallas de acceso (2026-10-26)
| Elemento | Nombre oficial |
|---|---|
| Archivos | `espacio/panel_acceso.tsx` (panel visual ilustrativo de las pantallas de acceso) |
| Componentes | `PanelAcceso`, `Tramo`, `CampoAcceso` y `CampoContrasena`; tipos `EstadoEtapa` (`completada`, `activa`, `pendiente`) y `Errores` |
| Utilidades CSS de movimiento | `entrada-lateral`, `pulso-acento`, `encender`, `trazo-activo`, `latido` y `reticula-puntos` |

### Añadidos con el motor de reglas de automatización (ADR-0008, fase 5, 2026-10-27)
| Elemento | Nombre oficial |
|---|---|
| Tipos | `tipo_evento_automatizacion` (`tarea_estado_cambiado`, `tarea_vencida`), `estado_version_regla` (`borrador`, `publicada`), `estado_ejecucion` (`pendiente`, `exitosa`, `fallida`, `omitida`) y `estado_accion` (`programada`, `completada`, `fallida`) |
| Tablas | `reglas_automatizacion`, `versiones_regla`, `periodos_activacion_regla`, `eventos_automatizacion`, `ejecuciones_automatizacion` y `acciones_automatizacion` |
| Columnas | `activador`, `condiciones`, `acciones` y `publicada_en` (en `versiones_regla`); `activada_en` y `desactivada_en` (periodos); `tipo`, `clave_evento`, `datos`, `ocurrido_en`, `ejecucion_origen_id`, `profundidad`, `procesado_en`, `intentos_reparto` y `codigo_error` (eventos); `version_regla_id`, `evento_id`, `intentos`, `max_intentos`, `proximo_intento_en`, `iniciada_en`, `terminada_en`, `codigo_error`, `mensaje_error` y `resultado` (ejecuciones); `orden` (acciones); `evento_id` y `accion_id` (en `notificaciones`). `version_regla_id` sigue la convención de `version_flujo_id` en lugar de `version_regla` |
| Catálogo (valores del contrato) | Condiciones `estado_destino` (clave `estados`), `proyecto` (clave `proyecto_id`) y `con_responsable` (clave `valor`); acción `notificar` (clave `destinatarios`: `responsable` o `propietarios_y_administradores`); motivo de omisión de un destinatario `ya_notificado` |
| RPC | `crear_regla`, `guardar_borrador_regla`, `crear_version_borrador_regla`, `publicar_version_regla`, `activar_regla` y `pausar_regla` (argumentos `p_organizacion_id`, `p_nombre`, `p_activador`, `p_condiciones`, `p_acciones`, `p_version_regla_id` y `p_regla_id`) |
| Funciones internas (`privado`) | `activador_de_texto`, `validar_definicion_regla`, `organizacion_de_regla`, `organizacion_de_version_regla`, `etiqueta_estado_tarea`, `mensaje_resultado_automatizacion`, `condiciones_cumplidas`, `motivo_omision_automatizacion`, `ejecutar_accion_notificar`, `ejecutar_automatizacion`, `registrar_fallo_ejecucion` y `procesar_automatizaciones`; de triggers: `proteger_version_regla`, `proteger_periodo_activacion_regla`, `validar_origen_notificacion`, `validar_evento_automatizacion` y `emitir_evento_estado_tarea`. `privado.detectar_tareas_vencidas` se reemplaza para emitir el evento |
| Parámetro de sesión | `nexo.ejecucion_origen_id`: lo fija el motor en su transacción para que el evento de un cambio causado por una acción herede su origen |
| Job de Cron | `procesar_automatizaciones` |
| Acciones de auditoría | `regla.creada`, `version_regla.borrador_guardado`, `version_regla.borrador_creado`, `version_regla.publicada`, `regla.activada`, `regla.pausada`, `ejecucion.terminada` y `evento.reparto_fallido` (tipos de recurso `regla`, `version_regla`, `ejecucion` y `evento`) |
| Códigos de error nuevos | `activador_invalido`, `condiciones_invalidas`, `demasiadas_condiciones`, `condicion_desconocida`, `condicion_repetida`, `condicion_no_aplicable`, `condicion_invalida`, `proyecto_invalido`, `acciones_invalidas`, `sin_acciones`, `demasiadas_acciones`, `accion_desconocida`, `accion_invalida`, `version_regla_inmutable`, `periodo_no_eliminable`, `periodo_cerrado_inmutable`, `periodo_cambio_no_permitido`, `regla_no_encontrada`, `version_regla_no_encontrada`, `regla_ya_activa`, `regla_sin_version_publicada`, `activacion_no_valida`, `regla_no_activa`, `origen_notificacion_invalido`, `evento_sin_tarea` y `evento_sin_hallazgo`. Reutiliza `nombre_invalido`, `version_publicada_inmutable`, `publicacion_directa_no_permitida`, `version_no_publicada`, `borrador_existente`, `version_ya_publicada` y `ahora_invalido` |
| Códigos de resultado de una ejecución | `condiciones_no_cumplidas`, `tarea_no_disponible`, `hallazgo_resuelto`, `profundidad_maxima`, `ciclo_detectado` (omitida); `fallo_transitorio` (pendiente de reintento); `reintentos_agotados` y `error_interno` (fallida); `error_registro` (pendiente de reintento o fallida, si falló el registro del resultado); `reparto_fallido` (evento descartado tras 3 fallos de reparto) |
| Archivos de prueba | `supabase/tests/reglas_automatizacion.test.sql`, `supabase/tests/ejecucion_automatizaciones.test.sql` y `pruebas/api/reglas_automatizacion.test.ts` |

### Añadidos con los flujos versionados (ADR-0007, fase 2, 2026-10-25)
| Elemento | Nombre oficial |
|---|---|
| Tipos | `estado_tarea` (`pendiente`, `en_curso`, `en_revision`, `completada`, `cancelada`) y `estado_version_flujo` (`borrador`, `publicada`) |
| Tablas | `definiciones_flujo`, `versiones_flujo`, `estados_version_flujo` y `transiciones_version_flujo` |
| Columnas | `zona_horaria` (en `organizaciones`); `es_predeterminado`; `definicion_flujo_id`, `numero`, `estado_inicial` y `publicada_en` (en `versiones_flujo`); `version_flujo_id`; `estado_origen` y `estado_destino` |
| Funciones internas (`privado`) | `es_estado_terminal`, `transicion_permitida`, `crear_flujo_predeterminado`; de triggers: `validar_zona_horaria`, `proteger_version_flujo`, `proteger_contenido_version_flujo` y `crear_flujo_al_crear_organizacion` |
| Códigos de error (`detail`) | `zona_horaria_invalida`, `publicacion_directa_no_permitida`, `version_publicada_inmutable`, `version_flujo_inmutable`, `estado_inicial_no_incluido` y `sin_estado_terminal` |
| Nombre del flujo creado automáticamente | «Flujo predeterminado» |

### Añadidos con proyectos y tareas (ADR-0007, fase 2, 2026-10-25)
| Elemento | Nombre oficial |
|---|---|
| Tablas | `proyectos` y `tareas` |
| Columnas | `version_flujo_id`, `archivado_en` (en `proyectos`); `proyecto_id`, `titulo`, `descripcion`, `responsable_id`, `fecha_limite` y `vence_en` (en `tareas`) |
| RPC | `crear_proyecto`, `archivar_proyecto`, `crear_tarea`, `editar_tarea`, `asignar_responsable`, `cambiar_estado_tarea`, `eliminar_tarea` y `cambiar_zona_horaria` |
| Argumentos de RPC | `p_proyecto_id`, `p_tarea_id`, `p_titulo`, `p_descripcion`, `p_responsable_id`, `p_fecha_limite`, `p_hora_limite`, `p_estado`, `p_version_flujo_id`, `p_archivado` y `p_zona_horaria` |
| Funciones internas (`privado`) | `vence_en_de_fecha`, `tarea_vencida`, `autorizar_escritura_tarea`, `bloquear_tarea`, `puede_gestionar_tarea`, `validar_responsable`, `validar_texto_tarea`, `vence_en_con_hora`; de triggers: `proteger_proyecto`, `preparar_tarea` y `retirar_responsable_de_tareas` |
| Acciones de auditoría | `proyecto.creado`, `proyecto.archivado`, `proyecto.desarchivado`, `tarea.creada`, `tarea.editada`, `tarea.reasignada`, `tarea.estado_cambiado`, `tarea.eliminada`, `tarea.responsable_retirado` y `organizacion.zona_horaria_cambiada` |
| Gestión de flujos (ADR-0007, fase 2, bloque 4) | RPC `crear_flujo`, `crear_version_borrador`, `guardar_borrador_flujo` y `publicar_version_flujo` (argumentos `p_nombre`, `p_version_flujo_id`, `p_estados`, `p_estado_inicial` y `p_transiciones`, lista JSON de objetos con las claves `origen` y `destino`); funciones `privado.autorizar_gestion_flujos`, `privado.organizacion_de_version_flujo` y `privado.flujo_tiene_salida`; acciones de auditoría `flujo.creado`, `version_flujo.borrador_creado`, `version_flujo.borrador_guardado` y `version_flujo.publicada`; códigos de error `version_flujo_no_encontrada`, `version_no_publicada`, `borrador_existente`, `estados_invalidos`, `estado_inicial_terminal`, `transiciones_invalidas`, `transicion_invalida`, `version_ya_publicada` y `flujo_sin_salida` |
| Códigos de error (`detail`) del bloque de detección | `ahora_invalido`, `hallazgo_no_encontrado`, `hallazgo_ya_resuelto` y `notificacion_no_encontrada` |
| Detección (ADR-0007, fase 2, bloque 3) | Tipos `tipo_hallazgo` (`tarea_vencida`) y `prioridad_hallazgo` (`baja`, `media`, `alta`); tablas `hallazgos` (`tarea_id`, `tipo`, `prioridad`, `clave_deduplicacion`, `evidencia`, `detectado_en`, `resuelto_en`, `resuelto_por`) y `notificaciones` (`destinatario_id`, `hallazgo_id`, `titulo`, `mensaje`, `leida_en`); funciones `privado.detectar_tareas_vencidas` y `privado.clave_hallazgo_vencimiento`; RPC `resolver_hallazgo` y `marcar_notificacion_leida` (argumentos `p_hallazgo_id`, `p_notificacion_id`); job de Cron `detectar_tareas_vencidas`; acciones de auditoría `hallazgo.creado` y `hallazgo.resuelto` |
| Códigos de error (`detail`) | `proyecto_no_encontrado`, `tarea_no_encontrada`, `proyecto_archivado`, `proyecto_sin_cambios`, `archivado_invalido`, `version_flujo_no_disponible`, `version_proyecto_inmutable`, `proyecto_inmutable`, `titulo_invalido`, `descripcion_invalida`, `responsable_no_es_miembro`, `responsable_sin_cambios`, `hora_sin_fecha`, `estado_invalido`, `estado_sin_cambios`, `transicion_no_permitida`, `tarea_sin_cambios` y `zona_horaria_sin_cambios` |

**Convenciones de código TypeScript** (decisión del 2026-10-24): los nombres siguen en español, pero cada lenguaje conserva su estilo habitual.
- Funciones, variables y propiedades propias en `camelCase`: `prepararEscenario`, `llamarRpc`, `estadoHttp`, `organizacionA`.
- Tipos, interfaces y clases en `PascalCase`: `ResultadoRpc`, `RechazoEsperado`, `FotoEstado`. Los componentes de React también, porque JSX exige que empiecen por mayúscula (ADR-0006).
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
