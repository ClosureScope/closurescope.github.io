import metrics from '../../../.generated/math-delimiter-metrics.json';

const namespace = 'http://www.w3.org/1998/Math/MathML';

// Keep semantic MathML. Only add a transparent box for the radicand's clearance.
export function prepareMathLayout(root) {
  for (const radical of root.querySelectorAll('msqrt, mroot')) {
    const box = document.createElementNS(namespace, 'mrow');
    box.dataset.radicand = '';
    if (radical.localName === 'msqrt') {
      while (radical.firstChild) box.append(radical.firstChild);
    } else {
      box.append(radical.firstElementChild);
    }
    radical.prepend(box);
  }
  // Blink's single-glyph math shaping bypasses the dtls GSUB feature. Use the
  // font's equivalent Unicode dotless letters; preserve explicit dotted accents.
  for (const base of root.querySelectorAll('mover[accent="true"]:not(.dotted) > mi:first-child')) {
    const dotless = { '𝑖': '𝚤', '𝑗': '𝚥', i: 'ı', j: 'ȷ' }[base.textContent];
    if (dotless) base.textContent = dotless;
  }
}

function fontData(element) {
  const style = getComputedStyle(element);
  if (!style.fontFamily.includes('New Computer Modern Math')) return null;
  return { style, size: parseFloat(style.fontSize),
    ...metrics[Number(style.fontWeight) >= 600 ? 'bold' : 'book']._layout };
}

function kernAt(glyph, corner, height, size) {
  const table = glyph?.[4]?.[corner];
  if (!table) return 0;
  const index = table[0].findIndex(limit => height < limit * size);
  return table[1][index < 0 ? table[1].length - 1 : index] * size;
}

// Reset only properties owned by this module, before measuring native layout.
export function resetMathLayout(root) {
  for (const node of root.querySelectorAll('[data-math-margin]')) {
    node.style.removeProperty('margin-left');
    delete node.dataset.mathMargin;
  }
  for (const node of root.querySelectorAll('[data-math-accent]')) {
    node.style.removeProperty('width');
    delete node.dataset.mathAccent;
  }
  for (const node of root.querySelectorAll('[data-radicand]')) node.style.removeProperty('padding-top');
}

export function repairMathLayout(root) {
  // These measurements require ink-sized token boxes (Blink). Gecko exposes
  // font line boxes instead and already handles these placements differently.
  // Probe behavior rather than browser names; never feed line boxes into an
  // ink-metric calculation.
  const probe = document.createElementNS(namespace, 'math');
  probe.style.cssText = 'position:absolute;visibility:hidden;font-family:"New Computer Modern Math";font-size:32px';
  const token = document.createElementNS(namespace, 'mi');
  token.textContent = '𝑥';
  probe.append(token);
  document.body.append(probe);
  const inkBoxes = token.getBoundingClientRect().height < 32 * .65;
  probe.remove();
  if (!inkBoxes) return;
  // Children first: a repaired script/radical changes its parent's ink height.
  const elements = [...root.querySelectorAll('msub, msup, msubsup, msqrt, mroot, mover, munder')].reverse();
  for (const element of elements) {
    const data = fontData(element);
    if (!data) continue;
    const { size, glyphs, radical, horizontal } = data;
    const base = element.firstElementChild;
    if (!base) continue;

    if (element.matches('msqrt, mroot')) {
      if (!base.hasAttribute('data-radicand')) continue;
      // Typst radical.rs distributes the unused height of the selected surd
      // above and below its radicand. Native MathML leaves it below instead.
      // Infer the surd height from its layout box, excluding the extra ascender.
      // A tall root index can inflate that box, so do not infer from those roots.
      if (element.localName === 'mroot' && element.lastElementChild.getBoundingClientRect().top < element.getBoundingClientRect().top + radical[3] * size) continue;
      const gap = radical[data.style.mathStyle === 'normal' ? 1 : 0] * size;
      const bounds = element.getBoundingClientRect();
      const content = base.getBoundingClientRect();
      const surplus = bounds.height - content.height
        - gap - (radical[2] + radical[3]) * size;
      const existing = content.top - bounds.top - gap - (radical[2] + radical[3]) * size;
      const correction = surplus / 2 - existing;
      if (correction > .5) base.style.paddingTop = `${correction}px`;
      continue;
    }

    if (element.matches('mover, munder')) {
      const accent = element.lastElementChild;
      // Single glyph accents use MATH attachment points (combining accents may
      // have zero advance). Setting their width would destroy that alignment.
      if (base.matches('mi, mn') && !base.children.length) continue;
      if (accent.localName !== 'mo' || accent.getAttribute('stretchy') === 'false'
          || accent.style.width || !horizontal.includes(accent.textContent.trim())) continue;
      const width = base.getBoundingClientRect().width;
      // Chromium reserves the unstretched width for horizontal operators.
      if (width > accent.getBoundingClientRect().width + 1.5) {
        accent.style.width = `${width}px`;
        accent.dataset.mathAccent = '';
      }
      continue;
    }

    // Simple glyph bases: don't apply an italic correction to an arbitrary
    // compound expression, operator with limits, or an author-positioned script.
    if (!base.matches('mi, mn') || base.children.length) continue;
    if (getComputedStyle(base).fontSize !== data.style.fontSize
        || getComputedStyle(base).fontWeight !== data.style.fontWeight) continue;
    const glyph = glyphs[base.textContent];
    if (!glyph) continue;
    const rect = base.getBoundingClientRect();
    const baseline = rect.top + Math.ceil(glyph[1] * size);
    for (let i = 1; i < element.children.length; i++) {
      const script = element.children[i];
      if (script.style.marginLeft || script.style.marginInlineStart) continue;
      const superscript = element.localName === 'msup' || (element.localName === 'msubsup' && i === 2);
      const scriptSize = parseFloat(getComputedStyle(script).fontSize);
      const scriptGlyph = script.matches('mi, mn') ? glyphs[script.textContent] : null;
      const bounds = script.getBoundingClientRect();
      const nearHeight = baseline - (superscript ? bounds.bottom : bounds.top);
      const farHeight = scriptGlyph
        ? (superscript ? rect.top : rect.bottom) - (bounds.top + Math.ceil(scriptGlyph[1] * scriptSize))
        : nearHeight;
      const corner = superscript ? 'tr' : 'br';
      const opposite = superscript ? 'bl' : 'tl';
      const kern = Math.max(...[nearHeight, -farHeight].map(height =>
        kernAt(glyph, corner, height, size) + kernAt(scriptGlyph, opposite, height, scriptSize)));
      const desired = (superscript ? glyph[3] * size : 0) + kern;
      const correction = desired - (bounds.left - rect.right);
      // Engines which already place the script correctly need no adjustment.
      if (Math.abs(correction) > .5) {
        script.style.marginLeft = `${correction}px`;
        script.dataset.mathMargin = '';
      }
    }
  }
}
