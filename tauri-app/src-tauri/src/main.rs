mod tray;
mod wsl;

use std::sync::Mutex;
use tauri::Manager;

#[derive(serde::Serialize, Clone)]
struct WslStatus {
    ready: bool,
    wsl_installed: bool,
    distro_registered: bool,
}

static HERMES_URL: Mutex<Option<String>> = Mutex::new(None);

#[tauri::command]
async fn check_wsl_ready() -> Result<WslStatus, String> {
    let wsl_installed = wsl::is_wsl_enabled().await?;
    if !wsl_installed {
        return Ok(WslStatus {
            ready: false,
            wsl_installed: false,
            distro_registered: false,
        });
    }
    let distro_registered = wsl::is_distro_registered().await?;
    Ok(WslStatus {
        ready: distro_registered,
        wsl_installed: true,
        distro_registered,
    })
}

#[tauri::command]
async fn start_hermes() -> Result<String, String> {
    if let Some(url) = HERMES_URL.lock().ok().and_then(|g| g.clone()) {
        return Ok(url);
    }

    wsl::start_services().await?;
    wsl::wait_for_ready_inside_wsl(120).await?;

    // wslhost.exe forwards localhost:{port} -> WSL VM automatically.
    // If that fails, fall back to a TCP proxy via the WSL VM IP.
    let port = wsl::service_port();
    let url = if wsl::tcp_check_host("127.0.0.1", port).await {
        format!("http://localhost:{}", port)
    } else {
        let wsl_ip = wsl::get_wsl_ip().await?;
        let proxy_port = wsl::start_port_proxy(wsl_ip, port).await?;
        format!("http://localhost:{}", proxy_port)
    };

    if let Ok(mut guard) = HERMES_URL.lock() {
        *guard = Some(url.clone());
    }
    Ok(url)
}

#[tauri::command]
async fn stop_hermes() -> Result<(), String> {
    if let Ok(mut guard) = HERMES_URL.lock() {
        *guard = None;
    }
    wsl::stop_services().await
}

#[tauri::command]
async fn get_hermes_status() -> Result<String, String> {
    wsl::health_check().await
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![
            check_wsl_ready,
            start_hermes,
            stop_hermes,
            get_hermes_status,
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
