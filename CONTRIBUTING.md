# Contributing

感谢你帮助改进 Skill Lens。

## 开发流程

1. 使用 macOS 14+ 与 Swift 6 工具链。
2. 修改 `project.yml` 或新增源文件后运行 `xcodegen generate`。
3. 运行完整测试，确保真实 Codex 集成测试使用临时 `CODEX_HOME`。
4. 提交应聚焦一个问题，并说明用户可见变化与验证结果。

## 协议改动

Codex App Server 仍会演进。协议适配应遵守：忽略未知字段、保留未知枚举原值、兼容已知命名差异，并为新 fixture 增加测试。不要为了通过某个版本而直接读取或改写内部数据库。

## 安全要求

- 不记录 token、密码、完整环境变量值或未脱敏命令。
- 不执行 Skill 或 Hook 提供的内容。
- 所有写操作必须经过 Codex 接口并回读验证。
- 不把当前连接观察到的事件描述成全局历史。
