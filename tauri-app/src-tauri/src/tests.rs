use std::collections::VecDeque;
use std::sync::Mutex;

use crate::wsl::{self, CmdOutput, CommandRunner, WslOps};

// ===========================================================================
// C — Retained pure-function tests
// ===========================================================================

mod decode_wsl_output {
    use super::*;

    #[test]
    fn plain_utf8() {
        let input = b"HermesLinux\nUbuntu\n";
        let result = wsl::decode_wsl_output(input);
        assert!(result.contains("HermesLinux"));
        assert!(result.contains("Ubuntu"));
    }

    #[test]
    fn utf16le_with_null_bytes() {
        let input: Vec<u8> = "Hi\n"
            .encode_utf16()
            .flat_map(|c| c.to_le_bytes())
            .collect();
        let result = wsl::decode_wsl_output(&input);
        assert_eq!(result.trim(), "Hi");
    }

    #[test]
    fn utf16le_distro_name() {
        let text = "HermesLinux\r\nUbuntu\r\n";
        let input: Vec<u8> = text
            .encode_utf16()
            .flat_map(|c| c.to_le_bytes())
            .collect();
        let result = wsl::decode_wsl_output(&input);
        assert!(result.contains("HermesLinux"));
    }

    #[test]
    fn utf16le_with_bom() {
        let mut input: Vec<u8> = vec![0xFF, 0xFE];
        input.extend("OK".encode_utf16().flat_map(|c| c.to_le_bytes()));
        let result = wsl::decode_wsl_output(&input);
        assert!(result.contains("OK"));
    }

    #[test]
    fn empty_input() {
        assert_eq!(wsl::decode_wsl_output(b""), "");
    }

    #[test]
    fn single_byte_falls_through_to_utf8() {
        assert_eq!(wsl::decode_wsl_output(b"x"), "x");
    }
}

mod parse_distro_wsl_version {
    use super::*;

    const HEADER: &str = "  NAME            STATE           VERSION\n";

    #[test]
    fn version_2_running() {
        let output = format!("{}* HermesLinux     Running         2\n", HEADER);
        assert_eq!(wsl::parse_distro_wsl_version(&output, "HermesLinux"), Some(2));
    }

    #[test]
    fn version_1_stopped() {
        let output = format!("{}  HermesLinux     Stopped         1\n", HEADER);
        assert_eq!(wsl::parse_distro_wsl_version(&output, "HermesLinux"), Some(1));
    }

    #[test]
    fn distro_not_found() {
        let output = format!("{}  Ubuntu          Running         2\n", HEADER);
        assert_eq!(wsl::parse_distro_wsl_version(&output, "HermesLinux"), None);
    }

    #[test]
    fn multiple_distros() {
        let output = format!(
            "{}* Ubuntu          Running         2\n  HermesLinux     Stopped         1\n",
            HEADER
        );
        assert_eq!(wsl::parse_distro_wsl_version(&output, "HermesLinux"), Some(1));
        assert_eq!(wsl::parse_distro_wsl_version(&output, "Ubuntu"), Some(2));
    }

    #[test]
    fn default_marker_asterisk_stripped() {
        let output = "* HermesLinux    Running    2\n";
        assert_eq!(wsl::parse_distro_wsl_version(output, "HermesLinux"), Some(2));
    }

    #[test]
    fn empty_output() {
        assert_eq!(wsl::parse_distro_wsl_version("", "HermesLinux"), None);
    }

    #[test]
    fn header_only_no_distros() {
        assert_eq!(wsl::parse_distro_wsl_version(HEADER, "HermesLinux"), None);
    }

    #[test]
    fn extra_whitespace() {
        let output = "   *   HermesLinux      Running      2   \n";
        assert_eq!(wsl::parse_distro_wsl_version(output, "HermesLinux"), Some(2));
    }
}

mod url_port {
    #[test]
    fn standard_url() {
        assert_eq!(crate::url_port("http://localhost:8787"), 8787);
    }

    #[test]
    fn trailing_slash() {
        assert_eq!(crate::url_port("http://localhost:8787/"), 8787);
    }

    #[test]
    fn high_port() {
        assert_eq!(crate::url_port("http://127.0.0.1:54321/"), 54321);
    }

