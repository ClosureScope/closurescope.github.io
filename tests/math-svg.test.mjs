import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { test } from 'node:test';
import { chromium, firefox } from 'playwright-core';
import { namespaceSvgIds } from '../scripts/svg-math.mjs';
import { typst } from '../scripts/build-posts.mjs';

const repo = resolve('.');
test('SVG math preserves the PDF output', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'svg-pdf-'));
  try {
    const wrapped = join(dir, 'wrapped.typ');
    await writeFile(wrapped, `#import "${repo}/typst/web-math.typ": web-equation\n#show math.equation: web-equation\n#include "${repo}/tests/fixtures/math-layout.typ"`);
    const args = ['compile', '--root', '/', '--creation-timestamp', '0'];
    typst([...args, 'tests/fixtures/math-layout.typ', join(dir, 'original.pdf')]);
    typst([...args, wrapped, join(dir, 'wrapped.pdf')]);
    assert.deepEqual(await readFile(join(dir, 'original.pdf')), await readFile(join(dir, 'wrapped.pdf')));
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('SVG formulas: baseline, scaling, references, copy, no JS and mobile overflow', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'svg-browser-'));
  let browser;
  try {
    const destination = join(dir, 'fixture.html');
    typst(['compile', '--root', repo, '--features', 'html', 'tests/fixtures/svg-math.typ', destination]);
    const exported = await readFile(destination, 'utf8');
    const body = namespaceSvgIds(exported.match(/<body[^>]*>([\s\S]*)<\/body>/)[1]);
    const article = await readFile('site/dist/posts/value-iteration/index.html', 'utf8');
    const css = article.match(/<link rel="stylesheet"[^>]*>/)[0];
    const script = article.match(/<script type="module"[^>]*>[\s\S]*?<\/script>/)[0];
    const engine = process.env.MATH_BROWSER === 'firefox' ? firefox : chromium;
    browser = await engine.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
    const context = await browser.newContext();
    await context.route('http://math.test/**', async route => {
      const path = new URL(route.request().url()).pathname;
      if (path === '/fixture') {
        return route.fulfill({ contentType: 'text/html; charset=utf-8', body:
          `<!doctype html><meta charset=utf-8>${css}<article><div class=prose>${body}</div></article>${script}` });
      }
      const file = resolve('site/dist', `.${path.endsWith('/') ? path + 'index.html' : path}`);
      await route.fulfill({ body: await readFile(file), contentType: file.endsWith('.js') ? 'text/javascript' : file.endsWith('.css') ? 'text/css' : file.endsWith('.woff2') ? 'font/woff2' : 'text/html; charset=utf-8' });
    });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.goto('http://math.test/fixture');
    await page.evaluate(() => document.fonts.ready);
    const check = () => page.evaluate(() => {
      const formulas = [...document.querySelectorAll('.math-formula')];
      const ids = [...document.querySelectorAll('[id]')].map(e => e.id);
      const broken = [...document.querySelectorAll('svg use')].filter(e => {
        const id = (e.getAttribute('href') || e.getAttribute('xlink:href')).slice(1);
        return !e.closest('svg').querySelector(`[id="${id}"]`);
      });
      const baseline = [...document.querySelectorAll('p')].filter(p => p.textContent.startsWith('Baseline')).map(p => {
        const formula = p.querySelector('.math-inline');
        const marker = document.createElement('span');
        marker.style.cssText = 'display:inline-block;width:0;height:0';
        formula.after(marker);
        const target = marker.getBoundingClientRect().top;
        const svg = formula.querySelector('svg').getBoundingClientRect();
        const depth = parseFloat(getComputedStyle(formula).verticalAlign);
        marker.remove();
        return svg.bottom + depth - target;
      });
      return { count: formulas.length, svgs: formulas.filter(f => f.querySelector('svg')).length,
        duplicates: ids.length - new Set(ids).size, broken: broken.length,
        overflow: document.documentElement.scrollWidth > innerWidth, baseline,
        scrollable: formulas.some(f => { const v = f.querySelector('.math-visual'); return v.scrollWidth > v.clientWidth + 1; }),
        width: document.querySelector('.math-visual svg').getBoundingClientRect().width,
        references: [...document.querySelectorAll('a[href^="#svg-"]')].map(a => a.textContent),
        visibleMath: [...document.querySelectorAll('math')].some(m => !m.closest('.math-semantic')),
      };
    });
    const initial = await check();
    assert(initial.count > 15 && initial.svgs === initial.count);
    assert.equal(initial.duplicates, 0);
    assert.equal(initial.broken, 0);
    assert.equal(initial.visibleMath, false);
    assert.deepEqual(initial.references, ['Equation\u00a01', 'Equation\u00a02']);
    for (const width of [1280, 390]) {
      await page.setViewportSize({ width, height: 900 });
      for (const size of [16, 17, 24, 32]) {
        await page.evaluate(size => { document.querySelector('article').style.fontSize = `${size}px`; }, size);
        const result = await check();
        assert(!result.overflow, `${width}/${size}: no page overflow`);
        assert(result.scrollable, 'long equations scroll without shrinking their glyphs');
        assert(result.baseline.every(delta => Math.abs(delta) < .15), `baseline ${width}/${size}: ${result.baseline}`);
        assert(Math.abs(result.width / size - initial.width / 17) < .02, 'formula scales in em');
      }
    }
    await page.evaluate(() => {
      Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async text => { window.copiedMath = text; } } });
    });
    await page.locator('.math-inline').first().dispatchEvent('pointerdown', { pointerType: 'touch' });
    assert(await page.locator('.math-inline .math-copy').first().evaluate(button => document.activeElement === button), 'touch reveals inline copy');
    await page.locator('.math-copy').first().focus();
    await page.locator('.math-copy').first().click();
    assert.match(await page.evaluate(() => window.copiedMath), /^<math[^>]*xmlns="http:\/\/www.w3.org\/1998\/Math\/MathML"/);
    await page.evaluate(() => { navigator.clipboard.writeText = async () => { throw new Error('denied'); }; });
    await page.locator('.math-copy').first().click();
    await page.locator('dialog[open]').waitFor();
    assert.match(await page.locator('dialog textarea').inputValue(), /<msqrt>/);
    await page.keyboard.press('Escape');
    await page.locator('dialog').waitFor({ state: 'detached' });

    const posts = JSON.parse(await readFile('.generated/posts.json', 'utf8'));
    for (const width of [1280, 390]) {
      await page.setViewportSize({ width, height: 900 });
      for (const post of posts) {
        await page.goto(`http://math.test/posts/${post.slug}/`);
        await page.evaluate(() => document.fonts.ready);
        const result = await check();
        assert(!result.overflow, post.slug);
        assert.equal(result.duplicates, 0, post.slug);
        assert.equal(result.broken, 0, post.slug);
      }
    }
    await context.close();
    const noJS = await browser.newContext({ javaScriptEnabled: false });
    await noJS.route('**/*', async route => {
      const path = new URL(route.request().url()).pathname;
      if (path === '/') return route.fulfill({ contentType: 'text/html', body: `<!doctype html><meta charset=utf-8>${css}<article><div class=prose>${body}</div></article>` });
      await route.fulfill({ body: await readFile(resolve('site/dist', `.${path}`)), contentType: path.endsWith('.css') ? 'text/css' : 'font/woff2' });
    });
    const plain = await noJS.newPage();
    await plain.goto('http://math.test/');
    assert(await plain.locator('.math-visual svg').first().isVisible(), 'SVG remains visible without JS');
    assert.equal(await plain.locator('.math-copy').count(), 0);
    assert.deepEqual(errors, []);
  } finally {
    await browser?.close();
    await rm(dir, { recursive: true, force: true });
  }
});
