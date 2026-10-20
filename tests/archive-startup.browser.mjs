import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { extname, join } from 'node:path';
import { chromium } from 'playwright-core';

// Run after pnpm build. Serve the production output through Playwright so the
// check never starts or stops the author's development server.
const posts = JSON.parse(await readFile('.generated/posts.json', 'utf8'));
const browser = await chromium.launch({
  args: ['--enable-webgl', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
});
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2' };
try {
  for (const legacy of [false, true]) {
    const context = await browser.newContext({
      viewport: legacy ? { width: 390, height: 844 } : { width: 1280, height: 800 },
    });
    await context.addInitScript(legacy => {
      if (legacy) localStorage.setItem('closurescope-rhine-settings', JSON.stringify({ motion: { boot: true } }));
      // Pause only expensive 3D drawing in this software-rendered smoke test.
      // Native RAF remains available to UI animations and Playwright itself.
      const raf = requestAnimationFrame.bind(window);
      window.requestAnimationFrame = callback => String(callback).includes('--detail-shade') ? 0 : raf(callback);
    }, legacy);
    const audioRequests = [];
    await context.route('http://archive.test/**', async route => {
      const path = new URL(route.request().url()).pathname;
      if (path.endsWith('.ogg')) {
        audioRequests.push(path);
        // A music download failure must never block browsing or reopen a gate.
        await route.fulfill({ status: 503, body: 'Music unavailable' });
        return;
      }
      const file = join('site/dist', path.endsWith('/') ? `${path}index.html` : path);
      await route.fulfill({ body: await readFile(file), contentType: mime[extname(file)] ?? 'application/octet-stream' });
    });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`http://archive.test/${legacy ? '?time=12&freeze=1&review=1' : ''}`);
    if (!posts.length) {
      await page.locator('#empty-archive').waitFor({ state: 'visible' });
    } else {
      await page.waitForFunction(() => window.rhine?.stats().ready);
      const initial = await page.evaluate(() => window.rhine.stats());
      assert.equal(initial.mode, 'archive');
      assert.equal(initial.startup, 'started');
      assert.equal(initial.audio.scene, 'archive');
      assert.equal(initial.audio.preferences.sound, true);
      assert.equal(initial.audio.preferences.music, true);
      assert.equal(audioRequests.length, 0, 'no sound preparation gate before normal interaction');
      assert.equal(await page.locator('#boot, #skip, .entry-start, .mobile-entry, .welcome').count(), 0);
      assert.equal(await page.locator('#loading').count(), 0);
      assert.equal(await page.locator('[data-action="replay"], [data-action="restart"]').count(), 0);
      assert.equal(await page.locator('#stage').getAttribute('inert'), null);
      assert((await page.locator('#selected-title').textContent()).includes(posts[0].title));
      assert.equal(await page.locator('#three-scene').evaluate(node => getComputedStyle(node).opacity), '1');
      await page.locator('[data-action="settings"]').click();
      assert.equal(await page.locator('[data-motion="boot"]').count(), 0);
      await page.locator('[data-action="motion-preset"][data-preset="reduced"]').click();
      await page.locator('[data-action="motion-preset"][data-preset="full"]').click();
      assert.equal(await page.evaluate(() => window.rhine.stats().mode), 'archive');
      await page.locator('[data-action="close-modal"]').click();
      const firstCategory = posts[0].category;
      const firstFiles = posts.filter(post => post.category === firstCategory);
      assert.equal(await page.locator('#file-ticks button').count(), firstFiles.length);
      if (firstFiles.length > 1) {
        await page.locator('[data-action="next"]').click();
        assert.equal(await page.evaluate(() => window.rhine.stats().selected), firstFiles[1].slug);
      }
      await page.locator('[data-action="open"]').first().click();
      assert.equal(await page.evaluate(() => window.rhine.stats().mode), 'detail');
      await page.locator('[data-action="back"]').click();
      assert.equal(await page.evaluate(() => window.rhine.stats().mode), 'archive');
    }
    assert.deepEqual(errors, []);
    await context.close();
    console.log(`PASS: direct archive entry, ${legacy ? 'legacy settings / mobile' : 'fresh settings / desktop'}`);
  }
} finally {
  await browser.close();
}
