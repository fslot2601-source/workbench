# Workbench 1.2.0

Workbench 是为 Codex 制作的中文 macOS 本地工具箱，用来查看和管理 Skills、Hooks、Memory、MCP、账户用量、本机存储与配置备份。

## 本次更新

- 重新设计总览，一页展示最近用量、Skills、Hooks、Memory、MCP 和存储状态。
- Skills 支持显式、隐式、隐藏三态说明与安全切换，并自动翻译英文用途。
- Hooks 按触发时机和处理器分别展示，说明匹配条件、执行顺序与流程影响。
- Memory 按内容、适用范围、关联项目和来源证据整理，支持复制自然语言调整指令。
- MCP 展示配置、认证、连接和实际暴露的工具与资源，并隔离每个 MCP 的开关状态。
- 增加 Codex 官方限额、Token 活动、本机存储分级清理、GitHub 私人仓库备份和备份记录。
- 增加原生状态栏面板、设置和系统自检。
- 更新 Workbench 图标，并统一白天与暗色模式配色。

## 系统要求

- macOS 14 或更高版本。
- 本机已安装 Codex CLI；Workbench 不捆绑 Codex。
- GitHub 备份为可选功能，需要安装 GitHub CLI (`gh`) 并完成登录。

## 下载

- `Workbench-1.2.0-13.dmg`：拖入“应用程序”安装。
- `Workbench-1.2.0-13.zip`：直接解压使用。
- `Workbench-1.2.0-13-SHA256SUMS.txt`：下载校验值。

校验命令：

```sh
shasum -a 256 -c Workbench-1.2.0-13-SHA256SUMS.txt
```

## 未签名构建说明

当前社区构建没有 Apple Developer ID 签名，也没有经过 Apple 公证。首次打开时，请把 Workbench 拖入“应用程序”，右键选择“打开”；若 macOS 仍阻止运行，请前往“系统设置 → 隐私与安全性”，核对来源后选择“仍要打开”。

不要通过删除系统隔离属性来绕过 macOS 安全检查。

Workbench 是独立开源项目，与 OpenAI 不存在隶属或官方授权关系。
