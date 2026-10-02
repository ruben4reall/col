// Checks the website the way a visitor meets it, at four sizes, under the production headers of vercel.json:
// console errors, CSP violations, failed requests, images that did not load, horizontal overflow and text that
// overflows its box. Screenshots of every section (and of each demo state) go to site/.shots/.
// Usage: node tools/audit.mjs [--only desktop|laptop|tablet|phone] [--no-shots] [--path /page] [--wrapped]
// --wrapped checks the page inside the skeleton a preview host puts around it (light colours on body, img max-width).
// --url https://getcol.vercel.app checks the published site instead of site/ served locally.
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { parseArgs } from 'node:util';
import { setTimeout as sleep } from 'node:timers/promises';
import { launchChrome } from './cdp.mjs';
import { SITE_DIR, startServer } from './serve.mjs';

const SIZES = {
  desktop: { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false },
  laptop: { width: 1024, height: 700, deviceScaleFactor: 1, mobile: false },
  tablet: { width: 820, height: 1180, deviceScaleFactor: 1, mobile: true },
  phone: { width: 390, height: 844, deviceScaleFactor: 2, mobile: true },
};
const SECTIONS = ['top', 'overview', 'music', 'ai', 'prompter', 'everyday', 'design', 'setup', 'light', 'privacy', 'developers', 'open-source', 'faq', 'download'];

const { values } = parseArgs({ options: { only: { type: 'string' }, 'no-shots': { type: 'boolean' }, path: { type: 'string', default: '/' }, wrapped: { type: 'boolean' }, url: { type: 'string' } } });
const WRAPPED = join(SITE_DIR, 'artifact-check.html');
if (values.wrapped) {
  const skeleton = '<!doctype html><html><head><meta charset=utf8><meta name=viewport content="width=device-width,initial-scale=1"><style>:root{color-scheme:light}body{margin:0;padding:0;font:14px -apple-system,sans-serif;background:#faf9f5;color:#141413}img{max-width:100%}</style></head><body>\n';
  await writeFile(WRAPPED, skeleton + (await readFile(join(SITE_DIR, 'index.html'), 'utf8')) + '\n</body></html>');
  values.path = '/artifact-check.html';
}
const SHOTS = join(SITE_DIR, '.shots');
if (!values['no-shots']) { await rm(SHOTS, { recursive: true, force: true }); await mkdir(SHOTS, { recursive: true }); }

