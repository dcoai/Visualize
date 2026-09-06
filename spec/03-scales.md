# Scales

**Status:** Implemented

Scales map values from a data *domain* to a visual *range*. `Visualize.Scale` is a facade that constructs every scale kind and dispatches the common operations (`domain/2`, `range/2`, `apply/2`, `invert/2`, `ticks/1,2`, `nice/1`, `padding/2`, `bandwidth/1`, `clamp/2`) to the module named by the scale struct. This document specifies the facade protocol, then each scale module: `Linear`, `Log`, `Power`, `Symlog`, `Time`, `Ordinal`, `Band`, `Quantile`, `Quantize`, `Threshold`, and `Color`. Every scale is an immutable struct; setters return a new struct and never mutate.

## 1. Common Model

### 1.1 Scale Families

| Family | Modules | Domain | Range | Output |
|---|---|---|---|---|
| Continuous | `Linear`, `Log`, `Power`, `Symlog`, `Time` | two numbers (or two time values) | two numbers | float, interpolated |
| Discrete | `Ordinal`, `Band` | list of categories | list of values / two numbers | range element / band start |
| Discretising | `Quantile`, `Quantize`, `Threshold` | samples / two numbers / thresholds | list of values | range element |
| Colour | `Color` | two or three numbers | scheme, colour list, or function | `"#rrggbb"` string |

### 1.2 Domain and Range Representation

Continuous domains and ranges are **two-element lists** `[d0, d1]` / `[r0, r1]` for `Linear`, `Log`, `Time`, `Band`, and `Color`. `Power`, `Symlog`, and `Quantize` accept either a two-element list or a two-tuple and **store a two-tuple** `{d0, d1}`. Callers MUST NOT pattern-match on the stored representation; they MUST use the module's accessors.

> Decision: see spec/13 — the stored representation is to be unified as a two-element list across all continuous scales; the tuple form in `Power`, `Symlog`, and `Quantize` is an inconsistency, and `Visualize.Axis` (spec/05) reads `scale.range` as a list and falls back to `[0, 1]` for tuple ranges.

Domains MAY be descending (`d0 > d1`) and ranges MAY be descending (`r0 > r1`); the interpolation formulae below are sign-agnostic. Degenerate domains (`d0 == d1`) are not guarded and MUST be avoided by the caller: `apply/2` divides by zero.

### 1.3 The Facade Protocol

`Visualize.Scale.<op>(scale, …)` calls `scale.__struct__.<op>(scale, …)`. A scale module is *protocol-complete* when it defines all of: `domain/2`, `range/2`, `apply/2`, `invert/2`, `ticks/2`, `nice/1`, `padding/2`, `bandwidth/1`, `clamp/2`. Operations that do not apply to a scale kind MUST still be defined and MUST behave as identity (`nice/1`, `padding/2`, `clamp/2`), return `nil` (`invert/2`), or return `0` (`bandwidth/1`).

The table records what each module actually defines.

| Module | `apply/2` | `invert/2` | `ticks/2` | `nice/1` | `padding/2` | `bandwidth/1` | `clamp/2` | Facade constructor |
|---|---|---|---|---|---|---|---|---|
| `Linear` | yes | yes | yes | yes | identity | `0` | yes | `linear/0` |
| `Log` | yes | yes | yes | yes | identity | `0` | yes | `log/0,1` |
| `Time` | yes | yes | yes | yes | identity | `0` | yes | `time/0` |
| `Ordinal` | yes | `nil` | domain | identity | identity | `0` | identity | `ordinal/0` |
| `Band` | yes | `nil` | domain | identity | yes | yes | identity | `band/0` |
| `Color` | yes | `nil` | sequential only | identity | identity | `0` | yes | `sequential/1`, `diverging/1` |
| `Power` | **`scale/2`** | yes | yes | — | — | — | yes | `power/0`, `sqrt/0` |
| `Symlog` | **`scale/2`** | yes | yes | — | — | — | yes | `symlog/0` |
| `Quantile` | **`scale/2`** | — | — | — | — | — | — | `quantile/0` |
| `Quantize` | **`scale/2`** | — | — | — | — | — | — | `quantize/0` |
| `Threshold` | **`scale/2`** | — | — | — | — | — | — | — |

`Power`, `Symlog`, `Quantile`, `Quantize`, and `Threshold` name their mapping function `scale/2` rather than `apply/2`, and omit the remaining protocol functions. Consequently `Visualize.Scale.apply/2` raises `UndefinedFunctionError` for a scale returned by `Visualize.Scale.power/0`, `sqrt/0`, `symlog/0`, `quantile/0`, or `quantize/0`, as do `nice/1`, `padding/2`, and `bandwidth/1`; `Visualize.Scale.invert/2` and `ticks/2` additionally raise for the three discretising scales. `Visualize.Axis` therefore cannot be built on any of these five scales. `Threshold` has no facade constructor at all.