    #[test]
    fn no_port_falls_back_to_default() {
        assert_eq!(crate::url_port("http://localhost"), 8787);
    }

    #[test]
    fn port_with_no_trailing() {
        assert_eq!(crate::url_port("http://localhost:9000"), 9000);
    }
}

mod decode_then_parse {
    use super::*;

    #[test]
    fn utf16le_verbose_output_parsed_correctly() {
        let text = "  NAME            STATE           VERSION\r\n\
                     * HermesLinux     Running         2\r\n\
                       Ubuntu          Stopped         1\r\n";
        let raw: Vec<u8> = text
            .encode_utf16()
            .flat_map(|c| c.to_le_bytes())
            .collect();
        let decoded = wsl::decode_wsl_output(&raw);
        assert_eq!(wsl::parse_distro_wsl_version(&decoded, "HermesLinux"), Some(2));
        assert_eq!(wsl::parse_distro_wsl_version(&decoded, "Ubuntu"), Some(1));
    }

    #[test]
    fn utf8_verbose_output_parsed_correctly() {
        let text = "  NAME            STATE           VERSION\n\
                     * HermesLinux     Stopped         1\n";
        let decoded = wsl::decode_wsl_output(text.as_bytes());
        assert_eq!(wsl::parse_distro_wsl_version(&decoded, "HermesLinux"), Some(1));
    }
}

// ===========================================================================
// MockWslOps — for A-tier orchestration tests
// ===========================================================================

struct MockWslOps {
    calls: Mutex<Vec<String>>,
    is_wsl_enabled: Mutex<VecDeque<Result<bool, String>>>,
    is_distro_registered: Mutex<VecDeque<Result<bool, String>>>,
    clean_stale_pids: Mutex<VecDeque<Result<(), String>>>,
    start_services: Mutex<VecDeque<Result<String, String>>>,
    stop_services: Mutex<VecDeque<Result<(), String>>>,
    terminate_distro: Mutex<VecDeque<Result<(), String>>>,
    wait_for_vm: Mutex<VecDeque<Result<(), String>>>,
    wait_for_service_pids: Mutex<VecDeque<Result<(), String>>>,
    wait_for_http_ready: Mutex<VecDeque<Result<(), String>>>,
    get_service_logs: Mutex<VecDeque<Result<String, String>>>,
    get_wsl_ip: Mutex<VecDeque<Result<String, String>>>,
    tcp_check_host: Mutex<VecDeque<bool>>,
    start_port_proxy: Mutex<VecDeque<Result<u16, String>>>,
}

impl MockWslOps {
    fn new() -> Self {
        Self {
            calls: Mutex::new(vec![]),
            is_wsl_enabled: Mutex::new(VecDeque::new()),
            is_distro_registered: Mutex::new(VecDeque::new()),
            clean_stale_pids: Mutex::new(VecDeque::new()),
            start_services: Mutex::new(VecDeque::new()),
            stop_services: Mutex::new(VecDeque::new()),
            terminate_distro: Mutex::new(VecDeque::new()),
            wait_for_vm: Mutex::new(VecDeque::new()),
            wait_for_service_pids: Mutex::new(VecDeque::new()),
            wait_for_http_ready: Mutex::new(VecDeque::new()),
            get_service_logs: Mutex::new(VecDeque::new()),
            get_wsl_ip: Mutex::new(VecDeque::new()),
            tcp_check_host: Mutex::new(VecDeque::new()),
            start_port_proxy: Mutex::new(VecDeque::new()),
        }
    }

    /// Create a mock pre-configured for the happy path (all steps succeed, localhost reachable).
    fn happy_path() -> Self {
        let m = Self::new();
        m.tcp_check_host.lock().unwrap().push_back(true); // localhost check
        m.tcp_check_host.lock().unwrap().push_back(true); // final verify
        m
    }

    fn calls(&self) -> Vec<String> {
        self.calls.lock().unwrap().clone()
    }

    fn record(&self, name: &str) {
        self.calls.lock().unwrap().push(name.to_string());
    }
}

impl WslOps for MockWslOps {
    async fn is_wsl_enabled(&self) -> Result<bool, String> {
        self.record("is_wsl_enabled");
        self.is_wsl_enabled
            .lock()
            .unwrap()
            .pop_front()
            .unwrap_or(Ok(true))
    }

