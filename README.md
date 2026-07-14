# Workbench

一个给 Codex 用的 macOS 工具箱。

我平时用 Codex 时，经常不知道一个 Skill 到底有没有启用，Hook 会在什么时候运行，MCP 连上以后提供了哪些工具，Memory 里又记住了什么。这些东西其实都在，只是散落在配置文件、目录和运行状态里。熟悉命令行的人还能慢慢翻，普通用户基本无从下手。

所以我做了 Workbench。它把这些内容整理成一个中文界面，也顺手补上用量、存储、自检和 GitHub 备份。它不会替你运行 Skill，也不准备接管 Codex；我只是希望打开一个窗口，就能知道 Codex 现在是什么状态。

## 下载

从 [GitHub Releases](https://github.com/fslot2601-source/workbench/releases/latest) 下载最新的 DMG，打开后把 Workbench 拖进“应用程序”。

目前提供的是未签名社区版本。第一次启动请在 Finder 里右键 Workbench，选择“打开”。如果 macOS 仍然拦截，可以到“系统设置 → 隐私与安全性”里选择“仍要打开”。

需要 macOS 14 或更高版本，并且本机已经安装并登录 Codex。

## 我在意的事

Workbench 显示的状态必须有依据。配置里写着“开启”，不代表它已经连接成功；MCP 能启动，也不代表工具真的读到了。能确认到哪一步，界面就写到哪一步。确认不了，就直接告诉你还没验证。

我也不想做一个套着 UI 的配置文件编辑器。用户真正想知道的是“它有什么用”“什么时候会触发”“改了会怎样”，不是 TOML 里的字段名。常用操作可以在界面里完成，复杂调整仍然可以直接和 Codex 说。尤其是 Memory，Workbench 负责把它读明白，不在背后替用户改写。

这个项目首先是给中文用户做的，其中也包括没写过代码的人。这里的汉化不只是把 `Settings` 换成“设置”，还要把隐式 Skill、Hook 触发顺序、MCP 生效状态这些概念说成人话。遇到英文内容时，尽量给出中文翻译，同时保留原文。

数据都留在本机。Workbench 没有自己的账户，也不读取 Codex 或 GitHub 的登录令牌。Memory 默认只读，备份前可以看脱敏预览，清理存储也只处理明确列出的目录。

## 现在能做什么

- **Skills**：看用途、来源和依赖，区分隐式、显式、隐藏，也可以调整状态。
- **Hooks**：看触发时机、处理器、执行顺序和信任状态；多个 Hook 会分别列出。
- **MCP**：不只看开关，还会检查连接过程，并列出实际暴露的工具和资源。
- **Memory**：按内容整理 Codex 记住的东西，标出来源、更新时间、适用范围和当前是否生效。
- **用量**：显示 Codex 返回的限额、重置时间、Token 汇总和每日趋势。没有数据的项目不会猜。
- **存储**：查看 Codex Home 的空间占用。缓存、临时文件和日志可以按安全范围清理，重要内容保持只读或要求单独确认。
- **备份**：通过本机 GitHub CLI 把脱敏后的配置备份到私人仓库，并保留备份记录。
- **状态栏与自检**：从菜单栏快速看用量、存储和运行状态；遇到问题时可以从自检页找到具体环节。

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