> Decision: see spec/13 — every scale module MUST be protocol-complete under the name `apply/2`. `scale/2` on the five modules is to be retained as an alias of `apply/2` for one release and then removed; `Quantile`/`Quantize`/`Threshold` MUST define `invert/2` returning `nil`, `ticks/2` returning their thresholds, and identity `nice/1`/`padding/2`/`clamp/2`; `Power`/`Symlog` MUST define `nice/1` (delegating to `Linear.nice/1` on the domain) and identity `padding/2`/`bandwidth/1`; and the facade MUST gain `threshold/0`.

### 1.4 Clamping

`clamp/2` takes a boolean. The default is `false` for every scale except `Color`, whose default is `true`. When enabled, `Linear`, `Log`, `Time`, and `Color` clamp the normalised parameter `t` to `[0, 1]` before interpolating; `Power` and `Symlog` clamp the *output* to `[min(r0, r1), max(r0, r1)]`. The two formulations are equivalent for linear interpolation. `invert/2` never clamps.

## 2. `Visualize.Scale` Facade

| Function | Contract |
|---|---|
| `Visualize.Scale.linear/0` | Returns `Visualize.Scale.Linear.new/0`: domain `[0, 1]`, range `[0, 1]`. |
| `Visualize.Scale.log/0` | As `log/1` with base 10. |
| `Visualize.Scale.log/1` | Returns `Visualize.Scale.Log.new/1` with the given base. |
| `Visualize.Scale.power/0` | Returns `Visualize.Scale.Power.new/0` (exponent 1). |
| `Visualize.Scale.sqrt/0` | Returns `Visualize.Scale.Power.sqrt/0` (exponent 0.5). |
| `Visualize.Scale.symlog/0` | Returns `Visualize.Scale.Symlog.new/0`. |
| `Visualize.Scale.time/0` | Returns `Visualize.Scale.Time.new/0`. |
| `Visualize.Scale.ordinal/0` | Returns `Visualize.Scale.Ordinal.new/0`. |
| `Visualize.Scale.band/0` | Returns `Visualize.Scale.Band.new/0`. |
| `Visualize.Scale.quantize/0` | Returns `Visualize.Scale.Quantize.new/0`. |
| `Visualize.Scale.quantile/0` | Returns `Visualize.Scale.Quantile.new/0`. |
| `Visualize.Scale.sequential/1` | Returns `Visualize.Scale.Color.sequential/1`. |
| `Visualize.Scale.diverging/1` | Returns `Visualize.Scale.Color.diverging/1`. |
| `Visualize.Scale.domain/2` | Dispatches to the scale module's `domain/2`. |
| `Visualize.Scale.range/2` | Dispatches to the scale module's `range/2`. |
| `Visualize.Scale.apply/2` | Dispatches to the scale module's `apply/2`; maps a domain value to a range value. Raises `UndefinedFunctionError` for the five `scale/2` modules (see 1.3). |
| `Visualize.Scale.invert/2` | Dispatches to the scale module's `invert/2`; maps a range value back to the domain. Continuous scales only; discrete scales return `nil`. |
| `Visualize.Scale.ticks/1` | As `ticks/2` with count 10. |
| `Visualize.Scale.ticks/2` | Dispatches to the scale module's `ticks/2`; returns representative domain values, ascending for continuous scales, the domain itself for discrete scales. `count` is a hint, not a guarantee. |
| `Visualize.Scale.nice/1` | Dispatches to the scale module's `nice/1`; extends the domain outward to round values. |
| `Visualize.Scale.padding/2` | Dispatches to the scale module's `padding/2`; meaningful only for `Band`. |
| `Visualize.Scale.bandwidth/1` | Dispatches to the scale module's `bandwidth/1`; `0` for every scale but `Band`. |
| `Visualize.Scale.clamp/2` | Dispatches to the scale module's `clamp/2` with a boolean. |

## 3. `Visualize.Scale.Linear`

### 3.1 Struct

`%Visualize.Scale.Linear{domain: [0, 1], range: [0, 1], clamp?: false}`.

### 3.2 Semantics

- `apply/2`: `t = (v − d0) / (d1 − d0)`; if `clamp?`, `t` is clamped to `[0, 1]`; result is `r0 + t · (r1 − r0)`, always a float.
- `invert/2`: `t = (v − r0) / (r1 − r0)`; result `d0 + t · (d1 − d0)`. Never clamps.
- `ticks/2` (count `n`): the *nice step* is computed from `span = |d1 − d0|`, `raw = span / max(n, 1)`, `mag = 10^⌊log10 raw⌋`, `q = raw / mag`, and factor `1` if `q < 1.5`, `2` if `q < 3`, `5` if `q < 7`, else `10`; `step = factor · mag`. Ticks run from `⌈d0/step⌉·step` to `⌊d1/step⌋·step` inclusive, each rounded to `max(0, −⌊log10 step⌋)` decimal places. The tick count is approximately `n`; it is never guaranteed.
- `nice/1`: with the step for count 10, domain becomes `[⌊d0/step⌋·step, ⌈d1/step⌉·step]` (floats).
- `padding/2` is identity; `bandwidth/1` is `0`.

