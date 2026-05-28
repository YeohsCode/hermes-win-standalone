use std::process::Stdio;
use tokio::process::Command;
use tokio::time::{sleep, Duration};

const DISTRO_NAME: &str = "HermesLinux";
const SERVICES_SCRIPT: &str = "/opt/hermes/scripts/start-services.sh";
const STOP_SCRIPT: &str = "/opt/hermes/scripts/stop-services.sh";
const HEALTH_SCRIPT: &str = "/opt/hermes/scripts/health-check.sh";

pub async fn is_wsl_enabled() -> Result<bool, String> {
    let output = Command::new("wsl")
        .arg("--version")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await
        .map_err(|e| format!("Failed to check WSL: {}", e))?;

    Ok(output.status.success())
}

pub async fn is_distro_registered() -> Result<bool, String> {
    let output = Command::new("wsl")
        .args(["--list", "--quiet"])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await
        .map_err(|e| format!("Failed to list WSL distros: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    Ok(stdout.lines().any(|line| line.trim().trim_matches('\0') == DISTRO_NAME))
}

pub async fn start_services(port: u16) -> Result<(), String> {
    let status = Command::new("wsl")
        .args([
            "-d",
            DISTRO_NAME,
            "--",
            "bash",
            SERVICES_SCRIPT,
            &port.to_string(),
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to start services: {}", e))?;

    // Don't wait for the process — services run in background
    drop(status);
    Ok(())
}

pub async fn stop_services() -> Result<(), String> {
    let output = Command::new("wsl")
        .args(["-d", DISTRO_NAME, "--", "bash", STOP_SCRIPT])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await
        .map_err(|e| format!("Failed to stop services: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Stop services failed: {}", stderr));
    }
    Ok(())
}

pub async fn health_check() -> Result<String, String> {
    let output = Command::new("wsl")
        .args(["-d", DISTRO_NAME, "--", "bash", HEALTH_SCRIPT])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await
        .map_err(|e| format!("Health check failed: {}", e))?;

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

pub async fn wait_for_ready(port: u16, timeout_secs: u64) -> Result<(), String> {
    let start = std::time::Instant::now();
    let timeout = Duration::from_secs(timeout_secs);

    loop {
        if start.elapsed() > timeout {
            return Err(format!(
                "Hermes did not become ready within {} seconds",
                timeout_secs
            ));
        }

        match reqwest_check(port).await {
            Ok(true) => return Ok(()),
            _ => sleep(Duration::from_millis(500)).await,
        }
    }
}

async fn reqwest_check(port: u16) -> Result<bool, ()> {
    let url = format!("http://127.0.0.1:{}/health", port);
    let stream = tokio::net::TcpStream::connect(format!("127.0.0.1:{}", port)).await;
    match stream {
        Ok(_) => {
            drop(url);
            Ok(true)
        }
        Err(_) => Ok(false),
    }
}
