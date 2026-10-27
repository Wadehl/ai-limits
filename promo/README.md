# 宣传动画

`index.html` 是 1080×1440、12.4 秒的宣传动画。画面按时间逐帧计算，用浏览器直接打开会循环播放，改动文案与数值都在文件末尾的 `providers` 数组里。

画面使用样例数据，不含真实账号与密钥。

## 渲染视频

需要 Chrome、ffmpeg 与 Node 20 以上：

```bash
npm install
node render.mjs
```

输出 `out/agent-quota-promo.mp4` 与封面图，逐帧 PNG 保存在 `frames/`。`check_frames.py` 用 Pillow 检查关键帧的颜色、明暗与场景差异。
