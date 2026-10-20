# Scales

**Status:** Implemented

Scales map values from a data *domain* to a visual *range*. `Visualize.Scale` is a facade that constructs every scale kind and dispatches the common operations (`domain/2`, `range/2`, `apply/2`, `invert/2`, `ticks/1,2`, `nice/1`, `padding/2`, `bandwidth/1`, `clamp/2`) to the module named by the scale struct. This document specifies the facade protocol, then each scale module: `Linear`, `Log`, `Power`, `Symlog`, `Time`, `Ordinal`, `Band`, `Quantile`, `Quantize`, `Threshold`, `Color`, and `Radial`. Every scale is an immutable struct; setters return a new struct and never mutate.

## 1. Common Model

### 1.1 Scale Families

| Family | Modules | Domain | Range | Output |
|---|---|---|---|---|
| Continuous | `Linear`, `Log`, `Power`, `Symlog`, `Time`, `Radial` | two numbers (or two time values) | two numbers (`Radial`: radians) | float, interpolated |
| Discrete | `Ordinal`, `Band` | list of categories | list of values / two numbers | range element / band start |
| Discretizing | `Quantile`, `Quantize`, `Threshold` | samples / two numbers / thresholds | list of values | range element |
| Color | `Color` | two or three numbers | scheme, color list, or function | `"#rrggbb"` string |

### 1.2 Domain and Range Representation

Continuous domains and ranges are **two-element lists** `[d0, d1]` / `[r0, r1]` in every scale struct: `Linear`, `Log`, `Power`, `Symlog`, `Time`, `Radial`, `Band`, `Quantize`, and `Color`. `Power`, `Symlog`, and `Quantize` additionally accept a two-tuple on input to `domain/2` and `range/2` and store it as a list (D-15). `Visualize.Axis` (spec/05) reads `scale.range` as a two-element list, so every continuous scale draws with the range it was given.

