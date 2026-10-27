# AiLimits

macOS 菜单栏与桌面小组件，用来看本机各个 Agent 账号的额度剩余。

支持 Claude、Codex、Cursor、Grok 四种账号。凭据从本机已经登录的客户端里读取，再向各自的官方接口查询额度，过程中不需要手动填写任何密钥。

## 界面

菜单栏下拉面板：

<img src="docs/images/panel.png" width="380" alt="菜单栏下拉面板">

桌面小组件：

<img src="docs/images/widget-small.png" width="170" alt="单格小组件">
<img src="docs/images/widget-medium.png" width="364" alt="双格小组件">

<img src="docs/images/widget-large.png" width="364" alt="四格小组件">

图片由样例数据离屏渲染，不含真实账号信息。

## 功能

- **菜单栏面板**：点开菜单栏图标是一个下拉面板，每种账号各占一张卡片，列出 5 小时、7 天、月度等各个额度的剩余百分比、重置时间与套餐类型。进度条与数字都是剩余量，数字前标注「剩余」。
- **桌面小组件**：支持单格、双格、四格三种尺寸，按消耗最高的账号排在前面。开启系统里的「调暗桌面小组件」之后内容照常显示。
- **自动刷新**：启动时先显示已有的成功快照，再读取实时额度。正常情况下每 5 分钟刷新；读取失败后每 30 秒再试。短暂断网或服务端故障会在同一次读取中重试，最多请求 3 次。

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
- GrokBot 的每周额度由 Cursor 账号后台一并给出，地址是 `api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus`；账号没有 GrokBot 额度时这一项不显示

**Grok**

- 凭据：`$GROK_HOME/auth.json`，默认 `~/.grok/auth.json`
- 额度接口：`cli-chat-proxy.grok.com/v1/billing`，可用环境变量 `GROK_CLI_CHAT_PROXY_BASE_URL` 换到别的地址
- GrokBot 是独立于 GrokBuild 的另一份额度，读数来自 Grok Bot 桌面应用写在 `~/Library/Application Support/Grok Bot/sand-client-persistence` 的用量缓存。缓存里的有效期或者重置时间已经过去时不再展示，打开桌面上那个应用就会刷新
- 自动续期：`auth.x.ai` 签发的令牌即将过期或额度接口返回 401 时，使用本机的 `refresh_token` 静默续期，无需启动 Grok CLI。续期与 CLI 共用 `auth.json.lock`，新凭据以仅当前用户可读写的权限原子写回 `auth.json`。
- 仅当续期授权被撤销、缺少续期凭据或使用不支持的登录来源时，才需要重新登录。临时网络故障不会被提示成「登录已过期」。

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

- 凭据仅用于对应服务的额度查询与登录续期。Grok 续期请求只发送到经过验证的 `https://auth.x.ai` 地址，新凭据写回本机原有的 `auth.json`，供仪表盘与 CLI 共用。
- 共享快照包含额度和账号标签，不包含访问令牌或续期令牌。
- 没有统计、上报与联网的账号体系。

## 参考与致谢

- 额度信息的获取方式参考 [orca](https://github.com/stablyai/orca)
- 界面设计取自 [animal-island-ui-style](https://github.com/guokaigdg/animal-island-ui-style)
- 界面字体是 [Nunito](https://fonts.google.com/specimen/Nunito)，按 SIL Open Font License 1.1 使用，许可证见 `Resources/Nunito-OFL.txt`

## 许可证

MIT，见 `LICENSE`。