A descending domain (`d0 > d1`) yields the same ticks in descending order (the iteration range descends). A degenerate domain (`d0 == d1`) MUST yield `[d0]` from `ticks/2` and leave `nice/1` unchanged; the code raises `ArithmeticError` on `log10(0)` in both.

> Decision: see spec/13 — `Linear.ticks/2` and `nice/1` are to short-circuit on a zero span.

### 3.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Linear.new/0` | Returns the default struct. |
| `Visualize.Scale.Linear.domain/2` | Sets the domain; the argument MUST be a two-element list of numbers. |
| `Visualize.Scale.Linear.range/2` | Sets the range; the argument MUST be a two-element list of numbers. |
| `Visualize.Scale.Linear.clamp/2` | Sets `clamp?`. |
| `Visualize.Scale.Linear.apply/2` | Linear interpolation as in 3.2; returns a float. |
| `Visualize.Scale.Linear.invert/2` | Inverse interpolation as in 3.2; returns a float. |
| `Visualize.Scale.Linear.ticks/2` | Nice-step ticks as in 3.2. |
| `Visualize.Scale.Linear.nice/1` | Extends the domain to multiples of the count-10 nice step. |
| `Visualize.Scale.Linear.padding/2` | Identity. |
| `Visualize.Scale.Linear.bandwidth/1` | Returns `0`. |

## 4. `Visualize.Scale.Log`

### 4.1 Struct

`%Visualize.Scale.Log{domain: [1, 10], range: [0, 1], base: 10, clamp?: false}`.

### 4.2 Semantics

All logarithms are `log(x) / log(base)`.

- `domain/2` requires both bounds `> 0`; any other input fails to match (`FunctionClauseError`).
- `apply/2` requires `value > 0` (`FunctionClauseError` otherwise). `t = (log v − log d0) / (log d1 − log d0)`, clamped to `[0, 1]` when `clamp?`; result `r0 + t · (r1 − r0)`.
- `invert/2`: `t = (v − r0) / (r1 − r0)`; result `base ^ (log d0 + t · (log d1 − log d0))`.
- `ticks/2`: the integer powers `base^k` for `k` from `⌈log d0⌉` to `⌊log d1⌋`. **The count argument is ignored**; a domain spanning many decades returns one tick per decade regardless of count, and a sub-decade domain MAY return `[]`.
- `nice/1`: domain becomes `[base^⌊log d0⌋, base^⌈log d1⌉]`.
- `padding/2` identity; `bandwidth/1` `0`.

### 4.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Log.new/0` | As `new/1` with base 10. |
| `Visualize.Scale.Log.new/1` | Returns a log scale with the given base (any number `> 0`, `≠ 1`). |
| `Visualize.Scale.Log.domain/2` | Sets the domain; both values MUST be positive. |
| `Visualize.Scale.Log.range/2` | Sets the range (two-element list). |
| `Visualize.Scale.Log.clamp/2` | Sets `clamp?`. |
| `Visualize.Scale.Log.apply/2` | Log interpolation as in 4.2; `value` MUST be positive. |
| `Visualize.Scale.Log.invert/2` | Inverse as in 4.2. |
| `Visualize.Scale.Log.ticks/2` | Integer powers of the base within the domain; count ignored. |
| `Visualize.Scale.Log.nice/1` | Extends the domain to integer powers of the base. |
| `Visualize.Scale.Log.padding/2` | Identity. |
| `Visualize.Scale.Log.bandwidth/1` | Returns `0`. |

## 5. `Visualize.Scale.Power`

### 5.1 Struct

`%Visualize.Scale.Power{domain: {0, 1}, range: {0, 1}, exponent: 1, clamp?: false}`. `domain/2` and `range/2` accept a two-element list or a two-tuple and store a tuple.

### 5.2 Semantics

Let `e` be the exponent and `P(x) = |x|^e`.

- `scale/2`: `D = P(d1) − P(d0)`; `t = 0` if `D == 0`, else `(P(v) − P(d0)) / D`; `t` is negated when `v < 0`; result `r0 + t · (r1 − r0)`; when `clamp?`, the result is clamped to the range bounds in either order.
- `invert/2`: `t = (v − r0) / (r1 − r0)` (`0` if `r1 == r0`); result `(P(d0) + t · D)^(1/e)`. No sign handling: the result is always non-negative.
- `ticks/1,2`: delegate to `Linear.ticks/2` on `[d0, d1]` (linear spacing in the domain, not in the transformed space).
- `sqrt/0` is `new/0` with exponent 0.5.

