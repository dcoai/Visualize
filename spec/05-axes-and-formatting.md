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

**By currency code** (#593, D-155). With `code:`, an ISO 4217 code of §4.1's table, the currency writes itself: `precision` defaults to the code's **minor units** (`USD` 2, `JPY` 0, `BHD` 3; 2 for a code with none, such as `XAU`), the integer digits are grouped by the locale's separator and the point is the locale's (`locale:`, `"en"` by default, as §3.1), and the symbol is the locale's for that code — in `"en"`, `$` for `USD`, `€` for `EUR`, `£` for `GBP` and `¥` for `JPY` — written before the number after the sign: `currency(1240, code: "USD")` is `"$1,240.00"`, `currency(1240, code: "JPY")` `"¥1,240"`, `currency(-9.5, code: "EUR")` `"-€9.50"`. A code the locale has no symbol for is written after the number, a space between: `currency(1240, code: "CHF")` is `"1,240.00 CHF"`. `symbol:` is not taken with `code:`; a code not in the table raises `ArgumentError`.

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

### 2.9 `duration/1,2`

`duration(seconds)` prints a length of time in the unit its magnitude chooses (#191) — the one thing a fixed specifier cannot express. The units are `d` (86400 s), `h` (3600), `m` (60), `s` and `ms`. The largest unit the value reaches is taken: a whole count prints as it is (`45s`, `2m`, `1h`, `3d`); a count whose remainder is whole in the next finer unit prints both (`2m30s`, `1h30m`, `1d1h`) — among `d`, `h`, `m` and `s` only, seconds never pairing with milliseconds; any other prints the count to one decimal with a trailing zero trimmed (`1.5h` for 5430 s, `2.5s`, `0.5ms`). Below one second the unit is `ms`; zero is `0s`; a negative value is the positive one with a leading `−`. The value MUST be a number.

`duration(seconds, opts)` takes `style:` — `:magnitude`, the default, is `duration/1` — and `locale:` (§3.1). **`style: :compound`** is the label and tooltip form (#593, D-155): one second and above, the two largest non-zero of whole days, hours, minutes and seconds, joined by a space, the rest truncated (`1h 24m` for 5,040 s, `2d 3h`, `45s`, `1h 3s` for 3,603 s, a zero unit between two others dropped); below a second, milliseconds (`840ms`), and below a microsecond, nanoseconds (`500ns`), each to `precision:` decimals (default `2`) with trailing zeros and a trailing point trimmed (`0.5ms`, `1.25ms`); zero (and −0.0) is `0s`; a negative value is the positive one after `-`. An axis keeps §4.3's single scaled unit (`1.4 h`): one unit per axis, as one SI prefix per axis (D-134), so the compound form is never a tick format.

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
| `Visualize.Format.currency/2` | Currency string (2.6), by symbol or by ISO 4217 `code:` with its minor units and the `locale:`'s symbol. |
| `Visualize.Format.formatter/1` | Parses a d3-format specifier and returns a formatter function (2.7); raises `ArgumentError` on an invalid one. |
| `Visualize.Format.time/1` | As `time/2` with format `"%Y-%m-%d"`. |
| `Visualize.Format.time/2` | One-pass strftime-style formatting of a date/time struct (2.8). |
| `Visualize.Format.duration/1` | A length of time in seconds in the unit its magnitude chooses (2.9). |
| `Visualize.Format.duration/2` | `duration(seconds, style: :magnitude \| :compound, precision:, locale:)`: `duration/1`, or the compound label form `1h 24m`, `840ms` (2.9). |

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

A unit is named by its code in the **Unified Code for Units of Measure** (UCUM, <https://ucum.org/ucum>, Regenstrief Institute; the atoms and prefixes below are checked against its essence table, version 2.2 of 2024-06-17): case-sensitive, unambiguous codes built for exchange between machines and the ones OpenTelemetry's semantic conventions use. One name per unit is the point (#536, D-138, D-155): a source that says `"s"` and one that says `"sec"` must not draw two labels, so a code is checked, never guessed at. `Visualize.Unit` reads the subset of UCUM's grammar (§2.1 of the specification, *Syntax rules*) that measurement data uses, over a fixed table of atoms and prefixes, strict enough to refuse a typo and permissive enough for the codes real sources send:

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

A unit's symbol is a run of letters, `%` and bracketed parts — `[` up to the next `]` — so `[ft_i]`, `m[Hg]`, `mm[Hg]`, `B[SPL]` and `dB[SPL]` are each one symbol, as UCUM writes them; an exponent or an annotation ends it (`[ft_i]2`, `By{heap}`).

| Prefix | `da` | `h` | `k` | `M` | `G` | `T` | `d` | `c` | `m` | `u` | `n` | `p` | `Ki` | `Mi` | `Gi` | `Ti` |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Factor | 10¹ | 10² | 10³ | 10⁶ | 10⁹ | 10¹² | 10⁻¹ | 10⁻² | 10⁻³ | 10⁻⁶ | 10⁻⁹ | 10⁻¹² | 2¹⁰ | 2²⁰ | 2³⁰ | 2⁴⁰ |

The atoms, each with UCUM's definition (the *Factor* column is to the base of its dimension, below):

| Atom | Name | Metric | Dimension | Factor to the base | UCUM's definition | Symbol |
|---|---|---|---|---|---|---|
| `s` | second | yes | time | 1 | base | `s` |
| `min` | minute | no | time | 60 | 60 `s` | `min` |
| `h` | hour | no | time | 3,600 | 60 `min` | `h` |
| `d` | day | no | time | 86,400 | 24 `h` | `d` |
| `By` | byte | yes | information | 1 | 8 `bit` | `B` |
| `bit` | bit | yes | information | 1/8 | `1` | `bit` |
| `%` | percent | no | none | 1/100 | 10⁻² | `%` |
| `[ppm]` | parts per million | no | none | 10⁻⁶ | 10⁻⁶ | `ppm` |
| `[ppb]` | parts per billion | no | none | 10⁻⁹ | 10⁻⁹ | `ppb` |
| `mol` | mole | yes | none | 6.02214076 × 10²³ | 6.02214076 × 10²³ | `mol` |
| `Hz` | hertz | yes | time⁻¹ | 1 | `s-1` | `Hz` |
| `Cel` | degree Celsius | yes | temperature | — (affine) | `cel(1 K)` | `°C` |
| `[degF]` | degree Fahrenheit | no | temperature | — (affine) | `degf(5 K/9)` | `°F` |
| `K` | kelvin | yes | temperature | 1 | base | `K` |
| `m` | metre | yes | length | 1 | base | `m` |
| `[in_i]` | inch | no | length | 127/5,000 | 2.54 `cm` | `in` |
| `[ft_i]` | foot | no | length | 381/1,250 | 12 `[in_i]` | `ft` |
| `[yd_i]` | yard | no | length | 1,143/1,250 | 3 `[ft_i]` | `yd` |
| `[mi_i]` | mile | no | length | 201,168/125 | 5,280 `[ft_i]` | `mi` |
| `[nmi_i]` | nautical mile | no | length | 1,852 | 1,852 `m` | `nmi` |
| `ar` | are | yes | length² | 100 | 100 `m2` | `a` |
| `[acr_us]` | acre (US survey) | no | length² | 62,726,400,000/15,499,969 | 160 `[rd_us]2`, the rod 16.5 survey feet of 1,200/3,937 `m` | `ac` |
| `l`, `L` | litre | yes | length³ | 1/1,000 | `dm3` | `l`, `L` |
| `[foz_us]` | US fluid ounce | no | length³ | 473,176,473/16 × 10⁻¹² | `[gal_us]`/128 | `fl oz` |
| `[pt_us]` | US pint | no | length³ | 473,176,473 × 10⁻¹² | `[gal_us]`/8 | `pt` |
| `[gal_us]` | US gallon | no | length³ | 473,176,473/125 × 10⁻⁹ | 231 `[in_i]3` | `gal` |
| `[foz_br]` | imperial fluid ounce | no | length³ | 454,609/16 × 10⁻⁹ | `[gal_br]`/160 | `fl oz` |
| `[pt_br]` | imperial pint | no | length³ | 454,609/8 × 10⁻⁸ | `[gal_br]`/8 | `pt` |
| `[gal_br]` | imperial gallon | no | length³ | 454,609 × 10⁻⁸ | 4.54609 `l` | `gal` |
| `g` | gram | yes | mass | 1 | base | `g` |
| `t` | tonne | yes | mass | 10⁶ | 10³ `kg` | `t` |
| `[oz_av]` | ounce (avoirdupois) | no | mass | 45,359,237/1,600,000 | `[lb_av]`/16 | `oz` |
| `[lb_av]` | pound (avoirdupois) | no | mass | 45,359,237/100,000 | 7,000 grains of 64.79891 `mg` | `lb` |
| `[stone_av]` | stone | no | mass | 317,514,659/50,000 | 14 `[lb_av]` | `st` |
| `[kn_i]` | knot | no | length·time⁻¹ | 463/900 | `[nmi_i]/h` | `kn` |
| `W` | watt | yes | mass·length²·time⁻³ | 1,000 | `J/s` | `W` |
| `[HP]` | horsepower | no | mass·length²·time⁻³ | 37,284,993,579,113,511/(5 × 10¹⁰) | 550 `[ft_i].[lbf_av]/s` | `hp` |
| `J` | joule | yes | mass·length²·time⁻² | 1,000 | `N.m` | `J` |
| `cal` | calorie (thermochemical) | yes | mass·length²·time⁻² | 4,184 | `cal_th`, 4.184 `J` | `cal` |
| `[Cal]` | nutrition-label Calorie | no | mass·length²·time⁻² | 4,184,000 | `kcal_th` | `Cal` |
| `Pa` | pascal | yes | mass·length⁻¹·time⁻² | 1,000 | `N/m2` | `Pa` |
| `bar` | bar | yes | mass·length⁻¹·time⁻² | 10⁸ | 10⁵ `Pa` | `bar` |
| `[psi]` | pound per square inch | no | mass·length⁻¹·time⁻² | 8,896,443,230,521/1,290,320 | `[lbf_av]/[in_i]2` | `psi` |
| `m[Hg]` | metre of mercury | yes | mass·length⁻¹·time⁻² | 133,322,000 | 133.3220 `kPa` | `mHg` |
| `[in_i'Hg]` | inch of mercury | no | mass·length⁻¹·time⁻² | 16,931,894/5 | `m[Hg].[in_i]/m` | `inHg` |
| `rad` | radian | yes | angle | 1 | base | `rad` |
| `deg` | degree | no | angle | π/180 | `[pi].rad/360` × 2 | `°` |
| `C` | coulomb | yes | charge | 1 | base | `C` |
| `A` | ampere | yes | charge·time⁻¹ | 1 | `C/s` | `A` |
| `V` | volt | yes | mass·length²·time⁻²·charge⁻¹ | 1,000 | `J/C` | `V` |
| `lx` | lux | yes | luminous intensity·angle²·length⁻² | 1 | `lm/m2`, the lumen `cd.sr`, the steradian `rad2` | `lx` |
| `B` | bel | yes | level | 1 (logarithmic) | `lg(1 1)` | `B` |
| `B[SPL]` | bel sound pressure | yes | sound pressure level | 1 (logarithmic) | `2lg(2 10*-5.Pa)` | `B(SPL)` |

The bases are the second, the byte, the metre, the gram, the kelvin, the radian and the coulomb, so a watt is 1,000 g·m²·s⁻³, and the pound-force of `[HP]` and `[psi]` is `[lb_av]` times the standard acceleration of free fall, 9.80665 `m/s2`. A **symbol is matched whole before it is split**: `min` is the minute and `m` the metre, never a milli-`in` or a milli-nothing; `h` is the hour, `d` the day, `t` the tonne, `cal` the calorie and `bar` the bar, and only a symbol that is not an atom is read as a prefix and a metric atom, longest prefix first (`MiBy` is `Mi`·`By`, `dam` is `da`·`m`, `ms` is `m`·`s`, `kW` is `k`·`W`, `hPa` is `h`·`Pa`, `har` is `h`·`ar`, the hectare, `mm[Hg]` is `m`·`m[Hg]`, `dB` is `d`·`B`). So `s`, `ms`, `us`, `ns`, `min`, `h`, `d`, `By`, `kBy`, `MBy`, `GBy`, `TBy`, `KiBy`, `MiBy`, `GiBy`, `TiBy`, `bit`, `kbit`, `Mbit`, `%`, `[ppm]`, `Hz`, `kHz`, `Cel`, `[degF]`, `K`, `m`, `mm`, `cm`, `km`, `[in_i]`, `[ft_i]2`, `[mi_i]/h`, `[kn_i]`, `m2`, `har`, `[acr_us]`, `ml`, `dl`, `l`, `L`, `m3`, `[gal_us]`, `[pt_br]`, `g`, `kg`, `t`, `[lb_av]`, `[stone_av]`, `m/s`, `km/h`, `min/km`, `s-1`, `W`, `kW`, `[HP]`, `J`, `kJ`, `kW.h`, `cal`, `kcal`, `[Cal]`, `Pa`, `hPa`, `kPa`, `bar`, `mbar`, `[psi]`, `mm[Hg]`, `[in_i'Hg]`, `deg`, `rad`, `V`, `mA`, `mA.h`, `lx`, `ug/m3`, `mg/dl`, `mmol/l`, `B`, `dB`, `dB[SPL]`, `1`, `{request}`, `{request}/s`, `{beat}/min`, `/s` and `By{heap}` are codes; `sec`, `kmin` (the minute is not metric), `k[in_i]` (nor is the inch), `ft` (the foot is `[ft_i]`), `{x` (an unclosed annotation), `[in_i` (an unclosed bracket), `m//s`, `.s`, `s^2` and `""` are not. `B`, `kB` and `MB` are codes, but they are the bel, the kilobel and the megabel: a person's `MB` is read by `parse_alias/1` (below), never by `parse/1`. An annotation means the unity (UCUM §2.1.5): `{request}/s` is the dimension of `/s`, named. Parentheses, `10*`-style powers of ten, arcminutes and arcseconds, and the rest of UCUM's atoms are not read; the table grows by proposal.

A code has a **dimension** — the sum of its components' dimensions, each times its exponent, a quotient's negated — and a **factor**, the product of each component's factor (its prefix's times its atom's, or the integer) raised to its exponent, kept exact: a rational, times an integer power of π when the code holds `deg` (`factor/1` answers `{n, d}`, or `{n, d, k}` for n/d·πᵏ with k ≠ 0). The dimensions are `:time`, `:information`, `:length`, `:mass`, `:temperature`, `:angle`, `:charge` and `:luminous_intensity`, as UCUM's base units are, two **level** dimensions, and one `{:currency, code}` per currency (below). The mole is UCUM's number, so `mol` is dimensionless and `mmol/l` has the dimension of `/l`.

**Special units.** `Cel` and `[degF]` are UCUM's *affine* special units, scales with an offset: they have a dimension but no factor, and so does any code that holds one; they convert by their offsets (below). `B` and `B[SPL]` are UCUM's *logarithmic* units. UCUM gives a logarithmic unit the dimension of its argument; visualize gives each logarithmic reference a **level dimension** of its own instead — `:level` for `B`, the level of a bare ratio, and `:sound_pressure_level` for `B[SPL]` — so a level never meets the linear unit it is a logarithm of, and `dB[SPL]` is not a pressure (D-155). Within its level a logarithmic unit scales by its prefix like any other — a decibel is a tenth of a bel — so it has a factor; `Visualize.Unit.kind/1` says which kind a code is: `:linear`, `:affine` (it holds `Cel` or `[degF]`) or `:logarithmic` (it holds `B` or `B[SPL]`).

**Aliases.** `Visualize.Unit.parse_alias/1` reads the symbols people type and metresis stored (D-155) — `°C`, `°F`, `lb`, `st`, `mph`, `kn`, `inHg`, `mmHg`, `psi`, `kWh`, `B`, `KiB`, `ha`, `ac` — to codes, `{:ok, code}`, and **refuses an ambiguous one, naming its choices**: `{:error, {:ambiguous, alias, choices}}`, `choices` a list of `{code, meaning}`:

| Alias | Choices |
|---|---|
| `KB`, `kB` | `kBy` (1,000 bytes), `KiBy` (1,024 bytes) |
| `MB`, `GB`, `TB` | `MBy`/`MiBy`, `GBy`/`GiBy`, `TBy`/`TiBy` likewise |
| `gal`, `pt`, `floz`, `fl oz` | `[gal_us]` (US gallon), `[gal_br]` (imperial gallon); the pint and the fluid ounce (`floz`, `fl oz`) likewise |
| `oz` | `[oz_av]` (ounce, mass), `[foz_us]` (US fluid ounce), `[foz_br]` (imperial fluid ounce) |
| `cal` | `cal` (calorie), `[Cal]` (food Calorie, a kilocalorie) |
| `C` | `Cel` (degree Celsius), `C` (coulomb) |
| `dB` | `dB` (a level ratio), `dB[SPL]` (sound pressure level) |
| `kt` | `[kn_i]` (knot), `kt` (kilotonne) |
| `$` | `{iso4217:USD}`, `{iso4217:CAD}`, `{iso4217:AUD}`, `{iso4217:NZD}`, `{iso4217:HKD}`, `{iso4217:SGD}` |
| `¥` | `{iso4217:JPY}` (yen), `{iso4217:CNY}` (yuan) |

A code of the ISO 4217 table typed alone, in capitals (`USD`, `CHF`), is its currency, `{iso4217:USD}`; `€` is `{iso4217:EUR}` and `£` `{iso4217:GBP}`.

The alias table is read first, so an alias wins over a UCUM reading of the same spelling — a person who types `B` means a byte, and gets `By`. A string the table does not hold is read by `parse/1`: a valid code is its own alias (`{:ok, "kPa"}`), and any other is `{:error, {:unknown_alias, string}}`. Surrounding whitespace is ignored. `Visualize.Unit.format_error/1` words a refusal for a person: `"KB" is ambiguous: kBy (1,000 bytes) or KiBy (1,024 bytes)`.

**Currency: visualize's extension, beyond UCUM** (D-155). UCUM has no currency, and a plain annotation (`{USD}`) is UCUM's unity, so `{USD}` and `{EUR}` would read as one unit and as a count. visualize recognises one namespaced annotation, **`{iso4217:XXX}`**, `XXX` a code of the ISO 4217 table (list one, published 2026-09-17: 178 codes, each with its **minor units**, the decimals an amount is written to — `USD` 2, `JPY` 0, `BHD` 3, `CLF` 4, none for `XAU`), and gives **each code a dimension of its own**, `{:currency, "USD"}`:

- `{iso4217:USD}` and `{iso4217:EUR}` are different dimensions, so they never convert and never pair (`{:currency, from, to}` from `conversion/2`, below), as `kg` and `Cel` do not;
- a code composes like any unit: `{iso4217:USD}/h` is an hourly rate, `{iso4217:EUR}/kW/h` an energy price (UCUM's `/` is left-associative, so a price per kilowatt-hour divides twice: `{iso4217:EUR}/kW.h` would be euro-hours per kilowatt), `{iso4217:EUR}/{iso4217:USD}` an exchange rate, which is data like any other;
- its factor is the unity, so a currency scales only by the units around it;
- a code not in the table is refused by `parse/1`, `{:error, {:unknown_currency, code}}`, the extension being visualize's to check;
- its display symbol is the code (`{iso4217:USD}/h` → `USD/h`), and its formats are §2.6's and §4.3's.

**To any other UCUM reader, `{iso4217:USD}` and `{iso4217:EUR}` are both the dimensionless unit `1`, and so equal.** The annotation is valid UCUM syntax, so another reader degrades to "a count" rather than failing, but it cannot tell two currencies apart. visualize therefore never hands a currency code to a UCUM consumer — a telemetry export, an OpenTelemetry unit — without that caveat; within visualize, and between hosts that use it, the code is the currency. `Visualize.Unit.currency/1` is the ISO code a code holds alone (`"USD"` for `{iso4217:USD}`, `nil` for `{iso4217:USD}/h` and for any code that is not a currency), and `Visualize.Unit.minor_units/1` a code's minor units (`nil` for none).

**Display symbol.** `Visualize.Unit.symbol/2` writes a code as a reader reads it: each atom by the table's symbol, the prefix `u` as `µ`; a positive exponent above one as superscript digits (`m2` → `m²`); the components with a positive exponent joined by `·`, then `/` and those with a negative one by their magnitude, in parentheses when there are two or more (`kW.h` → `kW·h`, `By/s` → `B/s`, `Pa` stays `Pa`, `g/(m·s2)` → `g/(m·s²)`, `s-1` → `/s`, `[ft_i]2` → `ft²`, `[mi_i]/h` → `mi/h`, `har` → `ha`, `mm[Hg]` → `mmHg`, `dB[SPL]` → `dB(SPL)`, `deg` → `°`); the factor `1` and an annotation are dropped, so `1` and `{request}` are `""` and `{request}/s` is `/s` — but a currency annotation standing alone is written as its code (`{iso4217:USD}` → `USD`, `{iso4217:EUR}/kW/h` → `EUR/(kW·h)`). With `annotations: true` an annotation that stands alone as a component is written as its text without braces — `{request}/s` → `request/s`, `{request}` → `request` — and one attached to a unit is dropped even then, the unit saying more than its note (`By{heap}` → `B`).

**Conversion** (D-155) is in scope and exact. `Visualize.Unit.conversion(from, to)` answers `{:ok, {scale, offset}}`, so that a value in `from` is `value × scale + offset` in `to`, with `scale` an exact factor (`{n, d}`, or `{n, d, k}` for n/d·πᵏ) and `offset` an exact signed rational `{n, d}`; or `{:error, reason}`:

- **Two codes of one dimension with factors** convert by the ratio of their factors, offset `{0, 1}`: `[lb_av]` to `kg` is `{45359237, 100000000}`, `deg` to `rad` is `{1, 180, 1}`, `[mi_i]/h` to `km/h` is `{25146, 15625}`. That is also display scaling — 1,500 `ms` is 1.5 `s`.
- **The affine units** convert with their offsets, standing alone: UCUM defines `Cel` as `K` less 273.15 and `[degF]` as 5/9 `K` from 459.67 below its zero, so `Cel` to `[degF]` is exactly `{{9, 5}, {32, 1}}` and `[degF]` to `K` is `{{5, 9}, {45967, 180}}`; a prefixed one scales with its prefix (`mCel`). An affine unit inside a term (`Cel/h`, `[degF].m`) is not a temperature and has no offset to convert by: `{:affine_in_term, code}`, unless the two codes are the same.
- **Logarithmic units convert only to their own level** (§4.1): `B` to `dB` is `{10, 1}`, `dB[SPL]` to `B[SPL]` is `{1, 10}`; a level to or from a linear unit, or to another level, is `{:logarithmic, from, to}`.
- **Currency never converts**: an exchange rate is data, not a fact about a unit. Two codes holding different `{iso4217:…}` annotations are `{:currency, from, to}`, whatever else they hold; the same currency over different units of the rest converts as the rest does (`{iso4217:USD}/h` to `{iso4217:USD}/min` is `{1, 60}`).
- **Any other pair of dimensions** is `{:dimension, from, to}`.

A code that does not read is `{:error, reason}` of `parse/1`. `Visualize.Unit.convert(value, from, to)` is `value × scale + offset` as a float, the scale and offset exact and the arithmetic rounded once for an integer value, and raises `ArgumentError` with the reason worded by `format_error/1` for a pair `conversion/2` refuses. So 100 `Cel` is 212.0 `[degF]`, −40 `Cel` is −40.0 `[degF]`, 0 `K` is −273.15 `Cel`, 180 `deg` is π `rad`, and 30 `dB` is 3.0 `B`.

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

A quantity is what a unit measures. It chooses how a value is displayed — later a colour ramp and physical anchors too (#531 §3) — and carries the facts a host needs to aggregate and draw it (D-155). The list is fixed: it grows by proposal, never by a source naming a new one. `Visualize.Quantity.all/0` is the list in this order:

| Quantity | Base unit | Dimension | Kind | Bounds (in the base unit) | Additive across | Additive over time |
|---|---|---|---|---|---|---|
| `:duration` | `s` | time | linear | ≥ 0 | yes | yes |
| `:information` | `By` | information | linear | ≥ 0 | yes | yes |
| `:data_rate` | `By/s` | information·time⁻¹ | linear | ≥ 0 | yes | no |
| `:frequency` | `Hz` | time⁻¹ | linear | ≥ 0 | yes | no |
| `:ratio` | `1` | none | linear | 0 to 1 (0 to 100 in `%`) | no | no |
| `:count` | `1` | none | linear | ≥ 0 | yes | yes |
| `:temperature` | `Cel` | temperature | affine | — | no | no |
| `:length` | `m` | length | linear | ≥ 0 | yes | yes |
| `:speed` | `m/s` | length·time⁻¹ | linear | ≥ 0 | no | no |
| `:power` | `W` | mass·length²·time⁻³ | linear | — | yes | no |
| `:energy` | `J` | mass·length²·time⁻² | linear | — | yes | yes |
| `:pressure` | `Pa` | mass·length⁻¹·time⁻² | linear | — | no | no |
| `:area` | `m2` | length² | linear | ≥ 0 | yes | yes |
| `:volume` | `l` | length³ | linear | ≥ 0 | yes | yes |
| `:mass` | `g` | mass | linear | ≥ 0 | yes | yes |
| `:pace` | `s/m` | time·length⁻¹ | linear | ≥ 0 | no | no |
| `:angle` | `deg` | angle | cyclic | 0 to 360 | no | no |
| `:currency` | `{iso4217:XXX}`, by code | currency, one per code | linear | — | yes | yes |
| `:electric_potential` | `V` | mass·length²·time⁻²·charge⁻¹ | linear | — | no | no |
| `:electric_current` | `A` | charge·time⁻¹ | linear | — | yes | no |
| `:electric_charge` | `C` | charge | linear | ≥ 0 | yes | yes |
| `:illuminance` | `lx` | luminous intensity·angle²·length⁻² | linear | ≥ 0 | no | no |
| `:sound_level` | `dB[SPL]` | sound pressure level | logarithmic | — | no | no |
| `:mass_concentration` | `g/l` | mass·length⁻³ | linear | ≥ 0 | no | no |
| `:amount_concentration` | `mol/l` | length⁻³ (the mole is a number) | linear | ≥ 0 | no | no |

"Number" is not a quantity: a field with none is plainly formatted. A percent is a `:ratio` written in `%`. A bare `dB` is a level ratio and not a `:sound_level`, which takes `dB[SPL]` and `B[SPL]` (§4.1). A currency's unit is the annotation of §4.1's extension, `{iso4217:XXX}`, one dimension per code.

**Kind** (`Visualize.Quantity.kind/1`) says how values combine. `:linear` values are on a ratio scale. A temperature is `:affine`: its zero is a convention, so a difference is meaningful and a sum of absolutes is not. A sound level is `:logarithmic`: two levels do not add as numbers. An angle is `:cyclic`: 350° and 10° are 20° apart, so a mean of angles is circular.

**Bounds** (`Visualize.Quantity.bounds/1` in the base unit, `bounds/2` in a given unit, `{min | nil, max | nil}`) are a **display hint, never validation** (D-155): they tell an axis where a quantity's values physically lie — a duration is not negative, an angle wraps at 360° — so it can anchor at zero or stop at the wrap. A value outside them is never refused: a difference is legitimately negative (an elevation change, a clock offset, net energy), and a ratio may exceed one. A field's schema overrides them with its own `bounds` (spec/08 §10.1). `bounds/2` converts the base's bounds into the unit (`bounds(:angle, "rad")` is `{0, 2π}`, `bounds(:ratio, "%")` is `{0, 100}`); an affine unit's bounds are its quantity's, none for a temperature.

**Additivity depends on the aggregation** (D-155). A quantity carries two physical defaults: **across** — whether summing several series at one instant means anything (the total throughput of several links, the current into a node) — and **over time** — whether summing one series over time does (the bytes sent in a day, but not a day of power readings, which integrate to energy instead). A field's schema may state its **metric kind** (spec/08 §10.1), which refines the second: `Visualize.Quantity.additivity(quantity, metric_kind)` is `%{across: boolean, over_time: boolean}`, where

- no metric kind (`nil`) keeps the quantity's defaults;
- `:gauge` — a level sampled at instants — is never additive over time, since a sum of samples counts each level once per sample;
- `:counter` — the increments of an accumulating count — is additive over time exactly when the quantity is additive across, since increments of an extensive quantity add and increments of a temperature mean nothing;
- `:rate` — a quantity per unit time — is never additive over time: a rate integrates rather than adds;

and across is the quantity's default under every metric kind. A field with no quantity (a plain number) has both defaults `true`. A host derives its aggregation exclusions from the two: a sum over time is offered only when `over_time`, a sum of series only when `across`.

**Which family.** A quantity's display families are ladders of units, smallest first, each tagged with the unit systems it serves:

| Quantity | Metric | US | UK | Other families (any system) |
|---|---|---|---|---|
| `:duration` | — | — | — | `ns`, `us`, `ms`, `s`, `min`, `h`, `d` |
| `:information` | — | — | — | decimal `By`, `kBy`, `MBy`, `GBy`, `TBy`; binary `By`, `KiBy`, `MiBy`, `GiBy`, `TiBy`; bits `bit`, `kbit`, `Mbit`, `Gbit`, `Tbit` |
| `:data_rate` | — | — | — | the information families over `/s` |
| `:frequency` | — | — | — | `Hz`, `kHz`, `MHz`, `GHz`; events `/h`, `/min`, `/s` |
| `:temperature` | `Cel` | `[degF]` | `Cel` | — |
| `:length` | `mm`, `cm`, `m`, `km` | `[in_i]`, `[ft_i]`, `[mi_i]` | as US | — |
| `:area` | `cm2`, `m2`, `har`, `km2` | `[ft_i]2`, `[acr_us]`, `[mi_i]2` | as US | — |
| `:volume` | `ml`, `l`, `m3` | `[foz_us]`, `[pt_us]`, `[gal_us]` | `[foz_br]`, `[pt_br]`, `[gal_br]` | — |
| `:mass` | `mg`, `g`, `kg`, `t` | `[oz_av]`, `[lb_av]` | `[oz_av]`, `[lb_av]`, `[stone_av]` | — |
| `:speed` | `km/h` | `[mi_i]/h` | as US | — |
| `:pace` | `min/km` | `min/[mi_i]` | as US | — |
| `:power` | — | — | — | `W`, `kW`, `MW`, `GW` |
| `:energy` | — | — | — | `J`, `kJ`, `MJ`, `GJ`; watt-hours `W.h`, `kW.h`, `MW.h`, `GW.h`; calories `cal`, `kcal` |
| `:pressure` | `Pa`, `kPa`, `MPa` | `[psi]` | as US | — |
| `:electric_potential` | — | — | — | `mV`, `V`, `kV` |
| `:electric_current` | — | — | — | `mA`, `A` |
| `:electric_charge` | — | — | — | `mA.h`, `A.h` |
| `:illuminance` | — | — | — | `lx`, `klx` |

`:ratio`, `:count`, `:angle`, `:currency`, `:sound_level` and the two concentrations have no family: each is displayed in the unit it is given (a count in SI notation from a thousand, §4.3).

A unit **belongs to** the family that holds a member of its *shape* — its atoms and their exponents, prefixes aside, a binary prefix (`Ki`, `Mi`, `Gi`, `Ti`) kept apart from a decimal one, annotations aside — the first such family in the table's order (metric before US before UK before the others). So the data says which family and no setting does: `MiBy` belongs to the binary ladder and `kBy` to the decimal one — **decimal is the default**, as UCUM's `kBy` and `Telemetry.Metrics`' `:kilobyte` are 1,000 bytes, so a host that measures in `MiBy` keeps `KiB`/`MiB`/`GiB` and nobody else sees them — `bit/s` to the bits, `{request}/s` and `{beat}/min` to the events, `kW.h` to the watt-hours, `hPa` to `Pa`, `kPa`, `MPa`, `[ft_i]` to the US length ladder. A unit of no family's shape — `mbar`, `[nmi_i]`, `[yd_i]`, `[kn_i]`, `m/s`, `K`, `[Cal]` — belongs to none and is displayed as it is given. `Visualize.Quantity.family(quantity, unit, system)` is that ladder for a system (below), and `family/2` the unit's own.

**Unit systems** (D-155) are `:metric`, `:us`, `:uk` and `:as_posted`, `Visualize.Quantity.systems/0`. A system is a display preference and never touches the data: it chooses the family a value is shown in. Under `:metric`, `:us` or `:uk`, a quantity whose table row names a family for that system is shown in it — a mass in `kg` under `:us` is shown in `lb` — and any other quantity is shown as under `:as_posted`. Under **`:as_posted`**, the default, a value keeps its unit's own family and is only rescaled within it, which is D-138's display scaling unchanged. "Imperial" alone is not a system: a US and an imperial gallon are 20% apart, and the UK writes stones, imperial pints and °C. A preference that crosses dimensions is **not** a system switch and stays a per-field choice — a glucose reading in `mg/dl` against `mmol/l`, which needs the molar mass, or a pace against a speed, its reciprocal.

**The measure.** A unit and a quantity together are a *measure*, `%{unit: code | nil, quantity: quantity | nil}`, the two facts a field description carries (#535). `Visualize.Quantity.resolve/1` completes and checks one: the unit is checked (§4.1); a missing quantity is the one the unit's dimension implies — the table's dimension, a dimensionless unit holding `%` being `:ratio` and any other dimensionless one `:count`, and a code of one currency alone (`{iso4217:USD}`) `:currency` — or `nil` when no quantity has that dimension (`rad/s`, `Cel/s`, a bare `dB`); a missing unit is the quantity's base unit (`nil` for a `:currency`, whose code the data must say); a unit whose dimension is not its quantity's (`By` as a `:duration`, `dB` as a `:sound_level`) is `{:error, {:quantity, quantity, code}}`; a `:ratio` or a `:count` takes any dimensionless unit, and a `:currency` a code of one currency alone — `{iso4217:USD}`, not `{iso4217:USD}/h`, whose quantity is none of the list. It returns `{:ok, %{unit: code | nil, quantity: quantity | nil}}`, `{:error, {:unit, code, reason}}` for a code that does not read, `{:error, {:unknown_quantity, term}}` for a quantity not in the list, or the mismatch. `Visualize.Quantity.of_unit/1` is the inference alone.

**Unit and quantity are facts about the data, not knobs.** Neither changes what a value is; they say what it already is, so a display can choose for it. What a reader sees — the format, the tick count — stays the design's to override (§3, spec/14 §4.4), and the unit system is the viewer's; there is no setting that picks decimal against binary apart from the data.

### 4.3 Display scaling

**The display unit** of a domain in a measure, `Visualize.Quantity.display_unit(domain, measure, opts)` with `system:` (default `:as_posted`), is the member of the family the system chooses (§4.2) that fits the domain's magnitude `M`, the greatest `|d|` among its numbers: the **largest member in which `M` is at least 1**, else the smallest. So 0–1,500 `ms` is shown in `s` (`M` = 1.5 s), 0–900 `ms` in `ms`, 0–90 `s` in `min`, 0–1,500,000 `By` in `MBy`, 0–0.5 `/s` in `/min`, 0–3,000 `W` in `kW`, 0–0.5 `m` in `cm`; and under `system: :us`, 0–80 `kg` in `[lb_av]`, 0–5,000 `m` in `[mi_i]`, 0–20 `l` in `[gal_us]`, and `Cel` in `[degF]`. A family of one member is that member whatever the magnitude. A measure whose unit belongs to no family under the system, no quantity, or a unit without a factor (`Cel`) in its own family keeps the unit it has; at `M = 0` the unit is kept when it is in the family, and otherwise the member nearest it by factor is taken.

**The tick formatter** of a scale in a measure, `Visualize.Quantity.formatter(scale, measure, opts)` (`count:` and `locale:` as `Visualize.Format.Auto.formatter/2`, and `system:` as `display_unit/3`), writes every tick in the display unit:

- on `Linear`, `Power` and `Radial`: the domain converted to the display unit, its `Visualize.Format.Auto.notation/2` — `{:si, 3}` in place of `:grouped` for a `:count`, whose family is SI from a thousand (`1.2k`, `90k`), one prefix for the axis as ever — and each tick converted, written by `Visualize.Format.Auto.number/2` of that notation, then the display unit's symbol: `0 s`, `0.5 s`, `1 s`, `1.5 s` for 0–1,500 `ms`;
- on `Log` and `Symlog`, whose ticks are powers of ten in the scale's unit: each tick in its **own** display unit, the largest in which it is at least 1 among the family members a power of ten from the unit — so a tick lands on a round number, `1 ms`, `10 ms`, `100 ms`, `1 s`, `10 s`, `100 s`, `1k s`, never `1.67 min` — written by `Visualize.Format.Auto.number(:si)` as #532's log axis is; `0` and a quantity with no family keep the unit;
- on any other scale (`Time`, `Band`, `Ordinal`, the discretising scales): `Visualize.Format.Auto.formatter/2`, the measure unused.

**Ticks in the display unit** (#594, D-156). When the display unit differs from the scale's unit — a family scaled (0–100 `s` shown in `min`) or a system switched (0–40 `kg` shown in `[lb_av]` under `:us`) — the round numbers of the axis are chosen **in the display unit**: `Visualize.Quantity.ticks(scale, measure, opts)` (`count:` default `10`, and `system:` as `display_unit/3`) is `Visualize.Scale.ticks/2` at that count over the scale's domain converted into the display unit (d3's ticks of the converted domain; the scale's own domain is not niced again, because it is the data's), each tick converted back into the scale's unit by `Visualize.Unit.convert/3` for placement. 0–40 `kg` under `:us` ticks at `0 lb`, `20 lb`, `40 lb`, `60 lb`, `80 lb`, placed at 0, 9.0718474, 18.1436948, … `kg`; 0–100 `s` ticks at `0 min`, `0.2 min` … `1.6 min`, placed at 0, 12, … 96 `s`; never `88.184905 lb` or `1.6667 min`. The formatter of the same scale, measure, `count:` and `system:` labels each of those placed values with the round number it was converted from, not with the value converted back again, so a label never carries the round trip's last bit (`19.999999999999996 lb`). `ticks/3` is `nil` — the scale's own ticks, as before — when the display unit is the unit, when the measure has no unit or quantity, for a `:currency`, which never converts, and on any scale but `Linear`, `Power` and `Radial`: a `Log` or `Symlog` scale keeps its powers of ten and gives each its own unit as above.

The symbol follows the number after a space (`1.5 s`, `20 °C`, `2.5 MB`), except `%`, the degree `°` and a symbol that begins with `/`, which follow it directly (`45%`, `350°`, `12/s`); an empty symbol (`1`, `{request}`) adds nothing. A **`:currency`** measure in one code is written as money (#593, D-155): the domain's notation, `{:si, 3}` in place of `:grouped` as for a `:count`, then the code's symbol in the locale before the number and after its sign (`$0`, `$0.5k`, `$1.5k`, `-€2M`), or the code after it for a code the locale has no symbol for (`1.5k CHF`). A non-number is `to_string/1`. The function is pure, so an axis on a moving domain re-derives its display unit with its format on every realisation (spec/14 §12.5).

**One value: a label or a tooltip.** `Visualize.Quantity.format(value, measure, opts)` writes one value of a measure for a label or a tooltip, not an axis (#593, D-155; the formats metresis's views wrote, moved into the library): with `precision:` (default `2`), `locale:` (default `"en"`) and `system:` (default `:as_posted`; under another, the value is first converted into its `display_unit/3`), it is

- a `:duration`: `Visualize.Format.duration(seconds, style: :compound, precision: precision)` of the value in seconds (§2.9) — `1h 24m`, `840ms`;
- a `:currency` in one code: `Visualize.Format.currency(value, code: code)` (§2.6), its minor units and not `precision` — `$1,240.00`, `¥1,240`;
- a `:count`: the value rounded to an integer and grouped (`1,240`);
- anything else, a measure with no quantity included: the value to `precision` decimals, ungrouped, then the unit's suffix as above — `91.40%`, `0.91`, `350°` (precision 0), `1.20 rad`, `20.50 kg`, `1013.25 hPa`, `20.00 °C`.

**The label rule.** `Visualize.Quantity.label(measure)` is what a title says about a measure: **the unit, else the quantity, else nothing** — the symbol of the unit with its annotations written (`ms`, `kW·h`, `request/s`, `request`) when it is not empty, else the quantity's name with its underscores as spaces (`count`, `ratio`, `data rate`), else `nil`. An axis that draws its measure applies it to what its ticks cannot say (spec/14 §4.4).

### 4.4 Functions

| Function | Contract |
|---|---|
| `Visualize.Unit.parse/1` | `{:ok, components}` for a code (4.1), each `%{prefix: String.t() \| nil, atom: String.t() \| nil, factor: pos_integer() \| nil, annotation: String.t() \| nil, exponent: integer()}` with a quotient's exponent negated; `{:error, reason}` — `:empty`, `{:syntax, rest}` at the first character that does not read, `{:unknown_atom, symbol}`, `{:not_metric, prefix, atom}`, `{:unknown_currency, code}` for an `{iso4217:…}` annotation whose code is not in the table. |
| `Visualize.Unit.valid?/1` | Whether a string is a code (4.1). |
| `Visualize.Unit.parse_alias/1` | `{:ok, code}` for a symbol a person types, by the alias table and then `parse/1`; `{:error, {:ambiguous, alias, [{code, meaning}, …]}}` naming the choices, or `{:error, {:unknown_alias, string}}` (4.1). |
| `Visualize.Unit.format_error/1` | A refusal of `parse/1`, `parse_alias/1` or `conversion/2` as a line a person reads (4.1). |
| `Visualize.Unit.currency/1` | The ISO 4217 code a code is in when it is a currency alone (`{iso4217:USD}` → `"USD"`), else `nil` (4.1). |
| `Visualize.Unit.minor_units/1` | An ISO 4217 code's minor units, `nil` for none; `ArgumentError` for a code not in the table (4.1). |
| `Visualize.Unit.kind/1` | `:linear`, `:affine` (a code holding `Cel` or `[degF]`) or `:logarithmic` (one holding `B` or `B[SPL]`); raises `ArgumentError` for a code that does not read (4.1). |
| `Visualize.Unit.dimension/1` | The dimension of a code, a map from `:time`, `:information`, `:length`, `:mass`, `:temperature`, `:angle`, `:charge`, `:luminous_intensity`, `:level`, `:sound_pressure_level` and `{:currency, code}` to a non-zero exponent (`%{}` dimensionless); raises `ArgumentError` for a code that does not read. |
| `Visualize.Unit.factor/1` | The factor of a code to its base, an exact `{numerator, denominator}`, `{numerator, denominator, k}` for one holding π (n/d·πᵏ), or `nil` for one holding an affine unit; raises as `dimension/1`. |
| `Visualize.Unit.conversion/2` | `{:ok, {scale, offset}}`, exact, so that `value × scale + offset` converts `from` to `to`; `{:error, reason}` — `{:dimension, from, to}`, `{:logarithmic, from, to}`, `{:currency, from, to}`, `{:affine_in_term, code}`, or a reason of `parse/1` (4.1). |
| `Visualize.Unit.convert/3` | `value × scale + offset` of `conversion/2` as a float; `ArgumentError` naming the reason for a pair it refuses (4.1). |
| `Visualize.Unit.symbol/1` | As `symbol/2` with `[]` options. |
| `Visualize.Unit.symbol/2` | The display symbol of a code, `annotations:` (default `false`) writing a lone annotation's text (4.1). |
| `Visualize.Unit.from_telemetry/1` | `{:ok, code}` for a `Telemetry.Metrics` unit atom or `{from, to}` pair, `{:error, :native}`, `{:error, {:unknown, atom}}` (4.1). |
| `Visualize.Quantity.all/0` | The fixed list of quantities, in the order of 4.2. |
| `Visualize.Quantity.base_unit/1` | A quantity's base unit (4.2); `nil` for `:currency`. |
| `Visualize.Quantity.kind/1` | `:linear`, `:affine`, `:logarithmic` or `:cyclic` (4.2). |
| `Visualize.Quantity.bounds/1` | A quantity's bounds in its base unit, `{min \| nil, max \| nil}`: a display hint, never validation (4.2). |
| `Visualize.Quantity.bounds/2` | `bounds(quantity, unit)`: the bounds converted into the unit (4.2). |
| `Visualize.Quantity.additivity/1` | As `additivity/2` with no metric kind: the quantity's defaults. |
| `Visualize.Quantity.additivity/2` | `additivity(quantity \| nil, metric_kind \| nil)`: `%{across: boolean, over_time: boolean}`, the quantity's defaults refined by `:gauge`, `:counter` or `:rate` (4.2). |
| `Visualize.Quantity.systems/0` | `[:metric, :us, :uk, :as_posted]` (4.2). |
| `Visualize.Quantity.family/2` | `family(quantity, unit)`: the display family a unit of the quantity belongs to, smallest first, `[]` for none (4.2). |
| `Visualize.Quantity.family/3` | `family(quantity, unit, system)`: the family the system shows a unit of the quantity in — the system's own when the quantity has one, else the unit's (4.2). |
| `Visualize.Quantity.of_unit/1` | The quantity a code's dimension implies, or `nil` (4.2). |
| `Visualize.Quantity.resolve/1` | A measure completed and checked: `{:ok, measure}` or `{:error, reason}` (4.2). |
| `Visualize.Quantity.display_unit/2` | As `display_unit/3` with `[]` options. |
| `Visualize.Quantity.display_unit/3` | `display_unit(domain, measure, system: system)`: the member of the system's family that fits the domain (4.3). |
| `Visualize.Quantity.formatter/2` | As `formatter/3` with `[]` options. |
| `Visualize.Quantity.formatter/3` | `formatter(scale, measure, opts)`: the tick formatter in the display unit, with its symbol, labelling the placed values of `ticks/3` with their round numbers (4.3); `count:`, `locale:`, `system:`; raises `ArgumentError` for a measure `resolve/1` refuses. |
| `Visualize.Quantity.ticks/2` | As `ticks/3` with `[]` options. |
| `Visualize.Quantity.ticks/3` | `ticks(scale, measure, opts)`: the tick values, in the scale's unit, of round numbers in the display unit when it differs from the unit on a `Linear`, `Power` or `Radial` scale, else `nil` (4.3); `count:`, `system:`. |
| `Visualize.Quantity.suffix/1` | The tick suffix of a display unit: `""`, or its symbol with its separator (4.3). |
| `Visualize.Quantity.format/2` | As `format/3` with `[]` options. |
| `Visualize.Quantity.format/3` | `format(value, measure, opts)`: one value for a label or a tooltip — a compound duration, money in its code, a grouped count, else fixed decimals and the suffix (4.3); `precision:`, `locale:`, `system:`. |
| `Visualize.Quantity.label/1` | The label rule: the unit, else the quantity, else `nil` (4.3). |
