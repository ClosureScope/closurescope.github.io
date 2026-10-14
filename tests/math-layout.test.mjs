import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { test } from 'node:test';
import { chromium, firefox } from 'playwright-core';
import { scopeMathTableStyles } from '../scripts/math-styles.mjs';

// Use the real Typst exporter, including its helper CSS, rather than handwritten
// MathML that could miss export bugs such as nested matrix selector leakage.
test('Typst equations: radicals, scripts, accents, nested matrices and resizing', async () => {
  const temp = await mkdtemp(join(tmpdir(), 'blog-math-'));
  let browser;
  try {
    const fixture = join(temp, 'math.html');
    execFileSync(process.env.TYPST_BIN || 'typst', ['compile', '--features', 'html',
      'tests/fixtures/math-layout.typ', fixture], { stdio: 'pipe' });
    const exported = await readFile(fixture, 'utf8');
    const body = exported.match(/<body[^>]*>([\s\S]*)<\/body>/)[1];
    const styles = [...exported.matchAll(/<style[^>]*>[\s\S]*?<\/style>/g)].map(m => m[0]).join('');
    const article = await readFile('site/dist/posts/value-iteration/index.html', 'utf8');
    const css = article.match(/<link rel="stylesheet"[^>]*>/)[0];
    const script = article.match(/<script type="module"[^>]*><\/script>/)[0];
    const engine = process.env.MATH_BROWSER === 'firefox' ? firefox : chromium;
    browser = await engine.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('http://math.test/**', async route => {
      const path = new URL(route.request().url()).pathname;
      if (path === '/before' || path === '/after') {
        const after = path === '/after';
        await route.fulfill({ contentType: 'text/html; charset=utf-8', body:
          `<!doctype html><meta charset=utf-8>${css}${after ? scopeMathTableStyles(styles) : styles}<div class=prose style="font-size:32px">${body}</div>${after ? script : ''}` });
      } else {
        await route.fulfill({ body: await readFile(resolve('site/dist', `.${path}`)),
          contentType: path.endsWith('.js') ? 'text/javascript' : path.endsWith('.css') ? 'text/css' : 'font/woff2' });
      }
    });
    const measure = () => page.evaluate(() => {
      const math = document.querySelector('math');
      const radical = math.querySelector('msqrt');
      const ink = radical.querySelector('mi');
      const attachment = [...document.querySelectorAll('msubsup')].find(e => e.firstElementChild.textContent === '𝑉');
      const [base, sub, sup] = attachment.children;
      const brace = [...document.querySelectorAll('mover')].find(e => e.lastElementChild.textContent === '⏞');
      const nested = document.querySelector('mtable.multiline-equation mtable mtd');
      return {
        size: parseFloat(getComputedStyle(math).fontSize),
        clearance: ink.getBoundingClientRect().top - radical.getBoundingClientRect().top,
        sup: sup.getBoundingClientRect().left - base.getBoundingClientRect().right,
        sub: sub.getBoundingClientRect().left - base.getBoundingClientRect().right,
        braceCenter: (brace.lastElementChild.getBoundingClientRect().left + brace.lastElementChild.getBoundingClientRect().right
          - brace.firstElementChild.getBoundingClientRect().left - brace.firstElementChild.getBoundingClientRect().right) / 2,
        matrixGap: nested.nextElementSibling.firstElementChild.getBoundingClientRect().left - nested.firstElementChild.getBoundingClientRect().right,
        dotless: [...document.querySelectorAll('mover > mi:first-child')].map(e => e.textContent),
        fractionHeight: document.querySelector('mfrac').getBoundingClientRect().height,
        roots: [...document.querySelectorAll('msqrt, mroot')].map(e => e.getBoundingClientRect().height),
      };
    });
    await page.goto('http://math.test/before');
    await page.evaluate(() => document.fonts.ready);
    const before = await measure();
    await page.goto('http://math.test/after');
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(200);
    const after = await measure();
    assert(after.clearance >= before.clearance, 'radical clearance must not shrink');
    const inkBoxes = engine === chromium;
    if (inkBoxes) assert(after.clearance / after.size > .35, 'sqrt(x) must have Typst-like clearance');
    if (inkBoxes) assert(Math.abs(after.sup / after.size - .214) < .025, 'V superscript respects italic correction');
    if (inkBoxes) assert(Math.abs(after.sub / after.size + .1) < .025, 'V subscript respects MATH kerning');
    assert(Math.abs(after.braceCenter) < 1, 'overbrace centers over its complete base');
    assert(after.matrixGap > after.size * .2, 'nested matrix retains column spacing');
    assert(after.dotless.includes('𝚤') && after.dotless.includes('𝚥'), 'accent bases use dotless glyphs');
    if (!inkBoxes) {
      assert(Math.abs(after.sup - before.sup) < .2, 'preserve native Gecko scripts');
      assert(Math.abs(after.clearance - before.clearance) < .2, 'preserve native Gecko radicals');
    }
    assert.equal(after.fractionHeight, before.fractionHeight, 'ordinary fractions stay unchanged');
    assert(after.roots.every(height => height > 0 && Number.isFinite(height)));
    for (const size of [16, 17, 24, 32]) {
      await page.evaluate(size => { document.querySelector('.prose').style.fontSize = `${size}px`; }, size);
      await page.waitForTimeout(150);
      const current = await measure();
      if (inkBoxes) assert(Math.abs(current.sup / size - .214) < .04, `superscript at ${size}px`);
      if (inkBoxes) assert(current.clearance / size > .3, `radical at ${size}px`);
    }
    const repeated = await measure();
    assert(Math.abs(repeated.clearance - after.clearance) < .2, 'resizing does not accumulate padding');
    assert(Math.abs(repeated.sup - after.sup) < .2, 'resizing does not accumulate script corrections');
    assert.deepEqual(errors, []);
  } finally {
    await browser?.close();
    await rm(temp, { recursive: true, force: true });
  }
});