    async fn is_distro_registered(&self) -> Result<bool, String> {
        self.record("is_distro_registered");
        self.is_distro_registered
            .lock()
            .unwrap()
            .pop_front()
            .unwrap_or(Ok(true))
    }

    async fn ensure_wsl2(&self) -> Result<(), String> {
        self.record("ensure_wsl2");
        Ok(())
    }

    async fn clean_stale_pids(&self) -> Result<(), String> {
        self.record("clean_stale_pids");
        self.clean_stale_pids
            .lock()
            .unwrap()
            .pop_front()
            .unwrap_or(Ok(()))
    }

    async fn start_services(&self) -> Result<String, String> {
        self.record("start_services");
        self.start_services
            .lock()
            .unwrap()
            .pop_front()
            .unwrap_or(Ok("services started".into()))
    }

    async fn stop_services(&self) -> Result<(), String> {
        self.record("stop_services");
        self.stop_services
            .lock()
            .unwrap()
            .pop_front()
            .unwrap_or(Ok(()))
    }

    async fn terminate_distro(&self) -> Result<(), String> {
        self.record("terminate_distro");
        self.terminate_distro
            .lock()
            .unwrap()
            .pop_front()
            .unwrap_or(Ok(()))
    }

    async fn wait_for_vm(&self, _timeout_secs: u64) -> Result<(), String> {
        self.record("wait_for_vm");
        self.wait_for_vm
            .lock()
            .unwrap()
            .pop_front()
            .unwrap_or(Ok(()))
    }

    async fn wait_for_service_pids(&self, _timeout_secs: u64) -> Result<(), String> {
        self.record("wait_for_service_pids");
        self.wait_for_service_pids
            .lock()
            .unwrap()
            .pop_front()
            .unwrap_or(Ok(()))
    }

    async fn wait_for_http_ready(&self, _timeout_secs: u64) -> Result<(), String> {
        self.record("wait_for_http_ready");
        self.wait_for_http_ready
            .lock()
            .unwrap()
            .pop_front()
            .unwrap_or(Ok(()))
    }

    async fn get_service_logs(&self, _lines: u32) -> Result<String, String> {
        self.record("get_service_logs");
        self.get_service_logs
            .lock()
            .unwrap()
            .pop_front()
            .unwrap_or(Ok("mock logs".into()))
    }

    async fn health_check(&self) -> Result<String, String> {
        self.record("health_check");
        Ok("healthy".into())
    }

    async fn get_wsl_ip(&self) -> Result<String, String> {
        self.record("get_wsl_ip");
        self.get_wsl_ip
            .lock()
            .unwrap()
            .pop_front()
            .unwrap_or(Ok("172.20.0.2".into()))
    }

    async fn tcp_check_host(&self, _host: &str, _port: u16) -> bool {
        self.record("tcp_check_host");
        self.tcp_check_host
            .lock()
            .unwrap()
            .pop_front()
            .unwrap_or(true)
    }

    async fn start_port_proxy(&self, _target_ip: String, _target_port: u16) -> Result<u16, String> {
        self.record("start_port_proxy");
        self.start_port_proxy
            .lock()
            .unwrap()
            .pop_front()
            .unwrap_or(Ok(54321))
    }
}

/// Collect progress callback calls into a Vec.
fn progress_collector() -> (
    impl Fn(&str, &str) + Send + Sync,
    std::sync::Arc<Mutex<Vec<String>>>,
) {
    let log = std::sync::Arc::new(Mutex::new(vec![]));
    let log_clone = log.clone();
    let f = move |stage: &str, _msg: &str| {
        log_clone.lock().unwrap().push(stage.to_string());
    };
    (f, log)
}

// ===========================================================================
// A — Orchestration tests (MockWslOps, testing main.rs logic)
// ===========================================================================

mod orchestration {
    use super::*;

    // A1: Happy path — localhost direct
    #[tokio::test]
    async fn a1_happy_path_localhost_direct() {
        let mock = MockWslOps::happy_path();
        let (progress, _log) = progress_collector();
        let url_cache = Mutex::new(None);

        let result =
            crate::start_hermes_with_retry(&mock, &progress, &url_cache).await;

        assert_eq!(result.unwrap(), "http://localhost:8787");
        assert_eq!(
            url_cache.lock().unwrap().as_deref(),
            Some("http://localhost:8787")
        );
    }