The intended transform is D3's: `T(x) = sign(x) · |x|^e` applied uniformly to the domain bounds and the value, so that `t = (T(v) − T(d0)) / (T(d1) − T(d0))` and `invert` applies `T⁻¹`. The code applies `P` (absolute value, no sign) to the domain bounds and only negates `t` for a negative value, so any domain containing a negative bound (e.g. `[−10, 10]`, where `D = 0`) maps every value to `r0`, and `invert/2` cannot return a negative domain value.

> Decision: see spec/13 — `Power.scale/2` and `invert/2` MUST use the signed transform `T` on bounds and value alike.

### 5.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Power.new/0` | Returns the default struct (exponent 1). |
| `Visualize.Scale.Power.sqrt/0` | Returns a power scale with exponent 0.5. |
| `Visualize.Scale.Power.domain/2` | Sets the domain from a two-element list or tuple. |
| `Visualize.Scale.Power.range/2` | Sets the range from a two-element list or tuple. |
| `Visualize.Scale.Power.exponent/2` | Sets the exponent; MUST be a number. |
| `Visualize.Scale.Power.clamp/2` | Sets `clamp?`. |
| `Visualize.Scale.Power.scale/2` | Maps a domain value to the range as in 5.2. This is the `apply/2` operation under a non-protocol name (see 1.3). |
| `Visualize.Scale.Power.invert/2` | Inverse as in 5.2; result is non-negative. |
| `Visualize.Scale.Power.ticks/1` | As `ticks/2` with count 10. |
| `Visualize.Scale.Power.ticks/2` | `Linear.ticks/2` over the domain. |

## 6. `Visualize.Scale.Symlog`

### 6.1 Struct

`%Visualize.Scale.Symlog{domain: {−1, 1}, range: {0, 1}, constant: 1, clamp?: false}`. List or tuple accepted for `domain/2` and `range/2`; stored as tuples.

### 6.2 Semantics

The transform is `S(x) = sign(x) · ln(1 + |x| / c)` with inverse `S⁻¹(y) = sign(y) · c · (e^{|y|} − 1)`, where `c` is the constant (`> 0`, enforced by `constant/2`).

- `scale/2`: `t = (S(v) − S(d0)) / (S(d1) − S(d0))` (`0` if the denominator is zero); result `r0 + t · (r1 − r0)`, clamped to the range bounds when `clamp?`.
- `invert/2`: `t = (v − r0) / (r1 − r0)` (`0` if degenerate); result `S⁻¹(S(d0) + t · (S(d1) − S(d0)))`.
- `ticks/1,2` (count `n`): with `lo = min(d0, d1)`, `hi = max(d0, d1)`, the result is the ascending, de-duplicated union of: negated decades `−10^k` for `k` in `0, s, 2s, … ≤ ⌈log10(−lo)⌉` filtered to `≥ lo` (only when `lo < 0`); `0` when `lo ≤ 0 ≤ hi`; and decades `10^k` filtered to `(0, hi]` (only when `hi > 0`). The exponent stride is `s = max(1, ⌊⌈log10 bound⌉ / n⌋)`. The constant does not influence ticks. `10^0 = 1` is always a candidate; when `hi < 1` the positive list is empty.

### 6.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Symlog.new/0` | Returns the default struct. |
| `Visualize.Scale.Symlog.domain/2` | Sets the domain from a two-element list or tuple; MAY include zero and negatives. |
| `Visualize.Scale.Symlog.range/2` | Sets the range from a two-element list or tuple. |
| `Visualize.Scale.Symlog.constant/2` | Sets the linear/log transition constant; MUST be a number `> 0`. |
| `Visualize.Scale.Symlog.clamp/2` | Sets `clamp?`. |
| `Visualize.Scale.Symlog.scale/2` | Maps a domain value to the range as in 6.2 (`apply/2` under a non-protocol name, see 1.3). |
| `Visualize.Scale.Symlog.invert/2` | Inverse as in 6.2. |
| `Visualize.Scale.Symlog.ticks/1` | As `ticks/2` with count 10. |
| `Visualize.Scale.Symlog.ticks/2` | Signed decades and zero as in 6.2. |

## 7. `Visualize.Scale.Time`

### 7.1 Struct

`%Visualize.Scale.Time{domain: nil, range: [0, 1], clamp?: false}`. The domain MUST be set before use.

### 7.2 Accepted Value Types

Domain bounds and `apply/2` arguments MAY be any of `DateTime`, `Date`, `NaiveDateTime`, mixed freely. Each is reduced to Unix seconds: `DateTime` via `DateTime.to_unix/1`; `NaiveDateTime` as if UTC; `Date` as midnight UTC (`days since 1970-01-01 × 86400`). Sub-second precision is discarded.

`invert/2`, `ticks/2`, and `nice/1` always produce **UTC `DateTime`** values, whatever the domain's type. `invert/2` rounds to the nearest whole second.

### 7.3 Semantics

