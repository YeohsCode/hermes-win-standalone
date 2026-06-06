import { useState, useEffect, useCallback, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import Loading from "./pages/Loading";
import Setup from "./pages/Setup";

type AppState = "checking" | "setup_required" | "starting" | "ready" | "error";
type SetupReason = "wsl_missing" | "distro_missing";

interface WslStatus {
  ready: boolean;
  wsl_installed: boolean;
  distro_registered: boolean;
}

interface ProgressPayload {
  stage: string;
  message: string;
}

const STAGE_MESSAGES: Record<string, string> = {
  checking: "正在检测系统环境...",
  ensuring_wsl2: "确认 WSL2 环境...",
  cleaning: "清理旧进程...",
  starting_services: "启动服务...",
  waiting_vm: "等待 WSL 虚拟机...",
  waiting_pids: "等待服务进程启动...",
  waiting_http: "等待服务就绪...",
  connecting: "建立连接...",
  retrying: "首次启动失败，正在重试...",
};

function App() {
  const [state, setState] = useState<AppState>("checking");
  const [errorMsg, setErrorMsg] = useState("");
  const [setupReason, setSetupReason] = useState<SetupReason>("wsl_missing");
  const [progressMsg, setProgressMsg] = useState("正在检测系统环境...");
  const [logs, setLogs] = useState<string | null>(null);
  const startingRef = useRef(false);

  // Listen for progress events from the Rust backend
  useEffect(() => {
    const unlisten = listen<ProgressPayload>("hermes-progress", (event) => {
      const display =
        STAGE_MESSAGES[event.payload.stage] || event.payload.message;
      setProgressMsg(display);
    });
    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  const checkAndStart = useCallback(async () => {
    if (startingRef.current) return;
    startingRef.current = true;
    setLogs(null);

    try {
      // Step 1: Check WSL environment
      setProgressMsg("正在检测系统环境...");
      setState("checking");
      const status = await invoke<WslStatus>("check_wsl_ready");
      if (!status.ready) {
        setSetupReason(status.wsl_installed ? "distro_missing" : "wsl_missing");
        setState("setup_required");
        startingRef.current = false;
        return;
      }

      // Step 2: Ensure WSL2 version
      setProgressMsg("确认 WSL2 环境...");
      setState("starting");
      await invoke("ensure_wsl2");

      // Step 3: Start Hermes (backend emits progress events for sub-steps)
      setProgressMsg("启动服务...");
      const url = await invoke<string>("start_hermes");
      window.location.href = url;
    } catch (e) {
      setErrorMsg(String(e));
      setState("error");
      startingRef.current = false;
    }
  }, []);

  useEffect(() => {
    checkAndStart();
  }, [checkAndStart]);

  const handleViewLogs = async () => {
    try {
      const logContent = await invoke<string>("get_hermes_logs");
      setLogs(logContent || "（无日志内容）");
    } catch (e) {
      setLogs(`获取日志失败: ${e}`);
    }
  };

  const handleResetAndRetry = async () => {
    setErrorMsg("");
    setLogs(null);
    setProgressMsg("正在重置...");
    setState("starting");
    try {
      await invoke("reset_hermes");
    } catch {
      // reset is best-effort
    }
    startingRef.current = false;
    checkAndStart();
  };

  if (state === "checking" || state === "starting") {
    return <Loading message={progressMsg} />;
  }

  if (state === "setup_required") {
    return <Setup reason={setupReason} onRetry={checkAndStart} />;
  }

  if (state === "error") {
    return (
      <div style={styles.container}>
        <div style={styles.errorBox}>
          <h2 style={styles.errorTitle}>启动失败</h2>
          <p style={styles.errorMsg}>{errorMsg}</p>

          <div style={styles.buttonRow}>
            <button style={styles.logBtn} onClick={handleViewLogs}>
              查看日志
            </button>
            <button style={styles.resetBtn} onClick={handleResetAndRetry}>
              重置并重试
            </button>
            <button style={styles.retryBtn} onClick={() => { startingRef.current = false; checkAndStart(); }}>
              直接重试
            </button>
          </div>

          {logs !== null && (
            <div style={styles.logBox}>
              <h3 style={styles.logTitle}>服务日志</h3>
              <pre style={styles.logContent}>{logs}</pre>
            </div>
          )}
        </div>
      </div>
    );
  }

  return <Loading message="正在启动 Hermes 服务..." />;
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    width: "100%",
    height: "100%",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    background: "#1a1a2e",
    color: "#e0e0e0",
    fontFamily: "system-ui, -apple-system, sans-serif",
    overflow: "auto",
    padding: "2rem",
  },
  errorBox: {
    textAlign: "center",
    padding: "2rem",
    maxWidth: "600px",
    width: "100%",
  },
  errorTitle: {
    fontSize: "1.5rem",
    marginBottom: "1rem",
    color: "#ff6b6b",
  },
  errorMsg: {
    fontSize: "0.85rem",
    color: "#aaa",
    marginBottom: "1.5rem",
    maxWidth: "500px",
    wordBreak: "break-word",
    whiteSpace: "pre-wrap",
    textAlign: "left",
    margin: "0 auto 1.5rem",
    lineHeight: 1.6,
  },
  buttonRow: {
    display: "flex",
    gap: "0.75rem",
    justifyContent: "center",
    flexWrap: "wrap" as const,
    marginBottom: "1.5rem",
  },
  logBtn: {
    padding: "0.6rem 1.2rem",
    background: "rgba(255,255,255,0.1)",
    color: "#ccc",
    border: "1px solid rgba(255,255,255,0.2)",
    borderRadius: "6px",
    cursor: "pointer",
    fontSize: "0.9rem",
  },
  resetBtn: {
    padding: "0.6rem 1.2rem",
    background: "#d97706",
    color: "#fff",
    border: "none",
    borderRadius: "6px",
    cursor: "pointer",
    fontSize: "0.9rem",
  },
  retryBtn: {
    padding: "0.6rem 1.2rem",
    background: "#4a90d9",
    color: "#fff",
    border: "none",
    borderRadius: "6px",
    cursor: "pointer",
    fontSize: "0.9rem",
  },
  logBox: {
    textAlign: "left",
    background: "rgba(0,0,0,0.3)",
    borderRadius: "8px",
    padding: "1rem",
    marginTop: "1rem",
    maxHeight: "300px",
    overflow: "auto",
  },
  logTitle: {
    fontSize: "0.9rem",
    color: "#888",
    marginBottom: "0.5rem",
  },
  logContent: {
    fontSize: "0.75rem",
    color: "#aaa",
    fontFamily: "Consolas, 'Courier New', monospace",
    whiteSpace: "pre-wrap",
    wordBreak: "break-all",
    margin: 0,
    lineHeight: 1.5,
  },
};

export default App;
