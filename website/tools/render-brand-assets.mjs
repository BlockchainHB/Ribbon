// Renders the social preview (MP4 + poster) and favicon rasters from the built site.
//
// The OG composition matches Paper: file "Ribbon", page "03 · Social & favicon", artboard
// "OG · 1200×630". The workspace stage is the real hero scene, stepped frame by frame through
// its loop, so the video stays identical to the website animation.
//
// Requirements: a built site (`npm run build`), Google Chrome, ffmpeg, ImageMagick, and
// playwright-core outside this project's dependencies:
//   npm install --no-save --prefix /tmp/ribbon-render playwright-core@1
//   PLAYWRIGHT_CORE=/tmp/ribbon-render/node_modules/playwright-core/index.mjs \
//     node tools/render-brand-assets.mjs        (run from website/)
import { createServer } from 'node:http';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { extname, join, resolve } from 'node:path';

const { chromium } = await import(process.env.PLAYWRIGHT_CORE ?? 'playwright-core');
const site = resolve('dist');
const publicDir = resolve('public');
const brandIcon = resolve('../branding/IconComposer/Ribbon.icon/Assets/Cobalt-Original.png');
const fps = 30;
const posterTime = 2100; // ms into the hero loop: just after the first swipe, as in Paper.

const types = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.png': 'image/png', '.svg': 'image/svg+xml', '.json': 'application/json' };
const server = createServer((request, response) => {
  let path = join(site, decodeURIComponent(new URL(request.url, 'http://x').pathname));
  try { if (statSync(path).isDirectory()) path = join(path, 'index.html'); response.writeHead(200, { 'content-type': types[extname(path)] ?? 'application/octet-stream' }); response.end(readFileSync(path)); }
  catch { response.writeHead(404); response.end(); }
}).listen(0, '127.0.0.1');
await new Promise((ready) => server.once('listening', ready));
const origin = `http://127.0.0.1:${server.address().port}`;

// Reduced motion keeps the site's own controller paused, so only this script moves the clock.
const browser = await chromium.launch({ channel: 'chrome', headless: true });

async function renderSocial() {
  const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 2, reducedMotion: 'reduce' });
  await page.route('https://datafa.st/**', (route) => route.abort()); // no analytics from renders
  await page.goto(`${origin}/`, { waitUntil: 'networkidle' });
  await page.evaluate(() => {
    const demo = document.querySelector('[data-motion="workspace"]');
    document.body.replaceChildren();
    document.body.style.margin = '0';
    document.body.insertAdjacentHTML('afterbegin', `
      <div id="og" style="position:fixed;left:0;top:0;width:1200px;height:630px;overflow:hidden;background:#fff;box-sizing:border-box;padding:56px 56px 0;display:flex;flex-direction:column">
        <div style="display:flex;align-items:center;justify-content:space-between">
          <div style="display:flex;align-items:center;gap:12px"><img src="/assets/ribbon-icon.png" width="44" height="44" alt=""><span style="font:600 26px/32px var(--display);letter-spacing:-.02em;color:#000">Ribbon</span></div>
          <span style="font:400 20px/28px var(--body);color:#5D6470">ribbonwm.com</span>
        </div>
        <div style="display:flex;flex-direction:column;gap:14px;padding-top:40px">
          <span style="font:500 64px/66px var(--display);letter-spacing:-.04em;color:#000;white-space:pre">Your agents,\nright beside your work.</span>
          <span style="font:400 22px/30px var(--body);letter-spacing:-.01em;color:#5D6470">A scrolling workspace for your Mac. Free and open source.</span>
        </div>
        <div id="og-stage" style="position:absolute;left:56px;top:340px;width:1088px"></div>
        <style>#og-stage .hero-stage{height:262px}</style>
      </div>`);
    document.querySelector('#og-stage').append(demo);
    demo.querySelector('.hero-demo-captions').style.display = 'none';
    demo.querySelector('[data-scene-toggle]').style.display = 'none';
  });
  await page.waitForFunction(() => document.querySelector('#og-stage .hero-stage').getBoundingClientRect().width === 1088);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(500); // let the resize remount settle

  const duration = await page.evaluate(() => document.querySelector('[data-motion="workspace"]').getAnimations({ subtree: true })[0].effect.getTiming().duration);
  const frame = async (time, path) => {
    await page.evaluate((time) => {
      for (const animation of document.querySelector('[data-motion="workspace"]').getAnimations({ subtree: true })) { animation.pause(); animation.currentTime = time; }
      return new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));
    }, time);
    await page.screenshot({ path, clip: { x: 0, y: 0, width: 1200, height: 630 } });
  };

  const frames = mkdtempSync(join(tmpdir(), 'ribbon-og-'));
  const count = Math.round((duration / 1000) * fps);
  for (let index = 0; index < count; index++) await frame((index * 1000) / fps, join(frames, `${String(index).padStart(4, '0')}.png`));
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', String(fps), '-i', join(frames, '%04d.png'),
    '-vf', 'scale=1200:630:flags=lanczos,format=yuv420p', '-c:v', 'libx264', '-preset', 'slow', '-crf', '20',
    '-tune', 'animation', '-movflags', '+faststart', '-an', join(publicDir, 'social/og.mp4')]);

  await frame(posterTime, join(frames, 'poster.png'));
  execFileSync('magick', [join(frames, 'poster.png'), '-filter', 'Lanczos', '-resize', '1200x630', '-quality', '88', '-strip', join(publicDir, 'social/og.jpg')]);
  rmSync(frames, { recursive: true });
  console.log(`social: ${count} frames, ${duration} ms loop`);
}

async function renderFavicons() {
  const svg = readFileSync(join(publicDir, 'favicon.svg'), 'utf8');
  const page = await browser.newPage({ colorScheme: 'light' });
  const out = mkdtempSync(join(tmpdir(), 'ribbon-favicon-'));
  for (const size of [16, 32, 48]) {
    await page.setViewportSize({ width: size, height: size });
    await page.setContent(`<body style="margin:0">${svg.replace('<svg ', `<svg width="${size}" height="${size}" `)}</body>`);
    await page.screenshot({ path: join(out, `${size}.png`), omitBackground: true });
  }
  execFileSync('magick', [16, 32, 48].map((size) => join(out, `${size}.png`)).concat(join(publicDir, 'favicon.ico')));
  execFileSync('magick', [brandIcon, '-filter', 'Lanczos', '-resize', '180x180', '-strip', join(publicDir, 'apple-touch-icon.png')]);
  rmSync(out, { recursive: true });
  console.log('favicons: favicon.ico (16/32/48), apple-touch-icon.png (180)');
}

try { await renderFavicons(); await renderSocial(); }
finally { await browser.close(); server.close(); }
