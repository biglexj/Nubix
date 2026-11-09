use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use tauri::AppHandle;
use tauri::Manager;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSettings {
    #[serde(default = "default_close_to_tray")]
    pub close_to_tray: bool,
    #[serde(default)]
    pub autostart: bool,
}

fn default_close_to_tray() -> bool {
    true
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            close_to_tray: true,
            autostart: false,
        }
    }
}

#[cfg(windows)]
pub fn is_autostart_registered() -> bool {
    use winreg::enums::{HKEY_CURRENT_USER, KEY_READ};
    use winreg::RegKey;
    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    if let Ok(run_key) =
        hkcu.open_subkey_with_flags(r"Software\Microsoft\Windows\CurrentVersion\Run", KEY_READ)
    {
        run_key.get_value::<String, _>("Nubix").is_ok()
    } else {
        false
    }
}

#[cfg(not(windows))]
pub fn is_autostart_registered() -> bool {
    false
}

#[cfg(windows)]
pub fn set_autostart_registered(enable: bool) -> Result<(), String> {
    use winreg::enums::HKEY_CURRENT_USER;
    use winreg::RegKey;
    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let (run_key, _) = hkcu
        .create_subkey(r"Software\Microsoft\Windows\CurrentVersion\Run")
        .map_err(|e| format!("No se pudo acceder al registro de Windows: {}", e))?;

    if enable {
        let exe = std::env::current_exe()
            .map_err(|e| format!("Ruta del ejecutable no válida: {}", e))?;
        let cmd = format!("\"{}\" --autostart", exe.to_string_lossy());
        run_key
            .set_value("Nubix", &cmd)
            .map_err(|e| format!("No se pudo guardar la clave de inicio en el registro: {}", e))?;
    } else {
        let _ = run_key.delete_value("Nubix");
    }
    Ok(())
}

#[cfg(not(windows))]
pub fn set_autostart_registered(_enable: bool) -> Result<(), String> {
    Ok(())
}

pub fn settings_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|_| "No se pudo resolver la ruta de datos".to_string())?;
    let _ = fs::create_dir_all(&dir);
    Ok(dir.join("settings.json"))
}

pub fn load_settings(app: &AppHandle) -> AppSettings {
    let path = match settings_path(app) {
        Ok(p) => p,
        Err(_) => return AppSettings::default(),
    };
    if !path.exists() {
        return AppSettings {
            close_to_tray: true,
            autostart: is_autostart_registered(),
        };
    }
    let content = fs::read_to_string(&path).unwrap_or_default();
    let mut s: AppSettings = serde_json::from_str(&content).unwrap_or_default();
    s.autostart = is_autostart_registered();
    s
}

pub fn save_settings(app: &AppHandle, settings: &AppSettings) -> Result<(), String> {
    let path = settings_path(app)?;
    let data = serde_json::to_string_pretty(settings)
        .map_err(|e| format!("Error serializando ajustes: {}", e))?;
    fs::write(path, data).map_err(|e| format!("Error guardando ajustes: {}", e))?;
    let _ = set_autostart_registered(settings.autostart);
    Ok(())
}