    // A2: Happy path — localhost unreachable, proxy fallback
    #[tokio::test]
    async fn a2_proxy_fallback() {
        let mock = MockWslOps::new();
        mock.tcp_check_host.lock().unwrap().push_back(false); // localhost fails
        mock.tcp_check_host.lock().unwrap().push_back(true); // proxy port verify succeeds
        mock.start_port_proxy.lock().unwrap().push_back(Ok(54321));
        mock.get_wsl_ip
            .lock()
            .unwrap()
            .push_back(Ok("172.20.0.2".into()));

        let (progress, _log) = progress_collector();
        let url_cache = Mutex::new(None);

        let result =
            crate::start_hermes_with_retry(&mock, &progress, &url_cache).await;

        assert_eq!(result.unwrap(), "http://localhost:54321");
        assert!(mock.calls().contains(&"start_port_proxy".to_string()));
        assert!(mock.calls().contains(&"get_wsl_ip".to_string()));
    }

    // A3: Idempotent — cached URL returned without calling WSL
    #[tokio::test]
    async fn a3_idempotent_cached_url() {
        let mock = MockWslOps::new();
        let (progress, _log) = progress_collector();
        let url_cache = Mutex::new(Some("http://localhost:8787".into()));

        let result =
            crate::start_hermes_with_retry(&mock, &progress, &url_cache).await;

        assert_eq!(result.unwrap(), "http://localhost:8787");
        assert!(mock.calls().is_empty(), "No WSL calls should have been made");
    }

    // A4: First attempt fails → retry succeeds
    #[tokio::test]
    async fn a4_first_fails_retry_succeeds() {
        tokio::time::pause();

        let mock = MockWslOps::new();
        // First attempt: start_services fails
        mock.start_services
            .lock()
            .unwrap()
            .push_back(Err("script crashed".into()));
        // Second attempt: everything succeeds
        mock.start_services
            .lock()
            .unwrap()
            .push_back(Ok("ok".into()));
        mock.tcp_check_host.lock().unwrap().push_back(true);
        mock.tcp_check_host.lock().unwrap().push_back(true);

        let (progress, stages) = progress_collector();
        let url_cache = Mutex::new(None);

        let result =
            crate::start_hermes_with_retry(&mock, &progress, &url_cache).await;

        assert!(result.is_ok());
        let calls = mock.calls();
        assert!(calls.contains(&"stop_services".to_string()));
        assert!(calls.contains(&"terminate_distro".to_string()));
        assert!(stages.lock().unwrap().contains(&"retrying".to_string()));
    }

    // A5: Both attempts fail → combined error
    #[tokio::test]
    async fn a5_both_attempts_fail() {
        tokio::time::pause();

        let mock = MockWslOps::new();
        mock.start_services
            .lock()
            .unwrap()
            .push_back(Err("error_one".into()));
        mock.start_services
            .lock()
            .unwrap()
            .push_back(Err("error_two".into()));

        let (progress, _log) = progress_collector();
        let url_cache = Mutex::new(None);

        let result =
            crate::start_hermes_with_retry(&mock, &progress, &url_cache).await;

        let err = result.unwrap_err();
        assert!(err.contains("首次"), "Should contain first error label");
        assert!(err.contains("error_one"), "Should contain first error");
        assert!(err.contains("重试"), "Should contain retry label");
        assert!(err.contains("error_two"), "Should contain retry error");
    }

    // A6: wait_for_vm fails → VM-specific error
    #[tokio::test]
    async fn a6_vm_timeout_error() {
        let mock = MockWslOps::new();
        mock.wait_for_vm
            .lock()
            .unwrap()
            .push_back(Err("WSL 虚拟机在 30 秒内未响应".into()));

        let (progress, _log) = progress_collector();

        let result = crate::start_hermes_attempt(&mock, &progress).await;

        let err = result.unwrap_err();
        assert!(err.contains("虚拟机"), "Error should mention VM");
        assert!(!err.contains("HTTP"), "Error should NOT mention HTTP");
    }

