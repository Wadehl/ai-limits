from pathlib import Path

from PIL import Image, ImageChops, ImageStat

frames = sorted(Path("promo/frames").glob("*.png"))
if len(frames) < 300:
    raise SystemExit(f"帧数不足：{len(frames)}")

checks = [("标题", 45), ("面板", 120), ("小组件", 225), ("本机读取", 300), ("结尾", 360)]
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

for first, second in [("标题", "面板"), ("面板", "小组件"), ("小组件", "本机读取"), ("本机读取", "结尾")]:
    diff = ImageChops.difference(images[first], images[second])
    mean = sum(ImageStat.Stat(diff).mean) / 3
    if mean < 0.5:
        raise SystemExit(f"{first} 与 {second} 差别太小：{mean:.2f}")
    print(f"{first} -> {second} 平均像素差 {mean:.2f}")


def count_near(image, rgb, tolerance=12):
    red, green, blue = rgb
    total = 0
    for pixel in image.getdata():
        if abs(pixel[0] - red) <= tolerance and abs(pixel[1] - green) <= tolerance and abs(pixel[2] - blue) <= tolerance:
            total += 1
    return total


def check_region(name, frame_name, box, min_colors, teal=0, paper=0):
    crop = images[frame_name].crop(box)
    colors = crop.getcolors(maxcolors=1_000_000)
    count = 0 if not colors else len(colors)
    if count < min_colors:
        raise SystemExit(f"{name} 颜色只有 {count} 种，截图没有画出来")
    teal_count = count_near(crop, (25, 200, 185))
    paper_count = count_near(crop, (247, 243, 223))
    if teal_count < teal:
        raise SystemExit(f"{name} 里的青色只有 {teal_count} 个像素，应用截图没有显示")
    if paper_count < paper:
        raise SystemExit(f"{name} 里的卡片底色只有 {paper_count} 个像素，应用截图没有显示")
    stat = ImageStat.Stat(crop)
    if max(stat.stddev) < 8:
        raise SystemExit(f"{name} 几乎没有内容：{stat.stddev}")
    print(f"{name} 颜色 {count}，青色 {teal_count}，卡片底色 {paper_count}")


check_region("面板截图", "面板", (90, 380, 520, 1334), 800, teal=2000, paper=50000)
check_region("大号小组件", "小组件", (90, 380, 570, 884), 400, teal=500, paper=20000)
check_region("小号小组件", "小组件", (620, 380, 860, 620), 200, teal=100, paper=5000)

for name, box in [("面板截图", (90, 380, 520, 1334)), ("大号小组件", (90, 380, 570, 884))]:
    before = images["标题"].crop(box)
    after = images["面板"].crop(box) if name == "面板截图" else images["小组件"].crop(box)
    mean = sum(ImageStat.Stat(ImageChops.difference(before, after)).mean) / 3
    if mean < 6:
        raise SystemExit(f"{name} 在对应场景里没有出现：{mean:.2f}")
    print(f"{name} 与前一场景的平均像素差 {mean:.2f}")


def check_text(name, frame_name, box, min_dark):
    crop = images[frame_name].crop(box)
    dark = sum(1 for pixel in crop.getdata() if sum(pixel) < 300)
    if dark < min_dark:
        raise SystemExit(f"{name} 只有 {dark} 个深色像素，文字没有显示")
    print(f"{name} 深色像素 {dark}")


check_text("标题文字", "标题", (90, 370, 990, 910), 3000)
check_text("Agent 列表", "面板", (580, 380, 990, 900), 1500)
check_text("尺寸说明", "小组件", (620, 690, 990, 1060), 800)
check_text("读取列表", "本机读取", (90, 400, 990, 900), 2000)
check_text("结尾文字", "结尾", (90, 500, 990, 1010), 2000)

sizes = {frame.stat().st_size for frame in frames}
if len(sizes) < 30:
    raise SystemExit("帧文件大小几乎没有变化，画面可能停在原处")
print(f"共 {len(frames)} 帧，文件大小 {min(sizes)}–{max(sizes)} 字节")
