type SetupReason = "wsl_missing" | "distro_missing";

interface SetupProps {
  reason: SetupReason;
  onRetry: () => void;
}

function Setup({ reason, onRetry }: SetupProps) {
  return (
    <div style={styles.container}>
      <div style={styles.card}>
        {reason === "wsl_missing" ? (
          <>
            <h1 style={styles.title}>需要启用 WSL2</h1>
            <p style={styles.description}>
              Hermes 需要 Windows Subsystem for Linux 2 (WSL2) 来运行。
              请按照以下步骤启用：
            </p>
            <ol style={styles.steps}>
              <li style={styles.step}>
                以管理员身份打开 PowerShell
              </li>
              <li style={styles.step}>
                运行命令：
                <code style={styles.code}>wsl --install</code>
              </li>
              <li style={styles.step}>
                重启计算机
              </li>
              <li style={styles.step}>
                重新打开 Hermes
              </li>
            </ol>
          </>
        ) : (
          <>
            <h1 style={styles.title}>HermesLinux 未安装</h1>
            <p style={styles.description}>
              WSL2 已启用，但 HermesLinux 发行版未找到。
              请重新运行 Hermes 安装程序以导入系统环境。
            </p>
            <ol style={styles.steps}>
              <li style={styles.step}>
                重新运行 HermesSetup 安装程序
              </li>
              <li style={styles.step}>
                确保安装过程中无错误提示
              </li>
              <li style={styles.step}>
                安装完成后重新打开 Hermes
              </li>
            </ol>
          </>
        )}
        <button style={styles.retryBtn} onClick={onRetry}>
          我已完成，重新检测
        </button>
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
    padding: "2rem",
  },
  card: {
    background: "rgba(255,255,255,0.05)",
    borderRadius: "12px",
    padding: "2.5rem",
    maxWidth: "500px",
    width: "100%",
    border: "1px solid rgba(255,255,255,0.1)",
  },
  title: {
    fontSize: "1.5rem",
    fontWeight: 600,
    marginBottom: "1rem",
    color: "#f0c040",
  },
  description: {
    fontSize: "0.95rem",
    color: "#aaa",
    lineHeight: 1.6,
    marginBottom: "1.5rem",
  },
  steps: {
    paddingLeft: "1.5rem",
    marginBottom: "2rem",
  },
  step: {
    marginBottom: "0.8rem",
    lineHeight: 1.5,
    fontSize: "0.9rem",
  },
  code: {
    display: "block",
    marginTop: "0.4rem",
    padding: "0.5rem 0.8rem",
    background: "rgba(0,0,0,0.3)",
    borderRadius: "4px",
    fontFamily: "Consolas, monospace",
    fontSize: "0.85rem",
    color: "#4a90d9",
  },
  retryBtn: {
    width: "100%",
    padding: "0.75rem",
    background: "#4a90d9",
    color: "#fff",
    border: "none",
    borderRadius: "8px",
    cursor: "pointer",
    fontSize: "1rem",
    fontWeight: 500,
  },
};

export default Setup;
