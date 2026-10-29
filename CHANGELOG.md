# 更新日志

本文件记录狸记额度（Linook，旧名 AiLimits）每个版本的变化，格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [0.3.0] - 2026-10-29

### 新增

- 菜单栏常驻项轮流展示每个账号自己剩余最多的那份额度，图标与数字一起切换，每 6 秒换一个账号。
- 设置窗口：面板底部增加「设置」，可以开关开机自动启动，也可以按账号关掉进度条；设置通过应用组共享给桌面小组件，修改后立即重画。
- Claude、Codex、Cursor、Grok 卡片与小组件格子增加账号图标，取自 LobeHub 图标库。
- 设置页面用样例数据离屏渲染成 README 图片。
- GitHub Actions：PR 与 main 分支自动测试并做临时签名构建；推送 `v*` 标签时生成 `.zip`、`.dmg` 并发布到 GitHub Releases。
- `scripts/build-release.sh`：不需要 Apple 开发者账号的临时签名构建，产物放到 `dist/`。
- README 增加安装、首次打开放行与桌面小组件的设置步骤。

### 变更

- 关掉某个账号的进度条之后，该账号的额度仍保留右侧的剩余百分比。
- 产品改名为「狸记额度」（英文名 Linook）：应用包改为 `Linook.app`，系统里显示为「狸记额度」，发布包改为 `Linook-<版本>-macOS.dmg/.zip`，dmg 卷名为 Linook。小组件名称「Agent 额度」不变。
- 为了兼容已安装的版本与小组件登记，bundle id（`com.kevinkwok.AiLimits*`）、应用组标识与快照目录 `~/Library/Application Support/AiLimits/` 保持不变。从 AiLimits 升级时，需要先删掉旧的 `AiLimits.app`。
- 小组件的共享位置可在构建时选择：默认仍走应用组；临时签名构建改用 `~/Library/Application Support/AiLimits/`，因为 macOS 15 起临时签名的小组件扩展无法访问应用组。
- 应用组标识按 `DEVELOPMENT_TEAM` 自动生成，`build-app.sh` 支持用环境变量换成自己的团队编号。

## [0.2.0] - 2026-10-27

### 新增

- 菜单栏面板与桌面小组件的进度条、百分比统一改为展示剩余额度，菜单栏图标显示全部窗口中最低的剩余百分比。
- Grok 卡片增加独立的 GrokBot 每周额度，读数来自 Grok Bot 桌面应用写在 `~/Library/Application Support/Grok Bot/sand-client-persistence` 的本机用量缓存；缓存过期或已经过了重置时间时不再展示。
- Cursor 卡片增加账号后台给出的 GrokBot 每周额度，账号没有这项额度时自动省略。
- Grok 访问令牌自动续期：令牌即将到期或者额度接口返回 401 时，使用本机 `refresh_token` 静默续期并写回 `auth.json`，与 Grok CLI 共用文件锁。
- README 增加菜单栏面板与三种尺寸桌面小组件的界面图片，全部由样例数据离屏渲染。
- 增加额度解析与版面规则的单元测试。

### 变更

- 应用组共享目录不可用时，在读取位置抛出错误并在面板上提示，不再直接终止进程。
- GET 请求遇到短暂的连接失败或者 5xx 响应时重试，最多请求 3 次；POST 请求不自动重发，避免重复交换凭据。
- 启动时先显示最近一次成功快照，再读取实时额度；读取失败后 30 秒重试，正常状态下每 5 分钟刷新。
- 桌面小组件继续按消耗最高的账号排序，面板刷新期间不再重复进入刷新状态。

## [0.1.0] - 2026-09-30

### 新增

- macOS 菜单栏下拉面板，展示 Claude、Codex、Cursor、Grok 四种账号的额度窗口、重置时间与套餐类型。
- 桌面小组件，支持单格、双格、四格三种尺寸，跟随系统调暗桌面小组件的显示方式。
- 从本机已经登录的客户端读取凭据，无需手动填写密钥；快照通过应用组共享给小组件扩展。
- 界面取自 animal-island-ui-style 设计系统，界面字体使用 Nunito。
