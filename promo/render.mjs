import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import puppeteer from "puppeteer-core";

const ROOT = path.resolve(import.meta.dirname, "..");
const PAGE = path.join(ROOT, "promo/index.html");
const OUT = path.join(ROOT, "promo/out");
const FRAMES = path.join(ROOT, "promo/frames");
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const FPS = 30;
const WIDTH = 1080;
const HEIGHT = 1440;

await fs.rm(FRAMES, { recursive: true, force: true });
await fs.mkdir(FRAMES, { recursive: true });
await fs.mkdir(OUT, { recursive: true });

const browser = await puppeteer.launch({
  executablePath: CHROME,
  headless: true,
  protocolTimeout: 180_000,
  args: [
    "--allow-file-access-from-files",
    "--font-render-hinting=none",
    "--hide-scrollbars",
    "--force-color-profile=srgb",
    "--disable-lcd-text"
  ],
  defaultViewport: { width: WIDTH, height: HEIGHT, deviceScaleFactor: 1 }
});

const page = await browser.newPage();
const pageErrors = [];
page.on("pageerror", (error) => pageErrors.push(error.message));
page.on("console", (message) => {
  if (message.type() === "error") pageErrors.push(message.text());
});

await page.evaluateOnNewDocument(() => { window.__CAPTURE = true; });
await page.goto(`file://${PAGE}`, { waitUntil: "load" });
await page.evaluate(async () => {
  await document.fonts.load('900 30px Nunito');
  await document.fonts.ready;
});

if (pageErrors.length) {
  throw new Error(`页面加载出错：${pageErrors.join(" | ")}`);
}

const duration = await page.evaluate(() => window.__duration);
const fonts = await page.evaluate(() => ({
  nunito: document.fonts.check('900 30px Nunito'),
  chinese: document.fonts.check('900 30px "PingFang SC"', '额度')
}));
if (!fonts.nunito || !fonts.chinese) {
  throw new Error(`字体没有就绪：${JSON.stringify(fonts)}`);
}

const overflow = await page.evaluate(() => {
  const selectors = [
    ".sign h1", ".sign p", ".tag", ".cta", ".menubar b", ".ribbon", ".updated",
    ".name", ".plan", ".label", ".pct", ".caption b", ".caption span",
    ".end-inner h1", ".end-inner .lead", ".end-inner .meta", ".end-inner .fine"
  ];
  const found = [];
  for (const time of [0.5, 3.6, 6.8, 9.8, 11.8]) {
    window.__setTime(time);
    for (const selector of selectors) {
      for (const element of document.querySelectorAll(selector)) {
        const overflowX = element.scrollWidth - element.clientWidth;
        const overflowY = element.scrollHeight - element.clientHeight;
        if ((overflowX > 1 || overflowY > 1) && element.getBoundingClientRect().width > 0) {
          found.push(`${selector} 在 ${time}s 溢出 ${overflowX}x${overflowY}`);
        }
      }
    }
  }
  window.__setTime(0);
  return found;
});
if (overflow.length) {
  throw new Error(`文字溢出：${overflow.join("；")}`);
}

const layout = await page.evaluate(() => {
  const box = (selector) => {
    const rect = document.querySelector(selector).getBoundingClientRect();
    return { x: rect.x, y: rect.y, right: rect.right, bottom: rect.bottom, width: rect.width, height: rect.height };
  };
  window.__setTime(3.6);
  const panel = box("#panel");
  const caption = box("#caption");
  const menubar = box("#menubar");
  window.__setTime(9.8);
  const desktop = box("#desktop");
  const widgetCaption = box("#widgetCaption");
  window.__setTime(11.8);
  const end = box(".end-inner");
  return { panel, caption, menubar, desktop, widgetCaption, end };
});

const inside = (rect) => rect.x >= 0 && rect.y >= 0 && rect.right <= WIDTH && rect.bottom <= HEIGHT;
for (const [name, rect] of Object.entries(layout)) {
  if (!inside(rect)) {
    throw new Error(`${name} 超出画面：${JSON.stringify(rect)}`);
  }
}
if (layout.panel.bottom >= layout.caption.y) {
  throw new Error(`说明文字压住了面板：面板底部 ${layout.panel.bottom}，文字顶部 ${layout.caption.y}`);
}
if (layout.desktop.bottom >= layout.widgetCaption.y) {
  throw new Error(`小组件说明文字压住了桌面卡片`);
}

console.log(`面板 ${Math.round(layout.panel.width)}x${Math.round(layout.panel.height)}，底部 ${Math.round(layout.panel.bottom)}`);
console.log(`说明文字顶部 ${Math.round(layout.caption.y)}`);
console.log(`时长 ${duration}s，${FPS}fps，共 ${Math.round(duration * FPS)} 帧`);

const total = Math.round(duration * FPS);
for (let frame = 0; frame < total; frame += 1) {
  const time = frame / FPS;
  await page.evaluate((value) => window.__setTime(value), time);
  await page.screenshot({
    path: path.join(FRAMES, `${String(frame).padStart(4, "0")}.png`),
    type: "png",
    clip: { x: 0, y: 0, width: WIDTH, height: HEIGHT },
    captureBeyondViewport: false
  });
  if (frame % 60 === 0) console.log(`渲染 ${frame}/${total}`);
}

await browser.close();

const video = path.join(OUT, "agent-quota-promo.mp4");
await new Promise((resolve, reject) => {
  const ffmpeg = spawn("ffmpeg", [
    "-y",
    "-framerate", String(FPS),
    "-i", path.join(FRAMES, "%04d.png"),
    "-c:v", "libx264",
    "-profile:v", "high",
    "-preset", "slow",
    "-crf", "18",
    "-pix_fmt", "yuv420p",
    "-movflags", "+faststart",
    "-an",
    video
  ], { stdio: "inherit" });
  ffmpeg.on("exit", (code) => code === 0 ? resolve() : reject(new Error(`ffmpeg 退出码 ${code}`)));
});

const poster = path.join(OUT, "agent-quota-promo-cover.png");
await fs.copyFile(path.join(FRAMES, "0042.png"), poster);

console.log(`视频 ${video}`);
console.log(`封面 ${poster}`);
