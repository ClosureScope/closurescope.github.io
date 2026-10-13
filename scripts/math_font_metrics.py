"""Read the actual vertical delimiter variants from the shipped math fonts."""
from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTFont


def delimiter_metrics(font_directory):
    result = {}
    for face in ("Book", "Bold"):
        font = TTFont(font_directory / f"NewCMMath-{face}.woff2")
        glyphs = font.getGlyphSet()
        variants = font["MATH"].table.MathVariants
        units = font["head"].unitsPerEm
        data = {}
        # Vertical fences only: horizontal accents, arrows and large operators
        # have different layout rules and must not be affected by this repair.
        for character in "()[]{}⌊⌋⌈⌉⟨⟩⟪⟫|‖∣∥⦃⦄⦅⦆⦇⦈⟦⟧⟬⟭⟮⟯⎰⎱":
            glyph = font.getBestCmap().get(ord(character))
            if glyph not in variants.VertGlyphCoverage.glyphs:
                continue
            construction = variants.VertGlyphConstruction[
                variants.VertGlyphCoverage.glyphs.index(glyph)]
            sizes = []
            for variant in construction.MathGlyphVariantRecord:
                pen = BoundsPen(glyphs)
                glyphs[variant.VariantGlyph].draw(pen)
                # Advance width, ink ascent, ink descent, all in em units.
                sizes.append([round(font["hmtx"][variant.VariantGlyph][0] / units, 6),
                              round(pen.bounds[3] / units, 6),
                              round(-pen.bounds[1] / units, 6)])
            data[character] = sizes
        result[face.lower()] = data
        font.close()
    return result