// Everything measured inside the page: returns a list of problems.
const INSPECT = `(() => {
  const out = [];
  const doc = document.documentElement;
  if (doc.scrollWidth > innerWidth + 1) out.push('page scrolls sideways: ' + doc.scrollWidth + ' > ' + innerWidth);
  for (const img of document.images) {
    if (img.complete && img.naturalWidth === 0) out.push('image did not load: ' + img.getAttribute('src'));
  }
  const wide = [];
  for (const el of document.querySelectorAll('body *')) {
    const r = el.getBoundingClientRect();
    if (r.width === 0 || getComputedStyle(el).position === 'fixed') continue;
    if (r.right > innerWidth + 1 && !el.closest('.table-card') && !el.closest('.mac') && !el.closest('.chip-row')) wide.push(el.tagName.toLowerCase() + (el.className ? '.' + String(el.className).split(' ')[0] : '') + ' right=' + Math.round(r.right));
    if (['P', 'H1', 'H2', 'H3', 'A', 'BUTTON', 'SPAN', 'LI', 'SUMMARY'].includes(el.tagName) && el.scrollWidth > el.clientWidth + 1 && getComputedStyle(el).overflow !== 'visible' && !el.classList.contains('visually-hidden')) out.push('text clipped: ' + el.tagName + ' ' + el.textContent.trim().slice(0, 40));
  }
  if (wide.length) out.push('past the right edge: ' + [...new Set(wide)].slice(0, 6).join(', '));
  // Contrast: each element holding text, against the first opaque background behind it. Text over pictures is left
  // out (the pictures are captures, checked by eye).
  const rgb = (c) => (c.match(/[0-9.]+/g) || []).map(Number);
  const lum = ([r, g, b]) => [r, g, b].map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; })
    .reduce((sum, v, i) => sum + v * [0.2126, 0.7152, 0.0722][i], 0);
  const low = new Set();
  for (const el of document.querySelectorAll('body *')) {
    const text = [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim());
    if (!text || el.closest('.stage, .mac, .visually-hidden, .skip')) continue;
    const style = getComputedStyle(el);
    if (style.visibility === 'hidden' || style.display === 'none' || parseFloat(style.opacity) === 0) continue;
    if (style.webkitTextFillColor === 'rgba(0, 0, 0, 0)' || style.color === 'rgba(0, 0, 0, 0)') continue; // gradient text
    let bg = null;
    for (let node = el; node; node = node.parentElement) {
      const b = rgb(getComputedStyle(node).backgroundColor);
      if (b.length >= 3 && (b[3] === undefined || b[3] > 0.9)) { bg = b; break; }
    }
    bg = bg || [0, 0, 0];
    const [l1, l2] = [lum(rgb(style.color)), lum(bg)].sort((a, b) => b - a);
    const ratio = (l1 + 0.05) / (l2 + 0.05);
    if (ratio < 4.5) low.add(el.tagName.toLowerCase() + ' "' + el.textContent.trim().slice(0, 32) + '" ' + ratio.toFixed(1) + ':1');
  }
  if (low.size) out.push('low contrast: ' + [...low].slice(0, 8).join('; ') + (low.size > 8 ? ' and ' + (low.size - 8) + ' more' : ''));
  out.push(...window.__islet.csp.map((c) => 'CSP: ' + c), ...window.__islet.errors.map((e) => 'error: ' + e));
  return out;
})()`;

const server = await startServer();
const chrome = await launchChrome();
let failures = 0;
try {
  for (const [name, size] of Object.entries(SIZES)) {
    if (values.only && values.only !== name) continue;
    const page = await chrome.newPage(size);
    await page.goto((values.url ?? server.url) + values.path);
    await sleep(1200);
    const problems = [...(await page.evaluate(INSPECT)), ...page.problems];
    for (const t of page.transfers()) if (t.status >= 400) problems.push(`HTTP ${t.status}: ${t.url}`);
    const bytes = page.transfers().reduce((sum, t) => sum + t.bytes, 0);
    console.log(`${name} ${size.width}x${size.height}: ${problems.length ? problems.length + ' problem(s)' : 'clean'}, ${Math.round(bytes / 1024)} KB transferred`);
    for (const p of problems) console.log('  - ' + p);
    failures += problems.length;
    if (!values['no-shots']) {
      // Each demo state on the hero, then every section from its top.
      const states = await page.evaluate(`[...document.querySelectorAll('[data-tour-chips] .chip')].map((c) => c.dataset.state)`);
      for (const state of states) {
        await page.evaluate(`document.querySelector('[data-tour-chips] .chip[data-state="${state}"]').click(); scrollTo(0, 0)`);
        await sleep(900);
        await page.screenshot(join(SHOTS, `${name}-hero-${state}.png`));
      }
      for (const id of SECTIONS) {
        await page.evaluate(`document.getElementById('${id}').scrollIntoView({ block: 'start', behavior: 'instant' })`);
        await sleep(1300);
        await page.screenshot(join(SHOTS, `${name}-${id}.png`));
      }
      await page.evaluate(`scrollTo(0, document.documentElement.scrollHeight)`);
      await sleep(350);
      await page.screenshot(join(SHOTS, `${name}-footer.png`));
    }
    await page.close();
  }
} finally {
  await chrome.close();
  await server.close();
  if (values.wrapped) await rm(WRAPPED, { force: true });
}
process.exitCode = failures ? 1 : 0;
