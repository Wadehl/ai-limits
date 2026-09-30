# AiLimits

macOS 菜单栏与桌面小组件，用来看本机各个 Agent 账号的额度剩余。

支持 Claude、Codex、Cursor、Grok 四种账号。凭据从本机已经登录的客户端里读取，再向各自的官方接口查询额度，过程中不需要手动填写任何密钥。

## 功能

- **菜单栏面板**：点开菜单栏图标是一个下拉面板，每种账号各占一张卡片，列出 5 小时、7 天、月度等各个额度的消耗百分比、重置时间与套餐类型。
- **桌面小组件**：支持单格、双格、四格三种尺寸，按消耗最高的账号排在前面。开启系统里的「调暗桌面小组件」之后内容照常显示。
- **自动刷新**：每 5 分钟读取一次，结果同时写入应用组共享目录供小组件使用，并通知系统刷新小组件时间线。

## 支持的账号

**Claude**

- 凭据：钥匙串 `Claude Code-credentials`，其次 `~/.claude/.credentials.json`
- 额度接口：`api.anthropic.com/api/oauth/usage`
- 除了 5 小时与 7 天两个窗口，还会列出按模型划分的每周额度

**Codex**

- 凭据：`$CODEX_HOME/auth.json`，默认 `~/.codex/auth.json`
- 额度接口：`chatgpt.com/backend-api/wham/usage`
- 接口给出的主次窗口按窗口长度对应到 5 小时与 7 天

**Cursor**

- 凭据：钥匙串 `cursor-access-token`，其次 `~/.cursor/auth.json`、`~/.cursor/cli-config.json`，以及 Cursor 桌面端的 `state.vscdb`
- 额度接口：`cursor.com/api/usage-summary`

**Grok**

- 凭据：`$GROK_HOME/auth.json`，默认 `~/.grok/auth.json`
- 额度接口：`cli-chat-proxy.grok.com/v1/billing`，可用环境变量 `GROK_CLI_CHAT_PROXY_BASE_URL` 换到别的地址

任何一个账号取不到数据只会影响它自己的那张卡片，其余账号照常显示。

## 构建

需要 macOS 14 以上、带 Swift 6 工具链的 Xcode，以及 xcodegen。

```bash
brew install xcodegen
./scripts/build-app.sh
```

脚本会生成 `AiLimits.xcodeproj`、构建 Release、把产物安装到 `/Applications/AiLimits.app`，并向 LaunchServices 注册小组件扩展。

签名使用的是 `project.yml` 里的 `DEVELOPMENT_TEAM`，应用组的标识在 `project.yml` 与 `Sources/AiLimitsCore/SnapshotStore.swift` 两处。macOS 要求应用组的标识前面带上开发者团队编号，换成你自己的团队编号之后才能构建，这三处的值要保持一致。

应用本身不开启沙盒，因为它需要读取 `~/.claude`、`~/.codex`、`~/.cursor`、`~/.grok` 这些目录；小组件扩展按照系统要求开启了沙盒，只通过应用组共享目录拿到数据。

## 开发

```bash
swift build
swift test
./scripts/render-widget-preview.sh
```

`render-widget-preview.sh` 把三种尺寸在三种绘制方式与底色下离屏渲染成 PNG，输出到 `logs/widget-preview`，用来在没有桌面小组件的环境里检查版面。

## 项目结构

- `Sources/AiLimitsCore` — 额度模型、四种账号的凭据读取与额度查询、应用组共享文件的读写
- `Sources/AiLimitsUI` — 设计系统的配色与字体、进度条、小组件版面
- `Sources/AiLimitsApp` — 菜单栏应用与下拉面板
- `Sources/AiLimitsWidget` — 桌面小组件扩展
- `Sources/AiLimitsWidgetPreview` — 把小组件版面离屏渲染成 PNG 的命令行工具
- `Tests` — 版面规则与配色的单元测试

## 隐私

- 凭据只在本机进程内读取，不写入磁盘，也不发往上面列出的接口之外的任何地址。
- 没有统计、上报与联网的账号体系。

## 参考与致谢

- 额度信息的获取方式参考 [orca](https://github.com/stablyai/orca)
- 界面设计取自 [animal-island-ui-style](https://github.com/guokaigdg/animal-island-ui-style)
- 界面字体是 [Nunito](https://fonts.google.com/specimen/Nunito)，按 SIL Open Font License 1.1 使用，许可证见 `Resources/Nunito-OFL.txt`

## 许可证

MIT，见 `LICENSE`。
