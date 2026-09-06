# Axes and Formatting

**Status:** Implemented

`Visualize.Axis` builds a reference axis — domain line, tick marks, and labels — for any scale that implements `ticks/2` and `apply/2`, returning a backend-neutral `Visualize.IR.Element` group that `Visualize.Render` serialises. `Visualize.Format` supplies the label formatters an axis (or any chart text) uses: grouped numbers, SI prefixes, percentages, currency, exponential and fixed notation, a D3-style specifier parser, and a strftime-like date formatter. Sizes are in user units (pixels under SVG).

## 1. `Visualize.Axis`

### 1.1 Struct

```
%Visualize.Axis{
  scale: nil, orient: :bottom,
  ticks: nil, tick_values: nil, tick_format: nil,
  tick_size_inner: 6, tick_size_outer: 6, tick_padding: 3, offset: 0
}
```

`orient` is one of `:top`, `:right`, `:bottom`, `:left`. The four constructors each take a scale struct and set the orientation. The scale MUST implement `ticks/2` and `apply/2` (see spec/03 section 1.3: `Power`, `Symlog`, `Quantile`, `Quantize`, and `Threshold` do not, and cannot be used with `Axis` until that decision is implemented).

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

### 1.3 Orientation Parameters

| Orient | `k` | Tick axis | Tick group transform | `text-anchor` |
|---|---|---|---|---|
| `:top` | `−1` | x | `translate(pos, 0)` | `:middle` |
| `:bottom` | `+1` | x | `translate(pos, 0)` | `:middle` |
| `:left` | `−1` | y | `translate(0, pos)` | `:end` |
| `:right` | `+1` | y | `translate(0, pos)` | `:start` |

`k` is the direction multiplier: ticks extend away from the plot area. `pos = Scale.apply(scale, value) + offset`.

### 1.4 Element Structure

`generate/1` returns:

```
group  style: %{fill: :none, font_size: 10, font_family: "sans-serif", text_anchor: <1.3>}
├── path   style: %{stroke: :current_color}          — the domain line
└── group  style: %{class: "tick"}, transform: <1.3>  — one per tick value
    ├── line  attrs: %{x1: 0, y1: 0, x2: …, y2: …}, style: %{stroke: :current_color}
    └── text  attrs: %{x | y, dy}, style: %{fill: :current_color}, content: label
```

Domain line path, with `[r0, r1]` the scale's range and `o = tick_size_outer`:

- `:top`/`:bottom`: `M r0,k·o  V 0  H r1  V k·o`
- `:left`/`:right`: `M k·o,r0  H 0  V r1  H k·o`

The range is read from `scale.range` when it is a two-element list; any other shape (e.g. the tuple ranges of `Power`/`Symlog`) falls back to `[0, 1]`.

Tick line: `:top`/`:bottom` from `(0, 0)` to `(0, k·inner)`; `:left`/`:right` from `(0, 0)` to `(k·inner, 0)`.

Tick label attributes, with `i = tick_size_inner`, `p = tick_padding`:

| Orient | Attributes | Intended |
|---|---|---|
| `:top` | `y: −k·i − p` (evaluates to `i − p`), `dy: "0em"` | `y: k·(i + p)` |
| `:bottom` | `y: k·i + p`, `dy: "0.71em"` | as coded |
| `:left` | `x: k·i − p`, `dy: "0.32em"` | as coded |
| `:right` | `x: k·i + p`, `dy: "0.32em"` | as coded |

For `:top`, `k = −1` makes `−k·i − p = i − p` (`+3` at defaults), placing the label *below* the axis line, inside the plot; the label MUST sit at `−(i + p)`.

> Decision: see spec/13 — the `:top` label offset is to be `k·(tick_size_inner + tick_padding)`.

### 1.5 Tick Values and Labels

Tick values are `tick_values` when set, else `Scale.ticks(scale, ticks || 10)`. For a `Band` or `Ordinal` scale that is the domain; the tick is placed at `apply/2`, i.e. the **band start**. D3 centres band ticks by adding `bandwidth / 2`; callers wanting centred ticks MUST add it through `offset/2`.