    // A7: wait_for_service_pids fails → PID-specific error with logs
    #[tokio::test]
    async fn a7_pid_timeout_with_logs() {
        let mock = MockWslOps::new();
        mock.wait_for_service_pids
            .lock()
            .unwrap()
            .push_back(Err("PID 文件未找到\n\n最近日志:\nfatal: module not found".into()));

        let (progress, _log) = progress_collector();

        let result = crate::start_hermes_attempt(&mock, &progress).await;

        let err = result.unwrap_err();
        assert!(err.contains("PID"), "Error should mention PID");
        assert!(
            err.contains("module not found"),
            "Error should include diagnostic logs"
        );
    }

    // A8: wait_for_http_ready fails → HTTP-specific error with logs
    #[tokio::test]
    async fn a8_http_timeout_with_logs() {
        let mock = MockWslOps::new();
        mock.wait_for_http_ready
            .lock()
            .unwrap()
            .push_back(Err("HTTP 端口在 90 秒内未就绪\n\n最近日志:\nbind error".into()));

        let (progress, _log) = progress_collector();

        let result = crate::start_hermes_attempt(&mock, &progress).await;

        let err = result.unwrap_err();
        assert!(err.contains("HTTP"), "Error should mention HTTP");
        assert!(
            err.contains("bind error"),
            "Error should include diagnostic logs"
        );
    }

    // A9: stop clears URL cache
    #[tokio::test]
    async fn a9_stop_clears_cache() {
        let mock = MockWslOps::new();
        let url_cache = Mutex::new(Some("http://localhost:8787".into()));

        crate::stop_hermes_impl(&mock, &url_cache).await.unwrap();

        assert!(url_cache.lock().unwrap().is_none());
        assert!(mock.calls().contains(&"stop_services".to_string()));
    }

    // A10: reset clears cache + calls stop/terminate/clean in order
    #[tokio::test]
    async fn a10_reset_call_sequence() {
        let mock = MockWslOps::new();
        let url_cache = Mutex::new(Some("http://localhost:8787".into()));

        crate::reset_hermes_impl(&mock, &url_cache).await.unwrap();

        assert!(url_cache.lock().unwrap().is_none());
        let calls = mock.calls();
        let stop_idx = calls.iter().position(|c| c == "stop_services").unwrap();
        let term_idx = calls.iter().position(|c| c == "terminate_distro").unwrap();
        let clean_idx = calls
            .iter()
            .position(|c| c == "clean_stale_pids")
            .unwrap();
        assert!(stop_idx < term_idx, "stop before terminate");
        assert!(term_idx < clean_idx, "terminate before clean");
    }

    // A11: progress callback sequence
    #[tokio::test]
    async fn a11_progress_callback_sequence() {
        let mock = MockWslOps::happy_path();
        let (progress, stages) = progress_collector();

        let _ = crate::start_hermes_attempt(&mock, &progress).await;

        let stages = stages.lock().unwrap().clone();
        assert_eq!(
            stages,
            vec![
                "cleaning",
                "starting_services",
                "waiting_vm",
                "waiting_pids",
                "waiting_http",
                "connecting"
            ]
        );
    }

    // A12: TCP final verification fails → error not cached
    #[tokio::test]
    async fn a12_tcp_verify_fails() {
        let mock = MockWslOps::new();
        mock.tcp_check_host.lock().unwrap().push_back(true); // localhost check passes
        mock.tcp_check_host.lock().unwrap().push_back(false); // final verify fails

        let (progress, _log) = progress_collector();

        let result = crate::start_hermes_attempt(&mock, &progress).await;

        let err = result.unwrap_err();
        assert!(err.contains("无法通过"), "Should report unreachable");
        assert!(err.contains("localhost"), "Should include the URL");
    }

    // A13: check_wsl_ready — WSL enabled + distro registered → ready
    #[tokio::test]
    async fn a13_check_ready_all_good() {
        let mock = MockWslOps::new();
        mock.is_wsl_enabled.lock().unwrap().push_back(Ok(true));
        mock.is_distro_registered.lock().unwrap().push_back(Ok(true));

        let status = crate::check_wsl_ready_impl(&mock).await.unwrap();

        assert!(status.ready);
        assert!(status.wsl_installed);
        assert!(status.distro_registered);
    }

