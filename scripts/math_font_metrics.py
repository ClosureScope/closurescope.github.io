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
        info = font['MATH'].table.MathGlyphInfo
        italics = dict(zip(info.MathItalicsCorrectionInfo.Coverage.glyphs,
                           info.MathItalicsCorrectionInfo.ItalicsCorrection))
        kerns = dict(zip(info.MathKernInfo.MathKernCoverage.glyphs,
                        info.MathKernInfo.MathKernInfoRecords))
        letters = {}
        for code, name in font.getBestCmap().items():
            if name not in italics and name not in kerns:
                continue
            pen = BoundsPen(glyphs)
            glyphs[name].draw(pen)
            if not pen.bounds:
                continue
            kern = {}
            for corner, field in [('tr', 'TopRightMathKern'), ('br', 'BottomRightMathKern'),
                                  ('tl', 'TopLeftMathKern'), ('bl', 'BottomLeftMathKern')]:
                table = getattr(kerns.get(name), field, None)
                if table:
                    kern[corner] = [[v.Value / units for v in table.CorrectionHeight],
                                    [v.Value / units for v in table.KernValue]]
            letters[chr(code)] = [font['hmtx'][name][0] / units,
                                  pen.bounds[3] / units, -pen.bounds[1] / units,
                                  getattr(italics.get(name), 'Value', 0) / units, kern]
        constants = font['MATH'].table.MathConstants
        data['_layout'] = {
            'glyphs': letters,
            'radical': [getattr(constants, key).Value / units for key in
                        ['RadicalVerticalGap', 'RadicalDisplayStyleVerticalGap',
                         'RadicalRuleThickness', 'RadicalExtraAscender']],
            'horizontal': [chr(code) for code, name in font.getBestCmap().items()
                           if name in variants.HorizGlyphCoverage.glyphs],
        }
        result[face.lower()] = data
        font.close()
    return result
