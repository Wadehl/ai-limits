# 宣传动画

`index.html` 是 1080×1440、12.4 秒的应用介绍动画。画面按时间逐帧计算，用浏览器直接打开会循环播放。分镜依次是标题、菜单栏面板、桌面小组件、本机读取与结尾。

面板和小组件的画面直接使用 `docs/images` 里的离屏渲染截图，不在 HTML 里重画界面。文案与时间点都在 `index.html` 里修改。

画面使用样例数据，不含真实账号与密钥。

## 渲染视频

需要 Chrome、ffmpeg 与 Node 20 以上：

```bash
npm install
node render.mjs
```

输出 `out/agent-quota-promo.mp4` 与封面图，逐帧 PNG 保存在 `frames/`。`check_frames.py` 用 Pillow 检查关键帧的颜色、明暗、场景差异与文字区域，并确认应用截图和卡片底色出现在对应画面里。
