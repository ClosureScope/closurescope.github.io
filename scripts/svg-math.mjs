// Typst's independently exported frames reuse glyph IDs. Give each SVG its own
// ID namespace before embedding several frames in one HTML document. Handle
// nested SVGs as part of the outer frame; preserve links to document anchors.
export function namespaceSvgIds(html) {
  let depth = 0;
  let start = 0;
  let cursor = 0;
  let index = 0;
  let output = '';
  for (const token of html.matchAll(/<\/?svg\b[^>]*>/g)) {
    if (!token[0].startsWith('</')) {
      if (depth++ === 0) start = token.index;
    } else if (--depth === 0) {
      const end = token.index + token[0].length;
      const svg = html.slice(start, end);
      const prefix = `formula-${index++}-`;
      const ids = new Set([...svg.matchAll(/\bid="([^"]+)"/g)].map(m => m[1]));
      const scoped = svg.replace(/\bid="([^"]+)"/g, (_, id) => `id="${prefix}${id}"`)
        .replace(/((?:xlink:)?href=")#([^"]+)"/g,
          (match, attr, id) => ids.has(id) ? `${attr}#${prefix}${id}"` : match)
        .replace(/url\(#([^)]*)\)/g,
          (match, id) => ids.has(id) ? `url(#${prefix}${id})` : match);
      output += html.slice(cursor, start) + scoped;
      cursor = end;
    }
  }
  if (depth !== 0) throw new Error('Unbalanced SVG in Typst HTML');
  return output + html.slice(cursor);
}
