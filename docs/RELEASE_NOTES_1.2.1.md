# Workbench 1.2.1

这是一个连接兼容性修复版本。

Codex 整合进 ChatGPT 后，内置命令的位置从旧版 `Codex.app` 迁移到了 `ChatGPT.app`。Workbench 1.2.0 只识别旧位置和独立安装的 Codex CLI，因此部分新用户会一直看到“没有找到 Codex CLI”，即使 ChatGPT 已经安装并登录。

## 修复内容

- 自动识别 `ChatGPT.app` 内置的 Codex。
- 继续兼容旧版 `Codex.app` 和独立安装的 Codex CLI。
- 设置中可以直接选择 `ChatGPT.app`、`Codex.app` 或 `codex` 可执行文件。
- 选择错误位置时显示具体原因，例如应用不包含 Codex、文件没有执行权限等。
- 已通过当前 ChatGPT 内置 Codex 的 App Server 真实连接测试。

## 系统要求

- macOS 14 或更高版本。
- 本机已安装并登录 ChatGPT 桌面版，或已单独安装 Codex CLI。
- GitHub 备份为可选功能，需要安装 GitHub CLI (`gh`) 并完成登录。

## 下载

- `Workbench-1.2.1-14.dmg`：拖入“应用程序”安装。
- `Workbench-1.2.1-14.zip`：直接解压使用。
- `Workbench-1.2.1-14-SHA256SUMS.txt`：下载校验值。

校验命令：

```sh
shasum -a 256 -c Workbench-1.2.1-14-SHA256SUMS.txt
```

## 未签名构建说明

当前社区构建没有 Apple Developer ID 签名，也没有经过 Apple 公证。首次打开时，请把 Workbench 拖入“应用程序”，右键选择“打开”；若 macOS 仍阻止运行，请前往“系统设置 → 隐私与安全性”，核对来源后选择“仍要打开”。

不要通过删除系统隔离属性来绕过 macOS 安全检查。

Workbench 是独立开源项目，与 OpenAI 不存在隶属或官方授权关系。
