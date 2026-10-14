"""Restore repository webfonts to OpenType for deterministic SVG compilation."""
import hashlib
from pathlib import Path
from fontTools.ttLib import TTFont

root = Path(__file__).resolve().parent.parent
source = root / 'site/public/fonts'
output = root / '.generated/typst-fonts'
output.mkdir(parents=True, exist_ok=True)
# Latin and math use Typst 0.15.1's bundled fonts. These project-specific
# fonts must also be available on CI, where the author's OS fonts do not exist.
for name in ['NotoSerifSC-variable', 'NotoSansSC-variable', 'FandolKai-Regular', 'JetBrainsMono-Regular']:
    path = source / f'{name}.woff2'
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    stamp = output / f'{name}.sha256'
    destination = output / f'{name}.otf'
    if destination.exists() and stamp.exists() and stamp.read_text() == digest:
        continue
    font = TTFont(path, recalcTimestamp=False)
    font.flavor = None
    font.save(destination)
    font.close()
    stamp.write_text(digest)
print('[fonts] Typst SVG 编译字体已从仓库资产准备完成。')
