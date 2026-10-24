use std::process::Command;
use std::sync::Arc;
use tauri::{Emitter, Manager};
mod cloud;
mod preferences;

#[tauri::command]
async fn preferences_load(app: tauri::AppHandle) -> Result<Option<serde_json::Value>, String> {
    blocking(move || preferences::load(&app)).await
}
#[tauri::command]
async fn preferences_save(app: tauri::AppHandle, folders: serde_json::Value) -> Result<(), String> {
    blocking(move || preferences::save(&app, folders)).await
}
#[tauri::command]
async fn job_status(app: tauri::AppHandle) -> Result<Option<preferences::Job>, String> {
    blocking(move || preferences::job(&app)).await
}

async fn blocking<T: Send + 'static>(
    work: impl FnOnce() -> Result<T, String> + Send + 'static,
) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(work)
        .await
        .map_err(|_| "La operación se interrumpió.".to_string())?
}
#[tauri::command]
async fn cloud_accounts(app: tauri::AppHandle) -> Result<Vec<cloud::Account>, String> {
    blocking(move || cloud::list_accounts(&app)).await
}
#[tauri::command]
async fn cloud_existing(
    state: tauri::State<'_, Arc<cloud::CloudRuntime>>,
) -> Result<Vec<cloud::ExistingRemote>, String> {
    let runtime = state.inner().clone();
    blocking(move || cloud::existing_remotes(&runtime)).await
}
#[tauri::command]
async fn cloud_import(
    app: tauri::AppHandle,
    state: tauri::State<'_, Arc<cloud::CloudRuntime>>,
    name: String,
) -> Result<cloud::Account, String> {
    let runtime = state.inner().clone();
    blocking(move || cloud::import_remote(&app, &runtime, name)).await
}
#[tauri::command]
async fn cloud_connect(
    app: tauri::AppHandle,
    state: tauri::State<'_, Arc<cloud::CloudRuntime>>,
    json_path: String,
    name: String,
) -> Result<cloud::Account, String> {
    let runtime = state.inner().clone();
    blocking(move || cloud::connect(&app, &runtime, json_path, name)).await
}
#[tauri::command]
async fn cloud_disconnect(
    app: tauri::AppHandle,
    state: tauri::State<'_, Arc<cloud::CloudRuntime>>,
    id: String,
) -> Result<(), String> {
    let runtime = state.inner().clone();
    blocking(move || cloud::disconnect(&app, &runtime, &id)).await
}
#[tauri::command]
fn cloud_cancel(
    app: tauri::AppHandle,
    state: tauri::State<'_, Arc<cloud::CloudRuntime>>,
) -> Result<(), String> {
    cloud::cancel(&state);
    preferences::cancel_job(&app)
}
#[tauri::command]
async fn cloud_folders(
    app: tauri::AppHandle,
    state: tauri::State<'_, Arc<cloud::CloudRuntime>>,
    account_id: String,
    root_id: String,
) -> Result<Vec<cloud::RemoteFolder>, String> {
    let runtime = state.inner().clone();
    blocking(move || cloud::list_folders(&app, &runtime, &account_id, &root_id)).await
}
#[tauri::command]
async fn cloud_compare(
    app: tauri::AppHandle,
    state: tauri::State<'_, Arc<cloud::CloudRuntime>>,
    pair: cloud::Pair,
) -> Result<cloud::Comparison, String> {
    let runtime = state.inner().clone();
    blocking(move || cloud::compare(&app, &runtime, &pair)).await
}
#[tauri::command]
async fn cloud_upload(
    app: tauri::AppHandle,
    state: tauri::State<'_, Arc<cloud::CloudRuntime>>,
    pair: cloud::Pair,
) -> Result<cloud::Comparison, String> {
    let runtime = state.inner().clone();
    blocking(move || cloud::upload(&app, &runtime, &pair)).await
}

#[tauri::command]
async fn rclone_version() -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(|| {
        let mut command = Command::new("rclone");
        command.arg("version");
        #[cfg(target_os = "windows")]
        {
            use std::os::windows::process::CommandExt;
            command.creation_flags(0x08000000);
        }
        let output = command
            .output()
            .map_err(|_| "Rclone no disponible en PATH".to_string())?;
        if !output.status.success() {
            return Err("No se pudo consultar Rclone".into());
        }
        String::from_utf8_lossy(&output.stdout)
            .lines()
            .next()
            .map(str::to_owned)
            .ok_or_else(|| "Rclone no devolvió su versión".into())
    })
    .await
    .map_err(|_| "La consulta de Rclone se interrumpió".to_string())?
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(Arc::new(cloud::CloudRuntime::default()))
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                let state = window.state::<Arc<cloud::CloudRuntime>>();
                if cloud::is_busy(&state) {
                    api.prevent_close();
                    let _ = window.emit("operation-close-blocked", ());
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            rclone_version,
            cloud_accounts,
            cloud_existing,
            cloud_import,
            cloud_connect,
            cloud_disconnect,
            cloud_cancel,
            cloud_folders,
            cloud_compare,
            cloud_upload,
            preferences_load,
            preferences_save,
            job_status
        ])
        .run(tauri::generate_context!())
        .expect("No se pudo iniciar Nubix");
}
