use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    fs,
    io::{Read, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::atomic::{AtomicBool, Ordering},
    thread,
    time::{Duration, Instant},
};
use tauri::{AppHandle, Manager};

#[derive(Default)]
pub struct CloudRuntime {
    busy: AtomicBool,
    cancelled: AtomicBool,
}
struct Running<'a>(&'a CloudRuntime);
impl Drop for Running<'_> {
    fn drop(&mut self) {
        self.0.busy.store(false, Ordering::SeqCst);
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub struct Account {
    pub id: String,
    pub name: String,
    pub provider: String,
    pub email: Option<String>,
    pub root_label: String,
}
#[derive(Serialize)]
pub struct ExistingRemote {
    pub name: String,
    pub provider: String,
}
#[derive(Deserialize, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct RemoteFolder {
    pub name: String,
    #[serde(default, rename = "ID")]
    pub id: String,
    pub path: String,
}
#[derive(Default, Serialize, Deserialize)]
pub struct Comparison {
    pub identical: usize,
    pub local_only: usize,
    pub cloud_only: usize,
    pub different: usize,
    pub errors: usize,
}
#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Pair {
    pub local: String,
    pub remote: String,
    pub account_id: String,
    #[serde(default)]
    pub root_id: String,
    pub id: String,
}

