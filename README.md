# Workbench

Workbench 是为 Codex 制作的 macOS 本地工具箱。它把 Skills、Hooks、Memory、MCP、账户用量、本机存储和配置备份转换成普通人能理解的中文界面，并提供诊断与安全控制。

项目目标不是替代 Codex，也不是做通用配置文件编辑器，而是回答这些问题：

- Codex 当前发现了哪些能力？
- 某个 Skill 是否启用、是否允许自动匹配、来自哪里？
- 某个 Hook 何时运行、是否可信、为什么没有生效？
- MCP 是否只是写进配置，还是已经能读取到实际能力？
- 当前限额与 Token 活动如何，本机 Codex 又占用了多少空间？
- 修改后 Codex 是否真正接受了新状态？

## 已实现

- 原生 SwiftUI 三栏界面，按工作区读取 Codex 的实际有效状态
- Skills 的隐式、显式、隐藏、来源、依赖、错误与安全启停
- Hooks 的触发时机、来源、信任、managed 状态、处理器、脱敏命令与安全启停
- MCP 的配置开关、连接阶段、工具与资源数量；界面不展示参数、环境变量、查询字符串或工具 schema
- Codex 官方提供的账户限额、重置时间、Token 汇总与每日趋势；接口未提供的费用和常用模型明确标为不可用
- Codex Home 分类占用与分级清理：缓存可重建，过期临时文件与日志可移入废纸篓，归档会话必须单独确认，其余内容默认只读
- Codex Memory 按内容分类展示，区分当前生效与长期整理状态，并提供搜索、复制和来源追溯；应用本身不直接改写 Memory
- GitHub 私人仓库备份：通过本机 `gh` 登录，选择或创建仓库、上传脱敏预览，并从 GitHub 读取备份记录
- 原生状态栏面板，快速查看 Codex 限额、Token 活动、本机存储和自检状态
- 设置与系统自检页面，集中管理工作区、Codex 路径、状态栏刷新和各模块健康状态
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

也可以直接用 Xcode 打开 `SkillLens.xcodeproj`。应用不会捆绑 Codex；首次启动会从常见位置和 `PATH` 寻找 `codex`，也可以在设置中手动选择。

## 安装包与发布构建

生成本机测试用的通用架构 ZIP、DMG 和 SHA-256：

```sh
./scripts/build-release.sh
```

本次产物位于 `dist/` 根目录；再次构建时，旧产物会保留到 `dist/archive/`，避免 CI 或人工上传时混入旧版本。脚本会解开 ZIP、只读挂载 DMG，并确认两者包含同一版本、同一架构和同一内容的应用。

没有 Developer ID 证书时会生成明确标注的未签名社区构建，可随源码放入 GitHub Release，但不能描述成 Apple 已验证或已公证的软件。首次打开时，把 Workbench 拖入“应用程序”，右键选择“打开”；若 macOS 仍阻止运行，请前往“系统设置 → 隐私与安全性”，核对来源后选择“仍要打开”。不要通过删除系统隔离属性来绕过安全检查。

若以后使用 Developer ID，公开模式必须同时提供签名身份与钥匙串中的公证 profile；缺少任意一项都会直接失败。流程和验收命令见 [发布清单](docs/RELEASE_CHECKLIST.md)。

## 测试

```sh
xcodebuild -project SkillLens.xcodeproj -scheme SkillLens -configuration Debug \
  -destination 'platform=macOS' -only-testing:SkillLensTests test
```

测试包含协议 fixture、状态模型、脱敏规则，以及在临时 `CODEX_HOME` 中运行的真实 Codex App Server 集成测试。真实测试不会修改用户现有配置；未安装 Codex 时会自动跳过。

UI 自动化需要当前 macOS 图形会话允许 Xcode 控制应用。授权后可单独运行：

```sh
xcodebuild -project SkillLens.xcodeproj -scheme SkillLens -configuration Debug \
  -destination 'platform=macOS' -only-testing:SkillLensUITests test
```

## 隐私与安全

- 不包含遥测、广告或独立用户账户系统。用量页只通过本机 Codex App Server 请求当前 Codex 账户数据。
- 不捆绑 Codex，也不读取 Codex 登录令牌。
- Hook 命令、Skill Markdown 和图标路径均按不可信本地内容处理。
- 不执行界面里展示的 Skill 或 Hook 内容。
- Memory 页面只读取经脱敏的有限内容；raw 与 Chronicle 不进入主记忆列表，应用不直接写入 Codex 生成的 Memory 文件。
- Hook 启停使用 Codex `config/read` 与 `config/batchWrite`，通过版本号避免覆盖并发修改。
- 只承诺展示本应用连接所能观察到的 Hook 运行事件，不声称监控其他 Codex 客户端的全局会话。
- MCP 的“已启用”只表示有效配置开关；只有实际返回能力清单时才标为能力已读取。
- 存储页只读取文件元数据；清理限定在当前 Codex Home 下的固定目录白名单。缓存可永久重建，超过时限的临时文件与日志移入废纸篓，归档会话需单独确认；每次清理前都会重新扫描并校验路径、卷、符号链接和内容变化。
- GitHub 备份只在用户手动确认后运行，只接受私人仓库；Workbench 不读取或保存 GitHub token，认证由 GitHub CLI 与 macOS 钥匙串管理。
- MCP 清单和重载可能促使本机 Codex 连接用户已配置的远程 MCP；网络请求由 Codex 与相应 MCP 服务处理，Workbench 不另建上传通道。
- 缓存清理不是安全擦除，不能用于销毁敏感数据。

由于应用需要启动本机 Codex 并访问用户选择的工作区，当前构建不启用 App Sandbox。工程为 Release 启用 Hardened Runtime；公开分发包必须再使用 Developer ID 签名并完成 Apple 公证。隐私清单位于应用资源中，声明应用自身不跟踪、不收集数据。

## 项目原则

- App Server 是主要数据和写入通道；本地文件只用于补充 App Server 暂未表达的 Skill 调用策略。
- 不把“已启用”描述成“某次任务已经使用”。
- 不猜测并直接改写未知配置格式。
- 新 Codex 版本增加字段时保持兼容；关键字段或方法消失时明确报错。

贡献方式见 [CONTRIBUTING.md](CONTRIBUTING.md)，安全问题见 [SECURITY.md](SECURITY.md)。执行边界和兼容策略见 [docs/EXECUTION_PLAN.md](docs/EXECUTION_PLAN.md)。

## License

MIT。Workbench 是独立开源项目，与 OpenAI 无隶属或官方授权关系。
