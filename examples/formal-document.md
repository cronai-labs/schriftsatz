---
title: ''
lang: en-GB
imprint:
  - ABC Company Ltd · 1 Example Street · EX4 2MP Exampleton
  - 'Directors: A. Placeholder · Reg. 00000000, Example Companies Registry'
brand:
  ink: '1A1A1A'
  secondary: '666666'
  hairline: 'D8D8D8'
---

# Statement of account

**ABC Company Ltd**, registered in Exampleton under number 00000000
(hereinafter "the Company")

---

Every name, address, registration number and figure in this file is invented. It
exists to demonstrate the style, not to model any real organisation.

Build it with:

```
schriftsatz examples/formal-document.md
```

No `--style` is needed. Declaring `imprint:` is opting in to the page furniture
that shows it, so `styles/formal.tex` is loaded automatically.

## 1. What this example shows

1. **The imprint, as data.** Many jurisdictions require certain particulars on
   business correspondence. Set `imprint:` in the front matter — as this file
   does above — and it appears in the footer of every page. Set nothing and the
   footer carries a page number and nothing else. The style ships knowing
   nothing about you.

   It used to take a hand-written `tabular` here in the Markdown, and that is
   why this is metadata now: an unescaped `%` comments out the rest of the line,
   and `&` and `_` fail obscurely. Rendered through pandoc's LaTeX writer, a
   firm called `Müller & Co.` and a rate of `19 %` come out right without anyone
   quoting anything.

   Put the same block in a file and pass `--metadata-file house-style.yaml` to
   share one identity across every document an organisation produces. The
   document's own front matter still wins over the file.

2. **Brand colours.** `brand.ink`, `brand.secondary` and `brand.hairline` set
   the three colours the style declares. The values above are the neutral greys
   that apply if you set nothing.

3. **The `plain` page style.** Page one uses LaTeX's `plain` style whenever the
   document carries a title block. Without the mirrored definition in
   `formal.tex`, page one would silently lose the imprint while every later page
   kept it — and page one is exactly where a letter's particulars belong. That
   asymmetry is easy to ship without noticing, because the document looks fine
   unless you check page one specifically.

4. **The signature line**, below, which cannot be split by a page break.

## 2. A table, for the width filter

Column widths here follow the measured content, not the number of dashes in the
separator row. The third column holds an unbreakable compound.

| Item | Basis | Classification |
|:---|:---|:---|
| Provisions recognised for onerous supply agreements | Measured at the best estimate of the obligation | Kapitalertragsteuerbescheinigung |
| Deferred consideration | Temporary differences | Umsatzsteuervoranmeldung |
| Prepayments | Insurance premiums paid in advance | Gewerbesteuermessbescheid |

## 3. Figures, for the text layer

Copy these out of the built PDF and check that the signs survive: −1,204.00 and
−6,789.01 and (a parenthesised aside) and ¼ of the total. If any of the minus
signs or brackets vanish when pasted, the font's `calt` feature is substituting
glyphs with no cmap entry — see `docs/inter-calt-tounicode.md`.

\signatureline{Exampleton, 1 January 2026}{A. Placeholder — Director}