- `apply/2`: linear interpolation over Unix seconds, exactly as `Linear.apply/2`; clamps `t` when `clamp?`.
- `ticks/2` (count `n`): `target = span_seconds / n`; the interval is the first row of the table below whose seconds are `≥ target`, defaulting to `{86400, :day}` when none qualifies (i.e. when `target > 1 year`). The first tick is `d0` snapped by `ceil_to_interval`; subsequent ticks are produced by the step function until the tick exceeds `d1`.
- `nice/1`: chooses the interval for count 10 and sets the domain to `[floor_to_interval(d0), ceil_to_interval(d1)]`.

#### 7.3.1 Interval Table

| Seconds | Unit | Step |
|---|---|---|
| 1 | `:second` | + 1 s |
| 5 | `:second` | + 5 s |
| 15 | `:second` | + 15 s |
| 30 | `:second` | + 30 s |
| 60 | `:minute` | + 1 min |
| 300 | `:minute` | + 5 min |
| 900 | `:minute` | + 15 min |
| 1800 | `:minute` | + 30 min |
| 3600 | `:hour` | + 1 h |
| 10800 | `:hour` | + 3 h |
| 21600 | `:hour` | + 6 h |
| 43200 | `:hour` | + 12 h |
| 86400 | `:day` | + 1 day |
| 172800 | `:day` | + 2 days |
| 604800 | `:week` | + 7 days |
| 2592000 | `:month` | + 1 calendar month |
| 7776000 | `:month` | + 3 calendar months |
| 31536000 | `:year` | + 12 calendar months |

Sub-month steps add whole seconds. Month and year steps rewrite the `month`/`year` fields directly (`secs / 2592000` months), preserving the day-of-month without clamping.

#### 7.3.2 Snapping

| Interval | `ceil_to_interval` | `floor_to_interval` |
|---|---|---|
| `< 86400 s` | `⌈unix / secs⌉ · secs` | `⌊unix / secs⌋ · secs` |
| `:day` | midnight UTC of the value's **own** date | midnight UTC of the value's own date |
| `:week`, `:month`, `:year` | value unchanged (converted to `DateTime`) | value unchanged |

The intended behaviour is that every tick lies on an interval boundary within `[d0, d1]`, the `:day` ceiling is the *next* midnight when `d0` is not already at midnight, week/month/year ticks are snapped to Monday/first-of-month/first-of-year, month arithmetic clamps the day to the target month's length, and spans wider than `n` years select a multi-year interval from the linear nice-step sequence (2, 5, 10, … years). The code instead: floors the `:day` ceiling (the first tick MAY precede `d0`); does not snap week/month/year at all; can construct invalid dates (e.g. day 31 in a 30-day month) when stepping months; and, for spans wider than `n` years, falls back to **daily** ticks, producing thousands of values.

> Decision: see spec/13 — `Time.ticks/2` and `nice/1` are to snap on every interval, step months with day clamping, and extend the table with multi-year intervals.

### 7.4 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Time.new/0` | Returns the default struct with `domain: nil`. |
| `Visualize.Scale.Time.domain/2` | Sets the domain; a two-element list of `DateTime`, `Date`, or `NaiveDateTime`. |
| `Visualize.Scale.Time.range/2` | Sets the range (two-element list of numbers). |
| `Visualize.Scale.Time.clamp/2` | Sets `clamp?`. |
| `Visualize.Scale.Time.apply/2` | Maps a time value to the range as in 7.3; returns a float. |
| `Visualize.Scale.Time.invert/2` | Maps a range value to a UTC `DateTime` at whole-second precision. |
| `Visualize.Scale.Time.ticks/2` | Interval-based ticks as in 7.3; a list of UTC `DateTime`. |
| `Visualize.Scale.Time.nice/1` | Extends the domain to interval boundaries; the domain becomes UTC `DateTime` values. |
| `Visualize.Scale.Time.padding/2` | Identity. |
| `Visualize.Scale.Time.bandwidth/1` | Returns `0`. |

## 8. `Visualize.Scale.Ordinal`

### 8.1 Struct

`%Visualize.Scale.Ordinal{domain: [], range: [], unknown: nil}`.

### 8.2 Semantics

- `apply/2`: the index `i` of the first domain element equal (`==`) to the value; when not found the `unknown` value is returned. Otherwise `Enum.at(range, rem(i, length(range)))`: the range **cycles** when the domain is longer. The domain is never extended implicitly.
- An empty range with a found value raises `ArithmeticError` (`rem` by zero). Intended: return `unknown`.
- `invert/2` returns `nil`; `ticks/2` returns the domain (count ignored); `nice/1`, `clamp/2`, `padding/2` identity; `bandwidth/1` `0`.

> Decision: see spec/13 — `Ordinal.apply/2` with an empty range MUST return `unknown`.

