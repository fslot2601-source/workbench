# Skill Lens 1.0 执行计划

## 产品边界

Skill Lens 是 Codex App Server 的本地控制面客户端。1.0 覆盖 Skills 管理、按工作区查看 Hooks 定义与信任状态、展示本连接会话可观测到的 Hook 瞬态事件、中文诊断、安全变更和开源发布。

不承诺读取 Codex Desktop 或其他 CLI 进程的全局 Hook 历史；在共享 daemon 的多客户端事件语义得到官方保证和实测前，相关会话必须标记为“本应用会话”“已附加会话”或“仅配置”。

## 阶段与验收

1. 工程与协议基础：可发现 Codex，完成 initialize/initialized，正确处理响应前后的异步通知。
2. Skills：按 cwd 列出、刷新、解析自动匹配策略、诊断错误与依赖，并通过官方写接口安全启停。
3. Hooks：展示 effective config、来源、信任、managed 状态、matcher 与 handler，保留未知事件原始值。
4. 安全控制：Hook 配置写入前读取版本并使用乐观并发；Skill 使用专用 `skills/config/write` 接口；两类写入均回读验证，managed 配置拒绝修改。
5. 运行与恢复：处理 app-server 退出、半行 JSON、未知字段、超时和断线；运行状态明确标记为瞬态。
6. 发布：中文优先界面、单元测试、协议 fixture、运行验收、README、许可证与无签名开源构建；英文界面作为后续社区本地化工作，不阻塞个人版 1.0。

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
