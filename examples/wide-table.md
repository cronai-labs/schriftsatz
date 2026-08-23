---
title: Table Width Fixture
---

# What this fixture shows

Build it with:

```
schriftsatz examples/wide-table.md
```

Every line of the table below is longer than pandoc's `--columns` default, so
pandoc emits explicit relative widths. The separator row uses uniform dashes,
which gives pandoc no content signal at all — so it falls back to an equal
split, one third per column, regardless of what is in them.

The third column holds `Kapitalertragsteuerbescheinigung`: thirty-one
characters with no space, hyphen or slash in it. TeX cannot break it. One
third of the type area is not enough room, so it runs past the rule.

Build this file with and without `filters/table-widths.lua` and compare the
`Overfull \hbox` lines in the XeLaTeX log:

```
pandoc examples/wide-table.md -s -t latex -o without.tex
pandoc examples/wide-table.md -s -t latex -o with.tex \
    --lua-filter filters/table-widths.lua
xelatex without.tex ; xelatex with.tex
grep -c 'Overfull .hbox' without.log with.log
```

Measured on pandoc 3.10.2 with the stock article class:

| | widths | overfull boxes | total overflow |
|:---|:---|---:|---:|
| without the filter | 0.3333 / 0.3333 / 0.3333 | 2 | 52.8 pt |
| with the filter | 0.2965 / 0.2785 / 0.4250 | 1 | 9.3 pt |

The filter does not make the overflow zero, and it does not promise to: this
table is genuinely close to the limit of what fits. What it does is stop the
allocation from ignoring the content. See `docs/table-widths.md` for what the
filter does and does not claim.

# The table

| Description of the position as recorded in the ledger | Commentary supplied by the preparer | Classification |
|:---|:---|:---|
| Provisions for onerous contracts arising from long-term supply agreements | Recognised in accordance with the applicable measurement basis | Kapitalertragsteuerbescheinigung |
| Deferred tax assets | Temporary differences | Umsatzsteuervoranmeldung |
