# XeLaTeX + Inter: minus signs that vanish or turn to mojibake when you copy them

**Status:** reproduced on TeX Live 2026 / XeTeX 3.141592653-2.6-0.999998, poppler 26.08.0, pypdf 6.x, macOS 15.
**Affects:** any XeLaTeX document set in Inter — including via the CTAN `inter` package that ships with TeX Live — and, by the same mechanism, any font whose case-sensitive punctuation is encoded in the Private Use Area.

## Summary

Inter has a `calt` (contextual alternates) feature that substitutes `.case` variants of
`minus`, `hyphen`, `parenleft` and `parenright` when they sit next to capitals or digits —
the same marks, raised to suit cap height.

Those variants are encoded, but in the **Private Use Area**. XeTeX maps them faithfully, so
the PDF's ToUnicode table says a glyph is `U+EE6B` — and `U+EE6B` means nothing to anyone.

What each extractor does with that is where it gets interesting, because **they disagree**:

- **poppler** (`pdftotext`, and everything built on it) **discards** PUA codepoints. The
  character is silently deleted. `−123,45` extracts as `123,45`.
- **pypdf** keeps them. You get `123,45` — a mojibake character sitting where a minus
  sign should be.

Both are wrong, in opposite directions, and neither reports a problem. The PDF renders
perfectly in both cases.

In a profit-and-loss statement, one extractor turns a loss into a gain and the other produces
a number no parser will read. Neither warns you.

## Reproducer

No vendored fonts, no custom style file — the CTAN `inter` package ships with TeX Live:

```latex
\documentclass{article}
\usepackage{fontspec}
\setmainfont{Inter-Regular.otf}[Numbers={Proportional,Lining}]
\begin{document}
Materialaufwand −123,45 · (§ 4 Abs. 2 MusterG, ¼) −6.789,01 · Test (Klammer) −42
\end{document}
```

```console
$ xelatex mwe.tex && pdftotext mwe.pdf -
Materialaufwand 123,45 · (§ 4 Abs. 2 MusterG, ¼ 6.789,01 · Test Klammer) 42
```

Minus signs gone; one closing and one opening parenthesis gone. Note which marks survive —
the ones *not* adjacent to a capital or a digit. That asymmetry is the tell.

## What is actually happening

Worth stating precisely, because the obvious explanation is wrong and it changes which fix
you reach for.

**It is not that the glyphs are unencoded.** They are. Reading the CTAN font directly:

```console
$ uv run --with fonttools python -c "from fontTools.ttLib import TTFont; \
    f=TTFont('Inter-Regular.otf'); r={n:c for c,n in f.getBestCmap().items()}; \
    print({g: hex(r[g]) for g in ['minus.case','minus.case.tf','parenleft.case','parenright.case']})"
{'minus.case': '0xe09e', 'minus.case.tf': '0xee6b',
 'parenleft.case': '0xe081', 'parenright.case': '0xe082'}
```

Every one of them has a cmap entry, in the Private Use Area (`U+E000`–`U+F8FF`).

**It is not that XeTeX fails to write a ToUnicode table.** It writes one, and it is accurate.
Dumping it from the unfixed PDF above:

```
34 ToUnicode entries, 3 of which map into the PUA
  glyph <05A8> -> U+EE4E
  glyph <05A9> -> U+EE4F
  glyph <0602> -> U+EE6B
```

XeTeX did its job: the glyph really is `U+EE6B` as far as the font is concerned. The
information that `U+EE6B` is *semantically* a minus sign exists only inside the font's
`calt` lookup, and a ToUnicode table has nowhere to put that.

So the defect is a **semantic** one, not an encoding failure: a correct mapping to a
codepoint that carries no meaning outside this one font.

## Four candidates, and which one is actually right

| | poppler `pdftotext` | pypdf |
|:---|:---|:---|
| unmodified | `123,45` — minus deleted | `123,45` — mojibake |
| `RawFeature={-case}` | `123,45` — deleted | `123,45` — mojibake |
| `\XeTeXgenerateactualtext=1` | `−123,45` ✓ | `123,45` — mojibake |
| **`RawFeature={-calt}`** | **`−123,45` ✓** | **`−123,45` ✓** |

Every cell is asserted by `tests/calt-mwe/run.sh`, including the failing ones.

### `RawFeature={-case}` — wrong feature

The intuitive guess, because the substituted glyphs are named `.case`. But the substitution is
driven by `calt`, not by `case`. Output is unchanged. Recorded here because it costs an hour
to rule out.

### `\XeTeXgenerateactualtext=1` — fixes one extractor, not the other

A documented XeTeX primitive whose stated purpose is better copy/paste and search. It wraps
runs in `/ActualText` spans, and poppler honours them, so `pdftotext` starts returning
`−123,45`. It is tempting to stop here: the typography is preserved, `calt` stays on, and the
cost is about 2.4 % file size.

Do not stop here. `/ActualText` is an optional hint. The ToUnicode mapping still points at
`U+EE6B`, so every consumer that does not implement `/ActualText` — pypdf among them — still
gets the mojibake. You have fixed the tool you happened to test with and left the underlying
encoding untouched.

### `RawFeature={-calt}` — the actual fix ✅

```latex
\setmainfont{Inter-Regular.otf}[Numbers={Proportional,Lining}, RawFeature={-calt}]
```

Turning `calt` off means the substitution never happens. The glyph really is `U+2212`, the
cmap entry and the ToUnicode entry both say so, and no extractor has to implement anything
optional to agree.

**Cost:** Inter's case-sensitive punctuation. Measured by rendering the same page at 300 dpi
both ways and comparing the raster: **2,106 differing bytes out of 26 MB — 0.008 % of an A4
page.** Parentheses and minus signs sit at x-height rather than cap-height beside capitals.
For a document with numbers in it, that is the right trade.

## Why switching fonts does not help

Inter is not doing anything unusual. Encoding stylistic alternates in the PUA is normal
practice, and any font with case-sensitive punctuation forms behaves the same way. The
interaction — PUA-encoded alternates plus an extractor that either drops or passes through PUA
— is a property of the pipeline, not of one typeface.

LuaLaTeX does not exhibit the problem, which is a genuine option if changing engines is on the
table.

## Scope

Anything typeset with XeLaTeX in a font with case-sensitive punctuation, where the text layer
matters — that is, anything with numbers that someone will later copy, index, parse or audit.
Financial statements are the sharp case: a dropped minus sign inverts meaning while leaving a
plausible number behind.

## Reproduce it yourself

`tests/calt-mwe/` builds all four variants and asserts the extraction result of each, under
both extractors. Run `./tests/calt-mwe/run.sh`.