### 8.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Ordinal.new/0` | Returns the default struct. |
| `Visualize.Scale.Ordinal.domain/2` | Sets the domain; MUST be a list. |
| `Visualize.Scale.Ordinal.range/2` | Sets the range; MUST be a list. |
| `Visualize.Scale.Ordinal.unknown/2` | Sets the value returned for inputs not in the domain (default `nil`). |
| `Visualize.Scale.Ordinal.apply/2` | Category lookup with cycling range as in 8.2. |
| `Visualize.Scale.Ordinal.invert/2` | Returns `nil`. |
| `Visualize.Scale.Ordinal.ticks/2` | Returns the domain. |
| `Visualize.Scale.Ordinal.nice/1` | Identity. |
| `Visualize.Scale.Ordinal.clamp/2` | Identity. |
| `Visualize.Scale.Ordinal.padding/2` | Identity. |
| `Visualize.Scale.Ordinal.bandwidth/1` | Returns `0`. |

## 9. `Visualize.Scale.Band`

### 9.1 Struct

`%Visualize.Scale.Band{domain: [], range: [0, 1], padding_inner: 0, padding_outer: 0, align: 0.5, round?: false}`.

### 9.2 Setters and Guards

| Setter | Constraint |
|---|---|
| `padding/2` | `0 ≤ p < 1`; sets both `padding_inner` and `padding_outer`. |
| `padding_inner/2` | `0 ≤ p < 1`. |
| `padding_outer/2` | `p ≥ 0` (no upper bound). |
| `align/2` | `0 ≤ a ≤ 1`. |
| `round/2` | boolean. |

Violations fail to match (`FunctionClauseError`).

### 9.3 Band Maths

With `n = length(domain)`, `pi = padding_inner`, `po = padding_outer`, `span = r1 − r0`:

- `n == 0`: `bandwidth = 0`, `step = 0`, `start = r0`.
- Otherwise `step = span / max(1, n − pi + 2·po)`, `bandwidth = step · (1 − pi)`, `start = r0 + (span − step · (n − pi)) · align`.
- Position of category at index `i` is `start + i · step`.
- When `round?` is true, `bandwidth/1` and `apply/2` return `Kernel.round/1` of the value (an integer); `step/1` is **not** rounded.

`apply/2` returns `nil` for a value not in the domain. `ticks/2` returns the domain; `invert/2` returns `nil`; `nice/1`, `clamp/2` identity.

Intended semantics for a descending range (`r1 < r0`) are D3's: bands are laid out in reverse order with positive `bandwidth` and `step`. The code computes a negative `span`, hence negative `step` and `bandwidth`. The `max(1, …)` guard on the denominator, and rounding `bandwidth` without rounding `step` (D3 floors both, and recomputes `start` from the rounded step), are further departures.

> Decision: see spec/13 — `Band` is to adopt D3's reverse-range handling and round `step` together with `bandwidth`.

### 9.4 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Band.new/0` | Returns the default struct. |
| `Visualize.Scale.Band.domain/2` | Sets the list of categories. |
| `Visualize.Scale.Band.range/2` | Sets the range (two-element list). |
| `Visualize.Scale.Band.padding/2` | Sets inner and outer padding together (`0 ≤ p < 1`). |
| `Visualize.Scale.Band.padding_inner/2` | Sets inner padding (`0 ≤ p < 1`). |
| `Visualize.Scale.Band.padding_outer/2` | Sets outer padding (`p ≥ 0`). |
| `Visualize.Scale.Band.align/2` | Sets the distribution of outer space (`0` = all at end, `0.5` = centred, `1` = all at start). |
| `Visualize.Scale.Band.round/2` | Enables integer rounding of positions and bandwidth. |
| `Visualize.Scale.Band.apply/2` | Returns the band start for a category, or `nil` if absent. |
| `Visualize.Scale.Band.invert/2` | Returns `nil`. |
| `Visualize.Scale.Band.bandwidth/1` | Returns the band width as in 9.3. |
| `Visualize.Scale.Band.step/1` | Returns the distance between adjacent band starts (never rounded). |
| `Visualize.Scale.Band.ticks/2` | Returns the domain. |
| `Visualize.Scale.Band.nice/1` | Identity. |
| `Visualize.Scale.Band.clamp/2` | Identity. |

## 10. `Visualize.Scale.Quantile`

### 10.1 Struct

`%Visualize.Scale.Quantile{domain: [], range: [], thresholds: []}`. `thresholds` is derived and MUST NOT be set by callers.

### 10.2 Semantics

- `domain/2` sorts the sample list ascending and recomputes thresholds. `range/2` stores the list and recomputes thresholds.
- Thresholds exist only when both domain and range are non-empty and `n = length(range) > 1`: for `i` in `1 … n−1`, the `p = i/n` quantile of the sorted samples by linear interpolation at fractional index `p · (len − 1)`.
- `scale/2`: `nil` if the range is empty; the first range element if there are no thresholds; otherwise the range element at the count of thresholds `≤ value` (buckets are half-open, `[t_{k−1}, t_k)`).
- `invert_extent/2`: `nil` if domain or range is empty or the value is not in the range; otherwise `{lo, hi}` with `lo` the first sample (bucket 0) or `t_{k−1}`, and `hi` the last sample (last bucket) or `t_k`.
- `quantiles/1` returns the thresholds.