> Decision: see spec/13 — `Axis` SHOULD centre ticks on band scales by adding half the bandwidth to the position.

Default label (no `tick_format`): floats are rounded to 6 decimal places and printed with trailing zeros and a trailing `.` removed (`2.0 → "2"`, `0.1 + 0.2 → "0.3"`); any other value is `to_string/1` (`DateTime` therefore prints ISO 8601). A custom formatter receives the raw tick value.

### 1.6 Rendering

`render/1,2` is `generate/1` followed by `Visualize.Render.to_string/2` with the same options. `:backend` is `:svg`, `:canvas`, or a backend module; when omitted the configured default (`config :visualize, default_backend:`, itself defaulting to `:svg`) applies. Other options pass through to the backend.

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
| `Visualize.Axis.generate/1` | Returns the `IR.Element` group described in 1.4. |
| `Visualize.Axis.render/1` | As `render/2` with `[]` options. |
| `Visualize.Axis.render/2` | Renders `generate/1` through `Visualize.Render.to_string/2`; returns a string. |

## 2. `Visualize.Format`

### 2.1 `number/1,2`

Options: `:precision` (decimal places; default automatic), `:separator` (thousands, default `","`), `:decimal` (decimal point, default `"."`).

- Integer input: no fraction unless `:precision` is given, in which case that many `"0"`s.
- Float input: automatic precision is `0` for `|v| ≥ 100`, `1` for `≥ 10`, `2` for `≥ 1`, else `3`. The value is rounded to the precision; the fraction is padded/truncated to exactly `precision` digits; `precision: 0` yields no fraction.
- The integer part is grouped in threes from the right.

Grouping operates on the signed digit string, so a negative integer part whose digit count is a multiple of three gains a stray separator (`−123456 → "-,123,456"`). Intended: the sign is stripped before grouping and restored afterwards (`"-123,456"`).

> Decision: see spec/13 — `Format.number/2` MUST group the magnitude and prepend the sign.

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

Parses a D3-like specifier string and returns a 1-arity formatter. Precision is the digits after the first `.` in the specifier (`~r/\.(\d+)/`). Detection is by substring, tested **in this order**; the first match wins:

| Contains | Formatter |
|---|---|
| `s` | `si(v, precision: p \|\| 3)` |
| `%` | `percent(v, precision: p \|\| 1)` |
| `e` | `exponential(v, precision: p \|\| 2)` |
| `f` | `number(v, precision: p \|\| 2)` when the specifier also contains `,`; else `fixed(v, p \|\| 2)` |
| `d` | `number(round(v))` with `,`; else `Integer.to_string(round(v))` |
| none | `to_string/1` |

Because detection is by substring, any specifier containing `s` (or `e`) selects that branch irrespective of position; `formatter/1` is not a full D3 format parser and does not support fill, alignment, sign, `#`, zero-padding, width, `~`, or the `g`, `r`, `b`, `o`, `x`, `X`, `c` types.

### 2.8 `time/1,2`

`time(value, format \\ "%Y-%m-%d")` accepts `DateTime`, `Date`, or `NaiveDateTime` (a `Date` has hour, minute, and second `0`). Directives are replaced sequentially by `String.replace/3` in the order listed; unknown directives and all other text pass through verbatim, and there is no escape for a literal `%`.

| Directive | Value |
|---|---|
| `%Y` | 4-digit year, zero-padded |
| `%m` | 2-digit month |
| `%d` | 2-digit day of month |
| `%H` | 2-digit hour, 24-hour clock |
| `%M` | 2-digit minute |
| `%S` | 2-digit second |
| `%b` | abbreviated English month name (`Jan` … `Dec`) |
| `%B` | full English month name |

No other strftime directive (`%y`, `%j`, `%a`, `%A`, `%I`, `%p`, `%Z`, `%z`, `%f`, `%%`, …) is supported. Time zones are ignored; the struct's fields are printed as stored.

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
| `Visualize.Format.formatter/1` | Returns a formatter function for a specifier (2.7). |
| `Visualize.Format.time/1` | As `time/2` with format `"%Y-%m-%d"`. |
| `Visualize.Format.time/2` | Directive substitution over a date/time struct (2.8). |
