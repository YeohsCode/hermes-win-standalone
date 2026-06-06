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

// ===========================================================================
// Layer 2: CommandRunner — abstracts raw command execution for wsl.rs tests
// ===========================================================================

pub(crate) struct CmdOutput {
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub success: bool,
    #[allow(dead_code)]
    pub code: Option<i32>,
}

pub(crate) trait CommandRunner: Send + Sync {
    async fn exec(&self, args: &[&str]) -> Result<CmdOutput, String>;
    async fn spawn_session(&self, args: &[&str]) -> Result<(), String>;
    async fn kill_session(&self) -> Result<(), String>;
}

pub(crate) struct RealRunner;

impl CommandRunner for RealRunner {
    async fn exec(&self, args: &[&str]) -> Result<CmdOutput, String> {
        let output = Command::new("wsl")
            .args(args)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await
            .map_err(|e| format!("Failed to execute wsl: {}", e))?;
        Ok(CmdOutput {
            stdout: output.stdout,
            stderr: output.stderr,
            success: output.status.success(),
            code: output.status.code(),
        })
    }

    async fn spawn_session(&self, args: &[&str]) -> Result<(), String> {
        let child = Command::new("wsl")
            .args(args)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| format!("Failed to spawn session: {}", e))?;
        *WSL_SESSION
            .lock()
            .map_err(|e| format!("Lock error: {}", e))? = Some(child);
        Ok(())
    }

    async fn kill_session(&self) -> Result<(), String> {
        if let Some(mut c) = WSL_SESSION.lock().ok().and_then(|mut g| g.take()) {
            let _ = c.kill().await;
        }
        Ok(())
    }
}

// ===========================================================================
// Layer 1: WslOps — abstracts all WSL operations for main.rs orchestration tests
// ===========================================================================

pub(crate) trait WslOps: Send + Sync {
    async fn is_wsl_enabled(&self) -> Result<bool, String>;
    async fn is_distro_registered(&self) -> Result<bool, String>;
    async fn ensure_wsl2(&self) -> Result<(), String>;
    async fn clean_stale_pids(&self) -> Result<(), String>;
    async fn start_services(&self) -> Result<String, String>;
    async fn stop_services(&self) -> Result<(), String>;
    async fn terminate_distro(&self) -> Result<(), String>;
    async fn wait_for_vm(&self, timeout_secs: u64) -> Result<(), String>;
    async fn wait_for_service_pids(&self, timeout_secs: u64) -> Result<(), String>;
    async fn wait_for_http_ready(&self, timeout_secs: u64) -> Result<(), String>;
    async fn get_service_logs(&self, lines: u32) -> Result<String, String>;
    async fn health_check(&self) -> Result<String, String>;
    async fn get_wsl_ip(&self) -> Result<String, String>;
    async fn tcp_check_host(&self, host: &str, port: u16) -> bool;
    async fn start_port_proxy(&self, target_ip: String, target_port: u16) -> Result<u16, String>;
}

pub(crate) struct RealWslOps;

impl WslOps for RealWslOps {
    async fn is_wsl_enabled(&self) -> Result<bool, String> {
        is_wsl_enabled().await
    }
    async fn is_distro_registered(&self) -> Result<bool, String> {
        is_distro_registered().await
    }
    async fn ensure_wsl2(&self) -> Result<(), String> {
        ensure_wsl2().await
    }
    async fn clean_stale_pids(&self) -> Result<(), String> {
        clean_stale_pids().await
    }
    async fn start_services(&self) -> Result<String, String> {
        start_services().await
    }
    async fn stop_services(&self) -> Result<(), String> {
        stop_services().await
    }
    async fn terminate_distro(&self) -> Result<(), String> {
        terminate_distro().await
    }
    async fn wait_for_vm(&self, t: u64) -> Result<(), String> {
        wait_for_vm(t).await
    }
    async fn wait_for_service_pids(&self, t: u64) -> Result<(), String> {
        wait_for_service_pids(t).await
    }
    async fn wait_for_http_ready(&self, t: u64) -> Result<(), String> {
        wait_for_http_ready(t).await
    }
    async fn get_service_logs(&self, n: u32) -> Result<String, String> {
        get_service_logs(n).await
    }
    async fn health_check(&self) -> Result<String, String> {
        health_check().await
    }
    async fn get_wsl_ip(&self) -> Result<String, String> {
        get_wsl_ip().await
    }
    async fn tcp_check_host(&self, host: &str, port: u16) -> bool {
        tcp_check_host(host, port).await
    }
    async fn start_port_proxy(&self, ip: String, port: u16) -> Result<u16, String> {
        start_port_proxy(ip, port).await
    }
}

