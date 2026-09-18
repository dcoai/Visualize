# Axes and Formatting

**Status:** Implemented

`Visualize.Axis` builds a reference axis — domain line, tick marks, and labels — for any scale that implements `ticks/2` and `apply/2`, returning a backend-neutral `Visualize.IR.Element` group that `Visualize.Render` serialises. `Visualize.Format` supplies the label formatters an axis (or any chart text) uses: grouped numbers, SI prefixes, percentages, currency, exponential and fixed notation, a D3-style specifier parser, and a strftime-like date formatter. Sizes are in user units (pixels under SVG).

## 1. `Visualize.Axis`

### 1.1 Struct

```
%Visualize.Axis{
  scale: nil, orient: :bottom,
  ticks: nil, tick_values: nil, tick_format: nil,
  tick_size_inner: 6, tick_size_outer: 6, tick_padding: 3, offset: 0,
  theme: nil
}
```

`theme` is a `Visualize.Theme` ([08-utilities](08-utilities.md) §7) or `nil`, which stands for `Visualize.Theme.default/0`. `orient` is one of `:top`, `:right`, `:bottom`, `:left`. The four constructors each take a scale struct and set the orientation. The scale MUST implement `Visualize.Scale.Behaviour` (spec/03 §1.3) and its `apply/2` MUST return a number: every continuous scale (`Linear`, `Log`, `Power`, `Symlog`, `Time`) and the two discrete position scales (`Band`, `Ordinal` with a numeric range) qualify. The discretising scales and `Color` map values to range *elements*, not positions, so an axis on them is a caller error (`ArithmeticError` at the tick offset).

### 1.2 Setters

| Setter | Constraint | Effect |
|---|---|---|
| `ticks/2` | integer | tick-count hint passed to `Scale.ticks/2`; ignored when `tick_values` is set |
| `tick_values/2` | list | explicit tick values; bypasses the scale's `ticks/2` |
| `tick_format/2` | 1-arity function | maps a tick value to its label string |
| `tick_size_inner/2` | number | length of each tick line |
| `tick_size_outer/2` | number | length of the domain line's end caps |
| `tick_size/2` | number | sets inner and outer together |
| `tick_padding/2` | number | gap between tick line end and label |
| `offset/2` | number | added to every tick position (for crisp half-pixel alignment) |
| `theme/2` | `%Visualize.Theme{}` | the theme the axis's colours, font and size resolve from (1.4) |

### 1.3 Orientation Parameters

| Orient | `k` | Tick axis | Tick group transform | `text-anchor` |
|---|---|---|---|---|
| `:top` | `−1` | x | `translate(pos, 0)` | `:middle` |
| `:bottom` | `+1` | x | `translate(pos, 0)` | `:middle` |
| `:left` | `−1` | y | `translate(0, pos)` | `:end` |
| `:right` | `+1` | y | `translate(0, pos)` | `:start` |

`k` is the direction multiplier: ticks extend away from the plot area. `pos = Scale.apply(scale, value) + offset + c`, where `c = max(0, bandwidth − 2·offset) / 2` is d3-axis's band centring — `bandwidth` from `Visualize.Scale.bandwidth/1`, so `0` on every scale but `Band` — rounded when the band scale rounds (D-23).

### 1.4 Element Structure

`generate/1,2` returns:

```
group  style: %{fill: :none, font_size: <font_size>, font_family: <font_family>, text_anchor: <1.3>}, attrs: %{aria_hidden: "true"}
├── path   style: %{stroke: <axis>}                   — the domain line
└── group  style: %{class: "tick"}, transform: <1.3>  — one per tick value
    ├── line  attrs: %{x1: 0, y1: 0, x2: …, y2: …}, style: %{stroke: <axis>}
    └── text  attrs: %{x | y, dy}, style: %{fill: <text>}, content: label
```

`<axis>`, `<text>`, `<font_size>` and `<font_family>` are `Visualize.Theme.resolve/3` of the axis's theme for the slots of those names ([08-utilities](08-utilities.md) §7.1), in the mode of the `:resolve` option of `generate/2` — `:css` by default, so an SVG axis reads `stroke="var(--vis-axis, #666666)"` and a consumer restyles it in CSS; `:literal` gives a canvas the plain values. Nothing in an axis is `currentColor` any more (D-55). The group's `aria_hidden` attr renders as `aria-hidden="true"` (D-56): an axis is decoration a screen reader skips, the chart's `<title>` and `<desc>` carrying its meaning.

Domain line path, with `[r0, r1]` the scale's range and `o = tick_size_outer`:

