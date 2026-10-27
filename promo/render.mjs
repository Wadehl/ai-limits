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

const expectedImages = {
  "panel.png": [760, 1686],
  "widget-large.png": [728, 764],
  "widget-medium.png": [728, 340],
  "widget-small.png": [340, 340]
};
const images = await page.evaluate(() => [...document.images].map((image) => ({
  src: image.getAttribute("src"),
  width: image.naturalWidth,
  height: image.naturalHeight,
  complete: image.complete
})));
if (images.length !== Object.keys(expectedImages).length) {
  throw new Error(`截图数量不对：${images.length}`);
}
for (const image of images) {
  const name = path.basename(image.src);
  const expected = expectedImages[name];
  if (!expected) throw new Error(`多了一张截图：${image.src}`);
  if (!image.complete || image.width === 0) throw new Error(`截图没有加载：${image.src}`);
  if (image.width !== expected[0] || image.height !== expected[1]) {
    throw new Error(`${name} 尺寸不对：${image.width}x${image.height}`);
  }
}

const overflow = await page.evaluate(() => {
  const selectors = [
    ".brand", ".chrome-step", ".kicker", ".title-title", ".title-sub", ".title-meta", ".title-foot",
    ".chapter-kicker", ".chapter-title", ".agent-name", ".agent-windows", ".hint",
    ".legend-line", ".widget-note", ".read-index", ".read-title", ".read-desc", ".read-note",
    ".end-kicker", ".end-title", ".end-sub", ".end-meta", ".end-link"
  ];
  const found = [];
  for (const time of [0.9, 3.8, 7.4, 10.6, 12.2]) {
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
  window.__setTime(4.0);
  const panel = box("#panelShot");
  const agents = box("#agentList");
  window.__setTime(7.4);
  const large = box("#widgetLarge");
  const medium = box("#widgetMedium");
  const small = box("#widgetSmall");
  const legend = box("#widgetLegend");
  const note = box("#widgetNote");
  window.__setTime(10.6);
  const readList = box("#readList");
  const readNote = box("#readNote");
  window.__setTime(12.2);
  const titleBlock = box("#titleBlock");
  const titleFoot = box("#titleFoot");
  const end = box("#endInner");
  return { panel, agents, large, medium, small, legend, note, readList, readNote, titleBlock, titleFoot, end };
});

const inside = (rect) => rect.x >= 0 && rect.y >= 0 && rect.right <= WIDTH && rect.bottom <= HEIGHT;
for (const [name, rect] of Object.entries(layout)) {
  if (!inside(rect)) {
    throw new Error(`${name} 超出画面：${JSON.stringify(rect)}`);
  }
}
if (layout.panel.right + 40 > layout.agents.x) {
  throw new Error(`面板和 Agent 列表挤在一起：面板右边缘 ${layout.panel.right}，列表左边缘 ${layout.agents.x}`);
}
if (layout.panel.bottom > HEIGHT - 60) {
  throw new Error(`面板压到画面底部：${layout.panel.bottom}`);
}
if (layout.large.bottom + 30 > layout.medium.y) {
  throw new Error(`大号和中号小组件重叠：大号底部 ${layout.large.bottom}，中号顶部 ${layout.medium.y}`);
}
if (layout.small.bottom + 30 > layout.legend.y) {
  throw new Error(`小号小组件压住了尺寸说明：小号底部 ${layout.small.bottom}，说明顶部 ${layout.legend.y}`);
}
if (layout.readList.bottom + 60 > layout.readNote.y) {
  throw new Error(`读取说明压住了列表：列表底部 ${layout.readList.bottom}，说明顶部 ${layout.readNote.y}`);
}
if (layout.titleBlock.bottom + 60 > layout.titleFoot.y) {
  throw new Error(`标题压住了底部的 Agent 列表：标题底部 ${layout.titleBlock.bottom}`);
}

console.log(`面板 ${Math.round(layout.panel.width)}x${Math.round(layout.panel.height)}，底部 ${Math.round(layout.panel.bottom)}`);
console.log(`小组件大号底部 ${Math.round(layout.large.bottom)}，中号底部 ${Math.round(layout.medium.bottom)}`);
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
await fs.copyFile(path.join(FRAMES, "0120.png"), poster);

console.log(`视频 ${video}`);
console.log(`封面 ${poster}`);