fn command() -> Command {
    let mut c = Command::new("rclone");
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        c.creation_flags(0x08000000);
    }
    c.stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    c
}
fn capture(mut stream: impl Read) -> (Vec<u8>, bool) {
    let mut result = Vec::new();
    let mut bytes = [0; 8192];
    let mut exceeded = false;
    while let Ok(n) = stream.read(&mut bytes) {
        if n == 0 {
            break;
        }
        if result.len() + n <= 8 * 1024 * 1024 {
            result.extend_from_slice(&bytes[..n]);
        } else {
            exceeded = true;
        }
    }
    (result, exceeded)
}
fn error_message(stderr: &[u8]) -> String {
    let s = String::from_utf8_lossy(stderr).to_lowercase();
    if s.contains("invalid_grant") { "Google ha revocado o vencido la autorización. Vuelve a conectar la cuenta." }
    else if s.contains("invalid_client") { "Google rechazó el cliente OAuth. Comprueba que el JSON sea de una aplicación de escritorio." }
    else if s.contains("directory not found") { "La carpeta de Drive todavía no existe o no está accesible." }
    else if s.contains("duplicate") { "Drive contiene nombres duplicados en este destino. Revisa las carpetas antes de continuar." }
    else if s.contains("403") || s.contains("permission") { "Google rechazó el acceso. Comprueba los permisos y que tu cuenta sea usuario de prueba del cliente OAuth." }
    else if s.contains("timeout") || s.contains("network") || s.contains("connection") { "No se pudo conectar con Drive. Comprueba tu conexión e inténtalo otra vez." }
    else { "Rclone no pudo completar la operación. Comprueba el cliente OAuth, la conexión y el destino seleccionado." }.into()
}
fn run(
    runtime: &CloudRuntime,
    config: Option<&Path>,
    args: &[String],
    seconds: u64,
    allow_differences: bool,
) -> Result<Vec<u8>, String> {
    if runtime
        .busy
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        return Err("Hay otra operación en curso.".into());
    }
    let _guard = Running(runtime);
    runtime.cancelled.store(false, Ordering::SeqCst);
    let mut c = command();
    if let Some(config) = config {
        c.arg("--config").arg(config);
    }
    c.args(args);
    let mut child = c
        .spawn()
        .map_err(|_| "No se pudo iniciar Rclone. Comprueba su instalación y PATH.".to_string())?;
    let stdout = child.stdout.take().ok_or("No se pudo leer Rclone")?;
    let stderr = child.stderr.take().ok_or("No se pudo leer Rclone")?;
    let out = thread::spawn(move || capture(stdout));
    let err = thread::spawn(move || capture(stderr));
    let start = Instant::now();
    let mut interruption = None;
    let status = loop {
        if runtime.cancelled.load(Ordering::SeqCst)
            || start.elapsed() > Duration::from_secs(seconds)
        {
            interruption = Some(if runtime.cancelled.load(Ordering::SeqCst) {
                "Operación cancelada."
            } else {
                "La operación tardó demasiado. Puedes volver a intentarlo."
            });
            let _ = child.kill();
            break child.wait().map_err(|_| "No se pudo cerrar Rclone")?;
        }
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) => thread::sleep(Duration::from_millis(100)),
            Err(_) => {
                let _ = child.kill();
                let _ = child.wait();
                interruption = Some("La operación se interrumpió.");
                break child.wait().map_err(|_| "No se pudo cerrar Rclone")?;
            }
        }
    };
    let (stdout, too_large) = out.join().map_err(|_| "No se pudo leer la respuesta")?;
    let (stderr, _) = err.join().map_err(|_| "No se pudo leer la respuesta")?;
    if let Some(message) = interruption {
        return Err(message.into());
    }
    if too_large {
        return Err(
            "La respuesta es demasiado grande; selecciona una carpeta más concreta.".into(),
        );
    }
    if !status.success() && !(allow_differences && status.code() == Some(1)) {
        return Err(error_message(&stderr));
    }
    if String::from_utf8_lossy(&stderr)
        .to_lowercase()
        .contains("duplicate")
    {
        return Err(error_message(&stderr));
    }
    Ok(stdout)
}
fn args(items: &[&str]) -> Vec<String> {
    items.iter().map(|s| s.to_string()).collect()
}
fn data_dir(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|_| "No se pudo localizar la configuración")?
        .join("cloud");
    fs::create_dir_all(&dir).map_err(|_| "No se pudo crear la configuración")?;
    Ok(dir)
}
fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 100
        && id
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'-' || c == b'_')
}
fn config_path(app: &AppHandle, id: &str) -> Result<PathBuf, String> {
    if !valid_id(id) {
        return Err("Identificador de cuenta inválido.".into());
    }
    Ok(data_dir(app)?.join(format!("{id}.conf")))
}
fn accounts(app: &AppHandle) -> Result<Vec<Account>, String> {
    let path = data_dir(app)?.join("accounts.json");
    if !path.exists() {
        return Ok(vec![]);
    }
    serde_json::from_slice(&fs::read(path).map_err(|_| "No se pudo leer la lista de cuentas")?)
        .map_err(|_| "La lista de cuentas no es válida.".into())
}
fn store_accounts(app: &AppHandle, list: &[Account]) -> Result<(), String> {
    fs::write(
        data_dir(app)?.join("accounts.json"),
        serde_json::to_vec_pretty(list).map_err(|_| "No se pudo guardar la cuenta")?,
    )
    .map_err(|_| "No se pudo guardar la cuenta".into())
}
fn require_account(app: &AppHandle, id: &str) -> Result<Account, String> {
    accounts(app)?
        .into_iter()
        .find(|a| a.id == id)
        .ok_or("La cuenta ya no está conectada.".into())
}
fn write_config(path: &Path, config: &Value) -> Result<(), String> {
    let map = config.as_object().ok_or("Configuración inválida")?;
    let mut ini = String::from("[cloud]\n");
    for (k, v) in map {
        let Some(v) = v.as_str() else { continue };
        if !k.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'_') || v.contains(['\r', '\n']) {
            return Err("Configuración inválida.".into());
        }
        ini.push_str(&format!("{k} = {v}\n"));
    }
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options
        .open(path)
        .and_then(|mut f| f.write_all(ini.as_bytes()))
        .map_err(|_| "No se pudo guardar la configuración privada.".into())
}
fn identity(runtime: &CloudRuntime, path: &Path) -> Result<Option<String>, String> {
    let bytes = run(
        runtime,
        Some(path),
        &args(&[
            "about",
            "cloud:",
            "--json",
            "--retries",
            "1",
            "--contimeout",
            "15s",
            "--timeout",
            "30s",
        ]),
        90,
        false,
    )?;
    let _: Value =
        serde_json::from_slice(&bytes).map_err(|_| "Google devolvió una respuesta inválida.")?;
    // Drive's rclone backend does not implement config userinfo. Verify access
    // using about and display the user-provided connection label, not an inferred email.
    Ok(None)
}
fn finish_account(
    app: &AppHandle,
    runtime: &CloudRuntime,
    id: String,
    name: String,
    root_label: String,
) -> Result<Account, String> {
    let path = config_path(app, &id)?;
    let email = identity(runtime, &path)?;
    let account = Account {
        id,
        name,
        provider: "drive".into(),
        email,
        root_label,
    };
    let mut list = accounts(app)?;
    list.push(account.clone());
    store_accounts(app, &list)?;
    Ok(account)
}
pub fn list_accounts(app: &AppHandle) -> Result<Vec<Account>, String> {
    accounts(app)
}
pub fn existing_remotes(runtime: &CloudRuntime) -> Result<Vec<ExistingRemote>, String> {
    let data: Value =
        serde_json::from_slice(&run(runtime, None, &args(&["config", "dump"]), 30, false)?)
            .map_err(|_| "No se pudo leer la configuración de Rclone")?;
    Ok(data
        .as_object()
        .ok_or("Configuración inválida")?
        .iter()
        .filter(|(_, v)| v.get("type").and_then(Value::as_str) == Some("drive"))
        .map(|(name, _)| ExistingRemote {
            name: name.clone(),
            provider: "drive".into(),
        })
        .collect())
}
pub fn import_remote(
    app: &AppHandle,
    runtime: &CloudRuntime,
    name: String,
) -> Result<Account, String> {
    let data: Value =
        serde_json::from_slice(&run(runtime, None, &args(&["config", "dump"]), 30, false)?)
            .map_err(|_| "No se pudo leer Rclone")?;
    let source = data.get(&name).ok_or("La conexión no existe")?;
    if source.get("type").and_then(Value::as_str) != Some("drive") {
        return Err("Selecciona una conexión de Google Drive.".into());
    }
    let id = uuid::Uuid::new_v4().to_string();
    let path = config_path(app, &id)?;
    write_config(&path, source)?;
    let root = if source
        .get("team_drive")
        .and_then(Value::as_str)
        .is_some_and(|s| !s.is_empty())
    {
        "Unidad compartida"
    } else if source
        .get("root_folder_id")
        .and_then(Value::as_str)
        .is_some_and(|s| !s.is_empty())
    {
        "Carpeta raíz de la conexión"
    } else {
        "Mi unidad"
    };
    let result = finish_account(app, runtime, id, name, root.into());
    if result.is_err() {
        let _ = fs::remove_file(path);
    }
    result
}
pub fn connect(
    app: &AppHandle,
    runtime: &CloudRuntime,
    json_path: String,
    name: String,
) -> Result<Account, String> {
    if name.trim().is_empty() || name.len() > 80 {
        return Err("Escribe un nombre para la cuenta.".into());
    }
    let file = Path::new(&json_path);
    if fs::metadata(file)
        .map_err(|_| "No se pudo leer el JSON OAuth")?
        .len()
        > 1024 * 1024
    {
        return Err("El archivo OAuth es demasiado grande.".into());
    }
    let data: Value =
        serde_json::from_slice(&fs::read(file).map_err(|_| "No se pudo leer el JSON OAuth")?)
            .map_err(|_| "El archivo no es un JSON OAuth válido.")?;
    let installed = data
        .get("installed")
        .ok_or("Crea un cliente OAuth de tipo Aplicación de escritorio, no Aplicación web.")?;
    let client = installed
        .get("client_id")
        .and_then(Value::as_str)
        .filter(|s| s.ends_with(".apps.googleusercontent.com"))
        .ok_or("El JSON no contiene un client_id válido.")?;
    let secret = installed
        .get("client_secret")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .ok_or("El JSON no contiene el secreto OAuth.")?;
    let id = uuid::Uuid::new_v4().to_string();
    let path = config_path(app, &id)?;
    write_config(
        &path,
        &serde_json::json!({"type":"drive","client_id":client,"client_secret":secret,"scope":"drive"}),
    )?;
    let result = (|| {
        run(
            runtime,
            Some(&path),
            &args(&[
                "config",
                "update",
                "cloud",
                "config_is_local",
                "true",
                "config_refresh_token",
                "true",
                "config_change_team_drive",
                "false",
                "--no-output",
            ]),
            300,
            false,
        )?;
        finish_account(app, runtime, id, name.trim().into(), "Mi unidad".into())
    })();
    if result.is_err() {
        let _ = fs::remove_file(path);
    }
    result
}
pub fn disconnect(app: &AppHandle, runtime: &CloudRuntime, id: &str) -> Result<(), String> {
    if runtime.busy.load(Ordering::SeqCst) {
        return Err("Cancela la operación antes de desconectar.".into());
    }
    require_account(app, id)?;
    let path = config_path(app, id)?;
    if path.exists() {
        fs::remove_file(path).map_err(|_| "No se pudieron retirar las credenciales locales")?;
    }
    let list: Vec<_> = accounts(app)?.into_iter().filter(|a| a.id != id).collect();
    store_accounts(app, &list)
}
pub fn cancel(runtime: &CloudRuntime) {
    runtime.cancelled.store(true, Ordering::SeqCst)
}