- `:top`/`:bottom`: `M r0,k·o  V 0  H r1  V k·o`
- `:left`/`:right`: `M k·o,r0  H 0  V r1  H k·o`

The range is read from `scale.range`, a two-element list in every position scale (spec/03 §1.2); a struct without one falls back to `[0, 1]`.

Tick line: `:top`/`:bottom` from `(0, 0)` to `(0, k·inner)`; `:left`/`:right` from `(0, 0)` to `(k·inner, 0)`.

Tick label attributes, with `i = tick_size_inner`, `p = tick_padding`:

| Orient | Attributes |
|---|---|
| `:top` | `y: k·(i + p)` (`−9` at defaults), `dy: "0em"` |
| `:bottom` | `y: k·i + p` (`9`), `dy: "0.71em"` |
| `:left` | `x: k·i − p` (`−9`), `dy: "0.32em"` |
| `:right` | `x: k·i + p` (`9`), `dy: "0.32em"` |

Every label therefore sits `i + p` beyond the tick, away from the plot, as in d3-axis (D-23). The rendered SVG of every orientation over a linear, a band and a rounded band scale is recorded in `test/support/axis_golden.txt`.

### 1.5 Tick Values and Labels

Tick values are `tick_values` when set, else `Scale.ticks(scale, ticks || 10)`. For a `Band` or `Ordinal` scale that is the domain. On a `Band` scale each tick is centred in its band by the `c` term of 1.3, so `offset/2` is only the pixel offset; on every other scale the tick sits at `apply/2` (D-23).

