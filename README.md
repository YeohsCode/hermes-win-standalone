# Hermes Windows Offline Installer

面向离线/企业环境的 Hermes AI Agent Windows 一键安装包。

## 特性

- **完全离线安装** — 安装包内含所有依赖，目标机器无需联网
- **官方 Desktop App** — 打包上游 [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) 的 Electron 桌面应用
- **完整功能** — 聊天、文件浏览、语音、设置管理、Skills、定时任务
- **分层组件** — 核心 / 浏览器自动化 / 语音，按需选择
- **企业分发** — 单个 .exe，支持静默安装，可通过 SCCM/GPO 部署
- **中文界面** — 安装程序支持简体中文

## 系统要求

- Windows 10 (1809+) 或 Windows 11
- 4GB+ 可用磁盘空间（核心），8GB+（全功能）
- 不需要 WSL、不需要联网

## 架构

```
HermesSetup.exe (Inno Setup 离线安装包)
├─ Hermes Desktop App (Electron)  → {Program Files}\Hermes\
├─ hermes-agent (Python venv)     → %LOCALAPPDATA%\hermes\hermes-agent\
├─ PortableGit                    → %LOCALAPPDATA%\hermes\git\
└─ setup-hermes.ps1               → PATH, HERMES_HOME, bootstrap marker
```

安装完成后，Hermes Desktop App 直接启动，跳过首次联网下载步骤。

## 安装组件

| 组件 | 内容 | 大小 |
|------|------|------|
| **Core** (必选) | Hermes Desktop + Agent Runtime + PortableGit | ~500MB |
| **Browser** | Playwright + Chromium 浏览器自动化 | ~300MB |
| **Voice** | faster-whisper + ffmpeg + TTS 语音引擎 | ~500MB |

## 项目结构

```
hermes-win-standalone/
├── installer/               # Inno Setup 安装程序
│   ├── hermes-win.iss       #   安装脚本定义
│   └── scripts/             #   PowerShell 安装/卸载脚本
├── .github/workflows/       # CI/CD 流水线
│   ├── build-release.yml    #   构建 + 打包 + 发布
│   └── ci.yml               #   PR 验证
├── tests/                   # 测试脚本
└── docs/                    # 历史工作日志
```

本项目不包含自有的桌面应用代码。所有构建在 CI (GitHub Actions) 中完成。

## 发布

推送 `v*` 标签即自动触发 CI 构建并发布 Release：

```bash
git tag v3.0.0
git push origin v3.0.0
```

CI 流水线：
1. **build-runtime-bundle** — 下载 hermes-agent，构建 Python venv，打包 PortableGit
2. **build-electron-app** — 克隆上游仓库，构建 Electron Desktop App
3. **package-installer** — Inno Setup 打包为单个 .exe
4. **release** — 上传到 GitHub Releases

## 版本对应

`AGENT_VERSION` 在 `.github/workflows/build-release.yml` 中定义，指向上游 hermes-agent 的 git tag。

## License

MIT
