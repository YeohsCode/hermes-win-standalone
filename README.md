# Hermes Windows Standalone

一键安装的 Windows 版 Hermes AI Agent 桌面应用。

## 特性

- **Standalone 安装** — 安装包包含所有依赖，无需联网下载
- **Tauri 桌面应用** — 原生 Windows 窗口 + 系统托盘常驻
- **隔离 WSL2 环境** — 自定义 HermesLinux distro，不污染用户现有环境
- **分层组件** — 核心聊天 / 浏览器自动化 / 语音 / 消息网关，按需安装
- **动态端口** — 自动选择可用端口，避免冲突
- **干净卸载** — `wsl --unregister` 一键彻底删除

## 系统要求

- Windows 11 (或 Windows 10 2004+)
- WSL2 已启用（安装程序可引导启用）
- 4GB+ 可用磁盘空间（核心），8GB+（全功能）

## 架构

```
┌─────────────────────────────────────────┐
│  Tauri Desktop App (Windows 原生)       │
│  ┌───────────────────────────────────┐  │
│  │  WebView2 → localhost:{port}      │  │
│  └───────────────────────────────────┘  │
│  系统托盘 | 端口管理 | WSL 生命周期     │
└──────────────────┬──────────────────────┘
                   │ wsl -d HermesLinux
┌──────────────────▼──────────────────────┐
│  WSL2: HermesLinux (自定义 distro)      │
│  ┌─────────────┐  ┌─────────────────┐  │
│  │ hermes-agent│←─│ hermes-webui    │  │
│  │ (AI Agent)  │  │ (Web UI :port)  │  │
│  └─────────────┘  └─────────────────┘  │
│  Python 3.12 | Node.js 22 | 系统工具   │
└─────────────────────────────────────────┘
```

## 安装组件

| 组件 | 内容 | 大小 |
|------|------|------|
| **Core** (必选) | hermes-agent + hermes-webui + Python + git + ripgrep | ~300MB |
| **Browser** | Node.js 22 + Playwright + Chromium | ~300MB |
| **Voice** | faster-whisper + ffmpeg + TTS 引擎 | ~500MB |
| **Messaging** | Telegram/Discord/Slack/钉钉/飞书 + 云 SDK | ~50MB |

## 项目结构

```
code/
├── tauri-app/          # Tauri 桌面应用 (Rust + React/TypeScript)
│   ├── src-tauri/      #   Rust 后端: WSL 管理、端口、托盘
│   └── src/            #   React 前端: Loading、Setup 引导
├── wsl-distro/         # WSL2 rootfs 构建
│   ├── Dockerfile.*    #   分层 Dockerfile (core/browser/voice/messaging)
│   ├── scripts/        #   WSL 内服务管理脚本
│   └── build-rootfs.sh #   构建入口
├── installer/          # Inno Setup 安装程序
│   ├── hermes-win.iss  #   安装脚本定义
│   └── scripts/        #   PowerShell 辅助脚本
├── scripts/            # 开发工具脚本
├── tests/              # 测试脚本
├── docs/               # 文档和工作日志
└── .github/workflows/  # CI/CD
```

## 开发

### 前置条件

- Node.js 22+
- Rust (stable)
- Docker (用于构建 rootfs)

### 本地开发

```bash
# 前端类型检查
cd tauri-app && npm install && npx tsc --noEmit

# Rust 编译检查
cd tauri-app/src-tauri && cargo check

# 构建 WSL rootfs (需要 Docker)
cd wsl-distro
export AGENT_SRC=../../ref/hermes-agent
export WEBUI_SRC=../../ref/hermes-webui
./build-rootfs.sh core
```

### Tauri 开发模式 (Windows)

```bash
cd tauri-app
npm install
npm run tauri dev
```

## 发布

推送 `v*` 标签到 GitHub 即自动触发 CI 构建并发布 Release：

```bash
git tag v1.0.0
git push origin v1.0.0
```

CI 流水线：
1. **Linux Job**: 并行构建 4 个 rootfs 层 (core/browser/voice/messaging)
2. **Windows Job**: 构建 Tauri .exe + Inno Setup 打包
3. **Release Job**: 上传安装包到 GitHub Release

## License

MIT
