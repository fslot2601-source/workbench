# Changelog

## 1.1.0 - Unreleased

- 修正 Skills “问题”分类：只有已启用且确实存在错误或依赖缺失的 Skill 才进入该分类，隐藏状态不再被错误覆盖。
- 增加 Codex 官方限额、Token 汇总和每日趋势界面，不推测接口没有提供的费用与模型数据。
- 增加 MCP 配置、连接阶段、能力数量和安全启停界面。
- 增加 Codex Home 存储分类与缓存清理；会话、配置、凭据、Skills、插件、数据库及未知数据保持只读保护。

## 1.0.0 - Unreleased

- 建立原生 macOS SwiftUI 应用与中文信息架构。
- 接入 Codex App Server，支持 Skills、Hooks、通知和版本兼容。
- 支持 Skill 与 Hook 安全启停、写后验证和变更记录。
- 增加隔离的真实 Codex 集成测试、诊断、脱敏与原创应用图标。
