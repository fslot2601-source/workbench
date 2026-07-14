# Contributing

感谢你帮助改进 Workbench。

## 开发流程

1. 使用 macOS 14+ 与 Swift 6 工具链。
2. 修改 `project.yml` 或新增源文件后运行 `xcodegen generate`。
3. 运行 `SkillLensTests`；有图形会话和 Xcode 自动化权限时，再单独运行 `SkillLensUITests`。真实 Codex 集成测试必须使用临时 `CODEX_HOME`。
4. 提交应聚焦一个问题，并说明用户可见变化与验证结果。

发布候选包使用 `./scripts/build-release.sh` 生成；脚本会调用 `verify-release.sh` 解包 ZIP、挂载 DMG 并复核内部应用。本地单独复核未签名包时必须显式设置 `ALLOW_UNSIGNED=1`。公开分发模式必须同时使用 Developer ID Application 与 Apple 公证；完整步骤见 `docs/RELEASE_CHECKLIST.md`。

## 协议改动

Codex App Server 仍会演进。协议适配应遵守：忽略未知字段、保留未知枚举原值、兼容已知命名差异，并为新 fixture 增加测试。不要为了通过某个版本而直接读取或改写内部数据库。

## 安全要求

- 不记录 token、密码、完整环境变量值或未脱敏命令。
- 不执行 Skill 或 Hook 提供的内容。
- 所有写操作必须经过 Codex 接口并回读验证。
- 不把当前连接观察到的事件描述成全局历史。
- MCP 可能通过 Codex 连接远程服务；界面不得泄露 URL 查询参数、启动参数、环境变量值或工具 schema。
- 存储清理只能覆盖明确白名单目录：缓存、超过时限的临时文件与日志，以及用户单独确认的归档会话；必须拒绝符号链接、路径漂移、跨卷目标和扫描后变化。
