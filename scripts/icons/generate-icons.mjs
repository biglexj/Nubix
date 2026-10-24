// Regenera los iconos nativos de Nubix desde la fuente canónica del repositorio.
//
// Fuente canónica: assets/branding/icons/icon-transparent.png
//   Original creativo externo: D:\Imágenes\03_Proyectos\02_Development\Icons\Applications\Nubix\Nubix.af
//   Exportación transparente:   D:\Imágenes\03_Proyectos\02_Development\Icons\Applications\Nubix\Nubix-transparent.webp
//
// El estándar de Core exige que la compilación no dependa de la unidad D:, por eso
// el repositorio guarda la exportación y genera aquí sus derivados:
// https://github.com/biglexj/Docs/blob/main/global/architecture/asset-organization-standard.md
//
// Uso: npm run icons:generate

import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const source = join(root, "assets", "branding", "icons", "icon-transparent.png");
const iconsDir = join(root, "src-tauri", "icons");
const fingerprintPath = join(iconsDir, ".icon-source.sha256");
const installerIcon = join(root, "packaging", "windows", "Nubix.ico");
const tauriCli = join(root, "node_modules", "@tauri-apps", "cli", "tauri.js");

const requiredOutputs = [
  "32x32.png",
  "128x128.png",
  "128x128@2x.png",
  "icon.png",
  "icon.ico",
  "icon.icns",
];

function sha256(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

if (!existsSync(source)) {
  console.error(`No se encontró la fuente canónica del icono: ${source}`);
  process.exit(1);
}

mkdirSync(iconsDir, { recursive: true });

const sourceFingerprint = sha256(source);
const savedFingerprint = existsSync(fingerprintPath)
  ? readFileSync(fingerprintPath, "utf8").trim()
  : "";
const outputsExist = requiredOutputs.every((output) =>
  existsSync(join(iconsDir, output)),
);

if (savedFingerprint === sourceFingerprint && outputsExist) {
  console.log("✓ Iconos nativos actualizados; no es necesario regenerarlos.");
  process.exit(0);
}

console.log("La fuente del icono cambió. Regenerando recursos nativos...");
const generation = spawnSync(
  process.execPath,
  [tauriCli, "icon", source, "--output", iconsDir],
  { cwd: root, stdio: "inherit" },
);

if (generation.error) {
  console.error(`No se pudo ejecutar el CLI de Tauri: ${generation.error.message}`);
  process.exit(1);
}

if (generation.status !== 0) {
  console.error("El CLI de Tauri no pudo generar los iconos.");
  process.exit(generation.status ?? 1);
}

// El instalador usa una copia local del .ico nativo (ver packaging/windows/identity.iss).
copyFileSync(join(iconsDir, "icon.ico"), installerIcon);

writeFileSync(fingerprintPath, `${sourceFingerprint}\n`);
console.log("✓ Iconos nativos regenerados desde assets/branding/icons/icon-transparent.png.");
console.log("✓ packaging/windows/Nubix.ico actualizado.");
