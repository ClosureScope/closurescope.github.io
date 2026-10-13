import metrics from '../../../.generated/math-delimiter-metrics.json';

// Chromium reserves the widest variant's advance for every stretchy fence,
// even when it paints the smallest glyph. Keep native stretching, but size the
// box from the variant it actually painted. See mathml.igalia.com/project/.
export function repairMathSpacing(root) {
  if (!root) return;
  const repaired = new Set();
  let scheduled = false;

  function repair() {
    scheduled = false;
    // Re-measure native layout after a font-size/viewport change. Only undo
    // widths set here; authored MathML widths and stretchy=false stay intact.
    for (const operator of repaired) operator.style.removeProperty('width');
    repaired.clear();
    const updates = [];
    for (const operator of root.querySelectorAll('math mo')) {
      if (operator.getAttribute('stretchy')?.toLowerCase() === 'false'
          || operator.style.width || operator.style.inlineSize) continue;
      const style = getComputedStyle(operator);
      if (!style.fontFamily.includes('New Computer Modern Math')) continue;
      const variants = metrics[Number(style.fontWeight) >= 600 ? 'bold' : 'book'][operator.textContent.trim()];
      if (!Array.isArray(variants) || !variants.length) continue;
      const fontSize = parseFloat(style.fontSize);
      const bounds = operator.getBoundingClientRect();
      if (!fontSize || !bounds.height) continue;

      // Chromium rounds the glyph's ascent and descent up independently.
      // Match the measured height to those ink metrics, not to the height of
      // the surrounding expression (which also contains scripts and spacing).
      let match;
      let error = Infinity;
      for (const [width, ascent, descent] of variants) {
        const difference = Math.abs(bounds.height - (Math.ceil(ascent * fontSize) + Math.ceil(descent * fontSize)));
        if (difference < error || (difference === error && width > match?.[0])) {
          match = [width, ascent, descent];
          error = difference;
        }
      }
      // Do not guess for assembled extra-tall delimiters or other engines'
      // unmatched metrics. Correct browsers already have the right width.
      if (error > 1 || bounds.width <= match[0] * fontSize + 1.5) continue;
      updates.push([operator, `${match[0]}em`]);
    }
    for (const [operator, width] of updates) {
      operator.style.width = width;
      repaired.add(operator);
    }
  }

  function schedule() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(repair);
  }

  // Measurements made with a fallback font must never become permanent.
  document.fonts.ready.then(() => {
    schedule();
    new ResizeObserver(schedule).observe(root);
    window.addEventListener('resize', schedule, { passive: true });
    document.fonts.addEventListener('loadingdone', schedule);
  });
}
