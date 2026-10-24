import { open } from "@tauri-apps/plugin-dialog";
import { openUrl } from "@tauri-apps/plugin-opener";
import { invoke, isTauri } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { api, type Account, type Comparison, type Pair } from "./cloud";
type Folder = Pair & {
  mode: "mirror" | "copy";
  days: number;
  keep: boolean;
  rootLabel: string;
};
type Result = { comparison?: Comparison; error?: string; checked?: string };
const key = "nubix.folders.v1";
// Clave anterior a la marca Nubix: se lee para no perder las carpetas ya
// configuradas y se vuelve a guardar bajo la nueva en el siguiente cambio.
const legacyKey = "nubesync.folders.v1";
const defaults: Folder[] = ["01_Branding", "02_Contenidos", "03_Proyectos"].map(
  (name) => ({
    id: crypto.randomUUID(),
    local: `D:\\Imágenes\\${name}`,
    remote: `Imágenes/${name}`,
    mode: "mirror",
    days: 7,
    keep: false,
    accountId: "",
    rootId: "",
    rootLabel: "Mi unidad",
  }),
);
function load(): Folder[] {
  try {
    const list: unknown = JSON.parse(
      localStorage.getItem(key) || localStorage.getItem(legacyKey) || "null",
    );
    if (
      Array.isArray(list) &&
      list.every(
        (f) =>
          f &&
          typeof f.id === "string" &&
          typeof f.local === "string" &&
          typeof f.remote === "string" &&
          ["mirror", "copy"].includes(f.mode) &&
          Number.isInteger(f.days) &&
          typeof f.keep === "boolean",
      )
    )
      return list.map((f) => ({
        ...f,
        accountId: typeof f.accountId === "string" ? f.accountId : "",
        rootId: typeof f.rootId === "string" ? f.rootId : "",
        rootLabel: typeof f.rootLabel === "string" ? f.rootLabel : "Mi unidad",
      }));
  } catch {}
  return defaults;
}
let folders = load(),
  accounts: Account[] = [],
  selected = "",
  busy = false,
  runtime = "Comprobando Rclone…";
const results = new Map<string, Result>();
const jobPhases = new Map<string, string>();
let externalRunning = false;
let lastJobUpdate = "";
const esc = (s: string) =>
  s.replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ]!,
  );