Default label (no `tick_format`): floats are rounded to 6 decimal places and printed in plain decimal notation with trailing zeros and a trailing `.` removed (`2.0 → "2"`, `0.1 + 0.2 → "0.3"`, `1000.0 → "1000"`, `0.00001 → "0.00001"`) — never in exponent form, and never `-0` (#354; the rule of `Visualize.IR.Path.format_number/1`, D-12, at six decimals); any other value is `to_string/1` (`DateTime` therefore prints ISO 8601). A custom formatter receives the raw tick value.

### 1.6 Rendering

`render/1,2` is `generate/2` followed by `Visualize.Render.to_string/2` with the same options. `:backend` is `:svg`, `:canvas`, or a backend module; when omitted the configured default (`config :visualize, default_backend:`, itself defaulting to `:svg`) applies. `:resolve` is the theme mode of 1.4; when omitted it is `Visualize.Theme.mode/1` of the backend, so an SVG axis carries CSS references and a canvas axis literals without the caller saying so. Other options pass through to the backend.

### 1.7 Functions

| Function | Contract |
|---|---|
| `Visualize.Axis.top/1` | Creates an axis with `orient: :top` for the scale. |
| `Visualize.Axis.bottom/1` | Creates an axis with `orient: :bottom`. |
| `Visualize.Axis.left/1` | Creates an axis with `orient: :left`. |
| `Visualize.Axis.right/1` | Creates an axis with `orient: :right`. |
| `Visualize.Axis.ticks/2` | Sets the tick-count hint (integer). |
| `Visualize.Axis.tick_values/2` | Sets explicit tick values (list). |
| `Visualize.Axis.tick_format/2` | Sets the 1-arity label formatter. |
| `Visualize.Axis.tick_size_inner/2` | Sets the tick line length (default 6). |
| `Visualize.Axis.tick_size_outer/2` | Sets the domain-line end-cap length (default 6). |
| `Visualize.Axis.tick_size/2` | Sets both tick sizes. |
| `Visualize.Axis.tick_padding/2` | Sets the tick-to-label gap (default 3). |
| `Visualize.Axis.offset/2` | Sets the position offset added to every tick (default 0). |
| `Visualize.Axis.theme/2` | Sets the theme (default `nil`, meaning `Visualize.Theme.default/0`). |
| `Visualize.Axis.generate/1` | As `generate/2` with `resolve: :css`. |
| `Visualize.Axis.generate/2` | Returns the `IR.Element` group described in 1.4, its theme slots resolved in the `:resolve` mode. |
| `Visualize.Axis.render/1` | As `render/2` with `[]` options. |
| `Visualize.Axis.render/2` | Renders `generate/1` through `Visualize.Render.to_string/2`; returns a string. |

## 2. `Visualize.Format`

### 2.1 `number/1,2`

Options: `:precision` (decimal places; default automatic), `:separator` (thousands, default `","`), `:decimal` (decimal point, default `"."`).

- Integer input: no fraction unless `:precision` is given, in which case that many `"0"`s.
- Float input: automatic precision is `0` for `|v| ≥ 100`, `1` for `≥ 10`, `2` for `≥ 1`, else `3`. The value is rounded to the precision; the fraction is padded/truncated to exactly `precision` digits; `precision: 0` yields no fraction.
- The integer part is grouped in threes from the right.

The magnitude is grouped and the sign prepended afterwards (`−123456 → "-123,456"`, `−0.5 → "-0.500"`); a negative whose magnitude rounds to all zeros at the precision has no sign (`number(−0.0001, precision: 2) → "0.00"`) (D-24).

### 2.2 `si/1,2`

Option `:precision` — significant digits, default `3`. `0 → "0"`. The prefix is the largest whose threshold is `≤ |v|` from the table; values below `1e−24` use no prefix. The mantissa shows `precision − intdigits` decimals (never negative) when `≥ 1`, else `precision − 1` decimals. Sign is preserved.

| Threshold | Prefix |
|---|---|
| `1e24` | `Y` |
| `1e21` | `Z` |
| `1e18` | `E` |
| `1e15` | `P` |
| `1e12` | `T` |
| `1e9` | `G` |
| `1e6` | `M` |
| `1e3` | `k` |
| `1e0` | (none) |
| `1e−3` | `m` |
| `1e−6` | `µ` (U+00B5) |
| `1e−9` | `n` |
| `1e−12` | `p` |
| `1e−15` | `f` |
| `1e−18` | `a` |
| `1e−21` | `z` |
| `1e−24` | `y` |

### 2.3 `percent/1,2`

Options: `:precision` (decimal places, default `1`), `:multiply` (default `true`; multiply by 100 before formatting). Output is the fixed-decimal value followed by `"%"`.

### 2.4 `exponential/1,2`

Option `:precision` (default `2`): Erlang scientific notation with that many decimals, e.g. `1234 → "1.23e3"`.

### 2.5 `fixed/2`

`fixed(value, precision)` — no default; fixed decimal places via `:erlang.float_to_binary/2`. Integers are accepted and coerced.

### 2.6 `currency/1,2`

Options `:symbol` (default `"$"`), `:precision` (default `2`). Output is `sign <> symbol <> number(|v| rounded, precision: precision)`; the sign precedes the symbol (`"-$1,234.50"`).

### 2.7 `formatter/1`

`formatter(specifier)` parses a d3-format specifier and returns a 1-arity formatter; the parser and the formatting pipeline are d3-format's (D-24). The grammar is

```
[[fill]align][sign][symbol][0][width][,][.precision][~][type]
```

matched by d3's regular expression `^(?:(.)?([<>=^]))?([+\-( ])?([$#])?(0)?(\d+)?(,)?(\.\d+)?(~)?([a-z%])?$` (case-insensitive). A string it does not match raises `ArgumentError`.

| Part | Values | Default |
|---|---|---|
| `fill` | any one character, only with `align` | space |
| `align` | `>` right, `<` left, `^` centre, `=` after sign and symbol | `>` |
| `sign` | `-` minus for negatives, `+` plus or minus, `(` parentheses for negatives, space for positives | `-` |
| `symbol` | `$` currency prefix `"$"`; `#` prefix `0b`/`0o`/`0x` for types `b`/`o`/`x`/`X` | none |
| `0` | zero padding: `fill = "0"`, `align = "="` | off |
| `width` | minimum length of the whole output | none |
| `,` | group thousands with `","` | off |
| `.precision` | digits after the point for `e`, `f`, `%`; significant digits for `g`, `r`, `s`, `p`; ignored by the integer types | `6`; `12` with no type |
| `~` | trim insignificant trailing zeros (and a bare point), stopping at an exponent | off |
| `type` | below | none |

`n` is `,g`. No type (or an unrecognised letter) is `~g` with default precision `12`, so `formatter("").(1234.5)` is `"1234.5"` and `formatter("").(0.1 + 0.2)` is `"0.3"`. Significant precision is clamped to `[1, 21]`, fixed precision to `[0, 20]`.

Types, applied to the magnitude `|v|` (JavaScript's number methods are named where the output must match them):

| Type | Output |
|---|---|
| `e` | `toExponential(p)`: `d.ddde+X`, exponent unpadded with an explicit sign (`1234 → "1.23e+3"` at `.2e`) |
| `f` | `toFixed(p)` |
| `g` | `toPrecision(p)`: exponential when the decimal exponent is `< −6` or `≥ p`, else fixed with `p` significant digits |
| `r` | `p` significant digits in plain notation, zero-filled (`12345 → "12000"` at `.2r`) |
| `s` | the mantissa for the SI prefix of the thousands exponent (multiples of 3 in `[−24, 24]`), `p` significant digits across mantissa and prefix (`1234567 → "1.2M"` at `.2s`); the prefix letter is appended after the number |
| `%` | `f` of `100·v` with `"%"` appended |
| `p` | `r` of `100·v` with `"%"` appended |
| `d` | the integer nearest `|v|` (halves up), base 10 |
| `b`, `o`, `x`, `X` | that integer in base 2, 8, 16 lower-case, 16 upper-case |
| `c` | `to_string/1` of the value, no sign handling |

Then, as d3's `format`: a negative whose formatted magnitude is all zeros shows no sign unless `+` was requested; the sign is an ASCII `-` (d3's locale default is U+2212; the rest of this module uses `-`); grouping applies to the integer digits before the point or exponent — before padding, or after padding and limited to `width` when the fill is `0` (`"012,d"` of `1234567` is `"0,001,234,567"`); padding to `width` uses `fill`; `^` splits the padding with the smaller half on the left; `=` puts it after the sign and symbol. A non-number formats as `"NaN"`, padded like any other value. The reference table, from d3-format's documentation and implementation, is in `test/visualize/axis_format_test.exs`.

`exponential/2` keeps Erlang's exponent form (`"1.23e3"`, 2.4); only the parser follows JavaScript's.

### 2.8 `time/1,2`

`time(value, format \\ "%Y-%m-%d")` accepts `DateTime`, `Date`, or `NaiveDateTime`. The format is tokenised in one pass: `%` followed by one character is a directive, everything else is literal, so a directive's output is never re-scanned (`"%%Y"` is the text `%Y`). A `%` at the end of the format is literal. An unknown directive passes through verbatim (`"%Q" → "%Q"`) (D-25).

| Directive | Value |
|---|---|
| `%Y` | four-digit year, zero-padded |
| `%y` | two-digit year |
| `%m` | month `01`–`12` |
| `%d` | day of month `01`–`31` |
| `%e` | day of month, space-padded to two |
| `%j` | day of year `001`–`366` |
| `%H` | hour `00`–`23` |
| `%I` | hour `01`–`12` (`12` at midnight and noon) |
| `%M` | minute `00`–`59` |
| `%S` | second `00`–`60` |
| `%L` | milliseconds `000`–`999` (the microsecond field ÷ 1000) |
| `%p` | `AM` for hours `0`–`11`, else `PM` |
| `%a`, `%A` | abbreviated and full English weekday name |
| `%b`, `%B` | abbreviated and full English month name |
| `%U` | week of the year with Sunday as the first day, `00`–`53` (days before the first Sunday are week `00`) |
| `%w` | weekday as a number, Sunday `0` … Saturday `6` |
| `%Z` | `zone_abbr` of a `DateTime`; empty for the other structs |
| `%z` | `+hhmm`/`-hhmm` from a `DateTime`'s `utc_offset + std_offset`; empty for the other structs |
| `%%` | a literal `%` |

A `Date` has hour, minute, second and milliseconds `0`. Fields are printed as stored; no conversion between zones takes place.

### 2.9 Functions

| Function | Contract |
|---|---|
| `Visualize.Format.number/1` | As `number/2` with `[]` options. |
| `Visualize.Format.number/2` | Thousands-grouped number with optional fixed precision (2.1). |
| `Visualize.Format.si/1` | As `si/2` with 3 significant digits. |
| `Visualize.Format.si/2` | SI-prefixed number (2.2); `value` MUST be a number. |
| `Visualize.Format.percent/1` | As `percent/2` with defaults (1 decimal, ×100). |
| `Visualize.Format.percent/2` | Percentage string (2.3). |
| `Visualize.Format.exponential/1` | As `exponential/2` with 2 decimals. |
| `Visualize.Format.exponential/2` | Scientific notation (2.4). |
| `Visualize.Format.fixed/2` | Fixed decimal places (2.5). |
| `Visualize.Format.currency/1` | As `currency/2` with `"$"` and 2 decimals. |
| `Visualize.Format.currency/2` | Currency string (2.6). |
| `Visualize.Format.formatter/1` | Parses a d3-format specifier and returns a formatter function (2.7); raises `ArgumentError` on an invalid one. |
| `Visualize.Format.time/1` | As `time/2` with format `"%Y-%m-%d"`. |
| `Visualize.Format.time/2` | One-pass strftime-style formatting of a date/time struct (2.8). |
