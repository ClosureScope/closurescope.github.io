// Share Typst's paged math layout with HTML. The PDF path returns the original
// equation unchanged, including its labels, numbering and local show rules.
#let web-equation(it) = context {
  if target() != "html" { return it }
  // The paragraph's usual cap-height/baseline edges omit mathematical ink
  // above/below the line. Measure full bounds and the baseline with Typst.
  let ink = text(top-edge: "bounds", bottom-edge: "bounds", it)
  let full = measure(ink)
  let above = measure(text(top-edge: "bounds", bottom-edge: "baseline", it))
  let depth = calc.max(0, (full.height - above.height) / text.size)
  let visual = html.elem("span", attrs: (class: "math-visual", "aria-hidden": "true"),
    box(html.frame(ink)))
  let semantic = html.elem("span", attrs: (class: "math-semantic"),
    if it.alt != none { it.alt } else { it })
  html.elem(if it.block { "div" } else { "span" }, attrs: (
    class: "math-formula " + if it.block { "math-display" } else { "math-inline" },
    // Typst formats negative numbers with U+2212; CSS requires ASCII '-'.
    style: "vertical-align:-" + str(calc.round(depth, digits: 6)) + "em",
  ), visual + semantic)
}
