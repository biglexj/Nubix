use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};
use tauri::{AppHandle, Manager};

fn dir(app: &AppHandle) -> Result<PathBuf, String> {
    let p = app
        .path()
        .app_data_dir()
        .map_err(|_| "No se pudo localizar la configuración")?
        .join("cloud");
    fs::create_dir_all(&p).map_err(|_| "No se pudo guardar la configuración")?;
    Ok(p)
}
fn validate(value: &Value) -> Result<(), String> {
    let folders = value
        .as_array()
        .ok_or("La configuración de carpetas no es válida")?;
    for f in folders {
        let pair: crate::cloud::Pair = serde_json::from_value(f.clone())
            .map_err(|_| "La configuración de carpetas no es válida")?;
        if !Path::new(&pair.local).is_absolute()
            || pair.remote.is_empty()
            || pair.remote.contains([':', '\\', '\r', '\n', '\0'])
            || pair.remote.starts_with('/')
            || pair.remote.split('/').any(|p| {
                p.is_empty()
                    || p == "."
                    || p == ".."
                    || p.eq_ignore_ascii_case(".Nubix-history")
                    // Nombre anterior a la marca Nubix: sigue bloqueado para que
                    // nadie apunte un destino dentro del historial.
                    || p.eq_ignore_ascii_case(".NubeSync-history")
            })
        {
            return Err("La ruta de una carpeta no es válida".into());
        }
        if !matches!(
            f.get("mode").and_then(Value::as_str),
            Some("copy" | "mirror")
        ) || f
            .get("days")
            .and_then(Value::as_u64)
            .is_none_or(|n| n == 0 || n > 365)
            || f.get("keep").and_then(Value::as_bool).is_none()
            || f.get("rootLabel").and_then(Value::as_str).is_none()
        {
            return Err("Los ajustes de una carpeta no son válidos".into());
        }
    }
    Ok(())
}
pub fn load(app: &AppHandle) -> Result<Option<Value>, String> {
    let p = dir(app)?.join("folders.json");
    if !p.exists() {
        return Ok(None);
    }
    let value: Value =
        serde_json::from_slice(&fs::read(p).map_err(|_| "No se pudo leer la configuración")?)
            .map_err(|_| "La configuración no es válida")?;
    validate(&value)?;
    Ok(Some(value))
}
pub fn save(app: &AppHandle, value: Value) -> Result<(), String> {
    validate(&value)?;
    let bytes =
        serde_json::to_vec_pretty(&value).map_err(|_| "No se pudo guardar la configuración")?;
    let directory = dir(app)?;
    let tmp = directory.join(format!("folders-{}.tmp", uuid::Uuid::new_v4()));
    fs::write(&tmp, bytes).map_err(|_| "No se pudo guardar la configuración")?;
    fs::rename(&tmp, directory.join("folders.json")).map_err(|_| {
        let _ = fs::remove_file(tmp);
        "No se pudo guardar la configuración".into()
    })
}

#[derive(Serialize, Deserialize)]
pub struct FolderJob {
    pub id: String,
    pub state: String,
    #[serde(default)]
    pub transferred: u64,
    #[serde(default)]
    pub bytes: u64,
    #[serde(default)]
    pub total_bytes: u64,
    #[serde(default)]
    pub comparison: Option<crate::cloud::Comparison>,
    #[serde(default)]
    pub error: Option<String>,
}
#[derive(Serialize, Deserialize)]
pub struct Job {
    pub running: bool,
    pub pid: u32,
    pub updated: String,
    pub folders: Vec<FolderJob>,
}
fn alive(pid: u32) -> bool {
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        Command::new("tasklist")
            .creation_flags(0x08000000)
            .args(["/FI", &format!("PID eq {pid}"), "/FO", "CSV", "/NH"])
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .output()
            .is_ok_and(|o| String::from_utf8_lossy(&o.stdout).contains(&format!("\"{pid}\"")))
    }
    #[cfg(not(target_os = "windows"))]
    {
        Command::new("kill")
            .args(["-0", &pid.to_string()])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .is_ok_and(|s| s.success())
    }
}
pub fn job(app: &AppHandle) -> Result<Option<Job>, String> {
    let p = dir(app)?.join("job-status.json");
    if !p.exists() {
        return Ok(None);
    }
    let mut job: Job =
        serde_json::from_slice(&fs::read(p).map_err(|_| "No se pudo leer el avance")?)
            .map_err(|_| "No se pudo leer el avance")?;
    if job.running && !alive(job.pid) {
        job.running = false;
        for folder in &mut job.folders {
            if folder.state != "verified" && folder.state != "failed" {
                folder.state = "failed".into();
                folder.error =
                    Some("La subida se interrumpió. Revisa los cambios para continuar.".into());
            }
        }
    }
    Ok(Some(job))
}
pub fn cancel_job(app: &AppHandle) -> Result<(), String> {
    if job(app)?.is_some_and(|j| j.running) {
        fs::write(dir(app)?.join("cancel-job"), b"cancel")
            .map_err(|_| "No se pudo cancelar la subida")?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn preferences_reject_relative_source() {
        let f = serde_json::json!([{"id":"abc","local":"relative","remote":"Branding","accountId":"abc","rootId":"","rootLabel":"Drive","mode":"copy","days":7,"keep":true}]);
        assert!(validate(&f).is_err());
    }
    #[test]
    fn job_does_not_expose_extra_fields() {
        let j:Job=serde_json::from_value(serde_json::json!({"running":false,"pid":0,"updated":"now","folders":[],"token":"secret"})).unwrap();
        assert!(!serde_json::to_string(&j).unwrap().contains("secret"));
    }
}
