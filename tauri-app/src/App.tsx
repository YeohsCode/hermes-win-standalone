import { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import Loading from "./pages/Loading";
import Setup from "./pages/Setup";

type AppState = "checking" | "setup_required" | "starting" | "ready" | "error";

function App() {
  const [state, setState] = useState<AppState>("checking");
  const [errorMsg, setErrorMsg] = useState("");
  const [hermesUrl, setHermesUrl] = useState("");

  const checkAndStart = useCallback(async () => {
    try {
      setState("checking");
      const wslReady = await invoke<boolean>("check_wsl_ready");
      if (!wslReady) {
        setState("setup_required");
        return;
      }

      setState("starting");
      const url = await invoke<string>("start_hermes");
      setHermesUrl(url);
      setState("ready");
    } catch (e) {
      setErrorMsg(String(e));
      setState("error");
    }
  }, []);

  useEffect(() => {
    checkAndStart();
  }, [checkAndStart]);

  if (state === "checking" || state === "starting") {
    return <Loading state={state} />;
  }

  if (state === "setup_required") {
    return <Setup onRetry={checkAndStart} />;
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

  return (
    <iframe
      src={hermesUrl}
      style={styles.iframe}
      title="Hermes WebUI"
    />
  );
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
  iframe: {
    width: "100%",
    height: "100%",
    border: "none",
  },
};

export default App;
