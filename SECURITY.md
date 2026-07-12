# Security Policy

## Supported versions

项目处于 1.0 开发期，目前只维护主分支。

## Reporting

请不要在公开 Issue 中提交凭据、完整配置、Hook 命令或包含私人路径的日志。可先创建不含敏感信息的安全说明，并请求维护者提供私下沟通方式。

## Local trust boundary

Skill Lens 会读取用户选择工作区中的 Codex 元数据，并启动本机 Codex App Server。Skill、Hook、路径、图标和命令均被视为不可信输入。应用不应执行这些内容，也不应把它们上传到网络。
