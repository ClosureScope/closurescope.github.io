import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { resolve, sep } from 'node:path';
import { test } from 'node:test';
import { chromium } from 'playwright-core';

test('MathML fence spacing preserves operators, stretching and responsive layout', async () => {
  const directory = resolve('site/dist');
  const article = await readFile(resolve(directory, 'posts/value-iteration/index.html'), 'utf8');
  const css = article.match(/<link rel="stylesheet"[^>]*>/)[0];
  const script = article.match(/<script type="module"[^>]*><\/script>/)[0];
  const cases = {
    simple: '<mi>𝑓</mi><mrow><mo>(</mo><mi>𝑥</mi><mo>)</mo></mrow>',
    letters: '<mi>𝑎</mi><mi>𝑏</mi><mi>𝑐</mi>',
    scripts: '<msup><mi>𝑉</mi><mi>𝜋</mi></msup><mrow><mo>(</mo><msub><mi>𝑠</mi><mn>0</mn></msub><mo>)</mo></mrow>',
    operators: '<mi>𝑥</mi><mo>+</mo><mi>𝑦</mi><mo>=</mo><mn>1</mn>',
    fraction: '<mrow><mo>(</mo><mfrac><mi>𝑥</mi><mi>𝑦</mi></mfrac><mo>)</mo></mrow>',
    matrix: '<mrow><mo>[</mo><mtable><mtr><mtd><mn>1</mn></mtd><mtd><mn>2</mn></mtd></mtr><mtr><mtd><mn>3</mn></mtd><mtd><mn>4</mn></mtd></mtr></mtable><mo>]</mo></mrow>',
    tall: '<mrow><mo>{</mo><mspace height="6em" depth="2em"/><mo>}</mo></mrow>',
    fixed: '<mo stretchy="false">(</mo><mi>𝑥</mi><mo stretchy="false">)</mo>',
    authored: '<mo style="width:2em">(</mo><mi>𝑥</mi><mo style="width:2em">)</mo>',
  };
  cases.bold = cases.simple;
  const formulas = Object.entries(cases).map(([id, body]) =>
    `<p><math id="${id}" style="${id === 'bold' ? 'font-weight:700' : ''}">${body}</math></p>`).join('');
  const server = createServer(async (request, response) => {
    try {
      const path = new URL(request.url, 'http://localhost').pathname;
      if (path === '/before' || path === '/after') {
        response.setHeader('Content-Type', 'text/html; charset=utf-8');
        response.end(`<!doctype html><meta charset="utf-8">${css}<div class="prose" style="font-size:17px">${formulas}</div>${path === '/after' ? script : ''}`);
        return;
      }
      const file = resolve(directory, `.${path.endsWith('/') ? `${path}index.html` : path}`);
      if (!file.startsWith(directory + sep)) throw new Error('Invalid path');
      response.setHeader('Content-Type', file.endsWith('.js') ? 'text/javascript' : file.endsWith('.css') ? 'text/css' : file.endsWith('.woff2') ? 'font/woff2' : 'text/html; charset=utf-8');
      response.end(await readFile(file));
    } catch { response.writeHead(404).end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('response', response => { if (response.status() >= 400) errors.push(response.url()); });
    const base = `http://127.0.0.1:${server.address().port}`;
    const results = {};
    for (const name of ['before', 'after']) {
      await page.goto(`${base}/${name}`);
      await page.evaluate(() => document.fonts.ready);
      await page.waitForTimeout(100); // font event + ResizeObserver + animation frame
      results[name] = await page.evaluate(() => Object.fromEntries([...document.querySelectorAll('math[id]')].map(math => [math.id, {
        width: math.getBoundingClientRect().width,
        heights: [...math.querySelectorAll('mo')].map(mo => mo.getBoundingClientRect().height),
      }])));
    }
    assert(results.after.simple.width < 35, 'f(x) must not reserve oversized fences at 17px');
    for (const id of ['letters', 'operators', 'tall', 'fixed', 'authored']) {
      assert.deepEqual(results.after[id], results.before[id], `${id} must remain unchanged`);
    }
    for (const id of ['simple', 'scripts', 'fraction', 'matrix', 'bold']) {
      assert(results.after[id].width <= results.before[id].width, id);
      assert.deepEqual(results.after[id].heights, results.before[id].heights, `${id}: stretching preserved`);
    }
    await page.evaluate(() => { document.querySelector('.prose').style.fontSize = '24px'; });
    await page.waitForTimeout(100);
    const resized = await page.locator('#simple mo').first().evaluate(mo => mo.getBoundingClientRect().width);
    assert(resized > 8 && resized < 11, 'width follows changed font size');
    const posts = JSON.parse(await readFile('.generated/posts.json', 'utf8'));
    for (const width of [1280, 390]) {
      await page.setViewportSize({ width, height: 900 });
      for (const post of posts) {
        assert.equal((await page.goto(`${base}/posts/${post.slug}/`)).status(), 200);
        await page.evaluate(() => document.fonts.ready);
        await page.waitForTimeout(100);
        assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${post.slug}: page overflow`);
      }
    }
    assert.deepEqual(errors, []);
  } finally {
    await browser?.close();
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
});
