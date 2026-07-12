# Skill Lens 发布清单

## 自动门禁

- `xcodegen generate` 后工程无未提交漂移。
- Debug 完整测试通过，真实 Codex 测试只在隔离 `CODEX_HOME` 中写入。
- 有图形会话且已授权 Xcode 自动化时，单独运行 `SkillLensUITests` 验证单窗口启动并生成应用窗口截图；无图形会话的 CI 明确跳过，不伪装为已通过。
- Release archive 同时包含 `arm64` 与 `x86_64`。
- `.app` 包含有效 `PrivacyInfo.xcprivacy`、版本号和完整图标。
- ZIP、DMG 均可解包或校验，SHA-256 清单通过。

## 签名与公证

公开下载版本必须使用 `Developer ID Application` 证书签名，并启用 Hardened Runtime。设置：

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: ..." \
NOTARYTOOL_PROFILE="skill-lens-notary" \
./scripts/build-release.sh
```

发布前还必须通过：

```sh
codesign --verify --deep --strict "Skill Lens.app"
xcrun stapler validate "Skill-Lens-*.dmg"
spctl --assess --type open --context context:primary-signature "Skill-Lens-*.dmg"
```

没有证书时，脚本只生成供本机测试的未签名包，并明确输出警告；未签名包不得标记为正式下载版本。

## 人工验收矩阵

- 全新用户：首次启动、Codex 未安装、手动选择 Codex、切换工作区。
- 连接恢复：启动超时、App Server 意外退出、一次重新扫描恢复。
- 空与错误状态：Skills、Hooks、MCP、用量和存储分别验证加载、空、部分失败和完全失败。
- 写入安全：系统/管理员 Skill、托管 Hook、required 或非用户 MCP 均保持只读。
- 清理安全：只允许 `cache`；会话、配置、凭据、Skills、插件、数据库、日志和未知数据不变。
- 界面：最小/默认/大窗口、键盘导航、VoiceOver、高对比度、关闭最后窗口后重新打开。
- 安装：开启 Gatekeeper 的干净账户从 DMG 拖入 Applications，首次启动和卸载均正常。

## 发布记录

- 更新 `MARKETING_VERSION`、`CURRENT_PROJECT_VERSION` 和 `CHANGELOG.md` 日期。
- 记录 commit、Xcode/macOS 版本、测试数量、DMG/ZIP SHA-256。
- 不提交证书、notary profile、API key、token 或公证日志中的敏感字段。
