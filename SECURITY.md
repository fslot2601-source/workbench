# Security Policy

## Supported versions

当前维护 1.2.x 与主分支。安全修复优先进入主分支，再随下一个补丁版本发布。

## Reporting

请不要在公开 Issue 中提交凭据、完整配置、Hook 命令或包含私人路径的日志。可先创建不含敏感信息的安全说明，并请求维护者提供私下沟通方式。

## Local trust boundary

Workbench 会读取用户选择工作区中的 Codex 元数据，并启动本机 Codex App Server。Skill、Hook、MCP、路径、图标、命令和诊断文本均被视为不可信输入。应用不执行界面展示的 Skill 或 Hook 内容，也不建立遥测或独立上传通道。

Codex 本身可能连接 OpenAI 服务或用户配置的远程 MCP。Workbench 展示或重载 MCP 时可能触发这些既有连接；请按相应服务的隐私政策管理凭据与数据。

存储清理仅允许当前真实 Codex Home 下的固定白名单目录：`cache`、`.tmp`、`log` 和 `archived_sessions`。缓存目录可重建；临时文件只处理超过 24 小时的普通文件，日志只处理超过 7 天的普通文件，二者与归档会话默认移入 macOS 废纸篓。符号链接、扫描后变化、跨卷目标和非白名单类别会被拒绝。该功能不是安全擦除。

GitHub 备份依赖本机 GitHub CLI，Workbench 不读取或保存 GitHub token。上传前会再次确认目标是私人仓库，并只上传用户预览确认过的脱敏白名单内容。

使用 Developer ID 的正式二进制必须启用 Hardened Runtime 并完成 Apple 公证。未签名社区构建可以与源码一同发布，但必须明确标注“未签名、未公证”，不得冒充 Apple 已验证的软件。
