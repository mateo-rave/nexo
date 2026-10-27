import { expect, test, type Page } from "@playwright/test";

// Reglas de automatización contra el backend real del CI (ADR-0008): crear
// una regla desde el catálogo, publicarla y activarla; los cambios de estado
// de una tarea generan ejecuciones que procesa Supabase Cron cada minuto, así
// que la prueba espera a que el backend lo haga. Al final, la pausa.
// Datos sintéticos de example.com, únicos en cada ejecución.

// Capturas para la revisión visual de la sección: el workflow las sube como
// artefacto. test-results/ está fuera de Git.
async function capturar(page: Page, nombre: string) {
    await page.screenshot({ path: `test-results/capturas-reglas/${nombre}.png`, fullPage: true, animations: "disabled" });
}

test("reglas: crear, publicar, activar, ejecuciones y pausa", async ({ page }) => {
    // Hasta dos ejecuciones del job, más el margen de las recargas.
    test.setTimeout(210_000);

    const sufijo = crypto.randomUUID().slice(0, 8);
    const correo = `e2e.reglas.${sufijo}@example.com`;
    const contrasena = `Clave-${crypto.randomUUID()}`;
    const organizacion = `Agencia Reglas ${sufijo}`;
    const regla = `Avisar revisión ${sufijo}`;
    const proyecto = `Campaña Reglas ${sufijo}`;
    const tarea = `Preparar entrega ${sufijo}`;

    // Publicar, activar y pausar piden confirmación.
    const dialogos: string[] = [];
    page.on("dialog", (dialogo) => {
        dialogos.push(dialogo.message());
        void dialogo.accept();
    });

    await page.goto("/#/app");
    await page.getByRole("button", { name: "¿No tienes cuenta? Créala" }).click();
    await page.getByLabel("Nombre visible").fill("Persona Reglas");
    await page.getByLabel("Correo").fill(correo);
    await page.getByLabel("Contraseña").fill(contrasena);
    await page.getByRole("button", { name: "Crear cuenta" }).click();

    await page.getByLabel("Nombre de la organización").fill(organizacion);
    await page.getByRole("button", { name: "Crear organización" }).click();
    await expect(page.getByRole("heading", { level: 1, name: organizacion })).toBeVisible();

    const secciones = page.getByRole("navigation", { name: "Secciones" });
    await secciones.getByRole("button", { name: "Reglas" }).click();
    await expect(page.getByText("Todavía no hay reglas.")).toBeVisible();

    // Nueva regla: cuando una tarea pasa a En revisión, avisar a propietarios
    // y administradores (marcado por defecto).
    await page.getByRole("button", { name: "Nueva regla" }).click();
    await page.getByLabel("Nombre de la regla").fill(regla);
    await page.getByLabel("Cuando cambia el estado de una tarea").check();
    await page.getByLabel("Solo si la tarea pasa a uno de estos estados").check();
    await page.getByLabel("En revisión", { exact: true }).check();
    await expect(page.getByLabel("Propietarios y administradores")).toBeChecked();
    await capturar(page, "01-nueva-regla");
    await page.getByRole("button", { name: "Crear borrador" }).click();

    await expect(page.getByRole("heading", { level: 2, name: regla })).toBeVisible();
    await expect(page.getByText("Sin activar", { exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: "Activar" })).toBeDisabled();

    // Guardar el borrador muestra la confirmación
    await page.getByRole("button", { name: "Guardar borrador" }).click();
    await expect(page.getByText("Borrador guardado.")).toBeVisible();
    await capturar(page, "02-borrador-guardado");

    // Publicar la versión 1 y activarla
    await page.getByRole("button", { name: "Publicar versión 1" }).click();
    await expect(page.getByText("Versión 1 publicada")).toBeVisible();
    await expect(
        page.getByText("Cuando una tarea pasa a En revisión, avisar a propietarios y administradores."),
    ).toBeVisible();
    await capturar(page, "03-publicada-sin-activar");
    await page.getByRole("button", { name: "Activar" }).click();
    await expect(page.getByText("Activa", { exact: true })).toBeVisible();
    expect(dialogos).toHaveLength(2);
    await capturar(page, "04-activa");

    // Una tarea pasa a En curso (no cumple la condición) y luego a En revisión
    await secciones.getByRole("button", { name: "Proyectos" }).click();
    await page.getByLabel("Nombre", { exact: true }).fill(proyecto);
    await page.getByRole("button", { name: "Crear proyecto" }).click();
    await page.getByRole("button", { name: proyecto }).click();
    await page.getByLabel("Título").fill(tarea);
    await page.getByRole("button", { name: "Crear tarea" }).click();
    const fila = page.getByRole("listitem").filter({ hasText: tarea });
    await fila.getByRole("button", { name: "En curso" }).click();
    await expect(fila.getByText("En curso", { exact: true })).toBeVisible();
    await fila.getByRole("button", { name: "En revisión" }).click();
    await expect(fila.getByText("En revisión", { exact: true })).toBeVisible();

    // Ejecuciones: se actualizan hasta que el job haya procesado ambos eventos
    await secciones.getByRole("button", { name: "Reglas" }).click();
    await page.getByRole("button", { name: new RegExp(regla) }).click();
    const ejecuciones = page.getByRole("list", { name: "Ejecuciones de la regla" });
    await expect(async () => {
        await page.getByRole("button", { name: "Actualizar" }).click();
        await expect(ejecuciones.getByText("Exitosa", { exact: true })).toBeVisible({ timeout: 5_000 });
        await expect(ejecuciones.getByText("Omitida", { exact: true })).toBeVisible({ timeout: 5_000 });
    }).toPass({ timeout: 150_000, intervals: [5_000] });

    const exitosa = ejecuciones.getByRole("listitem").filter({ hasText: "Exitosa" });
    await expect(exitosa.getByText("Avisó a Persona Reglas.")).toBeVisible();
    await expect(exitosa.getByText(/intento 1 de 3/)).toBeVisible();
    const omitida = ejecuciones.getByRole("listitem").filter({ hasText: "Omitida" });
    await expect(omitida.getByText("El evento no cumple las condiciones de la regla.")).toBeVisible();
    await capturar(page, "05-ejecuciones");

    // La notificación de la regla llega al propietario
    await secciones.getByRole("button", { name: "Notificaciones" }).click();
    await expect(page.getByText(`Regla «${regla}»`)).toBeVisible();
    await expect(page.getByText(`La tarea «${tarea}» pasó a En revisión.`)).toBeVisible();

    // Pausar: la pantalla explica que no cancela los eventos ya ocurridos
    await secciones.getByRole("button", { name: "Reglas" }).click();
    await page.getByRole("button", { name: new RegExp(regla) }).click();
    await page.getByRole("button", { name: "Pausar" }).click();
    await expect(page.getByText("Pausada", { exact: true })).toBeVisible();
    await expect(page.getByText(/no actúa sobre los eventos nuevos/)).toBeVisible();
    await expect(page.getByRole("button", { name: "Reactivar" })).toBeEnabled();
    expect(dialogos).toHaveLength(3);
    expect(dialogos[2]).toContain("Los eventos que ya ocurrieron mientras estaba activa se seguirán procesando.");
    await capturar(page, "06-pausada");

    // Persistencia: tras recargar, la regla sigue pausada
    await page.reload();
    await secciones.getByRole("button", { name: "Reglas" }).click();
    await expect(page.getByRole("listitem").filter({ hasText: regla }).getByText("Pausada")).toBeVisible();
    await capturar(page, "07-lista");

    // Móvil (390 px): lista, detalle con ejecuciones y formulario sin enviar
    await page.setViewportSize({ width: 390, height: 844 });
    await capturar(page, "08-movil-lista");
    await page.getByRole("button", { name: new RegExp(regla) }).click();
    await expect(ejecuciones.getByText("Exitosa", { exact: true })).toBeVisible();
    await capturar(page, "09-movil-detalle");
    await page.getByRole("main").getByRole("button", { name: "Reglas", exact: true }).click();
    await page.getByRole("button", { name: "Nueva regla" }).click();
    await expect(page.getByLabel("Nombre de la regla")).toBeVisible();
    await capturar(page, "10-movil-nueva-regla");
});
