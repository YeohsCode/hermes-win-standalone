mod tray;
pub(crate) mod wsl;

#[cfg(test)]
mod tests;

use std::sync::Mutex;
use tauri::{Emitter, Manager};
use wsl::WslOps;

#[derive(serde::Serialize, Clone, Debug)]
struct WslStatus {
    ready: bool,
    wsl_installed: bool,
    distro_registered: bool,
}

#[derive(serde::Serialize, Clone)]
struct ProgressPayload {
    stage: String,
    message: String,
}

static HERMES_URL: Mutex<Option<String>> = Mutex::new(None);

fn emit_progress(app: &tauri::AppHandle, stage: &str, message: &str) {
    let _ = app.emit(
        "hermes-progress",
        ProgressPayload {
            stage: stage.to_string(),
            message: message.to_string(),
        },
    );
}

// ===========================================================================
// Testable orchestration functions (generic over WslOps + progress callback)
// ===========================================================================

pub(crate) async fn start_hermes_attempt<W, P>(wsl: &W, progress: &P) -> Result<String, String>
where
    W: WslOps,
    P: Fn(&str, &str) + Send + Sync,
{
    progress("cleaning", "清理旧进程...");
    wsl.clean_stale_pids().await?;

    progress("starting_services", "启动服务...");
    let _service_output = wsl.start_services().await?;

    progress("waiting_vm", "等待 WSL 虚拟机...");
    wsl.wait_for_vm(30).await?;

    progress("waiting_pids", "等待服务进程启动...");
    wsl.wait_for_service_pids(30).await?;

    progress("waiting_http", "等待服务就绪...");
    wsl.wait_for_http_ready(90).await?;

    progress("connecting", "建立连接...");
    let port = wsl::service_port();
    let url = if wsl.tcp_check_host("127.0.0.1", port).await {
        format!("http://localhost:{}", port)
    } else {
        let wsl_ip = wsl.get_wsl_ip().await?;
        let proxy_port = wsl.start_port_proxy(wsl_ip, port).await?;
        format!("http://localhost:{}", proxy_port)
    };

    if !wsl.tcp_check_host("127.0.0.1", url_port(&url)).await {
        return Err(format!("服务已就绪但无法通过 {} 访问。", url));
    }

    Ok(url)
}

pub(crate) async fn start_hermes_with_retry<W, P>(
    wsl: &W,
    progress: &P,
    url_cache: &Mutex<Option<String>>,
) -> Result<String, String>
where
    W: WslOps,
    P: Fn(&str, &str) + Send + Sync,
{
    if let Some(url) = url_cache.lock().ok().and_then(|g| g.clone()) {
        return Ok(url);
    }

    match start_hermes_attempt(wsl, progress).await {
        Ok(url) => {
            if let Ok(mut guard) = url_cache.lock() {
                *guard = Some(url.clone());
            }
            Ok(url)
        }
        Err(first_err) => {
            progress("retrying", "首次启动失败，正在重试...");
            let _ = wsl.stop_services().await;
            let _ = wsl.terminate_distro().await;
            tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;

            match start_hermes_attempt(wsl, progress).await {
                Ok(url) => {
                    if let Ok(mut guard) = url_cache.lock() {
                        *guard = Some(url.clone());
                    }
                    Ok(url)
                }
                Err(retry_err) => Err(format!(
                    "启动失败（已重试一次）\n\n首次: {}\n\n重试: {}",
                    first_err, retry_err
                )),
            }
        }
    }
}

pub(crate) async fn stop_hermes_impl<W: WslOps>(
    wsl: &W,
    url_cache: &Mutex<Option<String>>,
) -> Result<(), String> {
    if let Ok(mut guard) = url_cache.lock() {
        *guard = None;
    }
    wsl.stop_services().await
}

pub(crate) async fn reset_hermes_impl<W: WslOps>(
    wsl: &W,
    url_cache: &Mutex<Option<String>>,
) -> Result<(), String> {
    if let Ok(mut guard) = url_cache.lock() {
        *guard = None;
    }
    let _ = wsl.stop_services().await;
    let _ = wsl.terminate_distro().await;
    wsl.clean_stale_pids().await?;
    Ok(())
}

pub(crate) async fn check_wsl_ready_impl<W: WslOps>(wsl: &W) -> Result<WslStatus, String> {
    let wsl_installed = wsl.is_wsl_enabled().await?;
    if !wsl_installed {
        return Ok(WslStatus {
            ready: false,
            wsl_installed: false,
            distro_registered: false,
        });
    }
    let distro_registered = wsl.is_distro_registered().await?;
    Ok(WslStatus {
        ready: distro_registered,
        wsl_installed: true,
        distro_registered,
    })
}

pub(crate) fn url_port(url: &str) -> u16 {
    url.rsplit(':')
        .next()
        .and_then(|s| s.trim_end_matches('/').parse().ok())
        .unwrap_or(8787)
}

// ===========================================================================
// Tauri commands (thin wrappers that construct RealWslOps and delegate)
// ===========================================================================

#[tauri::command]
async fn check_wsl_ready() -> Result<WslStatus, String> {
    check_wsl_ready_impl(&wsl::RealWslOps).await
}

#[tauri::command]
async fn ensure_wsl2() -> Result<(), String> {
    wsl::RealWslOps.ensure_wsl2().await
}

#[tauri::command]
async fn start_hermes(app: tauri::AppHandle) -> Result<String, String> {
    let wsl = wsl::RealWslOps;
    let progress = |stage: &str, msg: &str| {
        emit_progress(&app, stage, msg);
    };
    start_hermes_with_retry(&wsl, &progress, &HERMES_URL).await
}

#[tauri::command]
async fn stop_hermes() -> Result<(), String> {
    stop_hermes_impl(&wsl::RealWslOps, &HERMES_URL).await
}

#[tauri::command]
async fn get_hermes_status() -> Result<String, String> {
    wsl::RealWslOps.health_check().await
}

#[tauri::command]
async fn get_hermes_logs() -> Result<String, String> {
    wsl::RealWslOps.get_service_logs(50).await
}

#[tauri::command]
async fn reset_hermes() -> Result<(), String> {
    reset_hermes_impl(&wsl::RealWslOps, &HERMES_URL).await
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![
            check_wsl_ready,
            ensure_wsl2,
            start_hermes,
            stop_hermes,
            get_hermes_status,
            get_hermes_logs,
            reset_hermes,
        ])
        .setup(|app| {
            let _ = tray::create_tray(app.handle());
            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                let app = window.app_handle();
                if app.tray_by_id("main").is_some() {
                    api.prevent_close();
                    window.hide().unwrap_or_default();
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
