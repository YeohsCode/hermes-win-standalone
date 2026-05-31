use std::process::Stdio;
use std::sync::Mutex;
use tokio::io;
use tokio::net::TcpListener;
use tokio::process::{Child, Command};
use tokio::time::{sleep, Duration};

const DISTRO_NAME: &str = "HermesLinux";
const SERVICES_SCRIPT: &str = "/opt/hermes/scripts/start-services.sh";
const STOP_SCRIPT: &str = "/opt/hermes/scripts/stop-services.sh";
const HEALTH_SCRIPT: &str = "/opt/hermes/scripts/health-check.sh";
const SERVICE_PORT: u16 = 8787;

static WSL_SESSION: Mutex<Option<Child>> = Mutex::new(None);

pub fn service_port() -> u16 {
    SERVICE_PORT
}

pub async fn is_wsl_enabled() -> Result<bool, String> {
    let status_output = Command::new("wsl")
        .arg("--status")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await;

    if let Ok(output) = status_output {
        if output.status.success() {
            return Ok(true);
        }
    }

    let list_output = Command::new("wsl")
        .args(["--list", "--quiet"])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await;

    match list_output {
        Ok(output) => Ok(output.status.success()),
        Err(_) => Ok(false),
    }
}

pub async fn is_distro_registered() -> Result<bool, String> {
    let output = Command::new("wsl")
        .args(["--list", "--quiet"])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await
        .map_err(|e| format!("Failed to list WSL distros: {}", e))?;

    let stdout = decode_wsl_output(&output.stdout);
    Ok(stdout.lines().any(|line| line.trim() == DISTRO_NAME))
}

fn decode_wsl_output(raw: &[u8]) -> String {
    if raw.len() >= 2 && raw.len() % 2 == 0 && raw.iter().skip(1).step_by(2).any(|&b| b == 0) {
        let u16s: Vec<u16> = raw
            .chunks_exact(2)
            .map(|c| u16::from_le_bytes([c[0], c[1]]))
            .collect();
        String::from_utf16_lossy(&u16s)
    } else {
        String::from_utf8_lossy(raw).into_owned()
    }
}

pub async fn start_services() -> Result<(), String> {
    let child = Command::new("wsl")
        .args([
            "-d",
            DISTRO_NAME,
            "--",
            "bash",
            "-c",
            &format!("bash {} {} && tail -f /dev/null", SERVICES_SCRIPT, SERVICE_PORT),
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("Failed to start services: {}", e))?;

    *WSL_SESSION
        .lock()
        .map_err(|e| format!("Lock error: {}", e))? = Some(child);

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

    let old_child = WSL_SESSION
        .lock()
        .ok()
        .and_then(|mut guard| guard.take());
    if let Some(mut child) = old_child {
        let _ = child.kill().await;
    }

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

pub async fn get_wsl_ip() -> Result<String, String> {
    let output = Command::new("wsl")
        .args(["-d", DISTRO_NAME, "--", "hostname", "-I"])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await
        .map_err(|e| format!("Failed to get WSL IP: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let ip = stdout.trim().split_whitespace().next().unwrap_or("127.0.0.1");
    Ok(ip.to_string())
}

/// Check if the service is ready by probing from INSIDE the WSL VM.
/// This avoids any Windows↔WSL2 network routing issues.
pub async fn wait_for_ready_inside_wsl(timeout_secs: u64) -> Result<(), String> {
    let start = std::time::Instant::now();
    let timeout = Duration::from_secs(timeout_secs);

    loop {
        if start.elapsed() > timeout {
            return Err(format!(
                "Hermes did not become ready within {} seconds",
                timeout_secs
            ));
        }

        let check = Command::new("wsl")
            .args([
                "-d",
                DISTRO_NAME,
                "--",
                "bash",
                "-c",
                &format!(
                    "curl -s -o /dev/null -w '%{{http_code}}' http://localhost:{}/",
                    SERVICE_PORT
                ),
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await;

        if let Ok(output) = check {
            let code = String::from_utf8_lossy(&output.stdout);
            if code.trim() == "200" {
                return Ok(());
            }
        }

        sleep(Duration::from_secs(2)).await;
    }
}

pub async fn tcp_check_host(host: &str, port: u16) -> bool {
    tokio::net::TcpStream::connect(format!("{}:{}", host, port))
        .await
        .is_ok()
}

/// Bind a TCP proxy on localhost (OS-assigned port) forwarding to target_ip:target_port.
/// Returns the actual port the OS assigned.
pub async fn start_port_proxy(target_ip: String, target_port: u16) -> Result<u16, String> {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .map_err(|e| format!("Failed to bind proxy listener: {}", e))?;

    let actual_port = listener
        .local_addr()
        .map_err(|e| format!("Failed to get proxy address: {}", e))?
        .port();

    tokio::spawn(async move {
        loop {
            let (mut client, _) = match listener.accept().await {
                Ok(c) => c,
                Err(_) => continue,
            };
            let addr = format!("{}:{}", target_ip, target_port);
            tokio::spawn(async move {
                if let Ok(mut upstream) = tokio::net::TcpStream::connect(&addr).await {
                    let (mut cr, mut cw) = client.split();
                    let (mut ur, mut uw) = upstream.split();
                    let _ = tokio::join!(io::copy(&mut cr, &mut uw), io::copy(&mut ur, &mut cw));
                }
            });
        }
    });

    Ok(actual_port)
}
