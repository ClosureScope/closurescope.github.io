import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { extname, join } from 'node:path';
import { chromium } from 'playwright-core';

// Run the real scene, springs, camera and RAF timeline. Skip only GPU draw
// commands: software rasterization otherwise makes animation timing unreliable.
const browser = await chromium.launch({
  args: ['--enable-webgl', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
});
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2' };
try {
  for (const portrait of [false, true]) {
    const context = await browser.newContext({
      deviceScaleFactor: .25,
      viewport: portrait ? { width: 390, height: 844 } : { width: 1280, height: 800 },
    });
    await context.addInitScript(() => {
      localStorage.setItem('closurescope-rhine-settings', JSON.stringify({ superPerformance: true, sound: false, music: false }));
      for (const type of [WebGLRenderingContext, WebGL2RenderingContext]) {
        for (const name of ['drawArrays', 'drawElements', 'drawArraysInstanced', 'drawElementsInstanced']) {
          if (type.prototype[name]) type.prototype[name] = () => {};
        }
      }
    });
    await context.route('http://archive.test/**', async route => {
      const path = new URL(route.request().url()).pathname;
      const file = join('site/dist', path.endsWith('/') ? `${path}index.html` : path);
      await route.fulfill({ body: await readFile(file), contentType: mime[extname(file)] ?? 'application/octet-stream' });
    });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto('http://archive.test/');
    if (await page.locator('#empty-archive').isVisible()) {
      await context.close();
      continue;
    }
    await page.waitForFunction(() => window.rhine?.stats().ready && window.rhine.stats().renderedFrames > 2);
    const initial = await page.evaluate(() => window.rhine.stats());
    await page.locator('[data-action="open"]').first().click();
    await page.waitForFunction(() => {
      const s = window.rhine.stats();
      return s.inspecting && s.extraction > .4 && s.cameraDetail < .98;
    });
    await page.waitForFunction(() => {
      const s = window.rhine.stats();
      return s.extraction > 3.3 && s.cameraDetail > .98 && s.decryption.phase === 'clear';
    });
    const extracted = await page.evaluate(() => window.rhine.stats());
    assert.equal(await page.locator('.blog-reader').evaluate(node => getComputedStyle(node).opacity), '1', 'the article is revealed with the scene transition');
    assert(extracted.modelPosition[1] > initial.modelPosition[1] + 2, 'the selected model physically rises out of the array');
    assert.notDeepEqual(extracted.cameraPosition, initial.cameraPosition, 'the camera moves with the extraction');
    assert.equal(await page.locator('#stage').getAttribute('inert'), null, 'the model stays interactive beside the reader');
    await page.frameLocator('.blog-reader').locator('.prose').waitFor();
    await page.locator('[data-reader="back"]').click();
    await page.waitForFunction(() => {
      const s = window.rhine.stats();
      return s.browsing && s.cameraDetail < .02 && s.extraction < .6;
    });
    assert.equal(await page.evaluate(() => window.rhine.stats().selected), initial.selected);
    assert.deepEqual(errors, []);
    await context.close();
    console.log(`PASS: model extraction, camera movement, decryption and return / ${portrait ? 'mobile' : 'desktop'}`);
  }
} finally {
  await browser.close();
}
