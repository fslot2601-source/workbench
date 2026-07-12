# Security Policy

## Supported versions

当前维护 1.1.x 与主分支。安全修复优先进入主分支，再随下一个补丁版本发布。

## Reporting

请不要在公开 Issue 中提交凭据、完整配置、Hook 命令或包含私人路径的日志。可先创建不含敏感信息的安全说明，并请求维护者提供私下沟通方式。

## Local trust boundary

Skill Lens 会读取用户选择工作区中的 Codex 元数据，并启动本机 Codex App Server。Skill、Hook、MCP、路径、图标、命令和诊断文本均被视为不可信输入。应用不执行界面展示的 Skill 或 Hook 内容，也不建立遥测或独立上传通道。

Codex 本身可能连接 OpenAI 服务或用户配置的远程 MCP。Skill Lens 展示或重载 MCP 时可能触发这些既有连接；请按相应服务的隐私政策管理凭据与数据。

自动清理仅允许当前真实 Codex Home 下的 `cache` 目录。符号链接、普通文件、扫描后变化、跨卷目标和非白名单类别会被拒绝。缓存清理不是安全擦除。

正式二进制必须使用 Developer ID 签名、Hardened Runtime 和 Apple 公证。未签名的本地测试包不得冒充正式发布版本。
