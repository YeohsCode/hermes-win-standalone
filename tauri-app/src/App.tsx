import { useState, useEffect, useCallback, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import Loading from "./pages/Loading";
import Setup from "./pages/Setup";

type AppState = "checking" | "setup_required" | "starting" | "ready" | "error";
type SetupReason = "wsl_missing" | "distro_missing";

interface WslStatus {
  ready: boolean;
  wsl_installed: boolean;
  distro_registered: boolean;
}

function App() {
  const [state, setState] = useState<AppState>("checking");
  const [errorMsg, setErrorMsg] = useState("");
  const [setupReason, setSetupReason] = useState<SetupReason>("wsl_missing");
  const startingRef = useRef(false);

  const checkAndStart = useCallback(async () => {
    if (startingRef.current) return;
    startingRef.current = true;
    try {
      setState("checking");
      const status = await invoke<WslStatus>("check_wsl_ready");
      if (!status.ready) {
        setSetupReason(status.wsl_installed ? "distro_missing" : "wsl_missing");
        setState("setup_required");
        startingRef.current = false;
        return;
      }

      setState("starting");
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

  if (state === "checking" || state === "starting") {
    return <Loading state={state} />;
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
          <button style={styles.retryBtn} onClick={checkAndStart}>
            重试
          </button>
        </div>
      </div>
    );
  }

  return <Loading state="starting" />;
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
  },
  errorBox: {
    textAlign: "center",
    padding: "2rem",
  },
  errorTitle: {
    fontSize: "1.5rem",
    marginBottom: "1rem",
    color: "#ff6b6b",
  },
  errorMsg: {
    fontSize: "0.9rem",
    color: "#aaa",
    marginBottom: "1.5rem",
    maxWidth: "400px",
    wordBreak: "break-word",
  },
  retryBtn: {
    padding: "0.6rem 1.5rem",
    background: "#4a90d9",
    color: "#fff",
    border: "none",
    borderRadius: "6px",
    cursor: "pointer",
    fontSize: "1rem",
  },
};

export default App;
