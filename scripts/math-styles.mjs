// Typst 0.15.1 uses descendant selectors here. In a multiline equation they
// also match cells of nested matrices, erasing column spacing and script style.
export function scopeMathTableStyles(styles) {
  return styles
    .replace(/(mtable(?:\.[\w-]+)?) mtr([^{}]*?) mtd/g, '$1 > mtr$2 > mtd')
    .replace(/(mtable(?:\.[\w-]+)?) mtd/g, '$1 > mtr > mtd');
}
