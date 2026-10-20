import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  createMotionPreferences, fullMotion, reducedMotion, motionPresetFor,
  motionSettingsMarkup, motionSummary,
} from '../site/src/rhine/motion-preferences.ts';

test('legacy intro preferences do not change the remaining motion presets', () => {
  const full = createMotionPreferences({ boot: false }, undefined);
  assert.deepEqual(full, fullMotion());
  assert.equal(motionPresetFor(full), 'full');
  const custom = createMotionPreferences({ boot: true, selectionWave: false }, undefined);
  assert.equal(custom.selectionWave, false);
  assert.equal(motionPresetFor(custom), 'custom');
  assert.deepEqual(createMotionPreferences({ boot: true }, true), reducedMotion());
});

test('motion settings and summaries describe only current archive interactions', () => {
  for (const motion of [fullMotion(), reducedMotion()]) {
    const markup = motionSettingsMarkup(motion);
    assert(!/BOOT SEQUENCE|data-motion="boot"|重播|开场/.test(markup));
    assert(markup.includes('data-motion="selectionWave"'));
    assert(markup.includes('data-motion="documentReveal"'));
    assert(!motionSummary(motion).includes('开场'));
  }
});
