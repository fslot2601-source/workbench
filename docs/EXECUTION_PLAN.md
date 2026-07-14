# Workbench 执行计划

## 产品边界

Workbench 是 Codex App Server 的本地控制面客户端。1.0 覆盖 Skills 管理、按工作区查看 Hooks 定义与信任状态、展示本连接会话可观测到的 Hook 瞬态事件、中文诊断、安全变更和开源发布。

1.1 增加账户用量、MCP 与本机存储，同时修正 Skills “问题”分类。用量以 App Server 实际返回为准；MCP 把配置启用与实际能力读取分开；存储只允许清理固定缓存白名单。

1.2 增加可读的 Memory、GitHub 私人仓库备份、状态栏、设置和系统自检，并把应用品牌统一为 Workbench。Memory 以只读理解和自然语言调整为边界；GitHub 备份上传前必须提供脱敏预览并由用户确认。

不承诺读取 Codex Desktop 或其他 CLI 进程的全局 Hook 历史；在共享 daemon 的多客户端事件语义得到官方保证和实测前，相关会话必须标记为“本应用会话”“已附加会话”或“仅配置”。

## 阶段与验收

1. 工程与协议基础：可发现 Codex，完成 initialize/initialized，正确处理响应前后的异步通知。
2. Skills：按 cwd 列出、刷新、解析自动匹配策略、诊断错误与依赖，并通过官方写接口安全启停。
3. Hooks：展示 effective config、来源、信任、managed 状态、matcher 与 handler，保留未知事件原始值。
4. 安全控制：Hook 配置写入前读取版本并使用乐观并发；Skill 使用专用 `skills/config/write` 接口；两类写入均回读验证，managed 配置拒绝修改。
5. 运行与恢复：处理 app-server 退出、半行 JSON、未知字段、超时和断线；运行状态明确标记为瞬态。
6. 发布：中文优先界面、单元测试、协议 fixture、真实运行验收、README、许可证、通用架构 Release 包、校验和与 DMG；公开二进制必须使用 Developer ID 签名并完成 Apple 公证。英文界面作为后续社区本地化工作，不阻塞当前发布。
7. 账户用量：展示官方限额窗口、重置时间、Token 汇总和每日趋势；官方未提供的数据明确标为不可用。
8. MCP：合并有效配置与当前连接能力清单，区分配置、启动、可用、失败与停用状态；配置写入使用版本校验、重载和回读验证。
9. 存储：按类别汇总 Codex Home 占用；固定 `cache` 可重建，超过时限的 `.tmp` 与 `log` 文件移入废纸篓，`archived_sessions` 必须单独确认，其余类别保持只读；操作前校验路径、卷、符号链接与扫描后变化。
10. 发布工程：CI 同时运行 Debug 测试与无签名 Release 冒烟构建；本地发布脚本产出 ZIP、DMG 和 SHA-256，并支持可选的 Developer ID 签名、公证与 stapling。
11. Memory 与备份：Memory 按内容、适用范围和来源证据展示，不直接改写 Codex 文件；备份只接受 GitHub 私人仓库、白名单内容和用户确认过的脱敏预览。
12. 辅助入口：状态栏展示用量、存储与自检摘要；设置集中管理本地路径和刷新偏好；系统自检不把未配置的可选功能误报为故障。

## 兼容策略

- 不根据文档样例静态绑定协议；以运行时 initialize、实际功能调用探测和当前版本 schema 为准。Skills 与 Hooks 独立降级，单个方法不可用不伪装成全局断线。
- JSON 解码忽略未知字段，枚举保留 raw value。
- `skills/changed` 只作为失效信号，收到后重新执行 `skills/list`。
- Hook 事件名同时兼容 camelCase 与 snake_case。
- App Server 不支持或 Codex 版本过旧时，明确降级为诊断界面，不伪造绿色状态。

## 安全边界

- 不通过 shell 拼接命令启动 Codex。
- 不执行 Skill 或 Hook 中展示的文本。
- 日志不保存 token、环境变量值或未经脱敏的命令输出。
- 写入仅通过 Codex 的专用接口完成。Hook 配置保留版本校验与回读验证；Skill 专用接口保留回读验证。
- MCP 界面不展示启动参数、环境变量、URL 查询字符串或工具 schema。
- 账户协议未提供美元费用或常用模型时不从本地日志猜测。
- 当前会话、配置、凭据、Skills、插件、数据库和未知数据不进入清理范围。临时文件与日志只有超过明确时限后才可移入废纸篓；归档会话需要单独确认。
