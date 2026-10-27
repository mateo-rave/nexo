import { expect, test } from "@playwright/test";

// Recorrido principal desde el navegador contra el backend real del CI:
// registro, cierre e inicio de sesión, organización, proyecto, tarea y cambio
// de estado. Al final recarga la página: el estado solo persiste si quedó
// guardado en la base de datos.
// Datos sintéticos de example.com, únicos en cada ejecución.

test("recorrido: cuenta, organización, proyecto y tarea", async ({ page }) => {
    const sufijo = crypto.randomUUID().slice(0, 8);
    const correo = `e2e.${sufijo}@example.com`;
    const contrasena = `Clave-${crypto.randomUUID()}`;
    const organizacion = `Agencia E2E ${sufijo}`;
    const proyecto = `Web E2E ${sufijo}`;
    const tarea = `Maquetar portada ${sufijo}`;

    // Registro (el Supabase local no exige confirmar el correo)
    await page.goto("/#/app");
    await page.getByRole("button", { name: "¿No tienes cuenta? Créala" }).click();
    await page.getByLabel("Nombre visible").fill("Persona E2E");
    await page.getByLabel("Correo").fill(correo);
    await page.getByLabel("Contraseña").fill(contrasena);
    await page.getByRole("button", { name: "Crear cuenta" }).click();
    await expect(page.getByRole("heading", { name: "Crea tu organización" })).toBeVisible();

    // Cerrar sesión e iniciarla de nuevo
    await page.getByRole("button", { name: "Cerrar sesión" }).click();
    await expect(page.getByRole("heading", { name: "Inicia sesión" })).toBeVisible();
    await page.getByLabel("Correo").fill(correo);
    await page.getByLabel("Contraseña").fill(contrasena);
    await page.getByRole("button", { name: "Entrar" }).click();
    await expect(page.getByRole("heading", { name: "Crea tu organización" })).toBeVisible();

    // Organización
    await page.getByLabel("Nombre de la organización").fill(organizacion);
    await page.getByRole("button", { name: "Crear organización" }).click();
    await expect(page.getByRole("heading", { level: 1, name: organizacion })).toBeVisible();

    // El espacio abre en el panel; los proyectos tienen su propia sección
    const secciones = page.getByRole("navigation", { name: "Secciones" });
    await expect(page.getByRole("heading", { name: "Necesita atención" })).toBeVisible();
    await secciones.getByRole("button", { name: "Proyectos" }).click();

    // Proyecto
    await page.getByLabel("Nombre", { exact: true }).fill(proyecto);
    await page.getByRole("button", { name: "Crear proyecto" }).click();
    await page.getByRole("button", { name: proyecto }).click();
    await expect(page.getByRole("heading", { name: proyecto })).toBeVisible();

    // Tarea
    await page.getByLabel("Título").fill(tarea);
    await page.getByRole("button", { name: "Crear tarea" }).click();
    const fila = page.getByRole("listitem").filter({ hasText: tarea });
    await expect(fila).toBeVisible();
    await expect(fila.getByText("Pendiente", { exact: true })).toBeVisible();

    // Cambio de estado según el flujo predeterminado (pendiente → en curso)
    await fila.getByRole("button", { name: "En curso" }).click();
    await expect(fila.getByText("En curso", { exact: true })).toBeVisible();

    // Persistencia: tras recargar, el estado viene de la base de datos
    await page.reload();
    await secciones.getByRole("button", { name: "Proyectos" }).click();
    await page.getByRole("button", { name: proyecto }).click();
    const recargada = page.getByRole("listitem").filter({ hasText: tarea });
    await expect(recargada.getByText("En curso", { exact: true })).toBeVisible();
});