    // A14: check_wsl_ready — WSL not enabled → short-circuit
    #[tokio::test]
    async fn a14_check_ready_wsl_not_enabled() {
        let mock = MockWslOps::new();
        mock.is_wsl_enabled.lock().unwrap().push_back(Ok(false));

        let status = crate::check_wsl_ready_impl(&mock).await.unwrap();

        assert!(!status.ready);
        assert!(!status.wsl_installed);
        assert!(!status.distro_registered);
        assert!(
            !mock.calls().contains(&"is_distro_registered".to_string()),
            "Should not check distro when WSL is not enabled"
        );
    }

    // A15: check_wsl_ready — WSL enabled, distro not registered
    #[tokio::test]
    async fn a15_check_ready_distro_not_registered() {
        let mock = MockWslOps::new();
        mock.is_wsl_enabled.lock().unwrap().push_back(Ok(true));
        mock.is_distro_registered
            .lock()
            .unwrap()
            .push_back(Ok(false));

        let status = crate::check_wsl_ready_impl(&mock).await.unwrap();

        assert!(!status.ready);
        assert!(status.wsl_installed);
        assert!(!status.distro_registered);
    }

    // A16: check_wsl_ready — is_wsl_enabled errors → propagated
    #[tokio::test]
    async fn a16_check_ready_wsl_check_error() {
        let mock = MockWslOps::new();
        mock.is_wsl_enabled
            .lock()
            .unwrap()
            .push_back(Err("wsl --status failed".into()));

        let result = crate::check_wsl_ready_impl(&mock).await;

        assert!(result.unwrap_err().contains("wsl --status failed"));
    }
}

// ===========================================================================
// MockRunner — for B-tier wsl.rs internal logic tests
// ===========================================================================

struct MockRunner {
    exec_responses: Mutex<VecDeque<Result<CmdOutput, String>>>,
    exec_calls: Mutex<Vec<Vec<String>>>,
    session_spawned: Mutex<bool>,
    session_killed: Mutex<bool>,
}

impl MockRunner {
    fn new() -> Self {
        Self {
            exec_responses: Mutex::new(VecDeque::new()),
            exec_calls: Mutex::new(vec![]),
            session_spawned: Mutex::new(false),
            session_killed: Mutex::new(false),
        }
    }

    fn push_exec(&self, result: Result<CmdOutput, String>) {
        self.exec_responses.lock().unwrap().push_back(result);
    }

    fn exec_args(&self) -> Vec<Vec<String>> {
        self.exec_calls.lock().unwrap().clone()
    }

    fn was_session_spawned(&self) -> bool {
        *self.session_spawned.lock().unwrap()
    }

    fn was_session_killed(&self) -> bool {
        *self.session_killed.lock().unwrap()
    }
}

fn cmd_ok(stdout: &str) -> CmdOutput {
    CmdOutput {
        stdout: stdout.as_bytes().to_vec(),
        stderr: vec![],
        success: true,
        code: Some(0),
    }
}

fn cmd_fail(code: i32, stdout: &str, stderr: &str) -> CmdOutput {
    CmdOutput {
        stdout: stdout.as_bytes().to_vec(),
        stderr: stderr.as_bytes().to_vec(),
        success: false,
        code: Some(code),
    }
}

impl CommandRunner for MockRunner {
    async fn exec(&self, args: &[&str]) -> Result<CmdOutput, String> {
        self.exec_calls
            .lock()
            .unwrap()
            .push(args.iter().map(|s| s.to_string()).collect());
        self.exec_responses
            .lock()
            .unwrap()
            .pop_front()
            .unwrap_or(Ok(cmd_ok("")))
    }

    async fn spawn_session(&self, _args: &[&str]) -> Result<(), String> {
        *self.session_spawned.lock().unwrap() = true;
        Ok(())
    }

    async fn kill_session(&self) -> Result<(), String> {
        *self.session_killed.lock().unwrap() = true;
        Ok(())
    }
}

// ===========================================================================
// B — WSL internal logic tests (MockRunner, testing wsl.rs)
// ===========================================================================

mod wsl_internal {
    use super::*;

