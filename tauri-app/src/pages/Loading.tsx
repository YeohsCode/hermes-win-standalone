interface LoadingProps {
  state: "checking" | "starting";
}

function Loading({ state }: LoadingProps) {
  const message =
    state === "checking"
      ? "正在检测系统环境..."
      : "正在启动 Hermes 服务...";

  return (
    <div style={styles.container}>
      <div style={styles.content}>
        <div style={styles.spinner} />
        <h1 style={styles.title}>Hermes</h1>
        <p style={styles.message}>{message}</p>
      </div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    width: "100%",
    height: "100%",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    background: "linear-gradient(135deg, #1a1a2e 0%, #16213e 100%)",
    color: "#e0e0e0",
    fontFamily: "system-ui, -apple-system, sans-serif",
  },
  content: {
    textAlign: "center",
  },
  spinner: {
    width: "48px",
    height: "48px",
    margin: "0 auto 1.5rem",
    border: "3px solid rgba(255,255,255,0.1)",
    borderTopColor: "#4a90d9",
    borderRadius: "50%",
    animation: "spin 1s linear infinite",
  },
  title: {
    fontSize: "2rem",
    fontWeight: 600,
    marginBottom: "0.5rem",
    background: "linear-gradient(90deg, #4a90d9, #a855f7)",
    WebkitBackgroundClip: "text",
    WebkitTextFillColor: "transparent",
  },
  message: {
    fontSize: "0.95rem",
    color: "#888",
  },
};

export default Loading;
