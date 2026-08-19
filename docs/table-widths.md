# Content-measured table column widths

`filters/table-widths.lua` allocates LaTeX table column widths from the measured
content of the cells. This page states precisely what it does, what it does not do,
and how to check both claims yourself.

## What pandoc does without it

Two different things, depending on your input.

**If no source line exceeds `--columns` (default 72)**, pandoc emits no widths at all.
LaTeX sizes the table naturally, which is already content-aware — the table comes out
as wide as its content needs and is then centred, often leaving slack in the type area.

**If a source line does exceed `--columns`**, pandoc emits explicit relative widths
derived from **the number of dashes you typed in the separator row**. So:

```
|:-----------------------------------|:---------|---:|     →  0.7200 / 0.2000 / 0.0800
|:---|:---|---:|                                            →  0.3333 / 0.3333 / 0.3333
```

Identical content, different PDFs. Neither measures what is in the cells: the first
measures your ASCII art, the second is a flat split because uniform dashes carry no
signal. This is documented pandoc behaviour, not a defect — see
[jgm/pandoc#10433](https://github.com/jgm/pandoc/issues/10433) and
[#10111](https://github.com/jgm/pandoc/issues/10111), where the design is under
discussion upstream.

The practical consequence is that your source formatting becomes load-bearing, and
reformatting a table — something an editor or a formatter may do for you — silently
changes the output.

## What this filter does

Two stages, because one proportional pass is not safe:

1. **Floor.** Every column gets at least the width of its longest *unbreakable* token.
   Prose tolerates being squeezed because it rewraps at spaces. `1.234.567,89` does not:
   it contains no break opportunity, so a column narrower than that token overflows
   the rule no matter how much room exists elsewhere.

2. **Distribute.** Remaining slack is shared out in proportion to *uncovered demand* —
   the gap between what a column would naturally want and the floor it already has.
   Space goes where it still helps.

Widths are normalised to sum to 1, so the table fills the type area exactly.

If the floors alone already exceed the line, the table cannot fit at that capacity and
the filter distributes proportionally **to the floors**, which spreads the unavoidable
shortfall by relative unbreakable demand rather than starving whichever column happens
to hold the longest token.

## What it claims

- Column widths follow measured cell content, not the separator row and not an equal split.
- Source dash formatting stops affecting output.
- Tables fill the type area rather than sitting centred with slack.
- A column whose content includes a long unbreakable token gets room for it first.

## What it does not claim

**It is not a general guarantee against overflow.** If the content genuinely does not
fit the line, no allocation of widths will make it fit — you need a smaller size, a
landscape page, or fewer columns. The filter can reduce the overflow and put it in a
more sensible place; it cannot repeal arithmetic.

Measured on `examples/wide-table.md` with the stock article class:

| | widths | overfull boxes | total overflow |
|:---|:---|---:|---:|
| without the filter | 0.3333 / 0.3333 / 0.3333 | 2 | 52.8 pt |
| with the filter | 0.2965 / 0.2785 / 0.4250 | 1 | 9.3 pt |

The third column holds a thirty-one character compound with no break opportunity. An
equal split gives it a third of the line, which is not enough; the floor stage gives it
0.4250. The remaining 9.3 pt overflow is honest — that table is close to the limit of
what fits.

## Capacity

The one number you may need to set. `CAPACITY` is how many characters fit on one line
of a table, and it depends on your type area, body size and whether tables are set
smaller than body text. The default 80 is calibrated for A4, 11 pt, tables one step
down.

```
pandoc doc.md -M table-capacity=65 --lua-filter filters/table-widths.lua ...
```

Getting it wrong is not catastrophic but it does matter: too high and the floors are
under-generous, too low and the filter falls back to floor-proportional sizing earlier
than it needs to. Too low is the safer direction.

## Requirements

pandoc ≥ 2.17 and Lua 5.3+ (`utf8.len`). The filter checks the version at load time and
errors with a clear message rather than misbehaving quietly.

2.17 rather than 2.10 is deliberate. The Table AST landed in 2.10, but the *Lua* bindings
for `TableHead.rows`, `Row.cells` and `Cell.col_span` only arrived in 2.17
([jgm/pandoc#7718](https://github.com/jgm/pandoc/pull/7718)). On 2.16.2 the filter dies with
`attempt to index a nil value` as soon as it walks a row.

It is LaTeX-only and guards on `FORMAT`. Without that guard it also rewrites HTML, docx
and ODT output, where pandoc renders the widths as `<col style="width: 31%">` —
truncated rather than rounded, so they sum to 99 % and leave a visible gap.

## Prior art

- **[pantable](https://github.com/ickc/pantable)** measures content (`max characters + 3`
  per cell, normalised) but applies only to its own CSV-in-code-block syntax, not to
  pipe tables, and has no minimum-width floor — which is the stage that protects an
  unbreakable token.
- **[pandocker-lua-filters `table-width.lua`](https://github.com/pandocker/pandocker-lua-filters)**
  applies widths you supply by hand; it does not measure.
- Pandoc's own mechanism is the dash-ratio heuristic described above.

If you only need "make the table fill the line", `--columns=200` is a one-flag
alternative worth trying first: it stops pandoc emitting widths at all and lets LaTeX
size naturally. This filter is for when you want the allocation itself to follow the
content.
