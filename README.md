# Nexo — archivos iniciales del proyecto

Este paquete prepara el contexto de producto y las reglas para trabajar con Claude Code. Todavía no contiene el backend implementado.

## Cómo usarlo

1. Descomprime el contenido directamente en la raíz de tu carpeta `nexo`.
2. Abre una terminal dentro de esa carpeta.
3. Inicializa Git si aún no existe: `git init`.
4. Comprueba que el archivo `CLAUDE.md` quede en la raíz.
5. Ejecuta `claude`.
6. Pega el prompt de primera tarea que aparece al final de este README.

No crees un `.env` con credenciales hasta que la configuración del backend lo necesite. `.env.example` es una plantilla y sí puede versionarse.

## Prompt inicial para Claude Code

```text
Lee primero CLAUDE.md y todos los documentos dentro de docs/.

Estamos creando Nexo desde cero. Antes de instalar dependencias o escribir código de aplicación:
1. Inspecciona el repositorio y el entorno disponible.
2. Resume qué es Nexo, el público inicial, el problema, el alcance del MVP y lo que todavía es una hipótesis.
3. Detecta contradicciones o decisiones técnicas no resueltas entre los documentos.
4. Propón un plan por fases que priorice un flujo completo y funcional en el plazo objetivo de tres meses.
5. Actualiza los documentos solo cuando haya una razón clara y señala cada modificación.
6. No construyas frontend; lo desarrollaré por separado en Stitch.
7. No implementes todos los módulos aún. Presenta el plan y recomienda el siguiente paso pequeño.

No afirmes que una funcionalidad está implementada ni que una prueba pasó si no lo verificaste. No subas secretos, no hagas cambios destructivos ni despliegues a producción.
```

## Estructura incluida

- `CLAUDE.md`: reglas permanentes para Claude Code.
- `.gitignore`: archivos y datos locales que Git no debe rastrear.
- `.dockerignore`: exclusiones para imágenes Docker. Con la arquitectura Supabase no se prevé construir imágenes propias en el MVP; se conserva por si se necesita más adelante.
- `.env.example`: nombres de variables de entorno sin secretos reales.
- `.editorconfig`: formato básico consistente de archivos.
- `docs/product/`: visión, requisitos y alcance del MVP.
- `docs/architecture/`: arquitectura provisional (Supabase + Vercel) y decisiones técnicas (ADR-0001 a ADR-0004).
- `docs/qa/`: estrategia de pruebas.
- `docs/security/`: modelo inicial de amenazas y matriz de roles y permisos.
- `docs/operations/`: notas iniciales de despliegue, respaldos y recuperación.
- `docs/plans/`: planes de cada fase de implementación.

El contenido es una base de trabajo y debe evolucionar conforme se validen los requisitos y se tomen decisiones técnicas.