    // B1: ensure_wsl2 — already version 2
    #[tokio::test]
    async fn b1_already_wsl2() {
        let runner = MockRunner::new();
        let verbose = "  NAME  STATE  VERSION\n* HermesLinux  Running  2\n";
        runner.push_exec(Ok(cmd_ok(verbose)));

        let result = wsl::ensure_wsl2_with(&runner).await;

        assert!(result.is_ok());
        // Only one exec call (--list --verbose), no --set-version
        assert_eq!(runner.exec_args().len(), 1);
        assert!(runner.exec_args()[0].contains(&"--verbose".to_string()));
    }

    // B2: ensure_wsl2 — version 1, conversion succeeds
    #[tokio::test]
    async fn b2_wsl1_convert_succeeds() {
        let runner = MockRunner::new();
        let verbose = "  NAME  STATE  VERSION\n  HermesLinux  Stopped  1\n";
        runner.push_exec(Ok(cmd_ok(verbose))); // --list --verbose
        runner.push_exec(Ok(cmd_ok(""))); // --set-version succeeds

        let result = wsl::ensure_wsl2_with(&runner).await;

        assert!(result.is_ok());
        assert_eq!(runner.exec_args().len(), 2);
        let convert_args = &runner.exec_args()[1];
        assert!(convert_args.contains(&"--set-version".to_string()));
        assert!(convert_args.contains(&"HermesLinux".to_string()));
        assert!(convert_args.contains(&"2".to_string()));
    }

    // B3: ensure_wsl2 — version 1, conversion fails
    #[tokio::test]
    async fn b3_wsl1_convert_fails() {
        let runner = MockRunner::new();
        let verbose = "  NAME  STATE  VERSION\n  HermesLinux  Stopped  1\n";
        runner.push_exec(Ok(cmd_ok(verbose)));
        runner.push_exec(Ok(cmd_fail(1, "", "VMP not enabled")));

        let result = wsl::ensure_wsl2_with(&runner).await;

        let err = result.unwrap_err();
        assert!(err.contains("VMP not enabled"), "Error should include stderr");
        assert!(
            err.contains("VirtualMachinePlatform"),
            "Error should include fix hint"
        );
    }

    // B4: ensure_wsl2 — distro not in listing
    #[tokio::test]
    async fn b4_distro_not_found() {
        let runner = MockRunner::new();
        let verbose = "  NAME  STATE  VERSION\n  Ubuntu  Running  2\n";
        runner.push_exec(Ok(cmd_ok(verbose)));

        let result = wsl::ensure_wsl2_with(&runner).await;

        let err = result.unwrap_err();
        assert!(err.contains("未注册") || err.contains("无法确定"));
    }

    // B5: start_services — script succeeds (poll exit code, then read output)
    #[tokio::test]
    async fn b5_start_services_succeeds() {
        tokio::time::pause();
        let runner = MockRunner::new();
        runner.push_exec(Ok(cmd_ok("0"))); // poll: exit code
        runner.push_exec(Ok(cmd_ok("Starting agent...\nDone."))); // read output

        let result = wsl::start_services_with(&runner).await;

        assert!(result.is_ok());
        let output = result.unwrap();
        assert!(output.contains("Starting agent"));
        assert!(runner.was_session_spawned());
        assert!(!runner.was_session_killed());
    }

    // B6: start_services — script fails with exit code and captured output
    #[tokio::test]
    async fn b6_start_services_fails_with_output() {
        tokio::time::pause();
        let runner = MockRunner::new();
        runner.push_exec(Ok(cmd_ok("127"))); // poll: exit code 127
        runner.push_exec(Ok(cmd_ok("bash: hermes-agent: not found\nerror loading module"))); // output

        let result = wsl::start_services_with(&runner).await;

        let err = result.unwrap_err();
        assert!(err.contains("127"), "Error should include exit code");
        assert!(
            err.contains("hermes-agent: not found"),
            "Error should include script output"
        );
    }

    // B7: start_services — script fails, keep-alive session is killed
    #[tokio::test]
    async fn b7_start_services_fail_kills_keepalive() {
        tokio::time::pause();
        let runner = MockRunner::new();
        runner.push_exec(Ok(cmd_ok("1"))); // exit code 1
        runner.push_exec(Ok(cmd_ok("crash"))); // output

        let _ = wsl::start_services_with(&runner).await;

        assert!(runner.was_session_spawned(), "Session should have been started");
        assert!(
            runner.was_session_killed(),
            "Session should have been killed on failure"
        );
    }
}
