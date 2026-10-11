# Axes and Formatting

**Status:** Implemented

`Visualize.Axis` builds a reference axis — domain line, tick marks, and labels — for any scale that implements `ticks/2` and `apply/2`, returning a backend-neutral `Visualize.IR.Element` group that `Visualize.Render` serialises. `Visualize.Format` supplies the label formatters an axis (or any chart text) uses: grouped numbers, SI prefixes, percentages, currency, exponential and fixed notation, a D3-style specifier parser, and a strftime-like date formatter. `Visualize.Unit` and `Visualize.Quantity` name units by their UCUM codes and scale a value into the unit that fits it (§4). Sizes are in user units (pixels under SVG).

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

Default label (no `tick_format`): floats are rounded to 6 decimal places and printed in plain decimal notation with trailing zeros and a trailing `.` removed (`2.0 → "2"`, `0.1 + 0.2 → "0.3"`, `1000.0 → "1000"`, `0.00001 → "0.00001"`) — never in exponent form, and never `-0` (#354; the rule of `Visualize.IR.Path.format_number/1`, D-12, at six decimals); any other value is `to_string/1` (`DateTime` therefore prints ISO 8601). A custom formatter receives the raw tick value. These are the hand-built axis's defaults; the declarative layer's axis derives both, as follows.

`Visualize.Axis` keeps d3-axis's defaults — ten ticks, the default label of 1.5 — so an axis built by hand is d3's axis. The declarative layer's axis derives its count from its length (below) and its format from its scale's domain (§3) where the design gives neither (spec/14 §4.4, D-134); a caller building an axis by hand gets the same result with `ticks(Visualize.Axis.tick_count(length, orient))` and `tick_format(Visualize.Format.Auto.formatter(scale, count: count))`.

**Tick count from the length.** `tick_count(length, orient)` is the tick-count hint an axis `length` pixels long asks for: `⌊|length| / spacing⌋`, at least `2` and at most `10`. The spacing is Observable Plot's: `80` px a tick across a `:top` or `:bottom` axis, whose labels sit side by side and are as wide as their text, and `35` px down a `:left` or `:right` one, whose labels stack a line apart. So a 600 px wide x axis asks for 7 ticks, a 240 px one for 3, and a 300 px tall y axis for 8; ten, d3's default, is the cap, reached at 800 px across and 350 px down. The count is a hint (spec/03): a scale returns the nice ticks nearest it.

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
| `Visualize.Axis.tick_count/2` | `⌊length / spacing⌋` in `2..10`, spacing `80` across, `35` down (1.5). |

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

**Formatting in a scale's zone** (#447). `time/2` prints a `DateTime` in the zone it carries, so a zoned time scale's labels read local time without `time/2` knowing about scales: the scale's `ticks/2` and `invert/2` return `DateTime` values in its zone ([03-scales](03-scales.md) §7.4), and `%H`, `%d`, `%Z` and `%z` print that zone's wall clock, abbreviation and offset (`"%H:%M %Z"` gives `01:00 EDT` and then `01:00 EST` across the fall-back hour). A value that did not come from the scale — an explicit tick value, a UTC `DateTime` from the data — is shifted into the scale's zone by `Visualize.Scale.Time.local/2` before it is formatted, which is what the declarative layer's axis does for every tick of a time scale (spec/14 §4.4). A scale without a zone leaves every value as it is, so its labels are unchanged.

### 2.9 `duration/1`

`duration(seconds)` prints a length of time in the unit its magnitude chooses (#191) — the one thing a fixed specifier cannot express. The units are `d` (86400 s), `h` (3600), `m` (60), `s` and `ms`. The largest unit the value reaches is taken: a whole count prints as it is (`45s`, `2m`, `1h`, `3d`); a count whose remainder is whole in the next finer unit prints both (`2m30s`, `1h30m`, `1d1h`) — among `d`, `h`, `m` and `s` only, seconds never pairing with milliseconds; any other prints the count to one decimal with a trailing zero trimmed (`1.5h` for 5430 s, `2.5s`, `0.5ms`). Below one second the unit is `ms`; zero is `0s`; a negative value is the positive one with a leading `−`. The value MUST be a number.

### 2.10 Functions

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
| `Visualize.Format.duration/1` | A length of time in seconds in the unit its magnitude chooses (2.9). |

## 3. `Visualize.Format.Auto`

### 3.1 Derived formats

`Visualize.Format.Auto` derives a tick format from what a realised scale already knows — its domain and the tick count — so no host computes it (#532, D-134). Each function takes `locale:`, a locale name, `"en"` by default; `"en"` is the only one that ships, and any other raises `ArgumentError` naming it, so adding a locale later changes no signature. A locale holds the grouping separator, the decimal point and the time formats below; English month and weekday names are `time/2`'s (2.8).

**Time: from the span and the interval.** `time_format(domain, opts)` is the `time/2` specifier for a time domain `[t0, t1]` (`DateTime`, `NaiveDateTime` or `Date`, in either order), with `count:` the tick count (default `10`). The span is `|t1 − t0|` in seconds; the interval is the one the time scale's ticks use for that span and count (`Visualize.Scale.Time.interval/2`, spec/03 §7.3.1), *sub-day* when its unit is `:second`, `:minute` or `:hour`. The format names the units a reader needs to tell two ticks apart and no more:

| Span | Sub-day interval | Longer interval |
|---|---|---|
| ≤ 1 day | `%H:%M` (`%H:%M:%S` when the interval is in seconds) | — |
| ≤ 7 days | `%a %H:%M` (`Tue 12:00`) | `%a %d` (`Tue 05`) |
| ≤ 92 days | `%b %d %H:%M` (`Mar 05 12:00`) | `%b %d` (`Mar 05`) |
| longer | `%b %Y` (`Mar 2024`) | `%b %Y`; `%Y` when the interval is whole years |

So clock times within a day, days within a week, dates within a season and months beyond, each with the time of day while the ticks fall within a day. One format serves every tick of the axis, unlike d3's multi-scale `tickFormat`, which formats each tick by the boundary it lands on: an axis whose labels share one shape reads as one scale.

**Numbers: from the magnitude.** `notation(domain)` classifies a numeric domain by its magnitude `m`, the greatest `|d|` among its numbers:

| Magnitude | Notation | Labels |
|---|---|---|
| `m < 1000` | `:plain` | the default label of 1.5 (`0`, `250`, `0.25`) |
| `1000 ≤ m < 10⁶` | `:grouped` | the default label with its integer digits grouped in threes by the locale's separator (`90,000`, `12,500.5`) |
| `m ≥ 10⁶` | `{:si, e}` | `v / 10ᵉ` as the default label, then the prefix of `e` (`2.5M`, `0.5M`, `9M`); `0` stays `0` |

`e` is the exponent of the largest SI prefix from `M` (`6`) to `Y` (`24`) not above `m`, so **one prefix serves every tick**, as d3's `tickFormat` with an `s` specifier does: `0.5M, 1M, 1.5M`, never `500k, 1M, 1.5M`. `number(notation, opts)` is the formatter of a notation; it also takes `:si`, each value with its own prefix from `k` up (`1`, `100`, `1k`, `1M`) and plain below a thousand, which is what a log scale's ticks — orders of magnitude apart — want. A non-number formats as `to_string/1`.

**One scale.** `formatter(scale, opts)` is the derived formatter of a realised scale, with `count:` and `locale:`:

- `Visualize.Scale.Time`: `time/2` with `time_format/2` of the domain, each tick shifted into the scale's zone by `Visualize.Scale.Time.local/2` first (2.8), so a zoned axis reads local time; a non-time value formats as `to_string/1`;
- `Linear`, `Power` and `Radial`: `number/2` of `notation/1` of the domain;
- `Log` and `Symlog`: `number/2` of `:si` when the notation is `{:si, e}`, else of the notation;
- any other scale (`Band`, `Ordinal`, the discretising scales): `nil`, the default label.

The functions are pure: the same domain, count and locale give the same formatter, so a compiled chart re-derives them on every realisation and an axis on a moving domain follows it (spec/14 §12.5). Units and quantities (§4, #536) build their display scaling on `notation/1` and `number/2`.

### 3.2 Functions

| Function | Contract |
|---|---|
| `Visualize.Format.Auto.formatter/1` | As `formatter/2` with `[]` options. |
| `Visualize.Format.Auto.formatter/2` | The derived formatter of a realised scale, or `nil` (3.1). |
| `Visualize.Format.Auto.time_format/1` | As `time_format/2` with `[]` options. |
| `Visualize.Format.Auto.time_format/2` | The `time/2` specifier for a time domain's span and interval (3.1). |
| `Visualize.Format.Auto.notation/1` | As `notation/2` with `[]` options. |
| `Visualize.Format.Auto.notation/2` | `:plain`, `:grouped` or `{:si, e}` of a numeric domain's magnitude (3.1). |
| `Visualize.Format.Auto.number/1` | As `number/2` with `[]` options. |
| `Visualize.Format.Auto.number/2` | The formatter of a notation, `:si` per value included (3.1). |

## 4. Units and quantities

### 4.1 Units are UCUM codes

A unit is named by its code in the **Unified Code for Units of Measure** (UCUM, <https://ucum.org/ucum>, Regenstrief Institute, version 2.1): case-sensitive, unambiguous codes built for exchange between machines and the ones OpenTelemetry's semantic conventions use. One name per unit is the point (#536, D-138): a source that says `"s"` and one that says `"sec"` must not draw two labels, so a code is checked, never guessed at. `Visualize.Unit` reads the subset of UCUM's grammar (§2.1 of the specification, *Syntax rules*) that measurement data uses, over a fixed table of atoms and prefixes, strict enough to refuse a typo and permissive enough for the codes real sources send:

```
code       = "/" term | term
term       = component { ("." | "/") component }      left-associative, as UCUM §2.1.3
component  = annotation
           | unit [exponent] [annotation]
           | factor [annotation]
unit       = [prefix] atom                             a prefix only on a metric atom
exponent   = ["+" | "-"] digit { digit }
factor     = digit { digit }                           a positive integer, "1" the unity
annotation = "{" char { char } "}"                     ASCII 33–126 except "{" and "}"
```

| Prefix | `k` | `M` | `G` | `m` | `u` | `n` | `Ki` | `Mi` | `Gi` |
|---|---|---|---|---|---|---|---|---|---|
| Factor | 10³ | 10⁶ | 10⁹ | 10⁻³ | 10⁻⁶ | 10⁻⁹ | 2¹⁰ | 2²⁰ | 2³⁰ |

| Atom | Name | Metric | Dimension | Factor to the base | Symbol |
|---|---|---|---|---|---|
| `s` | second | yes | time | 1 | `s` |
| `min` | minute | no | time | 60 | `min` |
| `h` | hour | no | time | 3,600 | `h` |
| `d` | day | no | time | 86,400 | `d` |
| `By` | byte | yes | information | 1 | `B` |
| `bit` | bit | yes | information | 1/8 | `bit` |
| `%` | percent | no | none | 1/100 | `%` |
| `Hz` | hertz | yes | time⁻¹ | 1 | `Hz` |
| `Cel` | degree Celsius | yes | temperature | — | `°C` |
| `[degF]` | degree Fahrenheit | no | temperature | — | `°F` |
| `K` | kelvin | yes | temperature | 1 | `K` |
| `m` | metre | yes | length | 1 | `m` |
| `g` | gram | yes | mass | 1 | `g` |
| `W` | watt | yes | mass·length²·time⁻³ | 1,000 | `W` |
| `J` | joule | yes | mass·length²·time⁻² | 1,000 | `J` |
| `Pa` | pascal | yes | mass·length⁻¹·time⁻² | 1,000 | `Pa` |

The bases are the second, the byte, the metre, the gram and the kelvin, so a watt is 1,000 g·m²·s⁻³. A **symbol is matched whole before it is split**: `min` is the minute and `m` the metre, never a milli-`in` or a milli-nothing; only a symbol that is not an atom is read as a prefix and a metric atom, longest prefix first (`MiBy` is `Mi`·`By`, `ms` is `m`·`s`, `kW` is `k`·`W`). So `s`, `ms`, `us`, `ns`, `min`, `h`, `d`, `By`, `kBy`, `MBy`, `GBy`, `KiBy`, `MiBy`, `GiBy`, `bit`, `kbit`, `Mbit`, `%`, `Hz`, `kHz`, `Cel`, `[degF]`, `K`, `m`, `mm`, `km`, `m/s`, `km/h`, `m2`, `s-1`, `W`, `kW`, `J`, `kW.h`, `Pa`, `kPa`, `1`, `{request}`, `{request}/s`, `/s` and `By{heap}` are codes; `sec`, `kmin` (the minute is not metric), `B` (the bel, not in the table), `{x` (an unclosed annotation), `m//s`, `.s`, `s^2` and `""` are not. An annotation means the unity (UCUM §2.1.5): `{request}/s` is the dimension of `/s`, named. Parentheses, `10*`-style powers of ten and the rest of UCUM's atoms are not read; the table grows by proposal.

A code has a **dimension** — the sum of its components' dimensions, each times its exponent, a quotient's negated — and a **factor**, the product of each component's factor (its prefix's times its atom's, or the integer) raised to its exponent, kept as an exact rational. `Cel` and `[degF]` are UCUM's *special* units, scales with an offset: they have a dimension but no factor, and so does any code that holds one.

**Display symbol.** `Visualize.Unit.symbol/2` writes a code as a reader reads it: each atom by the table's symbol, the prefix `u` as `µ`; a positive exponent above one as superscript digits (`m2` → `m²`); the components with a positive exponent joined by `·`, then `/` and those with a negative one by their magnitude, in parentheses when there are two or more (`kW.h` → `kW·h`, `By/s` → `B/s`, `Pa` stays `Pa`, `g/(m·s2)` → `g/(m·s²)`, `s-1` → `/s`); the factor `1` and an annotation are dropped, so `1` and `{request}` are `""` and `{request}/s` is `/s`. With `annotations: true` an annotation that stands alone as a component is written as its text without braces — `{request}/s` → `request/s`, `{request}` → `request` — and one attached to a unit is dropped even then, the unit saying more than its note (`By{heap}` → `B`).

**Scaling** within a dimension is multiplication by a ratio of factors: `Visualize.Unit.convert(value, from, to)` is `value × factor(from) / factor(to)` for two codes of one dimension and both with a factor, and raises `ArgumentError` otherwise. That is display scaling — 1,500 `ms` is 1.5 `s` — and not conversion between unit systems: `Cel` to `[degF]` (or to `K`) is out of scope (#536) and raises.

**`Telemetry.Metrics` units.** `Visualize.Unit.from_telemetry/1` maps the unit atom a `Telemetry.Metrics` definition carries — or the `to` of its `{from, to}` conversion — to a code. visualize does not depend on `telemetry_metrics`; this is a table of atoms:

| Atom | Code | Atom | Code | Atom | Code |
|---|---|---|---|---|---|
| `:second` | `s` | `:byte` | `By` | `:percent` | `%` |
| `:millisecond` | `ms` | `:kilobyte` | `kBy` | `:unit` | `1` |
| `:microsecond` | `us` | `:megabyte` | `MBy` | `:hertz` | `Hz` |
| `:nanosecond` | `ns` | `:gigabyte` | `GBy` | `:celsius` | `Cel` |
| `:minute` | `min` | `:kibibyte` | `KiBy` | `:fahrenheit` | `[degF]` |
| `:hour` | `h` | `:mebibyte` | `MiBy` | `:kelvin` | `K` |
| `:day` | `d` | `:gibibyte` | `GiBy` | `:meter`, `:metre` | `m` |
| | | `:bit` | `bit` | `:watt` | `W` |
| | | `:kilobit` | `kbit` | `:kilowatt` | `kW` |
| | | `:megabit` | `Mbit` | `:joule` | `J` |
| | | | | `:pascal` | `Pa` |

It returns `{:ok, code}`, `{:error, :native}` for `:native` — a measurement in the VM's native time unit has no fixed size, and a definition converts it first (`unit: {:native, :millisecond}`) — and `{:error, {:unknown, atom}}` for any other atom, so a misspelt unit is refused rather than turned into an annotation. `:unit` is `Telemetry.Metrics`' own default, the dimensionless `1`. (`Telemetry.Metrics` converts `:kilobyte` by 1,000, which is UCUM's `kBy`.)

### 4.2 A fixed list of quantities

A quantity is what a unit measures. It chooses how a value is displayed — later a colour ramp and physical anchors too (#531 §3) — and the list is fixed: it grows by proposal, never by a source naming a new one. `Visualize.Quantity.all/0` is the list in this order:

| Quantity | Base unit | Dimension | Display family (smallest first) |
|---|---|---|---|
| `:duration` | `s` | time | `ns`, `us`, `ms`, `s`, `min`, `h`, `d` |
| `:information` | `By` | information | `By`, `kBy`, `MBy`, `GBy`; binary `By`, `KiBy`, `MiBy`, `GiBy`; bits `bit`, `kbit`, `Mbit`, `Gbit` |
| `:data_rate` | `By/s` | information·time⁻¹ | the information families over `/s`: `By/s`, `kBy/s`, `MBy/s`, `GBy/s`; binary; bits `bit/s` … `Gbit/s` |
| `:frequency` | `Hz` | time⁻¹ | `Hz`, `kHz`, `MHz`, `GHz`; events `/h`, `/min`, `/s` |
| `:ratio` | `1` | none | — (displayed in its own unit, `%` or `1`) |
| `:count` | `1` | none | — (SI notation from a thousand) |
| `:temperature` | `Cel` | temperature | — (displayed in its own unit) |
| `:length` | `m` | length | `mm`, `m`, `km` |
| `:speed` | `m/s` | length·time⁻¹ | — (displayed in its own unit) |
| `:power` | `W` | mass·length²·time⁻³ | `W`, `kW`, `MW`, `GW` |
| `:energy` | `J` | mass·length²·time⁻² | `J`, `kJ`, `MJ`, `GJ`; watt-hours `W.h`, `kW.h`, `MW.h`, `GW.h` |
| `:pressure` | `Pa` | mass·length⁻¹·time⁻² | `Pa`, `kPa`, `MPa` |

**Which family.** A quantity with more than one family takes the one its unit is written in, so the data says and no setting does: an information or data-rate unit holding the atom `bit` scales in bits, one holding a binary prefix (`Ki`, `Mi`, `Gi`) in binary prefixes, and every other in decimal prefixes — **decimal is the default**, as UCUM's `kBy` and `Telemetry.Metrics`' `:kilobyte` are 1,000 bytes, so a host that measures in `MiBy` keeps `KiB`/`MiB`/`GiB` and nobody else sees them; a frequency unit holding `Hz` scales in hertz and any other (`/s`, `{request}/s`) in events per hour, minute and second; an energy unit holding `h` (`kW.h`) in watt-hours and any other in joules.

**The measure.** A unit and a quantity together are a *measure*, `%{unit: code | nil, quantity: quantity | nil}`, the two facts a field description carries (#535). `Visualize.Quantity.resolve/1` completes and checks one: the unit is checked (§4.1); a missing quantity is the one the unit's dimension implies — the table's dimension, a dimensionless unit holding `%` being `:ratio` and any other dimensionless one `:count` — or `nil` when no quantity has that dimension (`g`, `Cel/s`); a missing unit is the quantity's base unit; a unit whose dimension is not its quantity's (`By` as a `:duration`) is `{:error, {:quantity, quantity, code}}`, and a `:ratio` or a `:count` takes any dimensionless unit. It returns `{:ok, %{unit: code | nil, quantity: quantity | nil}}`, `{:error, {:unit, code, reason}}` for a code that does not read, `{:error, {:unknown_quantity, term}}` for a quantity not in the list, or the mismatch. `Visualize.Quantity.of_unit/1` is the inference alone.

**Unit and quantity are facts about the data, not knobs.** Neither changes what a value is; they say what it already is, so a display can choose for it. What a reader sees — the format, the tick count — stays the design's to override (§3, spec/14 §4.4); there is no setting that picks a display unit, or decimal against binary, apart from the data.

### 4.3 Display scaling

**The display unit** of a domain in a measure, `Visualize.Quantity.display_unit(domain, measure)`, is the family member that fits the domain's magnitude `M`, the greatest `|d|` among its numbers converted to the base: the **largest member in which `M` is at least 1**, else the smallest. So 0–1,500 `ms` is shown in `s` (`M` = 1.5 s), 0–900 `ms` in `ms`, 0–90 `s` in `min`, 0–1,500,000 `By` in `MBy`, 0–0.5 `/s` in `/min`, 0–3,000 `W` in `kW`. A measure whose quantity has no family, a unit without a factor (`Cel`), no quantity, or `M = 0` keeps the unit it has.

**The tick formatter** of a scale in a measure, `Visualize.Quantity.formatter(scale, measure, opts)` (`count:` and `locale:` as `Visualize.Format.Auto.formatter/2`), writes every tick in the display unit:

- on `Linear`, `Power` and `Radial`: the domain converted to the display unit, its `Visualize.Format.Auto.notation/2` — `{:si, 3}` in place of `:grouped` for a `:count`, whose family is SI from a thousand (`1.2k`, `90k`), one prefix for the axis as ever — and each tick converted, written by `Visualize.Format.Auto.number/2` of that notation, then the display unit's symbol: `0 s`, `0.5 s`, `1 s`, `1.5 s` for 0–1,500 `ms`;
- on `Log` and `Symlog`, whose ticks are powers of ten in the scale's unit: each tick in its **own** display unit, the largest in which it is at least 1 among the family members a power of ten from the unit — so a tick lands on a round number, `1 ms`, `10 ms`, `100 ms`, `1 s`, `10 s`, `100 s`, `1k s`, never `1.67 min` — written by `Visualize.Format.Auto.number(:si)` as #532's log axis is; `0` and a quantity with no family keep the unit;
- on any other scale (`Time`, `Band`, `Ordinal`, the discretising scales): `Visualize.Format.Auto.formatter/2`, the measure unused.

The symbol follows the number after a space (`1.5 s`, `20 °C`, `2.5 MB`), except `%` and a symbol that begins with `/`, which follow it directly (`45%`, `12/s`); an empty symbol (`1`, `{request}`) adds nothing. A non-number is `to_string/1`. The function is pure, so an axis on a moving domain re-derives its display unit with its format on every realisation (spec/14 §12.5).

**The label rule.** `Visualize.Quantity.label(measure)` is what a title says about a measure: **the unit, else the quantity, else nothing** — the symbol of the unit with its annotations written (`ms`, `kW·h`, `request/s`, `request`) when it is not empty, else the quantity's name with its underscores as spaces (`count`, `ratio`, `data rate`), else `nil`. An axis that draws its measure applies it to what its ticks cannot say (spec/14 §4.4).

### 4.4 Functions

| Function | Contract |
|---|---|
| `Visualize.Unit.parse/1` | `{:ok, components}` for a code (4.1), each `%{prefix: String.t() \| nil, atom: String.t() \| nil, factor: pos_integer() \| nil, annotation: String.t() \| nil, exponent: integer()}` with a quotient's exponent negated; `{:error, reason}` — `:empty`, `{:syntax, rest}` at the first character that does not read, `{:unknown_atom, symbol}`, `{:not_metric, prefix, atom}`. |
| `Visualize.Unit.valid?/1` | Whether a string is a code (4.1). |
| `Visualize.Unit.dimension/1` | The dimension of a code, a map from `:time`, `:information`, `:length`, `:mass`, `:temperature` to a non-zero exponent (`%{}` dimensionless); raises `ArgumentError` for a code that does not read. |
| `Visualize.Unit.factor/1` | The factor of a code to its base, an exact `{numerator, denominator}`, or `nil` for one holding a special unit; raises as `dimension/1`. |
| `Visualize.Unit.convert/3` | `value × factor(from) / factor(to)` for two codes of one dimension with factors; `ArgumentError` otherwise (4.1). |
| `Visualize.Unit.symbol/1` | As `symbol/2` with `[]` options. |
| `Visualize.Unit.symbol/2` | The display symbol of a code, `annotations:` (default `false`) writing a lone annotation's text (4.1). |
| `Visualize.Unit.from_telemetry/1` | `{:ok, code}` for a `Telemetry.Metrics` unit atom or `{from, to}` pair, `{:error, :native}`, `{:error, {:unknown, atom}}` (4.1). |
| `Visualize.Quantity.all/0` | The fixed list of quantities, in the order of 4.2. |
| `Visualize.Quantity.base_unit/1` | A quantity's base unit (4.2). |
| `Visualize.Quantity.family/2` | `family(quantity, unit)`: the display family a unit of the quantity scales in, smallest first, `[]` for a quantity with none (4.2). |
| `Visualize.Quantity.of_unit/1` | The quantity a code's dimension implies, or `nil` (4.2). |
| `Visualize.Quantity.resolve/1` | A measure completed and checked: `{:ok, measure}` or `{:error, reason}` (4.2). |
| `Visualize.Quantity.display_unit/2` | `display_unit(domain, measure)`: the family member that fits the domain (4.3). |
| `Visualize.Quantity.formatter/2` | As `formatter/3` with `[]` options. |
| `Visualize.Quantity.formatter/3` | `formatter(scale, measure, opts)`: the tick formatter in the display unit, with its symbol (4.3); raises `ArgumentError` for a measure `resolve/1` refuses. |
| `Visualize.Quantity.suffix/1` | The tick suffix of a display unit: `""`, or its symbol with its separator (4.3). |
| `Visualize.Quantity.label/1` | The label rule: the unit, else the quantity, else `nil` (4.3). |
