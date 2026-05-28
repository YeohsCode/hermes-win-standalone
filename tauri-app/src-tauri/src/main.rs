mod port;
mod tray;
mod wsl;

#[tauri::command]
async fn check_wsl_ready() -> Result<bool, String> {
    let wsl_enabled = wsl::is_wsl_enabled().await?;
    if !wsl_enabled {
        return Ok(false);
    }
    let distro_exists = wsl::is_distro_registered().await?;
    Ok(distro_exists)
}

#[tauri::command]
async fn start_hermes() -> Result<String, String> {
    let port = port::find_available_port(8787);
    wsl::start_services(port).await?;
    wsl::wait_for_ready(port, 30).await?;
    Ok(format!("http://localhost:{}", port))
}

#[tauri::command]
async fn stop_hermes() -> Result<(), String> {
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
            tray::create_tray(app.handle())?;
            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                window.hide().unwrap_or_default();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