### 10.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Quantile.new/0` | Returns the default struct. |
| `Visualize.Scale.Quantile.domain/2` | Sets the sample list (sorted on entry) and recomputes thresholds. |
| `Visualize.Scale.Quantile.range/2` | Sets the discrete output list and recomputes thresholds. |
| `Visualize.Scale.Quantile.scale/2` | Maps a value to its bucket's range element (`apply/2` under a non-protocol name, see 1.3). |
| `Visualize.Scale.Quantile.invert_extent/2` | Returns `{lo, hi}` of sample values mapping to a range element, or `nil`. |
| `Visualize.Scale.Quantile.quantiles/1` | Returns the `n − 1` interior quantile thresholds. |

## 11. `Visualize.Scale.Quantize`

### 11.1 Struct

`%Visualize.Scale.Quantize{domain: {0, 1}, range: []}`. `domain/2` accepts a list or tuple; stored as a tuple.

### 11.2 Semantics

With `n = length(range)` and `step = (d1 − d0) / n`:

- `scale/2`: `nil` for an empty range; `t = (v − d0) / (d1 − d0)` (`0` if degenerate), clamped to `[0, 1]`; bucket `min(⌊t · n⌋, n − 1)`. Values outside the domain map to the first or last element (always clamped).
- `invert_extent/2`: `nil` for an empty range or unknown value; else `{d0 + k·step, d0 + (k+1)·step}`.
- `thresholds/1`: `[]` for an empty range; else `d0 + k·step` for `k` in `1 … n−1`. For `n == 1` the Elixir range `1..0` iterates descending and returns two spurious values `[d0 + step, d0]`; intended `[]`.
- `bucket_count/1` is `length(range)`.

> Decision: see spec/13 — `Quantize.thresholds/1` MUST return `[]` for a single-element range.

### 11.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Quantize.new/0` | Returns the default struct. |
| `Visualize.Scale.Quantize.domain/2` | Sets the continuous domain from a two-element list or tuple. |
| `Visualize.Scale.Quantize.range/2` | Sets the discrete output list. |
| `Visualize.Scale.Quantize.scale/2` | Maps a value to a uniform bucket's range element (`apply/2` under a non-protocol name, see 1.3). |
| `Visualize.Scale.Quantize.invert_extent/2` | Returns the domain sub-interval for a range element, or `nil`. |
| `Visualize.Scale.Quantize.thresholds/1` | Returns the `n − 1` interior bucket boundaries. |
| `Visualize.Scale.Quantize.bucket_count/1` | Returns the number of range elements. |

## 12. `Visualize.Scale.Threshold`

### 12.1 Struct

`%Visualize.Scale.Threshold{domain: [], range: []}`. The range SHOULD have exactly one more element than the domain.

### 12.2 Semantics

- `domain/2` sorts the thresholds ascending. `range/2` stores the list unchecked.
- `scale/2`: `nil` for an empty range; otherwise `Enum.at(range, k)` where `k` is the number of thresholds `≤ value` (binary search; a value equal to a threshold falls in the upper bucket). A range shorter than `length(domain) + 1` yields `nil` for the highest buckets.
- `invert_extent/2`: `nil` for an empty range or unknown value; bucket 0 → `{:neg_infinity, t_0}` (or `{:neg_infinity, :infinity}` with no thresholds); last bucket → `{t_{last}, :infinity}`; middle → `{t_{k−1}, t_k}`.
- `thresholds/1` returns the domain.
- `copy_with_domain/3` (`scale, data, n` with `n > 0`) sorts `data` and sets the domain to the de-duplicated values at indices `⌊i · len / (n + 1)⌋` (capped at `len − 1`) for `i` in `1 … n`; `[]` for empty data. The range is untouched.

### 12.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Threshold.new/0` | Returns the default struct. |
| `Visualize.Scale.Threshold.domain/2` | Sets the thresholds (sorted on entry). |
| `Visualize.Scale.Threshold.range/2` | Sets the output list; SHOULD be one longer than the domain. |
| `Visualize.Scale.Threshold.scale/2` | Maps a value to the bucket's range element (`apply/2` under a non-protocol name, see 1.3). |
| `Visualize.Scale.Threshold.invert_extent/2` | Returns `{lo, hi}` with `:neg_infinity`/`:infinity` at the ends, or `nil`. |
| `Visualize.Scale.Threshold.thresholds/1` | Returns the domain. |
| `Visualize.Scale.Threshold.copy_with_domain/3` | Returns the scale with `n` thresholds inferred from data at evenly spaced ranks. |

