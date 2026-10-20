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
      // UI navigation runs without scene RAF; animation sequencing is tested
      // separately against the live scene.
      if (!localStorage.getItem('closurescope-rhine-settings')) localStorage.setItem('closurescope-rhine-settings', JSON.stringify({ reduced: true, ...(legacy ? { motion: { boot: true }, superPerformance: true, rendering: { scale: 150, pixelRatio: 3 } } : {}) }));
      if (legacy) {
        localStorage.setItem('closurescope-saved', JSON.stringify(['old-article']));
      }
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
      assert.equal(initial.browsing, true, 'loaded archive is revealed and accepts pointer navigation');
      assert.equal(initial.reveal, 1);
      assert.equal(initial.inspecting, false);
      assert.equal(initial.audio.scene, 'archive');
      assert.equal(initial.audio.preferences.sound, true);
      assert.equal(initial.audio.preferences.music, true);
      assert.equal(audioRequests.length, 0, 'no sound preparation gate before normal interaction');
      assert.equal(await page.locator('#boot, #skip, .entry-start, .mobile-entry, .welcome').count(), 0);
      assert.equal(await page.locator('#loading').count(), 0);
      assert.equal(await page.locator('[data-action="saved"], [data-action="bookmark"], #saved-count, #selected-number, #hover-code, #object-id, .archive-counter').count(), 0);
      assert(!('saved' in initial));
      assert.equal(await page.locator('[data-action="replay"], [data-action="restart"]').count(), 0);
      assert.equal(await page.locator('#stage').getAttribute('inert'), null);
      assert((await page.locator('#selected-title').textContent()).includes(posts[0].title));
      assert.equal((await page.locator('header.brand').textContent()).trim(), 'ClosureScope');
      assert.equal(await page.locator('.file-title #selected-title').count(), 1);
      assert.equal(await page.locator('.archive-callout .eyebrow, .file-summary, #selected-clearance, .powered, .status-light').count(), 0);
      assert(!/INTERNAL DATABASE|FILE NUMBER|PUBLIC ARCHIVE/.test(await page.locator('#archive-ui').textContent()));
      assert(!/SESSION AUTHORIZED/.test(await page.locator('.system-footer').textContent()));
      const heading = await page.locator('#selected-title').evaluate(node => {
        const rect = node.getBoundingClientRect();
        return { right: rect.right, width: node.clientWidth, scrollWidth: node.scrollWidth, viewport: innerWidth };
      });
      assert(heading.right <= heading.viewport && heading.scrollWidth <= heading.width + 1, 'article heading fits without clipping');
      assert.equal(await page.locator('#three-scene').evaluate(node => getComputedStyle(node).opacity), '1');
      await page.locator('[data-action="settings"]').click();
      assert.equal(await page.locator('[data-motion], [data-action="motion-preset"], [data-color-theme], [data-pref="superPerformance"], [data-workbench-mode], .pwa-settings, .settings-shortcuts').count(), 0, 'settings contain no removed controls');
      assert.deepEqual(await page.locator('.settings-modal [data-pref]').evaluateAll(nodes => nodes.map(node => node.dataset.pref).sort()), ['music', 'sound']);
      assert.equal(await page.locator('#quality-preset').inputValue(), 'original');
      assert.equal(await page.locator('.quality-advanced, #quality-summary').count(), 0);
      const quality = await page.locator('#three-scene').evaluate(node => JSON.parse(node.dataset.renderQuality));
      assert.equal(quality.superPerformance, false, 'old performance preferences cannot override original quality');
      assert.equal(quality.transmission, 1);
      assert.equal(quality.depthOfField, 100);
      assert.equal(quality.shadows, 2048);
      assert.equal(quality.aoSamples, 32);
      await page.locator('#quality-preset').selectOption('performance');
      const performanceQuality = await page.locator('#three-scene').evaluate(node => JSON.parse(node.dataset.renderQuality));
      assert.equal(performanceQuality.depthOfField, 0);
      assert.equal(performanceQuality.aoSamples, 0);
      assert.equal(performanceQuality.shadows, 1024);
      assert.equal(performanceQuality.transmission, .5);
      await page.reload();
      await page.waitForFunction(() => window.rhine?.stats().ready);
      await page.locator('[data-action="settings"]').click();
      assert.equal(await page.locator('#quality-preset').inputValue(), 'performance', 'quality choice survives reloading');
      for (const [preset, samples] of [['high', 32], ['ultra', 64]]) {
        await page.locator('#quality-preset').selectOption(preset);
        const quality = await page.locator('#three-scene').evaluate(node => JSON.parse(node.dataset.renderQuality));
        assert.equal(quality.shadows, 4096);
        assert.equal(quality.antialias, 'smaa');
        assert.equal(quality.aoSamples, samples);
      }
      await page.reload();
      await page.waitForFunction(() => window.rhine?.stats().ready);
      await page.locator('[data-action="settings"]').click();
      assert.equal(await page.locator('#quality-preset').inputValue(), 'ultra', 'ultra quality survives reloading');
      await page.locator('#quality-preset').selectOption('original');
      const restoredQuality = await page.locator('#three-scene').evaluate(node => JSON.parse(node.dataset.renderQuality));
      assert.equal(restoredQuality.aoSamples, 32);
      assert.equal(restoredQuality.depthOfField, 100);
      assert.equal(await page.locator('[data-action="fullscreen"]').count(), await page.evaluate(() => Number(document.fullscreenEnabled)));
      await page.locator('[data-pref="music"]').uncheck();
      assert.equal(await page.evaluate(() => JSON.parse(localStorage.getItem('closurescope-rhine-settings')).music), false, 'music settings are saved');
      assert.equal(await page.evaluate(() => window.rhine.stats().mode), 'archive');
      await page.locator('[data-action="close-modal"]').click();
      const firstCategory = posts[0].category;
      const firstFiles = posts.filter(post => post.category === firstCategory);
      assert.equal(await page.locator('#file-ticks button').count(), firstFiles.length);
      if (firstFiles.length > 1) {
        await page.locator('[data-action="next"]').click();
        assert.equal(await page.evaluate(() => window.rhine.stats().selected), firstFiles[1].slug);
        assert.equal(await page.locator('#selected-title').textContent(), firstFiles[1].title);
        await page.locator('#three-scene canvas').dispatchEvent('wheel', { deltaY: 100 });
        assert.equal(await page.evaluate(() => window.rhine.stats().selected), firstFiles[2 % firstFiles.length].slug, 'scrolling the model advances the article');
      }
      assert((await page.locator('[data-action="search"]').textContent()).includes('DIRECTORY'));
      await page.locator('[data-action="search"]').click();
      assert(!/ARCHIVE INDEX|ARCHIVE DIRECTORY/.test(await page.locator('.terminal-modal').textContent()));
      assert.equal(await page.locator('.result-row').count(), posts.length);
      assert.equal(await page.locator('.result-name > b, .result-name > i').count(), 0);
      const target = posts.at(-1);
      await page.locator('#archive-search').fill(target.title);
      await page.waitForFunction(title => [...document.querySelectorAll('.result-row')].every(row => row.textContent.includes(title)), target.title);
      assert(await page.locator('.result-row').count() > 0);
      await page.locator('#archive-search').fill('__no_matching_blog_title__');
      await page.locator('.empty-results').waitFor();
      assert(!/收藏|编号/.test(await page.locator('.empty-results').textContent()));
      await page.locator('[data-action="reset-search"]').click();
      const lastCategory = target.category;
      await page.locator('[data-filter]').filter({ hasText: lastCategory }).click();
      assert.equal(await page.locator('.result-row').count(), posts.filter(post => post.category === lastCategory).length);
      await page.locator('.result-row').last().click();
      await page.waitForFunction(slug => window.rhine.stats().selected === slug && window.rhine.stats().mode === 'detail', target.slug);
      assert.equal(await page.evaluate(() => window.rhine.stats().mode), 'detail');
      assert.equal(await page.evaluate(() => window.rhine.stats().inspecting), true, 'reading requests the original model extraction');
      assert.equal(await page.locator('[data-action="bookmark"], .detail-kicker, #object-id, .detail-footnote > span').count(), 0);
      assert(!/SAVE ARCHIVE|REMOVE FROM SAVED|FILE X-|NO\.\d/.test(await page.locator('#detail-ui').textContent()));
      assert.equal(await page.locator('.detail-tabs, .metadata, .object-caption, .detail-actions, .detail-footnote').count(), 0);
      assert(!/文章信息|访问日志|正文格式/.test(await page.locator('#detail-ui').textContent()));
      await page.locator('.blog-reader').waitFor({ state: 'visible' });
      const dimensions = await page.locator('.blog-reader').boundingBox();
      const viewport = page.viewportSize();
      const brand = await page.locator('header.brand').boundingBox();
      assert(Math.abs(dimensions.y - brand.y) < 1, 'article scrolling clips at the top edge of ClosureScope');
      assert(Math.abs(dimensions.y + dimensions.height - viewport.height) < 1, 'article scrolling still reaches the screen bottom');
      assert(dimensions.width >= viewport.width * (legacy ? .9 : .75), 'reader preserves a generous reading width');
      assert(dimensions.height >= viewport.height * .7, 'reader uses the height freed by removing detail metadata');
      const panel = await page.locator('.reading-view').boundingBox();
      assert(Math.abs(panel.x + panel.width / 2 - viewport.width / 2) < 1, 'reading area is centered without a reserved model column');
      assert.equal(await page.locator('.reading-view').evaluate(node => getComputedStyle(node).boxShadow), 'none');
      assert(dimensions.x >= 0 && dimensions.x + dimensions.width <= viewport.width, 'reader fits inside the viewport');
      const reader = page.frameLocator('.blog-reader');
      await reader.locator('.prose').waitFor();
      await reader.locator('.site-header').waitFor({ state: 'hidden' });
      assert.equal(await reader.locator('body').evaluate(node => getComputedStyle(node).backgroundColor), 'rgba(0, 0, 0, 0)', 'the scene shows through the article background');
      assert(await reader.locator('.article-header').isVisible(), 'original article title remains visible');
      assert.equal(await reader.locator('html').evaluate(node => getComputedStyle(node).scrollbarWidth), 'none', 'only the document scrollbar is hidden');
      assert((await page.locator('.scene-visuals').evaluate(node => getComputedStyle(node).filter)).includes('blur('), 'frosting is applied to the complete scene');
      assert.equal(await page.locator('header.brand, .system-nav').evaluateAll(nodes => nodes.some(node => node.closest('.scene-visuals'))), false, 'navigation stays outside the scene blur');
      const typography = prose => {
        const style = getComputedStyle(prose);
        return { family: style.fontFamily, size: style.fontSize, lineHeight: style.lineHeight,
          width: prose.getBoundingClientRect().width, html: prose.innerHTML };
      };
      const standalone = await context.newPage();
      await standalone.setViewportSize(await reader.locator('body').evaluate(() => ({ width: innerWidth, height: innerHeight })));
      await standalone.goto(`http://archive.test/posts/${target.slug}/`);
      await standalone.evaluate(() => document.fonts.ready);
      await reader.locator('body').evaluate(() => document.fonts.ready);
      const articleLeft = await reader.locator('article').evaluate(node => node.getBoundingClientRect().left);
      const backRect = await page.locator('[data-reader="back"]').boundingBox();
      assert(backRect.x + backRect.width <= dimensions.x + articleLeft, 'return sits beside the article without overlapping text');
      assert.equal((await page.locator('[data-reader="back"]').textContent()).trim(), '←', 'return uses only the column navigation arrow');
      const arrowStyle = node => {
        const style = getComputedStyle(node);
        return { width: style.width, height: style.height, font: style.font };
      };
      assert.deepEqual(await page.locator('[data-reader="back"]').evaluate(arrowStyle),
        await page.locator('[data-action="column-prev"]').evaluate(arrowStyle), 'return shares the column arrow size and typography');
      const embedded = await reader.locator('.prose').evaluate(typography);
      const original = await standalone.locator('.prose').evaluate(typography);
      const { width: embeddedWidth, ...embeddedStyle } = embedded;
      const { width: originalWidth, ...originalStyle } = original;
      assert.deepEqual(embeddedStyle, originalStyle, 'original font properties, prose and SVG markup are preserved');
      if (legacy) assert.equal(embeddedWidth, dimensions.width - 104, 'mobile reserves a side gutter for the arrow');
      else assert(embeddedWidth > originalWidth * 1.25, 'desktop uses the available space for a wider article');
      const svgSize = node => ({ width: node.getBoundingClientRect().width, height: node.getBoundingClientRect().height });
      const embeddedSvg = reader.locator('.math-visual > svg').first();
      if (await embeddedSvg.count()) {
        const a = await embeddedSvg.evaluate(svgSize);
        const b = await standalone.locator('.math-visual > svg').first().evaluate(svgSize);
        assert.deepEqual(a, b, 'math retains its original rendered size');
      }
      await standalone.close();
      await reader.locator('body').evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
      assert(await reader.locator('body').evaluate(() => scrollY > 0 && scrollY + innerHeight >= document.documentElement.scrollHeight - 1), 'last lines are reachable by scrolling');
      await reader.locator('body').press('Escape');
      assert.equal(await page.evaluate(() => window.rhine.stats().mode), 'archive');
      await page.locator('[data-action="open"]').first().click();
      await page.locator('[data-action="search"]').click();
      await page.locator('#archive-search').waitFor({ state: 'visible' });
      await page.locator('.result-row').last().click();
      await page.waitForFunction(() => window.rhine.stats().mode === 'detail');
      await page.locator('[data-reader="back"]').click();
      assert.equal(await page.evaluate(() => window.rhine.stats().mode), 'archive');
      assert.equal(await page.evaluate(() => window.rhine.stats().browsing), true, 'returning from reading restores pointer navigation');
      const categoryFiles = posts.filter(post => post.category === target.category);
      if (categoryFiles.length > 1) {
        await page.locator('#three-scene canvas').dispatchEvent('wheel', { deltaY: 100 });
        assert.equal(await page.evaluate(() => window.rhine.stats().selected), categoryFiles[0].slug, 'model scrolling still works after returning from reading');
      }
      await page.mouse.move(30, viewport.height * .3);
      await page.mouse.down();
      assert.equal(await page.evaluate(() => window.rhine.stats().holdingArchive), true, 'model accepts a real pointer drag');
      await page.mouse.move(80, viewport.height * .3 + 50, { steps: 3 });
      assert(await page.evaluate(() => window.rhine.stats().dragTrack !== null), 'dragging moves the model track');
      await page.mouse.up();
      assert.equal(await page.evaluate(() => window.rhine.stats().holdingArchive), false);

    }
    assert.deepEqual(errors, []);
    await context.close();
    console.log(`PASS: direct archive entry, ${legacy ? 'legacy settings / mobile' : 'fresh settings / desktop'}`);
  }
} finally {
  await browser.close();
}
