# Workbench 发布清单

## 自动门禁

- `xcodegen generate` 后工程无未提交漂移。
- Debug 完整测试通过，真实 Codex 测试只在隔离 `CODEX_HOME` 中写入。
- 有图形会话且已授权 Xcode 自动化时，单独运行 `SkillLensUITests` 验证单窗口启动并生成应用窗口截图；无图形会话的 CI 明确跳过，不伪装为已通过。
- Release archive 同时包含 `arm64` 与 `x86_64`。
- `.app` 包含有效 `PrivacyInfo.xcprivacy`、版本号和完整图标。
- ZIP 必须解包、DMG 必须只读挂载；其中的应用须与归档应用具有相同 bundle id、版本、双架构和文件内容，SHA-256 清单通过。

## 未签名 GitHub Release

没有付费开发者证书时，可以发布源码与未签名构建，但 Release 标题和说明必须明确写出“未签名、未公证”。同时提供 ZIP、DMG、SHA-256 校验文件，并附上 README 中的首次打开方式。不得声称该构建通过 Apple 验证，也不建议用户删除隔离属性绕过系统检查。

发布前确认：

- 从 DMG 拖入“应用程序”后，可通过右键“打开”或“系统设置 → 隐私与安全性 → 仍要打开”完成首次启动。
- GitHub Release 中的三个文件名、版本号和校验文件完全一致。
- Release Notes 说明最低 macOS 版本、需要本机 Codex，GitHub 备份还需要可选的 `gh`。

## 可选的签名与公证

如果以后需要免除未签名首次启动提示，使用 `Developer ID Application` 证书签名、启用 Hardened Runtime 并完成公证。设置：

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: ..." \
NOTARYTOOL_PROFILE="workbench-notary" \
./scripts/build-release.sh
```

发布前还必须通过：

```sh
codesign --verify --deep --strict "Workbench.app"
xcrun stapler validate "Workbench-*.dmg"
spctl --assess --type open --context context:primary-signature "Workbench-*.dmg"
```

签名模式必须同时提供证书与公证 profile。只有一个变量、签名不是 Developer ID、缺少 stapled 公证票据或 Gatekeeper 评估失败时，脚本都会停止，且未完成包不会写入 `dist/`。每次构建前，根目录中的旧 Workbench 产物会移入 `dist/archive/`；CI 只上传 `dist/` 根目录中的当前 ZIP、DMG 和校验文件。没有证书时，脚本生成已验证结构与校验和的未签名社区构建。

## 自动更新源

从首个内置 Sparkle 的版本开始，Workbench 使用根目录的 `appcast.xml` 检查 GitHub Release 更新。Apple Developer ID 与 Sparkle 更新签名不是一回事：社区构建可以没有付费证书，但 ZIP 更新包必须由 Workbench 的 EdDSA 私钥签名。

私钥由 Sparkle 保存为 macOS 钥匙串项目：

- service：`https://sparkle-project.org`
- account：`workbench`
- 用途：只用于签署 Workbench 更新包

私钥不写入脚本、文档、日志、仓库或 Release。公钥通过 `SUPublicEDKey` 写入应用。应使用 Sparkle `generate_keys --account workbench -x` 将私钥导出到离线加密备份；导出文件不得放在仓库目录、网盘公开目录或 GitHub Artifact 中。

发布顺序：

1. 更新版本号、build、CHANGELOG 和 Release Notes。
2. 运行 `./scripts/build-release.sh` 并完成安装包验证。
3. 创建 GitHub Release，上传 ZIP、DMG 和 SHA-256 文件，确认下载地址已经公开可访问。
4. 运行 `./scripts/generate-appcast.sh <版本号>`，由本机钥匙串签署 ZIP 并更新 `appcast.xml`。
5. 检查 appcast 中的版本、build、下载地址、文件长度和 EdDSA 签名，然后提交并推送 `appcast.xml`。
6. 从上一个正式版本执行“检查更新…”，完成一次真实下载、验证、替换和重新启动。

不能先发布 appcast 再上传安装包，否则客户端可能在短时间内发现一个无法下载的更新。丢失私钥时也不能直接生成新钥匙继续发布；没有 Developer ID 作为第二信任链时，旧客户端不会信任新钥匙。

## 人工验收矩阵

- 全新用户：首次启动、Codex 未安装、手动选择 Codex、切换工作区。
- 连接恢复：启动超时、App Server 意外退出、一次重新扫描恢复。
- 空与错误状态：Skills、Hooks、MCP、用量和存储分别验证加载、空、部分失败和完全失败。
- 写入安全：系统/管理员 Skill、托管 Hook、required 或非用户 MCP 均保持只读。
- 清理安全：`cache` 可重建；`.tmp` 只处理超过 24 小时的普通文件，`log` 只处理超过 7 天的普通文件，二者与归档会话进入废纸篓；当前会话、配置、凭据、Skills、插件、数据库和未知数据不变。
- 备份安全：未登录、公开仓库、无默认分支、疑似凭据、符号链接和非白名单文件均拒绝上传；备份记录可从 GitHub 重新读取。
- 界面：最小/默认/大窗口、键盘导航、VoiceOver、高对比度、关闭最后窗口后重新打开。
- 安装：开启 Gatekeeper 的干净账户从 DMG 拖入 Applications，首次启动和卸载均正常。

## 发布记录

- 更新 `MARKETING_VERSION`、`CURRENT_PROJECT_VERSION` 和 `CHANGELOG.md` 日期。
- 记录 commit、Xcode/macOS 版本、测试数量、DMG/ZIP SHA-256。
- 不提交证书、notary profile、API key、token 或公证日志中的敏感字段。
- 记录 appcast 生成结果和从上一正式版本完成自动更新的验收结果，但不记录私钥内容。
