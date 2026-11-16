// Frames of the animated scenes, to check them by eye: each scene is scrolled into view and photographed at
// several moments of its timeline. Output: site/.shots/frames/<size>-<scene>-<ms>.png
// Usage: node tools/frames.mjs [--only desktop|phone]
import { mkdir, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { parseArgs } from 'node:util';
import { setTimeout as sleep } from 'node:timers/promises';
import { launchChrome } from './cdp.mjs';
import { SITE_DIR, startServer } from './serve.mjs';

const SIZES = {
  desktop: { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false },
  phone: { width: 390, height: 844, deviceScaleFactor: 2, mobile: true },
};
// Each scene of col.js (its data-scene) and the moments of its timeline worth a look.
const SCENES = {
  drop: [400, 1300, 2200, 2700, 3300, 4800, 6300],
  clip: [400, 1000, 1500, 1850, 2300, 3200, 4400, 6600],
};
const { values } = parseArgs({ options: { only: { type: 'string' } } });
const OUT = join(SITE_DIR, '.shots', 'frames');
await rm(OUT, { recursive: true, force: true });
await mkdir(OUT, { recursive: true });

const server = await startServer();
const chrome = await launchChrome();
try {
  for (const [name, size] of Object.entries(SIZES)) {
    if (values.only && values.only !== name) continue;
    for (const [scene, moments] of Object.entries(SCENES)) {
      const page = await chrome.newPage(size);
      await page.goto(server.url + '/');
      await sleep(400); // as a visitor would: scrolling in the very task of the load can hide the first observation
      await page.evaluate(`document.querySelector('[data-scene="${scene}"]').closest('figure').scrollIntoView({ block: 'center', behavior: 'instant' })`);
      const start = Date.now();
      for (const ms of moments) {
        await sleep(Math.max(0, ms - (Date.now() - start)));
        await page.screenshot(join(OUT, `${name}-${scene}-${ms}.png`));
      }
      if (page.problems.length) console.log(`${name} ${scene}:`, page.problems);
      await page.close();
    }
  }
} finally {
  await chrome.close();
  await server.close();
}
console.log('frames in site/.shots/frames');
