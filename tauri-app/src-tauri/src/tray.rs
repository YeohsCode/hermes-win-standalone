use tauri::{
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
    AppHandle, Manager,
};

pub fn create_tray(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let show = MenuItem::with_id(app, "show", "显示窗口", true, None::<&str>)?;
    let restart = MenuItem::with_id(app, "restart", "重启服务", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;

    let menu = Menu::with_items(app, &[&show, &restart, &quit])?;

    TrayIconBuilder::new()
        .menu(&menu)
        .tooltip("Hermes AI Agent")
        .on_menu_event(move |app, event| match event.id.as_ref() {
            "show" => {
                if let Some(window) = app.get_webview_window("main") {
                    window.show().unwrap_or_default();
                    window.set_focus().unwrap_or_default();
                }
            }
            "restart" => {
                let app_handle = app.clone();
                tauri::async_runtime::spawn(async move {
                    let _ = crate::stop_hermes().await;
                    let _ = crate::start_hermes().await;
                    if let Some(window) = app_handle.get_webview_window("main") {
                        window.show().unwrap_or_default();
                    }
                });
            }
            "quit" => {
                let app_handle = app.clone();
                tauri::async_runtime::spawn(async move {
                    let _ = crate::stop_hermes().await;
                    app_handle.exit(0);
                });
            }
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let tauri::tray::TrayIconEvent::DoubleClick { .. } = event {
                let app = tray.app_handle();
                if let Some(window) = app.get_webview_window("main") {
                    window.show().unwrap_or_default();
                    window.set_focus().unwrap_or_default();
                }
            }
        })
        .build(app)?;

    Ok(())
}