const cloud =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M7 18a5 5 0 0 1-1-9.9A6.5 6.5 0 0 1 18.5 10a4 4 0 0 1-.5 8Z"/><path d="m9 13 3-3 3 3m-3-3v7"/></svg>';
const folderIcon =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M3 7a2 2 0 0 1 2-2h5l2 3h7a2 2 0 0 1 2 2v9H3Z"/></svg>';
const dialog = () => document.querySelector<HTMLDialogElement>("#editor")!;
dialog().addEventListener("cancel", (event) => {
  if (busy) event.preventDefault();
});
let timer: ReturnType<typeof setTimeout>;
function notice(s: string) {
  const box = document.querySelector<HTMLElement>("#notice")!;
  box.textContent = s;
  box.classList.add("visible");
  clearTimeout(timer);
  timer = setTimeout(() => box.classList.remove("visible"), 6000);
}
function save() {
  try {
    localStorage.setItem(key, JSON.stringify(folders));
    if (isTauri())
      api.savePreferences(folders).catch((e) => notice(failure(e)));
  } catch {
    notice("No se pudo guardar la configuración.");
  }
}
function failure(e: unknown) {
  return e instanceof Error ? e.message : String(e);
}
function account(id: string) {
  return accounts.find((a) => a.id === id);
}
function status(f: Folder) {
  if (!account(f.accountId)) return "Sin cuenta";
  if (jobPhases.has(f.id)) return jobPhases.get(f.id)!;
  const r = results.get(f.id);
  if (r?.error) return "Error al comprobar";
  if (!account(f.accountId)) return "Sin cuenta";
  if (!r?.comparison) return "Sin comprobar";
  const c = r.comparison;
  return c.local_only + c.different
    ? `${c.local_only + c.different} por subir`
    : c.cloud_only
      ? `${c.cloud_only} solo en Drive`
      : "Sincronizado";
}
function render() {
  const current = account(selected) || accounts[0];
  if (current) selected = current.id;
  document.querySelector("#app")!.innerHTML =
    `<header><div class="brand"><span class="brand-icon">${cloud}</span><div><strong>Nubix</strong><span>Tu biblioteca, contigo.</span></div></div><span class="preview">GOOGLE DRIVE</span></header><main>
 <section class="account"><div class="drive-icon">△</div><div class="account-copy"><strong>${current ? esc(current.name) : "Google Drive"}</strong><span>${current ? esc(current.email || "Conexión guardada · Google Drive") : "Conecta tu cuenta para comenzar"}</span></div>${accounts.length > 1 ? `<select id="active-account" aria-label="Cuenta activa">${accounts.map((a) => `<option value="${esc(a.id)}" ${a.id === selected ? "selected" : ""}>${esc(a.name)}</option>`).join("")}</select>` : ""}<button id="connect" class="secondary" ${busy ? "disabled" : ""}>${current ? "Cuentas" : "Conectar cuenta"}</button></section>
 <section class="section-heading"><h1>Carpetas</h1><button id="add" class="secondary" ${busy ? "disabled" : ""}>＋ Añadir carpeta</button></section>
 <section class="folder-list" aria-label="Carpetas configuradas">${folders.length ? folders.map((f) => `<article class="folder-row"><span class="folder-icon">${folderIcon}</span><div class="folder-copy"><strong>${esc(f.local.split(/[\\/]/).filter(Boolean).pop() || f.local)}</strong><span class="path" title="${esc(f.local)}">${esc(f.local)}</span><span class="destination" title="${esc(`${account(f.accountId)?.name || "Sin cuenta"} / ${f.rootLabel} / ${f.remote}`)}">↳ ${esc(f.rootLabel)} / ${esc(f.remote)}</span><div class="tags"><span>${f.mode === "mirror" ? "Espejo" : "Copia"} · PC → Drive</span><span>${f.keep ? "Conservar en Drive" : f.mode === "mirror" ? `Espera: ${f.days} días · pendiente` : "Sin eliminaciones"}</span></div></div><div class="folder-state"><span class="status" title="${esc(results.get(f.id)?.error || results.get(f.id)?.checked || "")}"><i></i>${esc(status(f))}</span><button class="settings" data-id="${esc(f.id)}" ${busy ? "disabled" : ""} aria-label="Configurar ${esc(f.local)}">Configurar ↗</button></div></article>`).join("") : '<div class="empty">Añade una carpeta para comenzar.</div>'}</section>
 <section class="protection"><span class="shield">◇</span><div><strong>Subidas con historial recuperable.</strong><p>Las eliminaciones automáticas aún están desactivadas.</p></div></section>
 <div class="actions"><span>${busy ? "Operación en curso…" : "Primero revisa los cambios; después decide qué subir."}</span>${busy ? '<button id="cancel" class="secondary">Cancelar</button>' : `<button id="review" class="primary">↻ Revisar cambios</button>`}</div></main><footer><span>${esc(runtime)}</span><span>Nubix 0.2</span></footer>`;
  document
    .querySelector("#connect")!
    .addEventListener("click", () => connections());
  document.querySelector("#add")!.addEventListener("click", () => edit());
  document
    .querySelector<HTMLSelectElement>("#active-account")
    ?.addEventListener("change", (e) => {
      selected = (e.target as HTMLSelectElement).value;
      render();
    });
  document
    .querySelectorAll<HTMLButtonElement>(".settings")
    .forEach((b) =>
      b.addEventListener("click", () =>
        edit(folders.find((f) => f.id === b.dataset.id)),
      ),
    );
  document.querySelector("#review")?.addEventListener("click", () => review());
  document
    .querySelector("#cancel")
    ?.addEventListener("click", () =>
      api.cancel().catch((e) => notice(failure(e))),
    );
}
function wireClose() {
  dialog()
    .querySelector("#close")
    ?.addEventListener("click", () => dialog().close());
}
async function external(url: string) {
  if (isTauri()) await openUrl(url);
  else window.open(url, "_blank", "noopener,noreferrer");
}
async function connections() {
  const d = dialog();
  d.innerHTML = `<div class="dialog-title"><h2>Cuentas de nube</h2><button id="close" aria-label="Cerrar">✕</button></div><p class="form-note">Google Drive está disponible. La estructura admite añadir otros proveedores más adelante.</p>
 ${accounts.map((a) => `<div class="connected"><div><strong>${esc(a.name)}</strong><p>${esc(a.email || a.root_label)}</p></div><button class="disconnect" data-id="${esc(a.id)}">Desconectar</button></div>`).join("")}
 <label>Nombre de la cuenta<input id="account-name" value="Drive personal" maxlength="80"></label><button id="oauth-file" class="primary">Importar JSON OAuth y conectar</button><button id="existing" class="secondary">Usar conexión de Rclone</button>
 <details ${accounts.length ? "" : "open"} class="oauth-guide"><summary>Configurar Google por primera vez</summary><ol><li>Crea o selecciona un proyecto en Google Cloud.</li><li>Activa <strong>Google Drive API</strong>.</li><li>En Google Auth Platform configura la marca, tu correo y audiencia externa. Añade tu correo como usuario de prueba.</li><li>En Acceso a los datos añade el permiso <code>https://www.googleapis.com/auth/drive</code>.</li><li>En Clientes crea un cliente OAuth de tipo <strong>Aplicación de escritorio</strong> y descarga el JSON.</li><li>Vuelve aquí, importa el JSON e inicia sesión en el navegador.</li></ol><div class="link-actions"><button id="google-console">Abrir Google Cloud</button><button id="oauth-help">Guía de Rclone</button></div><p>Este permiso permite listar y modificar tu Drive. Nubix opera solo sobre los destinos elegidos. Las credenciales se guardan en los datos privados de la aplicación, fuera del proyecto.</p></details><p id="connection-status" role="status" class="form-note">${isTauri() ? "" : "La conexión se realiza desde la ventana de escritorio de Nubix."}</p>`;
  wireClose();
  if (!d.open) d.showModal();
  d.querySelector("#google-console")!.addEventListener("click", () =>
    external("https://console.cloud.google.com/").catch((e) =>
      notice(failure(e)),
    ),
  );
  d.querySelector("#oauth-help")!.addEventListener("click", () =>
    external("https://rclone.org/drive/#making-your-own-client-id").catch((e) =>
      notice(failure(e)),
    ),
  );
  d.querySelectorAll<HTMLButtonElement>(".disconnect").forEach((b) =>
    b.addEventListener("click", () => disconnectConfirm(b.dataset.id!)),
  );
  d.querySelector("#oauth-file")!.addEventListener("click", async () => {
    if (!isTauri()) {
      notice(
        "Abre Nubix en la ventana de escritorio para conectar tu cuenta.",
      );
      return;
    }
    const name = (
      d.querySelector("#account-name") as HTMLInputElement
    ).value.trim();
    if (!name) {
      notice("Escribe un nombre para esta cuenta.");
      return;
    }
    try {
      const path = await open({
        multiple: false,
        filters: [{ name: "Cliente OAuth de Google", extensions: ["json"] }],
      });
      if (typeof path !== "string") return;
      await connectTask(() => api.connect(path, name));
    } catch (e) {
      notice(failure(e));
    }
  });
  d.querySelector("#existing")!.addEventListener("click", async () => {
    try {
      const list = await api.existing();
      if (!list.length) {
        notice(
          "No hay conexiones de Google Drive en la configuración predeterminada de Rclone.",
        );
        return;
      }
      d.querySelector("#connection-status")!.innerHTML =
        `<label>Conexión existente<select id="existing-name">${list.map((r) => `<option>${esc(r.name)}</option>`).join("")}</select></label><button id="import-remote" class="primary">Conectar esta cuenta</button>`;
      d.querySelector("#import-remote")!.addEventListener("click", () =>
        connectTask(() =>
          api.import(
            (d.querySelector("#existing-name") as HTMLSelectElement).value,
          ),
        ),
      );
    } catch (e) {
      notice(failure(e));
    }
  });
}
async function connectTask(task: () => Promise<Account>) {
  const d = dialog();
  busy = true;
  render();
  d.querySelectorAll<HTMLButtonElement>("button").forEach(
    (b) => (b.disabled = true),
  );
  d.querySelector("#connection-status")!.innerHTML =
    'Completa la autorización en tu navegador. <button id="cancel-auth">Cancelar conexión</button>';
  d.querySelector("#cancel-auth")!.addEventListener("click", () =>
    api.cancel().catch((e) => notice(failure(e))),
  );
  try {
    const a = await task();
    accounts = await api.accounts();
    selected = a.id;
    folders = folders.map((f) =>
      f.accountId ? f : { ...f, accountId: a.id, rootLabel: a.root_label },
    );
    save();
    d.close();
    notice(
      `Conectado${a.email ? `: ${a.email}` : ""}. Configura el destino y revisa los cambios.`,
    );
  } catch (e) {
    d.querySelector("#connection-status")!.textContent = failure(e);
  } finally {
    busy = false;
    d.querySelectorAll<HTMLButtonElement>("button").forEach(
      (b) => (b.disabled = false),
    );
    render();
  }
}
function disconnectConfirm(id: string) {
  const a = account(id);
  if (!a) return;
  const d = dialog();
  d.innerHTML = `<div class="dialog-title"><h2>Desconectar ${esc(a.name)}</h2><button id="close" aria-label="Cerrar">✕</button></div><p class="form-note">Se retirarán las credenciales de Nubix en este equipo. Tus archivos y la configuración original de Rclone permanecen intactos. La autorización de Google se puede revocar desde tu cuenta de Google.</p><div class="dialog-actions"><button id="revoke-help">Ver accesos de Google</button><button id="disconnect-confirm" class="primary">Desconectar de Nubix</button></div>`;
  wireClose();
  d.querySelector("#revoke-help")!.addEventListener("click", () =>
    external("https://myaccount.google.com/connections").catch((e) =>
      notice(failure(e)),
    ),
  );
  d.querySelector("#disconnect-confirm")!.addEventListener(
    "click",
    async () => {
      try {
        await api.disconnect(id);
        accounts = await api.accounts();
        for (const f of folders.filter((f) => f.accountId === id))
          results.delete(f.id);
        d.close();
        render();
        notice("Cuenta desconectada de este equipo.");
      } catch (e) {
        notice(failure(e));
      }
    },
  );
}
function edit(existing?: Folder) {
  const d = dialog(),
    a = account(existing?.accountId || selected) || accounts[0];
  let rootId = existing?.rootId || "",
    rootLabel = existing?.rootLabel || a?.root_label || "Mi unidad";
  d.innerHTML = `<form><div class="dialog-title"><h2>${existing ? "Configurar carpeta" : "Añadir carpeta"}</h2><button type="button" id="close" aria-label="Cerrar">✕</button></div><label>Carpeta en este equipo<div class="input-row"><input name="local" required value="${esc(existing?.local || "")}" placeholder="Selecciona una carpeta"><button type="button" id="browse">Explorar</button></div></label>
 <label>Cuenta<select name="accountId">${accounts.length ? accounts.map((x) => `<option value="${esc(x.id)}" ${x.id === a?.id ? "selected" : ""}>${esc(x.email || x.name)}</option>`).join("") : '<option value="">Conecta una cuenta primero</option>'}</select></label>
 <label>Guardar dentro de<div class="input-row"><input id="root-label" readonly value="${esc(rootLabel)}"><button type="button" id="drive-browse">Elegir en Drive</button></div></label><label>Subcarpeta de destino<input name="remote" required value="${esc(existing?.remote || "")}" placeholder="Imágenes/Mi carpeta"></label><p id="exact-destination" class="destination-preview"></p>
 <div class="form-grid"><label>Modo<select name="mode"><option value="mirror" ${existing?.mode !== "copy" ? "selected" : ""}>Espejo · PC → Drive</option><option value="copy" ${existing?.mode === "copy" ? "selected" : ""}>Copia · PC → Drive</option></select></label><label>Espera para eliminar<select name="days">${[1, 7, 14, 30, 90].map((n) => `<option value="${n}" ${(existing?.days || 7) === n ? "selected" : ""}>${n} ${n === 1 ? "día" : "días"}</option>`).join("")}</select></label></div><label class="check"><input type="checkbox" name="keep" ${existing?.keep ? "checked" : ""}> Conservar en Drive aunque lo borre del PC</label><p class="form-note">La ruta nueva se creará al subir. Las versiones reemplazadas se conservan en .Nubix-history. Las eliminaciones con espera aún no están activas.</p><div class="dialog-actions">${existing ? '<button type="button" id="remove" class="danger">Quitar de la lista</button>' : ""}<button type="submit" class="primary">Guardar carpeta</button></div></form><section id="drive-picker" hidden></section>`;
  wireClose();
  const form = d.querySelector<HTMLFormElement>("form")!;
  const field = (name: string) =>
    form.elements.namedItem(name) as HTMLInputElement | HTMLSelectElement;
  const update = () => {
    field("days").disabled =
      field("mode").value === "copy" ||
      (field("keep") as HTMLInputElement).checked;
    d.querySelector("#exact-destination")!.textContent =
      `Destino: ${rootLabel} / ${field("remote").value || "…"}`;
  };
  form.addEventListener("input", update);
  form.addEventListener("change", update);
  update();
  field("accountId").addEventListener("change", () => {
    rootId = "";
    rootLabel = account(field("accountId").value)?.root_label || "Mi unidad";
    (d.querySelector("#root-label") as HTMLInputElement).value = rootLabel;
    update();
  });
  d.querySelector("#drive-browse")!.addEventListener("click", () => {
    if (!field("accountId").value) {
      notice("Conecta una cuenta para elegir el destino.");
      return;
    }
    pickDrive(field("accountId").value, (id, label) => {
      rootId = id;
      rootLabel = label;
      (d.querySelector("#root-label") as HTMLInputElement).value = label;
      update();
    });
  });
  d.querySelector("#browse")!.addEventListener("click", async () => {
    if (!isTauri()) {
      notice("El selector local está disponible en la ventana de Nubix.");
      return;
    }
    try {
      const path = await open({ directory: true, multiple: false });
      if (typeof path === "string") {
        field("local").value = path;
        if (!field("remote").value)
          field("remote").value = `Imágenes/${path.split(/[\\/]/).pop()}`;
        update();
      }
    } catch (e) {
      notice(failure(e));
    }
  });
  d.querySelector("#remove")?.addEventListener("click", () => {
    folders = folders.filter((f) => f.id !== existing!.id);
    results.delete(existing!.id);
    jobPhases.delete(existing!.id);
    save();
    d.close();
    render();
  });
  form.addEventListener("submit", (e) => {
    e.preventDefault();
    const remote = field("remote")
      .value.trim()
      .replace(/\\/g, "/")
      .replace(/^\/+|\/+$/g, "");
    const local = field("local").value.trim();
    if (
      !remote ||
      remote.includes(":") ||
      remote
        .split("/")
        .some(
          (p) =>
            !p ||
            p === "." ||
            p === ".." ||
            p.toLowerCase() === ".nubix-history" ||
            p.toLowerCase() === ".nubesync-history",
        )
    ) {
      notice("Escribe una subcarpeta relativa válida.");
      return;
    }
    const entry: Folder = {
      id: existing?.id || crypto.randomUUID(),
      local,
      remote,
      accountId: field("accountId").value,
      rootId,
      rootLabel,
      mode: field("mode").value as Folder["mode"],
      days: Number(field("days").value),
      keep: (field("keep") as HTMLInputElement).checked,
    };
    if (
      folders.some(
        (f) =>
          f.id !== entry.id &&
          (f.local.toLowerCase() === local.toLowerCase() ||
            (f.accountId === entry.accountId &&
              f.rootId === rootId &&
              f.remote.toLowerCase() === remote.toLowerCase())),
      )
    ) {
      notice("Esta carpeta o su destino ya están configurados.");
      return;
    }
    folders = existing
      ? folders.map((f) => (f.id === entry.id ? entry : f))
      : [...folders, entry];
    results.delete(entry.id);
    jobPhases.delete(entry.id);
    save();
    d.close();
    render();
    notice("Destino guardado.");
  });
  if (!d.open) d.showModal();
}
async function pickDrive(
  accountId: string,
  onSelect: (id: string, label: string) => void,
) {
  const d = dialog(),
    form = d.querySelector<HTMLFormElement>("form")!,
    picker = d.querySelector<HTMLElement>("#drive-picker")!;
  const trail = [{ id: "", name: account(accountId)!.root_label }];
  form.hidden = true;
  picker.hidden = false;
  const show = async () => {
    const current = trail[trail.length - 1];
    picker.innerHTML = `<div class="dialog-title"><h2>Elegir destino en Drive</h2><button id="back-form" aria-label="Volver">✕</button></div><p class="form-note">${esc(trail.map((t) => t.name).join(" / "))}</p><div id="remote-folders" class="remote-folders">Cargando carpetas…</div><div class="dialog-actions"><button id="parent" ${trail.length === 1 ? "disabled" : ""}>Subir un nivel</button><button id="choose-root" class="primary">Usar esta carpeta</button></div>`;
    picker.querySelector("#back-form")!.addEventListener("click", () => {
      picker.hidden = true;
      form.hidden = false;
    });
    picker.querySelector("#parent")!.addEventListener("click", () => {
      trail.pop();
      show();
    });
    picker.querySelector("#choose-root")!.addEventListener("click", () => {
      onSelect(current.id, trail.map((t) => t.name).join(" / "));
      picker.hidden = true;
      form.hidden = false;
    });
    try {
      const list = await api.folders(accountId, current.id);
      const box = picker.querySelector("#remote-folders")!;
      box.innerHTML = list.length
        ? list
            .map(
              (f, i) =>
                `<button data-index="${i}" ${f.ID ? "" : "disabled"}><span>▱ ${esc(f.Name)}</span><small>${esc(f.ID)}</small></button>`,
            )
            .join("")
        : "<p>Esta carpeta está vacía. Puedes usarla y escribir una subcarpeta nueva.</p>";
      box.querySelectorAll<HTMLButtonElement>("button").forEach((b) =>
        b.addEventListener("click", () => {
          const f = list[Number(b.dataset.index)];
          trail.push({ id: f.ID, name: f.Name });
          show();
        }),
      );
    } catch (e) {
      picker.querySelector("#remote-folders")!.textContent = failure(e);
    }
  };
  await show();
}
async function review() {
  jobPhases.clear();
  if (!isTauri()) {
    notice("Abre la ventana de Nubix para comprobar tus archivos en Drive.");
    return;
  }
  if (!accounts.length) {
    connections();
    return;
  }
  busy = true;
  render();
  try {
    for (const f of folders) {
      if (!account(f.accountId)) {
        results.set(f.id, { error: "Selecciona una cuenta en Configurar." });
        continue;
      }
      try {
        const comparison = await api.compare(f);
        results.set(f.id, {
          comparison,
          checked: `Comprobado: ${new Date().toLocaleString()}`,
        });
      } catch (e) {
        results.set(f.id, { error: failure(e) });
        if (failure(e).includes("cancelada")) break;
      }
      render();
    }
  } finally {
    busy = false;
    render();
  }
  showReview();
}
function showReview() {
  const d = dialog();
  const ready = folders.filter((f) => {
    const c = results.get(f.id)?.comparison;
    return c && c.local_only + c.different > 0;
  });
  d.innerHTML = `<div class="dialog-title"><h2>Revisión de cambios</h2><button id="close" aria-label="Cerrar">✕</button></div><div class="review-list">${folders
    .map((f) => {
      const r = results.get(f.id),
        c = r?.comparison;
      return `<article><strong>${esc(f.local.split(/[\\/]/).pop() || f.local)}</strong><p>${esc(`${account(f.accountId)?.name || "Sin cuenta"} / ${f.rootLabel} / ${f.remote}`)}</p>${c ? `<p>${c.identical} iguales · ${c.local_only} nuevos · ${c.different} modificados · ${c.cloud_only} solo en Drive</p>` : `<p class="error">${esc(r?.error || "Sin comprobar")}</p>`}</article>`;
    })
    .join(
      "",
    )}</div><p class="form-note">Solo se subirán los archivos nuevos o modificados. Las versiones reemplazadas irán al historial. Esta operación no elimina los archivos que estén solo en Drive.</p><div class="dialog-actions"><button id="upload" class="primary" ${ready.length ? "" : "disabled"}>Subir cambios (${ready.length} carpetas)</button></div>`;
  wireClose();
  d.querySelector("#upload")!.addEventListener("click", async () => {
    d.close();
    busy = true;
    render();
    try {
      for (const f of ready) {
        try {
          const comparison = await api.upload(f);
          results.set(f.id, {
            comparison,
            checked: `Comprobado: ${new Date().toLocaleString()}`,
          });
        } catch (e) {
          results.set(f.id, { error: failure(e) });
          break;
        }
        render();
      }
    } finally {
      busy = false;
      render();
      showReview();
    }
  });
  if (!d.open) d.showModal();
}
render();
if (isTauri()) {
  listen("operation-close-blocked", () =>
    notice("Cancela la operación en curso antes de cerrar Nubix."),
  ).catch(() => {});
  Promise.all([
    api.accounts(),
    invoke<string>("rclone_version"),
    api.preferences(),
  ])
    .then(([list, version, preferences]) => {
      accounts = list;
      if (preferences) {
        folders = preferences as Folder[];
        localStorage.setItem(key, JSON.stringify(folders));
      } else {
        save();
      }
      selected = list[0]?.id || "";
      runtime = version;
      render();
      let polling = false;
      const poll = async () => {
        if (polling) return;
        polling = true;
        try {
          const job = await api.job();
          if (!job) return;
          if (job.updated === lastJobUpdate && job.running === externalRunning)
            return;
          lastJobUpdate = job.updated;
          const wasRunning = externalRunning;
          externalRunning = job.running;
          if (wasRunning || externalRunning) busy = externalRunning;
          jobPhases.clear();
          for (const item of job.folders) {
            if (!folders.some((f) => f.id === item.id)) continue;
            if (item.comparison)
              results.set(item.id, {
                comparison: item.comparison,
                checked: `Comprobado: ${job.updated}`,
              });
            if (item.error) results.set(item.id, { error: item.error });
            if (item.state === "verified")
              jobPhases.set(item.id, "Subida verificada");
            else if (item.state === "pending")
              jobPhases.set(item.id, "En cola");
            else if (item.state === "checking")
              jobPhases.set(item.id, "Comparando…");
            else if (item.state === "verifying")
              jobPhases.set(item.id, "Verificando…");
            else if (item.state === "uploading")
              jobPhases.set(
                item.id,
                item.total_bytes > 0
                  ? `${Math.min(100, Math.floor((item.bytes / item.total_bytes) * 100))}% · ${item.transferred} archivos`
                  : "Preparando subida…",
              );
            else if (item.state === "failed")
              jobPhases.set(item.id, "Subida interrumpida");
          }
          render();
        } catch {
        } finally {
          polling = false;
        }
      };
      poll();
      setInterval(poll, 2500);
    })
    .catch((e) => {
      runtime = failure(e);
      render();
    });
} else {
  runtime = "Vista en navegador · conecta desde Nubix";
  render();
}
