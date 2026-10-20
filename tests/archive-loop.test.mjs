import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createArchiveIndex } from '../scripts/archive-index.mjs';

const posts = [1, 2, 6, 40, 3, 9, 5].flatMap((count, lane) =>
  Array.from({ length: count }, (_, row) => ({
    slug: `column-${lane}-post-${row}`, title: `Article ${lane}/${row}`, category: `分类 ${lane}`,
  })));
globalThis.document = { querySelector: () => ({ textContent: JSON.stringify(posts) }) };
const data = await import('../site/src/rhine/data.ts');
const loop = await import('../site/src/rhine/archive-loop.ts');

test('derive any number of unequal columns and stable article identities', () => {
  const index = createArchiveIndex(posts);
  assert.equal(index.columns.length, 7);
  assert.deepEqual(index.files.map(files => files.length), [1, 2, 6, 40, 3, 9, 5]);
  assert.equal(new Set(index.locations.map(location => location.slot)).size, posts.length);
  const added = createArchiveIndex([{ slug: 'new', title: 'New', category: 'New' }, ...posts]);
  assert.equal(added.records[1].id, index.records[0].id);
  assert.deepEqual(createArchiveIndex([]).columns, []);
});

test('loop navigation, negative cells and selections beyond the old 32-row capacity', () => {
  for (let lane = -14; lane < 14; lane++) {
    const files = data.columnFiles(loop.wrap(lane - 2, data.archiveColumns.length));
    for (let row = -75; row < 75; row++) {
      const index = loop.fileAtCell({ lane, row });
      assert(files.includes(index));
      for (const direction of [-1, 1]) {
        const next = files[loop.wrap(files.indexOf(index) + direction, files.length)];
        const cell = loop.selectionCell(next, { lane, row }, { axis: 'row', direction });
        assert.equal(loop.fileAtCell(cell), next);
        assert.equal(cell.row, row + direction);
      }
    }
  }
  const last = data.columnFiles(3).at(-1);
  assert.equal(data.fileLocation(last).row, 51);
  assert.equal(data.fileAtSlot(data.fileLocation(last).slot), last);
  assert.equal(loop.fileAtCell(loop.selectionCell(last, { lane: 0, row: 12 })), last);
});

test('coordinate rebasing preserves the contents of every unequal column', () => {
  const cells = Array.from({ length: 7 }, (_, lane) => ({ lane, row: 8199 + lane }));
  const selected = cells.map(cell => loop.fileAtCell(cell));
  data.rebaseArchiveRows(8192);
  cells.forEach((cell, i) => {
    const local = { lane: cell.lane - 7, row: cell.row - 8192 };
    assert.equal(loop.fileAtCell(local), selected[i]);
    const restored = loop.selectionCell(selected[i], local);
    assert.equal(loop.fileAtCell(restored), selected[i]);
  });
  data.resetArchiveRows();
  assert.equal(data.archiveRowOrigin(), 0);
});