## 13. `Visualize.Scale.Color`

### 13.1 Struct

`%Visualize.Scale.Color{type: :sequential, domain: [0, 1], interpolator: nil, clamp?: true}`. `diverging/1` sets `type: :diverging` and `domain: [0, 0.5, 1]`.

### 13.2 Interpolators

`sequential/1`, `diverging/1`, and `range/2` accept exactly one of:

| Input | Resolution |
|---|---|
| atom | a scheme name from 13.4; an **unknown atom silently resolves to `:blues`** |
| list of colour strings | used as evenly spaced stops; each MUST be `"#rgb"` or `"#rrggbb"` |
| 1-arity function | called with `t ∈ [0, 1]`, MUST return a colour string |

The intended behaviour for an unknown scheme name is a `FunctionClauseError` (or `ArgumentError`), not a silent fallback.

> Decision: see spec/13 — an unknown scheme atom MUST raise.

Stop-list interpolation: `n = length − 1`, `i = t · n`, `i0 = clamp(⌊i⌋, 0, n − 1)`, `i1 = min(i0 + 1, n)`, `local = i − i0`; each RGB channel is `round(c0 + (c1 − c0) · local)`; output is lowercase `"#rrggbb"`. With `clamp?` false and `t` outside `[0, 1]`, `local` leaves `[0, 1]` and channels extrapolate beyond `0…255`, producing malformed hex; callers that disable clamping MUST keep values within the domain.

### 13.3 Semantics

- `domain/2`: sequential takes `[d0, d1]`; diverging takes `[d0, d1, d2]` with `d1` the pivot. Other lengths fail to match.
- `apply/2` sequential: `t = (v − d0) / (d1 − d0)`. Diverging: `t = 0.5 · (v − d0) / (d1 − d0)` when `v < d1`, `0.5 + 0.5 · (v − d1) / (d2 − d1)` when `v > d1`, else `0.5`. `t` is clamped to `[0, 1]` when `clamp?` (default true), then passed to the interpolator.
- `ticks/2`: `Linear.ticks/2` over `[d0, d1]`. Pattern-matches a two-element domain and therefore **raises `FunctionClauseError` for diverging scales**; intended: ticks over `[d0, d2]`.
- `invert/2` `nil`; `nice/1`, `padding/2` identity; `bandwidth/1` `0`.
- `schemes/0` returns the 25 scheme names in unspecified (map-key) order; `scheme/1` returns the stop list or `nil`.

> Decision: see spec/13 — `Color.ticks/2` MUST accept a three-element diverging domain.

### 13.4 Schemes

Stops are D3-compatible hex strings; the count per scheme is given in parentheses.

Sequential, single-hue (8 stops each): `:blues`, `:greens`, `:greys`, `:oranges`, `:purples`, `:reds`.

Sequential, multi-hue: `:viridis` (9), `:inferno` (10), `:magma` (10), `:plasma` (10).

Diverging: `:brbg` (9), `:piyg` (9), `:prgn` (9), `:rdbu` (9), `:rdgy` (9), `:rdylbu` (9), `:rdylgn` (9), `:spectral` (11).

Categorical: `:category10` (10), `:accent` (8), `:dark2` (8), `:paired` (10), `:set1` (9), `:set2` (8), `:set3` (10).

Categorical schemes are stop lists like any other; used with `sequential/1` they are interpolated, not indexed. To pick categorical colours discretely, pass `Color.scheme(name)` as the range of a `Visualize.Scale.Ordinal`.

### 13.5 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Color.sequential/1` | Creates a sequential scale with domain `[0, 1]` from an interpolator (13.2). |
| `Visualize.Scale.Color.diverging/1` | Creates a diverging scale with domain `[0, 0.5, 1]` from an interpolator (13.2). |
| `Visualize.Scale.Color.domain/2` | Sets a two-element (sequential) or three-element (diverging) domain. |
| `Visualize.Scale.Color.range/2` | Replaces the interpolator; accepts a scheme atom, a stop list, or a 1-arity function. |
| `Visualize.Scale.Color.apply/2` | Returns the colour string for a value as in 13.3. |
| `Visualize.Scale.Color.clamp/2` | Sets `clamp?` (default `true`). |
| `Visualize.Scale.Color.schemes/0` | Returns the list of 25 scheme atoms. |
| `Visualize.Scale.Color.scheme/1` | Returns the stop list for a scheme atom, or `nil`. |
| `Visualize.Scale.Color.invert/2` | Returns `nil`. |
| `Visualize.Scale.Color.ticks/2` | `Linear.ticks/2` over the domain; sequential scales only (see 13.3). |
| `Visualize.Scale.Color.nice/1` | Identity. |
| `Visualize.Scale.Color.padding/2` | Identity. |
| `Visualize.Scale.Color.bandwidth/1` | Returns `0`. |
