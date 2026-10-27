import { expect, test } from "@playwright/test";

// Panel operativo contra el backend real del CI: una tarea con fecha límite
// pasada aparece en el panel solo cuando la detección programada (Supabase
// Cron, cada minuto) crea su hallazgo y la notificación. El navegador no
// calcula vencimientos: la prueba espera a que el backend lo haga.
// Datos sintéticos de example.com, únicos en cada ejecución.

test("panel: tarea vencida detectada, acceso directo y resolución", async ({ page }) => {
    // Hasta dos ejecuciones del job, más el margen de las recargas.
    test.setTimeout(180_000);

    const sufijo = crypto.randomUUID().slice(0, 8);
    const correo = `e2e.panel.${sufijo}@example.com`;
    const contrasena = `Clave-${crypto.randomUUID()}`;
    const organizacion = `Agencia Panel ${sufijo}`;
    const proyecto = `Campaña Panel ${sufijo}`;
    const tarea = `Enviar propuesta ${sufijo}`;

    // Hace tres días: vencida en cualquier zona horaria.
    const haceTresDias = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);

    await page.goto("/#/app");
    await page.getByRole("button", { name: "¿No tienes cuenta? Créala" }).click();
    await page.getByLabel("Nombre visible").fill("Persona Panel");
    await page.getByLabel("Correo").fill(correo);
    await page.getByLabel("Contraseña").fill(contrasena);
    await page.getByRole("button", { name: "Crear cuenta" }).click();

    await page.getByLabel("Nombre de la organización").fill(organizacion);
    await page.getByRole("button", { name: "Crear organización" }).click();
    await expect(page.getByRole("heading", { level: 1, name: organizacion })).toBeVisible();

    // Panel vacío de una organización nueva
    const atencion = page.getByRole("region", { name: "Necesita atención" });
    await expect(atencion.getByText("Nada pendiente.")).toBeVisible();

    // Proyecto y tarea sin responsable con fecha pasada: la notificación es
    // para el propietario.
    const secciones = page.getByRole("navigation", { name: "Secciones" });
    await secciones.getByRole("button", { name: "Proyectos" }).click();
    await page.getByLabel("Nombre", { exact: true }).fill(proyecto);
    await page.getByRole("button", { name: "Crear proyecto" }).click();
    await page.getByRole("button", { name: proyecto }).click();
    await page.getByLabel("Título").fill(tarea);
    await page.getByLabel("Fecha límite").fill(haceTresDias);
    await page.getByRole("button", { name: "Crear tarea" }).click();
    await expect(page.getByRole("listitem").filter({ hasText: tarea })).toBeVisible();

    // El panel (sección inicial) se recarga hasta que el job haya pasado.
    const filaHallazgo = atencion.getByRole("listitem").filter({ hasText: tarea });
    await expect(async () => {
        await page.reload();
        await expect(filaHallazgo).toBeVisible({ timeout: 5_000 });
    }).toPass({ timeout: 150_000, intervals: [5_000] });

    await expect(filaHallazgo.getByText("Vencida", { exact: true })).toBeVisible();
    await expect(filaHallazgo.getByText("Prioridad alta")).toBeVisible();
    const notificaciones = page.getByRole("region", { name: "Tus notificaciones" });
    await expect(notificaciones.getByText(`La tarea «${tarea}» superó su fecha límite.`)).toBeVisible();
    await expect(notificaciones.getByText("1 sin leer")).toBeVisible();

    // Acceso directo: abre el proyecto con la tarea resaltada y enfocada
    await filaHallazgo.getByRole("button", { name: /Abrir tarea/ }).click();
    await expect(page.getByRole("heading", { name: proyecto })).toBeVisible();
    await expect(page.getByRole("listitem").filter({ hasText: tarea })).toBeFocused();

    // Resolver el hallazgo desde el panel (RPC resolver_hallazgo)
    await secciones.getByRole("button", { name: "Panel" }).click();
    await filaHallazgo.getByRole("button", { name: /Resolver/ }).click();
    await expect(atencion.getByText("Nada pendiente.")).toBeVisible();

    // Persistencia: tras recargar sigue resuelto
    await page.reload();
    await expect(atencion.getByText("Nada pendiente.")).toBeVisible();
});
