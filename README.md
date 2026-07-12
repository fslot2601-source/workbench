# Skill Lens

Skill Lens 是一个面向 macOS 的 Codex 本地能力控制台。它把 Skills 和 Hooks 的有效状态转换成普通人能理解的中文界面，并提供诊断与安全控制。

项目目标不是替代 Codex，也不是做通用配置文件编辑器，而是回答四个问题：

- Codex 当前发现了哪些能力？
- 某个 Skill 是否启用、是否允许自动匹配、来自哪里？
- 某个 Hook 何时运行、是否可信、为什么没有生效？
- 修改后 Codex 是否真正接受了新状态？

## 已实现

- 原生 SwiftUI 三栏界面，按工作区读取 Codex 的实际有效状态
- Skills 的隐式、显式、隐藏、来源、依赖、错误与安全启停
- Hooks 的触发时机、来源、信任、managed 状态、处理器、脱敏命令与安全启停
- 仅限当前 App Server 连接的 Hook 瞬态运行记录，不冒充全局历史
- Hook 配置写入前版本校验；Skill 与 Hook 均使用 Codex 专用接口、写后回读验证和本地变更记录
- App Server 超时、未知字段、命名差异和意外退出处理
- 中文优先的普通人解释，不要求用户理解 JSON-RPC 或 TOML

## 本地构建

要求：

- macOS 14 或更高版本
- Xcode 16 或更高版本（Swift 6 工具链）
- 已安装 Codex CLI
- XcodeGen（只有修改 `project.yml` 后才需要）

生成工程并构建：

```sh
xcodegen generate
xcodebuild -project SkillLens.xcodeproj -scheme SkillLens -configuration Debug -destination 'platform=macOS' build
```

也可以直接用 Xcode 打开 `SkillLens.xcodeproj`。应用不会捆绑 Codex；首次启动会从常见位置寻找 `codex`，也可以在诊断页手动选择。

## 测试

```sh
xcodebuild -project SkillLens.xcodeproj -scheme SkillLens -configuration Debug -destination 'platform=macOS' test
```

测试包含协议 fixture、状态模型、脱敏规则，以及在临时 `CODEX_HOME` 中运行的真实 Codex App Server 集成测试。真实测试不会修改用户现有配置；未安装 Codex 时会自动跳过。

## 隐私与安全

- 默认不联网，不包含遥测或用户账户系统。
- 不捆绑 Codex，也不读取 Codex 登录令牌。
- Hook 命令、Skill Markdown 和图标路径均按不可信本地内容处理。
- 不执行界面里展示的 Skill 或 Hook 内容。
- Hook 启停使用 Codex `config/read` 与 `config/batchWrite`，通过版本号避免覆盖并发修改。
- 1.0 只承诺展示本应用连接所能观察到的 Hook 运行事件，不声称监控其他 Codex 客户端的全局会话。

由于应用需要启动本机 Codex 并访问用户选择的工作区，当前开源构建不启用 App Sandbox。发布构建应启用 Hardened Runtime 并完成开发者签名与公证。

## 项目原则

- App Server 是主要数据和写入通道；本地文件只用于补充 App Server 暂未表达的 Skill 调用策略。
- 不把“已启用”描述成“某次任务已经使用”。
- 不猜测并直接改写未知配置格式。
- 新 Codex 版本增加字段时保持兼容；关键字段或方法消失时明确报错。

贡献方式见 [CONTRIBUTING.md](CONTRIBUTING.md)，安全问题见 [SECURITY.md](SECURITY.md)。执行边界和兼容策略见 [docs/EXECUTION_PLAN.md](docs/EXECUTION_PLAN.md)。

## License

MIT。Skill Lens 是独立开源项目，与 OpenAI 无隶属或官方授权关系。
