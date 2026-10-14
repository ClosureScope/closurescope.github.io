import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { typst } from '../scripts/build-posts.mjs';

test('reject successful exports that silently omit mathematical content', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'math-export-'));
  try {
    const input = join(directory, 'unsupported.typ');
    for (const expression of ['overline(x)', 'underline(x)', 'cancel(x)']) {
      await writeFile(input, `$ ${expression} $`);
      assert.throws(() => typst(['compile', '--features', 'html', input, join(directory, 'out.html')]),
        /HTML 导出丢失了数学内容/);
    }
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
