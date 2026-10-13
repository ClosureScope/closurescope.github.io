# Webfont sources

- Libertinus Serif Regular, Bold, Italic, BoldItalic and NewCMMath Book, Bold:
  [typst-assets 0.15.1](https://crates.io/crates/typst-assets/0.15.1), the same
  font assets embedded in the pinned Typst compiler. The full OTF fonts were
  converted to WOFF2 with FontTools 4.66.0 and Brotli 1.2.0, without subsetting
  or changing outlines, metrics, or OpenType MATH tables.
- `LICENSE-Typst-Fonts.txt` is the asset package's complete NOTICE, including
  Libertinus's SIL OFL and NewComputerModern's GUST license.
- Existing Noto Serif SC, Noto Sans SC, FandolKai and JetBrains Mono source
  WOFF2 files retain their accompanying licenses. Chinese source fonts match
  the local template's installed fonts. `scripts/build-fonts.py` generates
  smaller Chinese fonts from the site's text, retaining layout features and
  variable weight axes. These generated subsets are modified webfont copies;
  the source fonts and local PDF fonts are not modified.

To reproduce the Latin and math conversion after extracting the asset crate:

```python
from fontTools.ttLib import TTFont

font = TTFont("typst-assets-0.15.1/files/fonts/NewCMMath-Book.otf")
font.flavor = "woff2"
font.save("NewCMMath-Book.woff2")
```

Repeat for the other five faces. Do not substitute NewCMMath-Regular for Book:
Typst uses Book for ordinary math. Preserve the MATH table and all glyphs;
stretchy operators require glyphs that do not appear directly in article text.
