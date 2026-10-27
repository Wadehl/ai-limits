from pathlib import Path

from PIL import Image, ImageChops, ImageStat

frames = sorted(Path("promo/frames").glob("*.png"))
if len(frames) < 300:
    raise SystemExit(f"帧数不足：{len(frames)}")

checks = [("标题", 45), ("面板", 120), ("高亮", 200), ("小组件", 300), ("结尾", 358)]
images = {}
for name, index in checks:
    image = Image.open(frames[index]).convert("RGB")
    if image.size != (1080, 1440):
        raise SystemExit(f"{name} 尺寸不对：{image.size}")
    colors = image.getcolors(maxcolors=1_000_000)
    if not colors or len(colors) < 400:
        raise SystemExit(f"{name} 颜色过少：{0 if not colors else len(colors)}")
    stat = ImageStat.Stat(image)
    if max(stat.stddev) < 12:
        raise SystemExit(f"{name} 几乎没有明暗变化：{stat.stddev}")
    images[name] = image
    print(f"{name} 颜色 {len(colors)}，标准差 {[round(v, 1) for v in stat.stddev]}")

for first, second in [("标题", "面板"), ("面板", "高亮"), ("高亮", "小组件"), ("小组件", "结尾")]:
    diff = ImageChops.difference(images[first], images[second])
    mean = sum(ImageStat.Stat(diff).mean) / 3
    if mean < 0.5:
        raise SystemExit(f"{first} 与 {second} 差别太小：{mean:.2f}")
    print(f"{first} -> {second} 平均像素差 {mean:.2f}")

regions = {
    "Cursor 的 GrokBot 行": (150, 718, 930, 792),
    "Grok 的 GrokBot 行": (150, 892, 930, 966),
    "说明文字": (240, 1020, 840, 1140)
}
focus = Image.open(frames[200]).convert("RGB")
later = Image.open(frames[240]).convert("RGB")
base = Image.open(frames[120]).convert("RGB")
for name, box in regions.items():
    base_crop = base.crop(box)
    focus_crop = focus.crop(box)
    if name.startswith("Grok"):
        focus_crop = later.crop(box)
    if name == "说明文字":
        base_crop = focus.crop(box)
        focus_crop = later.crop(box)
    mean = sum(ImageStat.Stat(ImageChops.difference(base_crop, focus_crop)).mean) / 3
    if mean < 2:
        raise SystemExit(f"{name} 没有出现变化：{mean:.2f}")
    print(f"{name} 与基准帧的平均像素差 {mean:.2f}")

sizes = {frame.stat().st_size for frame in frames}
if len(sizes) < 30:
    raise SystemExit("帧文件大小几乎没有变化，画面可能停在原处")
print(f"共 {len(frames)} 帧，文件大小 {min(sizes)}–{max(sizes)} 字节")