Domains MAY be descending (`d0 > d1`) and ranges MAY be descending (`r0 > r1`); the interpolation formulae below are sign-agnostic. A collapsed domain (`d0 == d1`) never raises: every continuous scale maps every value to the midpoint of the range, and a collapsed range inverts to the midpoint of the domain, through `Visualize.Scale.Behaviour.normalize/3` (d3-scale's `normalize`, D-49).

### 1.3 The Facade Protocol

`Visualize.Scale.<op>(scale, …)` calls `scale.__struct__.<op>(scale, …)`. The protocol is the behaviour `Visualize.Scale.Behaviour`, whose nine callbacks are `domain/2`, `range/2`, `apply/2`, `invert/2`, `ticks/2`, `nice/1`, `padding/2`, `bandwidth/1`, `clamp/2`. Every scale module MUST declare `@behaviour Visualize.Scale.Behaviour` and implement all nine (the module also provides the shared fraction, table below), so a missing operation is a compile error under `--warnings-as-errors` rather than an `UndefinedFunctionError` at dispatch (D-15). Operations that do not apply to a scale kind MUST behave as identity (`nice/1`, `padding/2`, `clamp/2`), return `nil` (`invert/2`), or return `0` (`bandwidth/1`); the discretizing scales return their thresholds from `ticks/2`.

The table records what each module defines.

| Function | Contract |
|---|---|
| `Visualize.Scale.Behaviour.normalize/3` | The position of a value between two bounds as a fraction: `(v − a) / (b − a)`, or `0.5` when `a == b` (D-49). Every continuous scale's `apply/2` and `invert/2` use it. |

| Module | `apply/2` | `invert/2` | `ticks/2` | `nice/1` | `padding/2` | `bandwidth/1` | `clamp/2` | Facade constructor |
|---|---|---|---|---|---|---|---|---|
| `Linear` | yes | yes | yes | yes | identity | `0` | yes | `linear/0` |
| `Log` | yes | yes | yes | yes | identity | `0` | yes | `log/0,1` |
| `Power` | yes | yes | yes | `Linear.nice/1` | identity | `0` | yes | `power/0`, `sqrt/0` |
| `Symlog` | yes | yes | yes | `Linear.nice/1` | identity | `0` | yes | `symlog/0` |
| `Time` | yes | yes | yes | yes | identity | `0` | yes | `time/0` |
| `Ordinal` | yes | `nil` | domain | identity | identity | `0` | identity | `ordinal/0` |
| `Band` | yes | `nil` | domain | identity | yes | yes | identity | `band/0` |
| `Quantile` | yes | `nil` | quantiles | identity | identity | `0` | identity | `quantile/0` |
| `Quantize` | yes | `nil` | thresholds | identity | identity | `0` | identity | `quantize/0` |
| `Threshold` | yes | `nil` | thresholds | identity | identity | `0` | identity | `threshold/0` |
| `Color` | yes | `nil` | domain extent | identity | identity | `0` | yes | `sequential/1`, `diverging/1` |
| `Radial` | yes | yes | equal divisions | identity | identity | `0` | yes | `radial/0` |

`Power`, `Symlog`, `Quantile`, `Quantize`, and `Threshold` also keep `scale/2` as an alias of `apply/2` for one release, after which it is removed; new code MUST call `apply/2`. `test/visualize/scale/protocol_test.exs` constructs every kind through the facade and calls all nine operations; it is the recurrence guard for this section.

### 1.4 Clamping

`clamp/2` takes a boolean. The default is `false` for every scale except `Color`, whose default is `true`. When enabled, `Linear`, `Log`, `Time`, `Radial`, and `Color` clamp the normalized parameter `t` to `[0, 1]` before interpolating; `Power` and `Symlog` clamp the *output* to `[min(r0, r1), max(r0, r1)]`. The two formulations are equivalent for linear interpolation. `invert/2` never clamps.

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
| `Visualize.Scale.threshold/0` | Returns `Visualize.Scale.Threshold.new/0`. |
| `Visualize.Scale.sequential/1` | Returns `Visualize.Scale.Color.sequential/1`. |
| `Visualize.Scale.diverging/1` | Returns `Visualize.Scale.Color.diverging/1`. |
| `Visualize.Scale.radial/0` | Returns `Visualize.Scale.Radial.new/0`: domain `[0, 1]`, range `[0, 2π]`. |
| `Visualize.Scale.domain/2` | Dispatches to the scale module's `domain/2`. |
| `Visualize.Scale.range/2` | Dispatches to the scale module's `range/2`. |
| `Visualize.Scale.apply/2` | Dispatches to the scale module's `apply/2`; maps a domain value to a range value. Total over every scale this module constructs (1.3). |
| `Visualize.Scale.invert/2` | Dispatches to the scale module's `invert/2`; maps a range value back to the domain. Continuous scales only; every other scale returns `nil`. |
| `Visualize.Scale.ticks/1` | As `ticks/2` with count 10. |
| `Visualize.Scale.ticks/2` | Dispatches to the scale module's `ticks/2`; returns representative domain values, ascending for continuous scales, the domain itself for discrete scales, the thresholds for discretizing scales. `count` is a hint, not a guarantee. |
| `Visualize.Scale.nice/1` | Dispatches to the scale module's `nice/1`; extends the domain outward to round values. |
| `Visualize.Scale.padding/2` | Dispatches to the scale module's `padding/2`; meaningful only for `Band`. |
| `Visualize.Scale.bandwidth/1` | Dispatches to the scale module's `bandwidth/1`; `0` for every scale but `Band`. |
| `Visualize.Scale.clamp/2` | Dispatches to the scale module's `clamp/2` with a boolean. |
| `Visualize.Scale.zone/2` | Delegates to `Visualize.Scale.Time.zone/2` (7.4). Not part of the protocol: a zone means something only to a time scale, so any other scale is a `FunctionClauseError`, not an identity. |

## 3. `Visualize.Scale.Linear`

### 3.1 Struct

`%Visualize.Scale.Linear{domain: [0, 1], range: [0, 1], clamp?: false}`.

### 3.2 Semantics

- `apply/2`: `t = (v − d0) / (d1 − d0)` (`0.5` when `d0 == d1`); if `clamp?`, `t` is clamped to `[0, 1]`; result is `r0 + t · (r1 − r0)`, always a float.
- `invert/2`: `t = (v − r0) / (r1 − r0)`; result `d0 + t · (d1 − d0)`. Never clamps.
- `ticks/2` (count `n`): the *nice step* is computed from `span = |d1 − d0|`, `raw = span / max(n, 1)`, `mag = 10^⌊log10 raw⌋`, `q = raw / mag`, and factor `1` if `q < 1.5`, `2` if `q < 3`, `5` if `q < 7`, else `10`; `step = factor · mag`. Ticks run from `⌈d0/step⌉·step` to `⌊d1/step⌋·step` inclusive, each rounded to `max(0, −⌊log10 step⌋)` decimal places; when no multiple of the step lies inside the domain the result is `[]`, never a value outside it. The tick count is approximately `n`; it is never guaranteed.
- `nice/1`: with the step for count 10, domain becomes `[⌊d0/step⌋·step, ⌈d1/step⌉·step]` (floats).
- `padding/2` is identity; `bandwidth/1` is `0`.

A descending domain (`d0 > d1`) yields the same ticks in descending order. A degenerate domain (`d0 == d1`) yields `[d0]` from `ticks/2` and leaves `nice/1` unchanged (D-17).

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
- `ticks/2` (count `n`): d3-scale's log ticks (D-17). With `i = log d0`, `j = log d1` (swapped and the result reversed when descending): when the base is an integer and `j − i < n`, every `k · base^e` for `1 ≤ k < base` and `e` from `⌊i⌋` to `⌈j⌉` that lies inside the domain — `1, 2, … 9, 10, 20, …` — and, when that yields fewer than `n / 2` values, `Visualize.Data.ticks/3` over the domain instead; otherwise `Visualize.Data.ticks(i, j, min(⌈j − i⌉, n))` mapped through `base^e`, so many decades are thinned to about `n` powers. Negative exponents divide (`3 / 10`, not `3 · 0.1`), and bases 10 and 2 use exact logarithms, so the values print as the decimals they are. A sub-decade domain yields linear ticks rather than `[]`; as with `Linear`, a count of 1 MAY still yield `[]` when no multiple of the step lies inside the domain.
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
| `Visualize.Scale.Log.ticks/2` | d3's log ticks as in 4.2: about `count` values, multiples within a decade, thinned powers across many. |
| `Visualize.Scale.Log.nice/1` | Extends the domain to integer powers of the base. |
| `Visualize.Scale.Log.padding/2` | Identity. |
| `Visualize.Scale.Log.bandwidth/1` | Returns `0`. |

## 5. `Visualize.Scale.Power`

### 5.1 Struct

`%Visualize.Scale.Power{domain: [0, 1], range: [0, 1], exponent: 1, clamp?: false}`. `domain/2` and `range/2` accept a two-element list or a two-tuple and store a list.

### 5.2 Semantics

Let `e` be the exponent and `T(x) = sign(x) · |x|^e` (D3's signed power), with inverse `T⁻¹(y) = sign(y) · |y|^(1/e)`.

- `apply/2`: `D = T(d1) − T(d0)`; `t = 0.5` if `D == 0`, else `(T(v) − T(d0)) / D`; result `r0 + t · (r1 − r0)`; when `clamp?`, the result is clamped to the range bounds in either order. A domain that includes negative values maps symmetrically: on `[−10, 10]` with `e = 2`, `−5` and `5` sit `0.125` either side of the midpoint.
- `invert/2`: `t = (v − r0) / (r1 − r0)` (`0.5` if `r1 == r0`); result `T⁻¹(T(d0) + t · D)`, negative when the domain value is.
- `ticks/1,2`: delegate to `Linear.ticks/2` on `[d0, d1]` (linear spacing in the domain, not in the transformed space).
- `nice/1`: the domain becomes `Linear.nice/1`'s domain for `[d0, d1]`.
- `padding/2` identity; `bandwidth/1` `0`.
- `sqrt/0` is `new/0` with exponent 0.5.

### 5.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Power.new/0` | Returns the default struct (exponent 1). |
| `Visualize.Scale.Power.sqrt/0` | Returns a power scale with exponent 0.5. |
| `Visualize.Scale.Power.domain/2` | Sets the domain from a two-element list or tuple; stored as a list. |
| `Visualize.Scale.Power.range/2` | Sets the range from a two-element list or tuple; stored as a list. |
| `Visualize.Scale.Power.exponent/2` | Sets the exponent; MUST be a number. |
| `Visualize.Scale.Power.clamp/2` | Sets `clamp?`. |
| `Visualize.Scale.Power.apply/2` | Maps a domain value to the range as in 5.2. |
| `Visualize.Scale.Power.scale/2` | Alias of `apply/2`, retained for one release (1.3). |
| `Visualize.Scale.Power.invert/2` | Inverse as in 5.2; signed. |
| `Visualize.Scale.Power.ticks/1` | As `ticks/2` with count 10. |
| `Visualize.Scale.Power.ticks/2` | `Linear.ticks/2` over the domain. |
| `Visualize.Scale.Power.nice/1` | `Linear.nice/1` over the domain. |
| `Visualize.Scale.Power.padding/2` | Identity. |
| `Visualize.Scale.Power.bandwidth/1` | Returns `0`. |

## 6. `Visualize.Scale.Symlog`

### 6.1 Struct

`%Visualize.Scale.Symlog{domain: [−1, 1], range: [0, 1], constant: 1, clamp?: false}`. List or tuple accepted for `domain/2` and `range/2`; stored as lists.

### 6.2 Semantics

The transform is `S(x) = sign(x) · ln(1 + |x| / c)` with inverse `S⁻¹(y) = sign(y) · c · (e^{|y|} − 1)`, where `c` is the constant (`> 0`, enforced by `constant/2`).

- `apply/2`: `t = (S(v) − S(d0)) / (S(d1) − S(d0))` (`0.5` if the denominator is zero); result `r0 + t · (r1 − r0)`, clamped to the range bounds when `clamp?`.
- `invert/2`: `t = (v − r0) / (r1 − r0)` (`0.5` if degenerate); result `S⁻¹(S(d0) + t · (S(d1) − S(d0)))`.
- `nice/1`: the domain becomes `Linear.nice/1`'s domain for `[d0, d1]`. `padding/2` identity; `bandwidth/1` `0`.
- `ticks/1,2` (count `n`): with `lo = min(d0, d1)`, `hi = max(d0, d1)`, the result is the ascending, de-duplicated union of: negated decades `−c · 10^k` for `k` in `0, s, 2s, … ≤ ⌈log10(−lo / c)⌉` (only when `lo < 0`); `0` when `lo ≤ 0 ≤ hi`; and decades `c · 10^k` for `k` up to `⌈log10(hi / c)⌉` (only when `hi > 0`) — every candidate filtered to `[lo, hi]`. The exponent stride is `s = max(1, ⌊⌈log10(bound / c)⌉ / n⌋)`. The decades start at the constant `c`, where the log region begins (D-17); with `c = 1` they are the powers of ten. A domain that contains no decade yields `[]`.

### 6.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Symlog.new/0` | Returns the default struct. |
| `Visualize.Scale.Symlog.domain/2` | Sets the domain from a two-element list or tuple; MAY include zero and negatives; stored as a list. |
| `Visualize.Scale.Symlog.range/2` | Sets the range from a two-element list or tuple; stored as a list. |
| `Visualize.Scale.Symlog.constant/2` | Sets the linear/log transition constant; MUST be a number `> 0`. |
| `Visualize.Scale.Symlog.clamp/2` | Sets `clamp?`. |
| `Visualize.Scale.Symlog.apply/2` | Maps a domain value to the range as in 6.2. |
| `Visualize.Scale.Symlog.scale/2` | Alias of `apply/2`, retained for one release (1.3). |
| `Visualize.Scale.Symlog.invert/2` | Inverse as in 6.2. |
| `Visualize.Scale.Symlog.ticks/1` | As `ticks/2` with count 10. |
| `Visualize.Scale.Symlog.ticks/2` | Signed decades of the constant, and zero, as in 6.2. |
| `Visualize.Scale.Symlog.nice/1` | `Linear.nice/1` over the domain. |
| `Visualize.Scale.Symlog.padding/2` | Identity. |
| `Visualize.Scale.Symlog.bandwidth/1` | Returns `0`. |

## 7. `Visualize.Scale.Time`

### 7.1 Struct

`%Visualize.Scale.Time{domain: nil, range: [0, 1], clamp?: false, zone: nil}`. The domain MUST be set before use. `zone` is the display zone of 7.4, an IANA name such as `"America/New_York"`, or `nil` for UTC.

### 7.2 Accepted Value Types

Domain bounds and `apply/2` arguments MAY be any of `DateTime`, `Date`, `NaiveDateTime`, mixed freely. Each is reduced to Unix seconds: `DateTime` via `DateTime.to_unix/1`; `NaiveDateTime` as if UTC; `Date` as midnight UTC (`days since 1970-01-01 × 86400`). Sub-second precision is discarded.

`invert/2`, `ticks/2`, and `nice/1` produce `DateTime` values in the scale's zone — **UTC** when it has none — whatever the domain's type. `invert/2` rounds to the nearest whole second. The reduction above does not depend on the zone: a `NaiveDateTime` is still read as UTC and a `Date` as midnight UTC, so a zone changes where ticks fall and how values print, never where a value is drawn.

### 7.3 Semantics

- `apply/2`: linear interpolation over Unix seconds, exactly as `Linear.apply/2`; clamps `t` when `clamp?`.
- `ticks/2` (count `n`): the interval is chosen as in 7.3.1 from `span_seconds / max(n, 1)`; the ticks are every boundary of that interval (7.3.2) from `ceil(d0)` up to and including `d1`. Every tick lies on a boundary inside `[d0, d1]`; the first never precedes `d0`. A descending domain yields the same ticks descending. A degenerate domain yields `[d0]` when `d0` is a whole second.
- `nice/1`: chooses the interval for count 10 and sets the domain to `[floor(d0), ceil(d1)]` (or `[ceil(d0), floor(d1)]` when descending). A domain already on boundaries is unchanged.
- `interval/2` (`span_seconds, count`) exposes the choice for callers that format ticks by their interval; it is not part of the scale protocol.

This is d3-time's model (D-16); the interval selection and the snapping are the reference behavior of `d3.timeTicks` and `interval.range`, with Monday-based weeks.

#### 7.3.1 Interval Table

An interval is `{unit, n}`: `n` units per step. The candidates, with the nominal seconds one step spans (30-day months, 365-day years):

| Interval | Seconds | Boundary |
|---|---|---|
| `{:second, 1}`, `{:second, 5}`, `{:second, 15}`, `{:second, 30}` | 1, 5, 15, 30 | Unix seconds that are a multiple of `n` |
| `{:minute, 1}`, `{:minute, 5}`, `{:minute, 15}`, `{:minute, 30}` | 60, 300, 900, 1800 | Unix seconds that are a multiple of `60·n` |
| `{:hour, 1}`, `{:hour, 3}`, `{:hour, 6}`, `{:hour, 12}` | 3600, 10800, 21600, 43200 | Unix seconds that are a multiple of `3600·n` (aligned to midnight UTC) |
| `{:day, 1}`, `{:day, 2}` | 86400, 172800 | midnight UTC of a day-of-month `d` with `(d − 1) mod n = 0` (two-day ticks restart on the 1st of each month) |
| `{:week, 1}` | 604800 | Monday 00:00 UTC |
| `{:month, 1}`, `{:month, 3}` | 2592000, 7776000 | 00:00 UTC on the 1st of a month `m` with `(m − 1) mod n = 0` |
| `{:year, 1}` | 31536000 | 00:00 UTC on 1 January |
| `{:year, k}`, `k > 1` | `k · 31536000` | 00:00 UTC on 1 January of a year `y` with `y mod k = 0` |

Selection, with `target = span_seconds / max(n, 1)`: of the two table rows whose seconds bracket `target`, the one closer in ratio (`target / below < above / target` picks the row below); a `target` below one second picks `{:second, 1}`. When `target` exceeds one year the interval is `{:year, k}` with `k = max(1, round(f · 10^⌊log10 raw⌋))` for `raw = span_years / n` and `f` from the d3 nice-step thresholds (`10` if `raw / 10^⌊log10 raw⌋ ≥ √50`, `5` if `≥ √10`, `2` if `≥ √2`, else `1`), so 24 years at count 10 step by 2 and three centuries by 20.

Because neighboring rows differ by at most `4.3×`, the number of ticks is within about `2.2×` of `n` either way.

#### 7.3.2 Snapping

`floor(t)` is the latest boundary at or before `t`; `ceil(t)` is `floor(t)` when `t` is already a boundary, else the boundary that follows. Stepping from a boundary to the next: sub-day intervals add `n` units of seconds; `{:day, n}` adds `n` days, or moves to the 1st of the next month when that would pass the month's end; `{:week, 1}` adds seven days; `{:month, n}` adds `n` calendar months; `{:year, k}` adds `k` years. Month arithmetic clamps the day to the target month's length (31 January + 1 month is the last day of February), so no step constructs an invalid date; ticks themselves always land on the 1st.

The table and the steps above describe a scale without a zone. A zoned scale reads every boundary in its zone's local calendar instead (7.4).

### 7.4 Display Zone

`zone(scale, name)` sets the zone the scale's ticks are counted in and its values are shown in (#447). The name is an IANA time zone, looked up in the host's configured `Calendar.TimeZoneDatabase` through `DateTime.shift_zone/3` and `DateTime.new/4`; the library takes no time zone dependency (D-115). `zone(scale, nil)` removes it.

**Storage does not change.** Values are reduced to Unix seconds exactly as in 7.2, so `apply/2` is the same function with or without a zone and a position stays linear in real time: a 25-hour day is drawn 25/24 as wide as a 24-hour one. The interval of 7.3.1 is chosen from the span in real seconds, as before.

**Boundaries are local.** With a zone, the boundary column of 7.3.1 is read in the zone's local calendar — the wall-clock time `DateTime.shift_zone/3` gives each instant:

- `{:second, n}`, `{:minute, n}`, `{:hour, n}`: every **real instant** whose local time has the second, the minute, or the minute and second at zero and the field (second, minute or hour of the local day) a multiple of `n`. Across a transition back, the repeated local hour yields its boundaries twice, at distinct instants, in instant order (`01:00 EDT`, then `01:00 EST`); across a transition forward, the boundaries of the skipped local hour do not exist and are absent. In a zone whose offset is not a whole hour (`Asia/Kolkata`, `+05:30`; `Asia/Kathmandu`, `+05:45`) the hour boundaries are the local hours, not the UTC ones.
- `{:day, n}`, `{:week, 1}`, `{:month, n}`, `{:year, k}`: the **local midnight** of every boundary date, the dates chosen by the date arithmetic of 7.3.2 applied to local dates (a local Monday, the 1st of a local month, 1 January of a local year). A day containing a transition is 23 or 25 hours long and its ticks are spaced accordingly. A local midnight that a transition skips is the first instant of that day; one a transition repeats is the earlier instant.

`floor`, `ceil` and the step of 7.3.2 follow the same reading, so `nice/1` extends the domain to local boundaries. `ticks/2` returns `DateTime` values in the zone, `nice/1` sets the domain to them, and `invert/2` returns a `DateTime` in the zone. Without a zone each of these is byte for byte what 7.2 and 7.3 say: UTC boundaries and UTC `DateTime` values.

**The zone is refused loudly.** `zone/2` checks the name against the host's database at the call and raises `ArgumentError` naming the zone and the reason — `:time_zone_not_found` for a name the database does not know, `:utc_only_time_zone_database` for a host with no database configured, where every zone but `Etc/UTC` is unknowable. There is no fallback to UTC: a host that asked for New York and silently got UTC would draw every day tick four or five hours from midnight. `check_zone/1` returns the same answer as a value, which is what the declarative layer's validator reports ([14-declarative-chart](14-declarative-chart.md) §4.3, §10.1).

`local(scale, value)` is a value as the scale shows it: a time value reduced as in 7.2 and shifted to the zone, or the value itself when the scale has none. An axis that formats explicit tick values passes them through it, so its labels read local time like the ticks it computes ([05-axes-and-formatting](05-axes-and-formatting.md) §2.8).

**In the examples** (#754, work item #773). The synced dashboard (`/dashboard`) offers *UTC*, *New York* and *Tokyo*: each panel's design says `zone:` on its time scale (none for UTC), so its ticks fall on that zone's hours and its labels read its wall clock, and the brushed window is written in the same zone through `Visualize.Scale.Time.zone/2` and `local/2`. The examples configure `Tz.TimeZoneDatabase`, as a host does: the library takes no tz dependency (D-115). The data stay in UTC; a zone is only how they are shown.

### 7.5 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Time.new/0` | Returns the default struct with `domain: nil` and no zone. |
| `Visualize.Scale.Time.domain/2` | Sets the domain; a two-element list of `DateTime`, `Date`, or `NaiveDateTime`. |
| `Visualize.Scale.Time.range/2` | Sets the range (two-element list of numbers). |
| `Visualize.Scale.Time.clamp/2` | Sets `clamp?`. |
| `Visualize.Scale.Time.apply/2` | Maps a time value to the range as in 7.3; returns a float. |
| `Visualize.Scale.Time.invert/2` | Maps a range value to a `DateTime` in the scale's zone (UTC without one) at whole-second precision. |
| `Visualize.Scale.Time.ticks/2` | Every boundary of the chosen interval inside the domain (7.3), in the zone's local calendar when it has one (7.4); a list of `DateTime` in the scale's zone, UTC without one. |
| `Visualize.Scale.Time.nice/1` | Extends the domain outward to the boundaries of the count-10 interval (local boundaries with a zone, 7.4); the domain becomes `DateTime` values in the scale's zone, UTC without one. |
| `Visualize.Scale.Time.interval/2` | The `{unit, n}` interval `count` ticks would use over a span of seconds (7.3.1). |
| `Visualize.Scale.Time.padding/2` | Identity. |
| `Visualize.Scale.Time.bandwidth/1` | Returns `0`. |
| `Visualize.Scale.Time.zone/2` | Sets the display zone (7.4), an IANA name or `nil`; raises `ArgumentError` naming the zone when the host's time zone database does not know it or the host has none. |
| `Visualize.Scale.Time.check_zone/1` | `:ok`, or `{:error, :time_zone_not_found}` / `{:error, :utc_only_time_zone_database}`: whether the host's time zone database can show a name (7.4). |
| `Visualize.Scale.Time.local/2` | A time value as the scale shows it: a `DateTime` in the scale's zone, or the value unchanged when the scale has none (7.4). |

## 8. `Visualize.Scale.Ordinal`

### 8.1 Struct

`%Visualize.Scale.Ordinal{domain: [], range: [], unknown: nil}`.

### 8.2 Semantics

- `apply/2`: `unknown` when the range is empty. Otherwise the index `i` of the first domain element equal (`==`) to the value; when not found the `unknown` value is returned, else `Enum.at(range, rem(i, length(range)))`: the range **cycles** when the domain is longer. The domain is never extended implicitly.
- `invert/2` returns `nil`; `ticks/2` returns the domain (count ignored); `nice/1`, `clamp/2`, `padding/2` identity; `bandwidth/1` `0`.
- **`unknown` is d3's `scaleOrdinal.unknown`** without d3's implicit default: the struct's `nil` means "no value", and the caller decides what that draws. A scale used for **color** gives it a color, so that a value outside the domain is still drawn, and drawn as *not one of the categories*: the declarative layer's `color` scale does so by default, with the theme's `:axis` slot, a neutral every theme makes visible on its background ([14-declarative-chart](14-declarative-chart.md) §4.3, D-122). A `nil` value is outside every domain inference builds, since inference drops `nil`s, so at this level it maps to `unknown` like any other stranger; the declarative layer reads a `nil` as no value at all and paints nothing (spec/14 §3.4).

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

`%Visualize.Scale.Band{domain: [], range: [0, 1], padding_inner: 0, padding_outer: 0, align: 0.5, round?: false, slots: %{}, layout: {0, 0, 0, false}}`.

`slots` and `layout` are derived, never set: every setter of §9.2 and `domain/2` and `range/2` lays the bands out again (d3-scale's `rescale`) and stores the result — `layout` is `{start, step, bandwidth, reverse}` of §9.3 and `slots` maps each category to its band's slot along the ascending range — so a scale is built once and read many times (#809, D-202). `inspect/1` leaves both out. A struct built by hand rather than by the setters has no slots, and places nothing.

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

This is d3-scale's `rescale` (D-17). With `n = length(domain)`, `pi = padding_inner`, `po = padding_outer`, `reverse = r1 < r0`, `lo = min(r0, r1)`, `hi = max(r0, r1)`:

- `n == 0`: `bandwidth = 0`, `step = 0`, every position `nil`.
- Otherwise `step = (hi − lo) / max(1, n − pi + 2·po)`, floored when `round?`; `start = lo + (hi − lo − step · (n − pi)) · align`; `bandwidth = step · (1 − pi)`; when `round?`, `start` and `bandwidth` are rounded (from the floored step) and every position is therefore an integer-valued float.
- Position of the category at index `i` is `start + i · step`, or `start + (n − 1 − i) · step` when `reverse`: a descending range lays the bands out in reverse with positive `step` and `bandwidth`.
- `step/1` returns `step` (floored when `round?`); `bandwidth/1` returns `bandwidth`.

**`apply/2`, `bandwidth/1` and `step/1` cost the same whatever the domain's length** (#809): `apply/2` reads the category's slot from `slots` and returns `start + slot · step`; nothing of the domain is walked and nothing of the layout is recomputed per call. Before #809, `apply/2` found the category with a linear search and recomputed the layout on every call, so a chart of `n` items over a domain of `n` categories cost `O(n²)`: a 50 × 50 grid spent a fifth of its drawing searching its two domains. A category repeated in the domain keeps its first index's slot, as the linear search found it, and categories equal by `==` are one category: an integral float is looked up as its integer, so `1` finds `1.0` and `-0.0` finds `0`. `test/visualize/scale/band_test.exs` holds `apply/2` over a 1,000-category domain to the reductions of one over 10.

`apply/2` returns `nil` for a value not in the domain. `ticks/2` returns the domain; `invert/2` returns `nil`; `nice/1`, `clamp/2` identity. Under `round?` the rounded start plus the rounded bandwidth MAY overshoot the range by under one unit, as in D3.

### 9.4 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Band.new/0` | Returns the default struct. |
| `Visualize.Scale.Band.domain/2` | Sets the list of categories. |
| `Visualize.Scale.Band.range/2` | Sets the range (two-element list). |
| `Visualize.Scale.Band.padding/2` | Sets inner and outer padding together (`0 ≤ p < 1`). |
| `Visualize.Scale.Band.padding_inner/2` | Sets inner padding (`0 ≤ p < 1`). |
| `Visualize.Scale.Band.padding_outer/2` | Sets outer padding (`p ≥ 0`). |
| `Visualize.Scale.Band.align/2` | Sets the distribution of outer space (`0` = all at end, `0.5` = centered, `1` = all at start). |
| `Visualize.Scale.Band.round/2` | Enables rounding: the step is floored, the start and bandwidth rounded. |
| `Visualize.Scale.Band.apply/2` | Returns the band start for a category, or `nil` if absent. |
| `Visualize.Scale.Band.invert/2` | Returns `nil`. |
| `Visualize.Scale.Band.bandwidth/1` | Returns the band width as in 9.3. |
| `Visualize.Scale.Band.step/1` | Returns the distance between adjacent band starts (floored when `round?`). |
| `Visualize.Scale.Band.ticks/2` | Returns the domain. |
| `Visualize.Scale.Band.nice/1` | Identity. |
| `Visualize.Scale.Band.clamp/2` | Identity. |

## 10. `Visualize.Scale.Quantile`

### 10.1 Struct

`%Visualize.Scale.Quantile{domain: [], range: [], thresholds: []}`. `thresholds` is derived and MUST NOT be set by callers.

### 10.2 Semantics

- `domain/2` sorts the sample list ascending and recomputes thresholds. `range/2` stores the list and recomputes thresholds.
- Thresholds exist only when both domain and range are non-empty and `n = length(range) > 1`: for `i` in `1 … n−1`, the `p = i/n` quantile of the sorted samples by linear interpolation at fractional index `p · (len − 1)`.
- `apply/2`: `nil` if the range is empty; the first range element if there are no thresholds; otherwise the range element at the count of thresholds `≤ value` (buckets are half-open, `[t_{k−1}, t_k)`), so a value at or above the last threshold reaches the last range element.
- `invert_extent/2`: `nil` if domain or range is empty or the value is not in the range; otherwise `{lo, hi}` with `lo` the first sample (bucket 0) or `t_{k−1}`, and `hi` the last sample (last bucket) or `t_k`.
- `quantiles/1` returns the thresholds; `ticks/2` returns the same list (count ignored).
- `invert/2` `nil`; `nice/1`, `padding/2`, `clamp/2` identity; `bandwidth/1` `0`.

### 10.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Quantile.new/0` | Returns the default struct. |
| `Visualize.Scale.Quantile.domain/2` | Sets the sample list (sorted on entry) and recomputes thresholds. |
| `Visualize.Scale.Quantile.range/2` | Sets the discrete output list and recomputes thresholds. |
| `Visualize.Scale.Quantile.apply/2` | Maps a value to its bucket's range element as in 10.2. |
| `Visualize.Scale.Quantile.scale/2` | Alias of `apply/2`, retained for one release (1.3). |
| `Visualize.Scale.Quantile.invert_extent/2` | Returns `{lo, hi}` of sample values mapping to a range element, or `nil`. |
| `Visualize.Scale.Quantile.quantiles/1` | Returns the `n − 1` interior quantile thresholds. |
| `Visualize.Scale.Quantile.invert/2` | Returns `nil`. |
| `Visualize.Scale.Quantile.ticks/2` | Returns `quantiles/1`. |
| `Visualize.Scale.Quantile.nice/1` | Identity. |
| `Visualize.Scale.Quantile.padding/2` | Identity. |
| `Visualize.Scale.Quantile.bandwidth/1` | Returns `0`. |
| `Visualize.Scale.Quantile.clamp/2` | Identity. |

## 11. `Visualize.Scale.Quantize`

### 11.1 Struct

`%Visualize.Scale.Quantize{domain: [0, 1], range: []}`. `domain/2` accepts a list or tuple; stored as a list.

### 11.2 Semantics

With `n = length(range)` and `step = (d1 − d0) / n`:

- `apply/2`: `nil` for an empty range; `t = (v − d0) / (d1 − d0)` (`0` if degenerate), clamped to `[0, 1]`; bucket `min(⌊t · n⌋, n − 1)`. Values outside the domain map to the first or last element (always clamped).
- `ticks/2` returns `thresholds/1` (count ignored); `invert/2` `nil`; `nice/1`, `padding/2`, `clamp/2` identity; `bandwidth/1` `0`.
- `invert_extent/2`: `nil` for an empty range or unknown value; else `{d0 + k·step, d0 + (k+1)·step}`.
- `thresholds/1`: `[]` for an empty or single-element range; else `d0 + k·step` for `k` in `1 … n−1`.
- `bucket_count/1` is `length(range)`.

### 11.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Quantize.new/0` | Returns the default struct. |
| `Visualize.Scale.Quantize.domain/2` | Sets the continuous domain from a two-element list or tuple; stored as a list. |
| `Visualize.Scale.Quantize.range/2` | Sets the discrete output list. |
| `Visualize.Scale.Quantize.apply/2` | Maps a value to a uniform bucket's range element as in 11.2. |
| `Visualize.Scale.Quantize.scale/2` | Alias of `apply/2`, retained for one release (1.3). |
| `Visualize.Scale.Quantize.invert_extent/2` | Returns the domain sub-interval for a range element, or `nil`. |
| `Visualize.Scale.Quantize.thresholds/1` | Returns the `n − 1` interior bucket boundaries. |
| `Visualize.Scale.Quantize.bucket_count/1` | Returns the number of range elements. |
| `Visualize.Scale.Quantize.invert/2` | Returns `nil`. |
| `Visualize.Scale.Quantize.ticks/2` | Returns `thresholds/1`. |
| `Visualize.Scale.Quantize.nice/1` | Identity. |
| `Visualize.Scale.Quantize.padding/2` | Identity. |
| `Visualize.Scale.Quantize.bandwidth/1` | Returns `0`. |
| `Visualize.Scale.Quantize.clamp/2` | Identity. |

## 12. `Visualize.Scale.Threshold`

### 12.1 Struct

`%Visualize.Scale.Threshold{domain: [], range: []}`. The range SHOULD have exactly one more element than the domain.

### 12.2 Semantics

- `domain/2` sorts the thresholds ascending. `range/2` stores the list unchecked.
- `apply/2`: `nil` for an empty range; otherwise `Enum.at(range, k)` where `k` is the number of thresholds `≤ value` (binary search; a value equal to a threshold falls in the upper bucket). A range shorter than `length(domain) + 1` yields `nil` for the highest buckets.
- `ticks/2` returns the domain (count ignored); `invert/2` `nil`; `nice/1`, `padding/2`, `clamp/2` identity; `bandwidth/1` `0`.
- `invert_extent/2`: `nil` for an empty range or unknown value; bucket 0 → `{:neg_infinity, t_0}` (or `{:neg_infinity, :infinity}` with no thresholds); last bucket → `{t_{last}, :infinity}`; middle → `{t_{k−1}, t_k}`.
- `thresholds/1` returns the domain.
- `copy_with_domain/3` (`scale, data, n` with `n > 0`) sorts `data` and sets the domain to the de-duplicated values at indices `⌊i · len / (n + 1)⌋` (capped at `len − 1`) for `i` in `1 … n`; `[]` for empty data. The range is untouched.

### 12.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Threshold.new/0` | Returns the default struct. |
| `Visualize.Scale.Threshold.domain/2` | Sets the thresholds (sorted on entry). |
| `Visualize.Scale.Threshold.range/2` | Sets the output list; SHOULD be one longer than the domain. |
| `Visualize.Scale.Threshold.apply/2` | Maps a value to the bucket's range element as in 12.2. |
| `Visualize.Scale.Threshold.scale/2` | Alias of `apply/2`, retained for one release (1.3). |
| `Visualize.Scale.Threshold.invert_extent/2` | Returns `{lo, hi}` with `:neg_infinity`/`:infinity` at the ends, or `nil`. |
| `Visualize.Scale.Threshold.thresholds/1` | Returns the domain. |
| `Visualize.Scale.Threshold.copy_with_domain/3` | Returns the scale with `n` thresholds inferred from data at evenly spaced ranks. |
| `Visualize.Scale.Threshold.invert/2` | Returns `nil`. |
| `Visualize.Scale.Threshold.ticks/2` | Returns the domain. |
| `Visualize.Scale.Threshold.nice/1` | Identity. |
| `Visualize.Scale.Threshold.padding/2` | Identity. |
| `Visualize.Scale.Threshold.bandwidth/1` | Returns `0`. |
| `Visualize.Scale.Threshold.clamp/2` | Identity. |

## 13. `Visualize.Scale.Color`

### 13.1 Struct

`%Visualize.Scale.Color{type: :sequential, domain: [0, 1], interpolator: nil, clamp?: true}`. `diverging/1` sets `type: :diverging` and `domain: [0, 0.5, 1]`.

### 13.2 Interpolators

`sequential/1`, `diverging/1`, and `range/2` accept exactly one of:

| Input | Resolution |
|---|---|
| atom | a scheme name from 13.4; an unknown atom raises `ArgumentError` naming `schemes/0` (D-17) |
| list of color strings | used as evenly spaced stops; each MUST be `"#rgb"` or `"#rrggbb"` |
| 1-arity function | called with `t ∈ [0, 1]`, MUST return a color string |

Stop-list interpolation: `n = length − 1`, `i = t · n`, `i0 = clamp(⌊i⌋, 0, n − 1)`, `i1 = min(i0 + 1, n)`, `local = i − i0`; each RGB channel is `round(c0 + (c1 − c0) · local)` clamped to `0…255`; output is lowercase `"#rrggbb"`. With `clamp?` false and `t` outside `[0, 1]`, `local` leaves `[0, 1]` and the end stops are extrapolated along their last segment; the channel clamp keeps the result a well-formed color.

### 13.3 Semantics

- `domain/2`: sequential takes `[d0, d1]`; diverging takes `[d0, d1, d2]` with `d1` the pivot. Other lengths fail to match.
- `apply/2` sequential: `t = (v − d0) / (d1 − d0)`. Diverging: `t = 0.5 · (v − d0) / (d1 − d0)` when `v < d1`, `0.5 + 0.5 · (v − d1) / (d2 − d1)` when `v > d1`, else `0.5`. `t` is clamped to `[0, 1]` when `clamp?` (default true), then passed to the interpolator.
- `ticks/2`: `Linear.ticks/2` over the domain's extent — `[d0, d1]` for a sequential scale, `[d0, d2]` for a diverging one.
- `invert/2` `nil`; `nice/1`, `padding/2` identity; `bandwidth/1` `0`.
- `schemes/0` returns the 25 scheme names in unspecified (map-key) order; `scheme/1` returns the stop list or `nil`.

### 13.4 Schemes

Stops are D3-compatible hex strings; the count per scheme is given in parentheses.

Sequential, single-hue (8 stops each): `:blues`, `:greens`, `:greys`, `:oranges`, `:purples`, `:reds`.

Sequential, multi-hue: `:viridis` (9), `:inferno` (10), `:magma` (10), `:plasma` (10).

Diverging: `:brbg` (9), `:piyg` (9), `:prgn` (9), `:rdbu` (9), `:rdgy` (9), `:rdylbu` (9), `:rdylgn` (9), `:spectral` (11).

Categorical: `:category10` (10), `:accent` (8), `:dark2` (8), `:paired` (10), `:set1` (9), `:set2` (8), `:set3` (10).

Categorical schemes are stop lists like any other; used with `sequential/1` they are interpolated, not indexed. To pick categorical colors discretely, pass `Color.scheme(name)` as the range of a `Visualize.Scale.Ordinal`.

### 13.5 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Color.sequential/1` | Creates a sequential scale with domain `[0, 1]` from an interpolator (13.2). |
| `Visualize.Scale.Color.diverging/1` | Creates a diverging scale with domain `[0, 0.5, 1]` from an interpolator (13.2). |
| `Visualize.Scale.Color.domain/2` | Sets a two-element (sequential) or three-element (diverging) domain. |
| `Visualize.Scale.Color.range/2` | Replaces the interpolator; accepts a scheme atom, a stop list, or a 1-arity function. |
| `Visualize.Scale.Color.apply/2` | Returns the color string for a value as in 13.3. |
| `Visualize.Scale.Color.clamp/2` | Sets `clamp?` (default `true`). |
| `Visualize.Scale.Color.schemes/0` | Returns the list of 25 scheme atoms. |
| `Visualize.Scale.Color.scheme/1` | Returns the stop list for a scheme atom, or `nil`. |
| `Visualize.Scale.Color.invert/2` | Returns `nil`. |
| `Visualize.Scale.Color.ticks/2` | `Linear.ticks/2` over the domain's extent (see 13.3). |
| `Visualize.Scale.Color.nice/1` | Identity. |
| `Visualize.Scale.Color.padding/2` | Identity. |
| `Visualize.Scale.Color.bandwidth/1` | Returns `0`. |

## 14. `Visualize.Scale.Radial`

### 14.1 Struct

`%Visualize.Scale.Radial{domain: [0, 1], range: [0, 6.283185307179586], clamp?: false}`. The range is in radians and defaults to one full turn, `[0, 2π]`; `range/2` sets any two radians, so a half rose spans `[−π/2, π/2]`.

### 14.2 Semantics

A radial scale maps a cyclic quantity — compass bearing, hour of day, day of year — to an angle (D-30). Angles follow `Visualize.Shape.Arc`'s convention (spec/04 §6.2): radians clockwise from 12 o'clock, so a bearing domain `[0, 360]` over the default range puts north at the top and east at the right with no further arithmetic.

- `apply/2`: `Linear.apply/2` over the domain and range: `t = (v − d0) / (d1 − d0)`, clamped to `[0, 1]` when `clamp?`, result `r0 + t · (r1 − r0)` in radians. A value outside the domain extrapolates (past a full turn) unless clamped; callers wrapping a cyclic value MUST reduce it modulo the period themselves.
- `invert/2`: `Linear.invert/2`; never clamps.
- `ticks/2` (count `n`): `n` equal divisions of the domain from `d0`: `d0 + i · (d1 − d0) / n` for `i` in `0 … n − 1` when the range spans a full turn (`|r1 − r0| ≥ 2π − 1e−9`, where `d1` coincides with `d0` on the circle), and `i` in `0 … n` otherwise. `n ≤ 0` yields `[]`. Unlike `Linear.ticks/2`, the count is exact and the values are not rounded to a nice step: a compass asks for 4, 8, or 16 and gets them; the nice-step sequence would give `0, 100, 200, 300`.
- `nice/1`: identity. The domain of a cyclic quantity is its period, already round; extending it would break the cycle.
- `padding/2` identity; `bandwidth/1` `0`.

### 14.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Scale.Radial.new/0` | Returns the default struct: domain `[0, 1]`, range `[0, 2π]`. |
| `Visualize.Scale.Radial.domain/2` | Sets the domain; a two-element list of numbers. |
| `Visualize.Scale.Radial.range/2` | Sets the range; a two-element list of radians. |
| `Visualize.Scale.Radial.clamp/2` | Sets `clamp?`. |
| `Visualize.Scale.Radial.apply/2` | Maps a domain value to radians as in 14.2; returns a float. |
| `Visualize.Scale.Radial.invert/2` | Maps radians back to the domain; returns a float. |
| `Visualize.Scale.Radial.ticks/2` | `count` equal divisions of the domain as in 14.2. |
| `Visualize.Scale.Radial.nice/1` | Identity. |
| `Visualize.Scale.Radial.padding/2` | Identity. |
| `Visualize.Scale.Radial.bandwidth/1` | Returns `0`. |
