# Alcance del MVP

## Objetivo
Validar si equipos pequeños de servicios pueden usar Nexo para coordinar un proceso repetitivo, detectar bloqueos y automatizar al menos una acción de bajo riesgo.

## Flujo prioritario
1. Registrar usuario.
2. Crear organización.
3. Crear proyecto.
4. Crear tarea y asignar responsable/fecha límite.
5. Configurar una regla limitada, por ejemplo detectar una tarea vencida.
6. Ejecutar el chequeo mediante un mecanismo controlado.
7. Crear un hallazgo y una notificación interna.
8. Consultar el historial de actividad y ejecución.

## Construir primero
- Identidad (Supabase Auth) y organizaciones.
- Membresías, roles y políticas RLS con pruebas de aislamiento.
- Proyectos y tareas.
- Flujo básico con definición estructurada y versiones publicadas inmutables (alcance mínimo: estados y transiciones permitidas de un proceso).
- Regla determinista de vencimiento de tareas (inactividad si el tiempo lo permite).
- Ejecución idempotente: un mismo evento no produce acciones ni notificaciones duplicadas.
- Auditoría de las operaciones importantes.
- Notificación interna.
- Métricas sencillas de la organización.
- Documentación de la API (Data API, RPC, Edge Functions) y pruebas.

Roles y permisos: `propietario`, `administrador` y `miembro`, según `docs/security/permissions.md`.

La arquitectura técnica es provisional: Supabase como backend y un frontend propio con React en el repositorio, con despliegue previsto en Vercel (ver `docs/architecture/decisions/`, en especial ADR-0006).

## Posponer
- Constructor visual complejo.
- Marketplace de integraciones.
- Integración con WhatsApp y cualquier otra integración externa, incluido el envío de correos de notificación.
- IA generativa para crear reglas automáticamente.
- Automatizaciones con efectos externos. La ADR-0003 ya describe cómo se harían (acción programada + Edge Function), pero no se implementan en el MVP.
- Suscripciones y cobros, hasta validar el modelo de negocio.
- Actualizaciones en tiempo real (Supabase Realtime).
- Sugerencias inteligentes de nuevas automatizaciones a partir de patrones repetidos.
- Aprobaciones especializadas y detección de aprobaciones demoradas.

## Regla de alcance
Toda funcionalidad nueva debe vincularse a un problema validado, un criterio de aceptación y una estimación de coste técnico. Si no es esencial para el flujo prioritario, se registra como futura y no bloquea el MVP.