pub fn is_busy(runtime: &CloudRuntime) -> bool {
    runtime.busy.load(Ordering::SeqCst)
}
fn validate_remote(path: &str) -> Result<(), String> {
    if path.is_empty()
        || path.len() > 2048
        || path.starts_with('/')
        || path.contains([':', '\\', '\0', '\r', '\n'])
        || path.split('/').any(|p| {
            p.is_empty()
                || p == ".."
                || p == "."
                || p.eq_ignore_ascii_case(".Nubix-history")
                // Nombre anterior a la marca Nubix: sigue bloqueado para que
                // nadie apunte un destino dentro del historial.
                || p.eq_ignore_ascii_case(".NubeSync-history")
        })
    {
        return Err("Usa una ruta relativa válida dentro de Drive.".into());
    }
    Ok(())
}
pub fn list_folders(
    app: &AppHandle,
    runtime: &CloudRuntime,
    account_id: &str,
    root_id: &str,
) -> Result<Vec<RemoteFolder>, String> {
    require_account(app, account_id)?;
    if !root_id.is_empty() && !valid_id(root_id) {
        return Err("Carpeta de Drive inválida.".into());
    }
    let mut a = args(&[
        "lsjson",
        "cloud:",
        "--dirs-only",
        "--max-depth",
        "1",
        "--retries",
        "1",
        "--contimeout",
        "15s",
        "--timeout",
        "30s",
    ]);
    if !root_id.is_empty() {
        a.extend(args(&["--drive-root-folder-id", root_id]));
    }
    let mut result: Vec<RemoteFolder> = serde_json::from_slice(&run(
        runtime,
        Some(&config_path(app, account_id)?),
        &a,
        90,
        false,
    )?)
    .map_err(|_| "Drive devolvió una lista inválida")?;
    result.sort_by_key(|f| f.name.to_lowercase());
    Ok(result)
}
fn pair_args(app: &AppHandle, pair: &Pair) -> Result<(PathBuf, Vec<String>), String> {
    require_account(app, &pair.account_id)?;
    validate_remote(&pair.remote)?;
    if !pair.root_id.is_empty() && !valid_id(&pair.root_id) {
        return Err("Carpeta raíz inválida.".into());
    }
    if !valid_id(&pair.id) {
        return Err("Identificador de carpeta inválido.".into());
    }
    let local = Path::new(&pair.local);
    if !local.is_absolute() || !local.is_dir() {
        return Err(
            "La carpeta local no está disponible. Comprueba que el disco esté conectado.".into(),
        );
    }
    let mut common = args(&["--retries", "1", "--contimeout", "15s", "--timeout", "30s"]);
    if !pair.root_id.is_empty() {
        common.extend(args(&["--drive-root-folder-id", &pair.root_id]));
    }
    Ok((config_path(app, &pair.account_id)?, common))
}
fn comparison(bytes: &[u8]) -> Comparison {
    let mut result = Comparison::default();
    for line in String::from_utf8_lossy(bytes).lines() {
        match line.as_bytes().first() {
            Some(b'=') => result.identical += 1,
            Some(b'+') => result.local_only += 1,
            Some(b'-') => result.cloud_only += 1,
            Some(b'*') => result.different += 1,
            Some(b'!') => result.errors += 1,
            _ => {}
        }
    }
    result
}
pub fn compare(app: &AppHandle, runtime: &CloudRuntime, pair: &Pair) -> Result<Comparison, String> {
    let (config, common) = pair_args(app, pair)?;
    let mut a = args(&[
        "copy",
        &pair.local,
        &format!("cloud:{}", pair.remote),
        "--dry-run",
        "--checksum",
        "--combined",
        "-",
        "--check-first",
    ]);
    a.extend(common);
    let result = comparison(&run(runtime, Some(&config), &a, 600, false)?);
    if result.errors > 0 {
        return Err("No se pudieron comprobar todos los archivos.".into());
    }
    Ok(result)
}
pub fn upload(app: &AppHandle, runtime: &CloudRuntime, pair: &Pair) -> Result<Comparison, String> {
    let (config, common) = pair_args(app, pair)?;
    let version = format!(
        "cloud:.Nubix-history/{}/{}",
        pair.id,
        uuid::Uuid::new_v4()
    );
    let mut a = args(&[
        "copy",
        &pair.local,
        &format!("cloud:{}", pair.remote),
        "--checksum",
        "--backup-dir",
        &version,
        "--check-first",
    ]);
    a.extend(common);
    run(runtime, Some(&config), &a, 24 * 60 * 60, false)?;
    compare(app, runtime, pair)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reject_unsafe_destinations() {
        for s in [
            "",
            "../otra",
            "a/../b",
            "C:/x",
            "a\\b",
            "/raiz",
            "a//b",
            ".Nubix-history/x",
            ".NubeSync-history/x",
        ] {
            assert!(validate_remote(s).is_err(), "{s}");
        }
        assert!(validate_remote("Imágenes/01_Branding/Ely").is_ok());
    }
    #[test]
    fn parse_differences() {
        let c = comparison(b"= same\n+ new\n- cloud\n* changed\n! unreadable\n");
        assert_eq!(
            (
                c.identical,
                c.local_only,
                c.cloud_only,
                c.different,
                c.errors
            ),
            (1, 1, 1, 1, 1)
        );
    }
    #[test]
    fn errors_never_return_credentials() {
        let error = error_message(b"invalid_client access_token=VERYSECRET");
        assert!(!error.contains("VERYSECRET"));
    }
    #[test]
    fn ids_cannot_escape_private_directory() {
        assert!(!valid_id("../secret"));
        assert!(!valid_id("a:b"));
        assert!(valid_id("abc-123_X"));
    }

    #[test]
    fn drive_folder_id_is_preserved() {
        let f: RemoteFolder =
            serde_json::from_str(r#"{"Name":"Imágenes","ID":"1abc_X","Path":"Imágenes"}"#).unwrap();
        assert_eq!(f.id, "1abc_X");
        assert_eq!(serde_json::to_value(f).unwrap()["ID"], "1abc_X");
    }

    #[test]
    fn rclone_dry_run_and_version_history() {
        let base = std::env::temp_dir().join(format!("nubix-test-{}", uuid::Uuid::new_v4()));
        let source = base.join("source");
        let dest = base.join("dest");
        let history = base.join("history");
        fs::create_dir_all(&source).unwrap();
        fs::create_dir_all(&dest).unwrap();
        fs::write(source.join("same.txt"), "same").unwrap();
        fs::write(dest.join("same.txt"), "same").unwrap();
        fs::write(source.join("changed.txt"), "NEW").unwrap();
        fs::write(dest.join("changed.txt"), "OLD").unwrap();
        fs::write(source.join("new.txt"), "new").unwrap();
        fs::write(dest.join("cloud.txt"), "cloud").unwrap();
        let runtime = CloudRuntime::default();
        let output = run(
            &runtime,
            None,
            &args(&[
                "copy",
                source.to_str().unwrap(),
                dest.to_str().unwrap(),
                "--dry-run",
                "--checksum",
                "--combined",
                "-",
                "--retries",
                "1",
            ]),
            30,
            false,
        )
        .unwrap();
        let c = comparison(&output);
        assert_eq!(
            (c.identical, c.local_only, c.cloud_only, c.different),
            (1, 1, 1, 1)
        );
        assert!(!dest.join("new.txt").exists());
        assert_eq!(fs::read_to_string(dest.join("changed.txt")).unwrap(), "OLD");
        run(
            &runtime,
            None,
            &args(&[
                "copy",
                source.to_str().unwrap(),
                dest.to_str().unwrap(),
                "--checksum",
                "--backup-dir",
                history.to_str().unwrap(),
                "--retries",
                "1",
            ]),
            30,
            false,
        )
        .unwrap();
        assert_eq!(fs::read_to_string(dest.join("changed.txt")).unwrap(), "NEW");
        assert_eq!(
            fs::read_to_string(history.join("changed.txt")).unwrap(),
            "OLD"
        );
        assert!(dest.join("cloud.txt").exists());
        for folder in [&source, &dest, &history] {
            for entry in fs::read_dir(folder).unwrap() {
                fs::remove_file(entry.unwrap().path()).unwrap();
            }
            fs::remove_dir(folder).unwrap();
        }
        fs::remove_dir(base).unwrap();
    }
}