// ===========================================================================
// Pure helpers
// ===========================================================================

pub fn service_port() -> u16 {
    SERVICE_PORT
}

pub(crate) fn decode_wsl_output(raw: &[u8]) -> String {
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

pub(crate) fn parse_distro_wsl_version(verbose_output: &str, distro_name: &str) -> Option<u32> {
    for line in verbose_output.lines() {
        let trimmed = line.trim().trim_start_matches('*').trim();
        if trimmed.starts_with(distro_name) {
            return trimmed
                .split_whitespace()
                .last()
                .and_then(|v| v.parse().ok());
        }
    }
    None
}

// ===========================================================================
// Testable _with variants (used by B-tier tests via MockRunner)
// ===========================================================================

pub(crate) async fn ensure_wsl2_with<R: CommandRunner>(runner: &R) -> Result<(), String> {
    let output = runner.exec(&["--list", "--verbose"]).await?;
    let stdout = decode_wsl_output(&output.stdout);
    let version = parse_distro_wsl_version(&stdout, DISTRO_NAME);

    match version {
        Some(2) => Ok(()),
        Some(1) => {
            let convert = runner.exec(&["--set-version", DISTRO_NAME, "2"]).await?;
            if !convert.success {
                let stderr = decode_wsl_output(&convert.stderr);
                return Err(format!(
                    "无法将 HermesLinux 转换为 WSL2: {}\n请确认 VirtualMachinePlatform 已启用且 WSL 内核已安装。",
                    stderr.trim()
                ));
            }
            Ok(())
        }
        Some(v) => Err(format!("HermesLinux WSL 版本异常: {}，需要版本 2", v)),
        None => Err("无法确定 HermesLinux 的 WSL 版本。请确认发行版已注册。".into()),
    }
}

/// WSL kills nohup'd background processes when the parent `wsl.exe` exits.
/// To keep the services alive, we combine the startup script and the keep-alive
/// into a single `wsl.exe` session. Output and exit code are captured via temp
/// files and read back through a separate `exec` call.
pub(crate) async fn start_services_with<R: CommandRunner>(runner: &R) -> Result<String, String> {
    let combined_cmd = format!(
        "rm -f /tmp/hermes-start-exit /tmp/hermes-start-output; \
         bash {} {} > /tmp/hermes-start-output 2>&1; \
         echo $? > /tmp/hermes-start-exit; \
         exec tail -f /dev/null",
        SERVICES_SCRIPT, SERVICE_PORT
    );

    runner
        .spawn_session(&["-d", DISTRO_NAME, "--", "bash", "-c", &combined_cmd])
        .await?;

    let deadline = std::time::Instant::now() + Duration::from_secs(15);
    loop {
        sleep(Duration::from_millis(500)).await;

        let check = runner
            .exec(&["-d", DISTRO_NAME, "--", "cat", "/tmp/hermes-start-exit"])
            .await;

        if let Ok(output) = &check {
            let exit_str = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !exit_str.is_empty() {
                let log = runner
                    .exec(&["-d", DISTRO_NAME, "--", "cat", "/tmp/hermes-start-output"])
                    .await
                    .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
                    .unwrap_or_default();

                let exit_code: i32 = exit_str.parse().unwrap_or(-1);
                if exit_code != 0 {
                    let _ = runner.kill_session().await;
                    return Err(format!(
                        "start-services.sh 退出码 {}\n--- output ---\n{}",
                        exit_code,
                        &log[..log.len().min(2000)]
                    ));
                }
                return Ok(log);
            }
        }

        if std::time::Instant::now() > deadline {
            let _ = runner.kill_session().await;
            return Err("start-services.sh 在 15 秒内未完成".into());
        }
    }
}

// ===========================================================================
// Public free functions (production code, delegates where possible)
// ===========================================================================

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

pub async fn ensure_wsl2() -> Result<(), String> {
    ensure_wsl2_with(&RealRunner).await
}

pub async fn clean_stale_pids() -> Result<(), String> {
    let _ = Command::new("wsl")
        .args([
            "-d",
            DISTRO_NAME,
            "--",
            "bash",
            "-c",
            "rm -f /run/hermes/*.pid 2>/dev/null; mkdir -p /run/hermes",
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .await;
    Ok(())
}

pub async fn start_services() -> Result<String, String> {
    start_services_with(&RealRunner).await
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

pub async fn terminate_distro() -> Result<(), String> {
    let _ = Command::new("wsl")
        .args(["--terminate", DISTRO_NAME])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .await;
    if let Some(mut c) = WSL_SESSION.lock().ok().and_then(|mut g| g.take()) {
        let _ = c.kill().await;
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

// ---------------------------------------------------------------------------
// Three-phase readiness checks
// ---------------------------------------------------------------------------

pub async fn wait_for_vm(timeout_secs: u64) -> Result<(), String> {
    let start = std::time::Instant::now();
    let deadline = Duration::from_secs(timeout_secs);

    loop {
        if start.elapsed() > deadline {
            return Err(format!(
                "WSL 虚拟机在 {} 秒内未响应。可能原因：WSL 内核未安装、VirtualMachinePlatform 未启用。",
                timeout_secs
            ));
        }
        let check = Command::new("wsl")
            .args(["-d", DISTRO_NAME, "--exec", "echo", "ok"])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await;
        if let Ok(output) = check {
            if output.status.success() {
                return Ok(());
            }
        }
        sleep(Duration::from_secs(1)).await;
    }
}

pub async fn wait_for_service_pids(timeout_secs: u64) -> Result<(), String> {
    let start = std::time::Instant::now();
    let deadline = Duration::from_secs(timeout_secs);

    loop {
        if start.elapsed() > deadline {
            let logs = get_service_logs(30).await.unwrap_or_default();
            return Err(format!(
                "服务进程在 {} 秒内未启动（PID 文件未找到或进程已退出）。\n\n最近日志:\n{}",
                timeout_secs, logs
            ));
        }
        let check = Command::new("wsl")
            .args([
                "-d",
                DISTRO_NAME,
                "--",
                "bash",
                "-c",
                "test -f /run/hermes/agent.pid && kill -0 $(cat /run/hermes/agent.pid) 2>/dev/null",
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await;
        if let Ok(output) = check {
            if output.status.success() {
                return Ok(());
            }
        }
        sleep(Duration::from_secs(2)).await;
    }
}

pub async fn wait_for_http_ready(timeout_secs: u64) -> Result<(), String> {
    let start = std::time::Instant::now();
    let deadline = Duration::from_secs(timeout_secs);

    loop {
        if start.elapsed() > deadline {
            let logs = get_service_logs(30).await.unwrap_or_default();
            return Err(format!(
                "服务进程已运行，但 HTTP 端口在 {} 秒内未就绪。服务可能正在初始化或已崩溃。\n\n最近日志:\n{}",
                timeout_secs, logs
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
            let code_num: u16 = code.trim().parse().unwrap_or(0);
            if (200..400).contains(&code_num) {
                return Ok(());
            }
        }
        sleep(Duration::from_secs(2)).await;
    }
}

pub async fn get_service_logs(lines: u32) -> Result<String, String> {
    let output = Command::new("wsl")
        .args([
            "-d",
            DISTRO_NAME,
            "--",
            "bash",
            "-c",
            &format!(
                "for f in /root/.hermes/logs/*.log; do \
                   [ -f \"$f\" ] || continue; \
                   echo \"=== $f ===\"; \
                   tail -n {} \"$f\" 2>/dev/null; \
                   echo; \
                 done",
                lines
            ),
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await
        .map_err(|e| format!("Failed to fetch logs: {}", e))?;

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

// ---------------------------------------------------------------------------
// Network helpers
// ---------------------------------------------------------------------------

pub async fn tcp_check_host(host: &str, port: u16) -> bool {
    tokio::net::TcpStream::connect(format!("{}:{}", host, port))
        .await
        .is_ok()
}

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
