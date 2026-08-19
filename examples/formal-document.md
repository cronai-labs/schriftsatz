---
title: ''
lang: en-GB
---

\renewcommand{\docimprint}{%
  \footnotesize\color{doc-secondary}%
  \begin{tabular}[b]{@{}l@{}}
  ABC Company Ltd · 1 Example Street · EX4 2MP Exampleton\\
  Directors: A. Placeholder · Reg. 00000000, Example Companies Registry
  \end{tabular}}

# Statement of account

**ABC Company Ltd**, registered in Exampleton under number 00000000
(hereinafter "the Company")

---

Every name, address, registration number and figure in this file is invented. It
exists to demonstrate the style, not to model any real organisation.

## 1. What this example shows

Three things `styles/formal.tex` provides, none of which are switched on by
default:

1. **The imprint.** Many jurisdictions require certain particulars on business
   correspondence. Redefine `\docimprint` — as this file does above — and it
   appears in the footer of every page. Leave it alone and the footer carries a
   page number and nothing else. The style ships knowing nothing about you.

2. **The `plain` page style.** Page one uses LaTeX's `plain` style whenever the
   document carries a title block. Without the mirrored definition in
   `formal.tex`, page one would silently lose the imprint while every later page
   kept it — and page one is exactly where a letter's particulars belong. That
   asymmetry is easy to ship without noticing, because the document looks fine
   unless you check page one specifically.

3. **The signature line**, below, which cannot be split by a page break.

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
