# Utilities

**Status:** Implemented

This document specifies the general-purpose modules used across the library: `Visualize.Color` (parsing, colour spaces and manipulation), `Visualize.Interpolate` (interpolator factories), `Visualize.Ease` (easing curves), `Visualize.Random` (seeded random variates) and `Visualize.Data` (statistics and data shaping). All are pure except `Random`, which reads and advances the calling process's `:rand` state.

## 1. Color

### 1.1 Struct

`%Visualize.Color{r, g, b, opacity}` with `r`, `g`, `b` in `[0, 255]` and `opacity` in `[0, 1]` (default `1.0`). Constructors round channels to integers; interpolation may leave them as floats.

### 1.2 Parsing

`parse/1` trims and lower-cases its argument and returns a colour or `nil`. A non-binary argument returns `nil`. Accepted syntaxes:

- Hex: `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`. Short digits are doubled; an alpha byte becomes `opacity = a / 255`. Any other length after `#` returns `nil`; a non-hex digit raises `ArgumentError`.
- `rgb(r, g, b)` and `rgba(r, g, b, a)`: integer channels, optional decimal alpha, arbitrary whitespace around separators. Percentages are not accepted. A non-matching string returns `nil`.
- `hsl(h, s, l)` and `hsla(h, s, l, a)`: decimal components, `%` optional on `s` and `l`. A non-matching string returns `nil`.
- Named colours: the 148 CSS colour keywords (the 147 classic names plus `rebeccapurple`, with both `gray` and `grey` spellings). Unknown names return `nil`.

`named/1` returns the lower-case hex string for a keyword (case-insensitively) or `nil`; `named_colors/0` returns the keyword list in unspecified order.

### 1.3 Constructors

- `rgb/3,4` clamps channels to `[0, 255]` and opacity to `[0, 1]` without rounding.
- `hsl/3,4` takes `h` in degrees (truncated to an integer and wrapped into `[0, 360)`), `s` and `l` in `[0, 100]` (clamped); channels are rounded.
- `lab/3,4` takes CIE L*a*b* (`l` 0–100, `a` and `b` roughly −128–127), converts through XYZ with reference white `Xn = 0.96422, Yn = 1, Zn = 0.82521` (the d3-color constants) to sRGB, clamps and rounds.
- `hcl/3,4` takes hue in degrees, chroma and luminance, converts to Lab (`a = c cos h`, `b = c sin h`) and delegates to `lab/4`.

### 1.4 Conversions

| Conversion | Output |
|---|---|
| `to_rgb/1` | `{r, g, b}` rounded integers. |
| `to_rgba/1` | `{r, g, b, opacity}`. |
| `to_hsl/1` | `%{h, s, l, opacity}` with `h` a float in `[0, 360)`, `s` and `l` in `[0, 100]`. |
| `to_lab/1` | `%{l, a, b, opacity}`. |
| `to_hcl/1` | `%{h, c, l, opacity}` with `h` in `[0, 360)`. |
| `to_hex/1` | `#rrggbb` in lower case, with `aa` appended when `opacity < 1`. |
| `to_string/1` | `rgb(r, g, b)` when `opacity == 1`, otherwise `rgba(r, g, b, opacity)` with the opacity printed as-is. |

### 1.5 Manipulation

- `brighter/1,2` and `darker/1,2`: `k` defaults to 1; the colour is converted to Lab, `L` is increased (decreased) by `18 * k`, and converted back. The factor is additive in Lab luminance, not multiplicative in RGB.
- `saturate/1,2` multiplies HSL saturation by `amount` (default `1.2`); `desaturate/1,2` is `saturate/2` with default `0.8`.
- `rotate/2` adds degrees to the HSL hue.
- `grayscale/1` sets every channel to `round(0.299 r + 0.587 g + 0.114 b)`.
- `invert/1` sets each channel to `255 - channel`.
- `with_opacity/2` sets a clamped opacity.
- `luminance/1` is WCAG relative luminance in `[0, 1]`; `contrast/2` is `(L_light + 0.05) / (L_dark + 0.05)` in `[1, 21]`.
- `mix/2` is `interpolate_rgb(c1, c2, 0.5)`.

### 1.6 Interpolation

Each `interpolate_*/3` takes two colours and `t` (not clamped) and returns a colour. `interpolate_rgb/3` interpolates channels and opacity linearly and leaves them unrounded. `interpolate_hsl/3` and `interpolate_hcl/3` interpolate in HSL and HCL respectively, taking the shorter arc around the hue circle; `interpolate_lab/3` interpolates in Lab. Results other than RGB pass through the corresponding constructor and are rounded.

### 1.7 Functions

| Function | Contract |
|---|---|
| `Visualize.Color.parse/1` | Parses hex, `rgb()`, `hsl()` or a keyword; `nil` when unrecognised (1.2). |
| `Visualize.Color.named/1` | Hex string for a colour keyword, or `nil`. |
| `Visualize.Color.named_colors/0` | All 148 colour keywords. |
| `Visualize.Color.rgb/3` | `rgb(r, g, b, 1.0)`. |
| `Visualize.Color.rgb/4` | Colour from clamped RGB channels and opacity. |
| `Visualize.Color.hsl/3` | `hsl(h, s, l, 1.0)`. |
| `Visualize.Color.hsl/4` | Colour from HSL; hue truncated to a whole degree. |
| `Visualize.Color.lab/3` | `lab(l, a, b, 1.0)`. |
| `Visualize.Color.lab/4` | Colour from CIE Lab, clamped to sRGB. |
| `Visualize.Color.hcl/3` | `hcl(h, c, l, 1.0)`. |
| `Visualize.Color.hcl/4` | Colour from HCL via Lab. |
| `Visualize.Color.to_rgb/1` | `{r, g, b}` integers. |
| `Visualize.Color.to_rgba/1` | `{r, g, b, opacity}`. |
| `Visualize.Color.to_hsl/1` | HSL map. |
| `Visualize.Color.to_lab/1` | Lab map. |
| `Visualize.Color.to_hcl/1` | HCL map. |
| `Visualize.Color.to_hex/1` | Lower-case hex, with alpha when translucent. |
| `Visualize.Color.to_string/1` | CSS `rgb()`/`rgba()` string. |
| `Visualize.Color.brighter/1` | `brighter(color, 1)`. |
| `Visualize.Color.brighter/2` | Lab luminance plus `18 k`. |
| `Visualize.Color.darker/1` | `darker(color, 1)`. |
| `Visualize.Color.darker/2` | Lab luminance minus `18 k`. |
| `Visualize.Color.with_opacity/2` | Copy with clamped opacity. |
| `Visualize.Color.saturate/1` | `saturate(color, 1.2)`. |
| `Visualize.Color.saturate/2` | HSL saturation multiplied by `amount`. |
| `Visualize.Color.desaturate/1` | `saturate(color, 0.8)`. |
| `Visualize.Color.desaturate/2` | `saturate(color, amount)`. |
| `Visualize.Color.rotate/2` | Hue rotated by degrees. |
| `Visualize.Color.grayscale/1` | Luma-weighted grey. |
| `Visualize.Color.invert/1` | Channel complement. |
| `Visualize.Color.luminance/1` | WCAG relative luminance. |
| `Visualize.Color.contrast/2` | WCAG contrast ratio. |
| `Visualize.Color.mix/2` | Equal RGB mix. |
| `Visualize.Color.interpolate_rgb/3` | Linear RGB interpolation, unrounded. |
| `Visualize.Color.interpolate_hsl/3` | HSL interpolation, shortest hue arc. |
| `Visualize.Color.interpolate_lab/3` | Lab interpolation. |
| `Visualize.Color.interpolate_hcl/3` | HCL interpolation, shortest hue arc. |

## 2. Interpolate

Every function in `Visualize.Interpolate` returns a one-argument function of `t`. `t` is not clamped unless stated; callers pass `[0, 1]` for the nominal range.

### 2.1 Colour inputs and output

`rgb/2`, `hsl/2` and `hsl_long/2` accept each endpoint as a hex string with or without `#` (3 or 6 digits), an `{r, g, b}` tuple, or one of thirteen basic names (`red`, `green`, `blue`, `white`, `black`, `yellow`, `cyan`, `magenta`, `orange`, `purple`, `pink`, `gray`, `grey`). Anything else is treated as black. `%Visualize.Color{}` structs are not accepted. The returned function yields `#RRGGBB` with upper-case hex digits (as produced by `Integer.to_string/2`).

### 2.2 Interpolators

| Factory | Input | Returned function |
|---|---|---|
| `number/2` | Two numbers | `t -> a + (b - a) * t`. |
| `round/2` | Two numbers | `t -> round(a + (b - a) * t)`, an integer. |
| `discrete/1` | Non-empty list of `n` values | `t -> values[clamp(floor(t * n), 0, n - 1)]`. |
| `rgb/2` | Two colours (2.1) | Per-channel linear blend, rounded and clamped, as hex. |
| `hsl/2` | Two colours | HSL blend with the shorter hue arc, as hex. |
| `hsl_long/2` | Two colours | HSL blend with the longer hue arc, as hex. |
| `array/2` | Two equal-length number lists | Element-wise `number/2`; returns a list. |
| `datetime/2` | Two `DateTime` | Millisecond-precision blend, rounded; returns a `DateTime`. |
| `date/2` | Two `Date` | Day-precision blend, rounded; returns a `Date`. |
| `string/2` | Two strings | Numbers embedded in `b` (pattern `-?\d+\.?\d*`) are blended pairwise with the numbers in `a`; non-numeric text is taken from `b`. When `a` has fewer numbers the missing ones start from 0; extra numbers in `a` are ignored. A whole result prints as an integer, otherwise as a float rounded to 4 decimals. |
| `transform/2` | Two SVG transform strings | Recognises the first `translate(x[, y])` (missing `y` is 0), `scale(s[, sy])` (a single value applies to both axes) and `rotate(a)` in each string; `rotate(a, cx, cy)` parses as 0. A component present in only one string is held constant; one absent from both defaults to identity. Output is `translate(x, y) scale(sx, sy) rotate(r)` joined by spaces, omitting components equal to identity, or `""`. Numbers print as integers when whole, otherwise rounded to 4 decimals. |
| `basis/1` | List of at least two numbers | Uniform cubic B-spline through the values with clamped end conditions; `t` is clamped to `[0, 1]`, and `t = 0` and `t = 1` return the first and last values exactly. |
| `zoom/2` | Two views `[cx, cy, w]` | van Wijk–Nuij smooth zoom with `ρ = 1.4`; returns `[cx, cy, w]`. When the centres coincide (distance below `1.0e-6`) only `w` changes, exponentially. |

### 2.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Interpolate.number/2` | Linear numeric interpolator. |
| `Visualize.Interpolate.round/2` | Linear interpolator rounded to an integer. |
| `Visualize.Interpolate.discrete/1` | Stepped interpolator over a non-empty list. |
| `Visualize.Interpolate.rgb/2` | RGB colour interpolator returning hex. |
| `Visualize.Interpolate.hsl/2` | HSL interpolator, short hue arc. |
| `Visualize.Interpolate.hsl_long/2` | HSL interpolator, long hue arc. |
| `Visualize.Interpolate.array/2` | Element-wise interpolator over equal-length lists. |
| `Visualize.Interpolate.datetime/2` | `DateTime` interpolator at millisecond precision. |
| `Visualize.Interpolate.date/2` | `Date` interpolator at day precision. |
| `Visualize.Interpolate.string/2` | Interpolates numbers embedded in a string template. |
| `Visualize.Interpolate.transform/2` | Interpolates translate, scale and rotate of SVG transform strings. |
| `Visualize.Interpolate.basis/1` | B-spline interpolator through a value list. |
| `Visualize.Interpolate.zoom/2` | Smooth zoom interpolator between `[cx, cy, w]` views. |

## 3. Ease

`Visualize.Ease` provides 25 easing functions from `t` in `[0, 1]` to a float, nominally in `[0, 1]` (the `elastic_*` and `back_*` families overshoot). `names/0` returns the 25 atoms below in this order; `by_name/1` returns the arity-1 function for an atom and raises `FunctionClauseError` for any other atom. `frames/2` with `count > 1` returns `count` values at `t = i / (count - 1)` for `i` in `0..count - 1`; `frames(_, 1)` returns `[1.0]`.

### 3.1 Formulas

With `c1 = 1.70158`, `c2 = c1 * 1.525`, `c3 = c1 + 1`, `c4 = 2π / 3`, `c5 = 2π / 4.5`, `n1 = 7.5625`, `d1 = 2.75`:

| Name | Formula |
|---|---|
| `:linear` | `t` |
| `:quad_in` | `t²` |
| `:quad_out` | `t (2 - t)` |
| `:quad_in_out` | `t < 0.5: 2t²`; else `-1 + (4 - 2t) t` |
| `:cubic_in` | `t³` |
| `:cubic_out` | `(t - 1)³ + 1` |
| `:cubic_in_out` | `t < 0.5: 4t³`; else `(2t - 2)³ / 2 + 1` |
| `:sin_in` | `1 - cos(πt / 2)` |
| `:sin_out` | `sin(πt / 2)` |
| `:sin_in_out` | `-(cos(πt) - 1) / 2` |
| `:exp_in` | `2^(10(t - 1))`; exactly `0.0` for the integer `0` |
| `:exp_out` | `1 - 2^(-10t)`; exactly `1.0` for the integer `1` |
| `:exp_in_out` | `t < 0.5: 2^(20t - 10) / 2`; else `(2 - 2^(-20t + 10)) / 2`; exact at integer `0` and `1` |
| `:circle_in` | `1 - sqrt(1 - t²)` |
| `:circle_out` | `sqrt(1 - (t - 1)²)` |
| `:circle_in_out` | `t < 0.5: (1 - sqrt(1 - 4t²)) / 2`; else `(sqrt(1 - (-2t + 2)²) + 1) / 2` |
| `:elastic_in` | `-2^(10t - 10) sin((10t - 10.75) c4)`; exact at integer `0` and `1` |
| `:elastic_out` | `2^(-10t) sin((10t - 0.75) c4) + 1`; exact at integer `0` and `1` |
| `:elastic_in_out` | `t < 0.5: -2^(20t - 10) sin((20t - 11.125) c5) / 2`; else `2^(-20t + 10) sin((20t - 11.125) c5) / 2 + 1`; exact at integer `0` and `1` |
| `:back_in` | `c3 t³ - c1 t²` |
| `:back_out` | `1 + c3 (t - 1)³ + c1 (t - 1)²` |
| `:back_in_out` | `t < 0.5: (2t)² ((c2 + 1) 2t - c2) / 2`; else `((2t - 2)² ((c2 + 1)(2t - 2) + c2) + 2) / 2` |
| `:bounce_in` | `1 - bounce_out(1 - t)` |
| `:bounce_out` | `t < 1/d1: n1 t²`; `t < 2/d1: n1 (t - 1.5/d1)² + 0.75`; `t < 2.5/d1: n1 (t - 2.25/d1)² + 0.9375`; else `n1 (t - 2.625/d1)² + 0.984375` |
| `:bounce_in_out` | `t < 0.5: (1 - bounce_out(1 - 2t)) / 2`; else `(1 + bounce_out(2t - 1)) / 2` |

The exact-endpoint clauses match the integer literals `0` and `1` only; the floats `0.0` and `1.0` fall through to the formula (`exp_in(0.0)` is `2^-10`).

Parameterised variants: `poly_in/2`, `poly_out/2` and `poly_in_out/2` take an exponent `e` (default 3): `t^e`; `1 - (1 - t)^e`; `t < 0.5: 2^(e-1) t^e` else `1 - (-2t + 2)^e / 2`. `back_in/2` and `back_out/2` take an overshoot `s` replacing `c1` (with `c3 = s + 1`); there is no `back_in_out/2`.

### 3.2 Functions

| Function | Contract |
|---|---|
| `Visualize.Ease.linear/1` | Identity as a float. |
| `Visualize.Ease.quad_in/1` | Quadratic ease-in. |
| `Visualize.Ease.quad_out/1` | Quadratic ease-out. |
| `Visualize.Ease.quad_in_out/1` | Quadratic ease-in-out. |
| `Visualize.Ease.cubic_in/1` | Cubic ease-in. |
| `Visualize.Ease.cubic_out/1` | Cubic ease-out. |
| `Visualize.Ease.cubic_in_out/1` | Cubic ease-in-out. |
| `Visualize.Ease.poly_in/1` | `poly_in(t, 3)`. |
| `Visualize.Ease.poly_in/2` | Polynomial ease-in with exponent. |
| `Visualize.Ease.poly_out/1` | `poly_out(t, 3)`. |
| `Visualize.Ease.poly_out/2` | Polynomial ease-out with exponent. |
| `Visualize.Ease.poly_in_out/1` | `poly_in_out(t, 3)`. |
| `Visualize.Ease.poly_in_out/2` | Polynomial ease-in-out with exponent. |
| `Visualize.Ease.sin_in/1` | Sinusoidal ease-in. |
| `Visualize.Ease.sin_out/1` | Sinusoidal ease-out. |
| `Visualize.Ease.sin_in_out/1` | Sinusoidal ease-in-out. |
| `Visualize.Ease.exp_in/1` | Exponential ease-in. |
| `Visualize.Ease.exp_out/1` | Exponential ease-out. |
| `Visualize.Ease.exp_in_out/1` | Exponential ease-in-out. |
| `Visualize.Ease.circle_in/1` | Circular ease-in. |
| `Visualize.Ease.circle_out/1` | Circular ease-out. |
| `Visualize.Ease.circle_in_out/1` | Circular ease-in-out. |
| `Visualize.Ease.elastic_in/1` | Elastic ease-in. |
| `Visualize.Ease.elastic_out/1` | Elastic ease-out. |
| `Visualize.Ease.elastic_in_out/1` | Elastic ease-in-out. |
| `Visualize.Ease.back_in/1` | Back ease-in with overshoot `1.70158`. |
| `Visualize.Ease.back_in/2` | Back ease-in with custom overshoot. |
| `Visualize.Ease.back_out/1` | Back ease-out with overshoot `1.70158`. |
| `Visualize.Ease.back_out/2` | Back ease-out with custom overshoot. |
| `Visualize.Ease.back_in_out/1` | Back ease-in-out. |
| `Visualize.Ease.bounce_in/1` | Bounce ease-in. |
| `Visualize.Ease.bounce_out/1` | Bounce ease-out. |
| `Visualize.Ease.bounce_in_out/1` | Bounce ease-in-out. |
| `Visualize.Ease.by_name/1` | Arity-1 function for one of the 25 names; raises otherwise. |
| `Visualize.Ease.names/0` | The 25 easing names. |
| `Visualize.Ease.frames/2` | `count` eased samples at evenly spaced `t`. |

## 4. Random

`Visualize.Random` draws from the process-local `:rand` generator. `seed/1` calls `:rand.seed(:exsss, {s, 2s, 3s})` and returns the new state, making subsequent draws in the calling process reproducible.

### 4.1 Distributions

| Family | Parameters and defaults | Result |
|---|---|---|
| `uniform/0,1,2` | `min = 0`, `max = 1` | Float in `[min, max)`. |
| `uniform_int/2` | `min`, `max` | Integer in `[min, max]`. |
| `normal/0,1,2` | `mean = 0`, `stddev = 1` | Box–Muller normal variate. |
| `log_normal/0,1,2` | `mu = 0`, `sigma = 1` | `exp(normal(mu, sigma))`. |
| `exponential/0,1` | `lambda = 1` | `-ln(1 - u) / lambda`. |
| `pareto/0,1` | `alpha = 1` | `1 / (1 - u)^(1 / alpha)`, minimum 1. |
| `bernoulli/0,1` | `p = 0.5` | `1` with probability `p`, else `0`. |
| `binomial/2` | `n`, `p` | Number of successes in `n` Bernoulli trials; MUST be `0` for `n = 0`. |
| `geometric/1` | `p` | Number of failures before the first success, `trunc(ln(1 - u) / ln(1 - p))`. |
| `poisson/1` | `lambda` | Knuth's multiplication method. |
| `gamma/1,2` | `shape > 0`, `scale = 1` | Marsaglia–Tsang; `shape < 1` is boosted through `shape + 1`. |
| `beta/2` | `alpha`, `beta` | `x / (x + y)` with `x = gamma(alpha)`, `y = gamma(beta)`. |
| `weibull/1,2` | `shape`, `scale = 1` | `scale * (-ln(1 - u))^(1 / shape)`. |
| `cauchy/0,1,2` | `location = 0`, `scale = 1` | `location + scale * tan(π (u - 0.5))`. |

### 4.2 Points and collections

- `in_circle/0..3` (`cx = 0`, `cy = 0`, `radius = 1`): uniform over the disc using `r = radius * sqrt(u)`.
- `on_circle/0..3` (same defaults): uniform on the circumference.
- `in_rect/4` (`x0, y0, x1, y1`): uniform over the rectangle.
- `samples/2` (`fun, n`): a list of `n` calls of the zero-arity function; MUST be `[]` for `n = 0`.
- `shuffle/1`: `Enum.shuffle/1`.
- `sample/2` (`list, n`): `n` distinct elements of a shuffled list (fewer when the list is shorter).
- `pick/1`: a random element, or `nil` for `[]`.

`binomial(0, p)` is 0 and `samples(fun, 0)` is `[]`: both iterate `1..n//1`, which is empty for `n = 0` (D-44).

### 4.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Random.seed/1` | Seeds `:rand` with `:exsss` from an integer. |
| `Visualize.Random.uniform/0` | `uniform(0, 1)`. |
| `Visualize.Random.uniform/1` | `uniform(min, 1)`. |
| `Visualize.Random.uniform/2` | Float in `[min, max)`. |
| `Visualize.Random.uniform_int/2` | Integer in `[min, max]`. |
| `Visualize.Random.normal/0` | `normal(0, 1)`. |
| `Visualize.Random.normal/1` | `normal(mean, 1)`. |
| `Visualize.Random.normal/2` | Gaussian variate. |
| `Visualize.Random.log_normal/0` | `log_normal(0, 1)`. |
| `Visualize.Random.log_normal/1` | `log_normal(mu, 1)`. |
| `Visualize.Random.log_normal/2` | Log-normal variate. |
| `Visualize.Random.exponential/0` | `exponential(1)`. |
| `Visualize.Random.exponential/1` | Exponential variate with rate `lambda`. |
| `Visualize.Random.pareto/0` | `pareto(1)`. |
| `Visualize.Random.pareto/1` | Pareto variate with shape `alpha` and minimum 1. |
| `Visualize.Random.bernoulli/0` | `bernoulli(0.5)`. |
| `Visualize.Random.bernoulli/1` | `1` with probability `p`, else `0`. |
| `Visualize.Random.binomial/2` | Successes in `n` trials of probability `p`. |
| `Visualize.Random.geometric/1` | Failures before the first success. |
| `Visualize.Random.poisson/1` | Poisson count with mean `lambda`. |
| `Visualize.Random.gamma/1` | `gamma(shape, 1)`. |
| `Visualize.Random.gamma/2` | Gamma variate; requires `shape > 0`. |
| `Visualize.Random.beta/2` | Beta variate. |
| `Visualize.Random.weibull/1` | `weibull(shape, 1)`. |
| `Visualize.Random.weibull/2` | Weibull variate. |
| `Visualize.Random.cauchy/0` | `cauchy(0, 1)`. |
| `Visualize.Random.cauchy/1` | `cauchy(location, 1)`. |
| `Visualize.Random.cauchy/2` | Cauchy variate. |
| `Visualize.Random.in_circle/0` | `in_circle(0, 0, 1)`. |
| `Visualize.Random.in_circle/1` | `in_circle(cx, 0, 1)`. |
| `Visualize.Random.in_circle/2` | `in_circle(cx, cy, 1)`. |
| `Visualize.Random.in_circle/3` | Uniform point in a disc. |
| `Visualize.Random.on_circle/0` | `on_circle(0, 0, 1)`. |
| `Visualize.Random.on_circle/1` | `on_circle(cx, 0, 1)`. |
| `Visualize.Random.on_circle/2` | `on_circle(cx, cy, 1)`. |
| `Visualize.Random.on_circle/3` | Uniform point on a circle. |
| `Visualize.Random.in_rect/4` | Uniform point in a rectangle. |
| `Visualize.Random.samples/2` | `n` draws from a zero-arity function. |
| `Visualize.Random.shuffle/1` | Random permutation. |
| `Visualize.Random.sample/2` | `n` distinct random elements. |
| `Visualize.Random.pick/1` | One random element or `nil`. |

## 5. Data

`Visualize.Data` shadows `Kernel.min/2` and `Kernel.max/2` inside the module. Every statistic takes an optional arity-1 accessor as its last argument (`nil` means the elements are the values).

### 5.1 Statistics

| Statistic | Empty input | Result |
|---|---|---|
| `min/1,2`, `max/1,2` | `nil` | Least or greatest value by term order. |
| `extent/1,2` | `nil` | `{min, max}`. |
| `sum/1,2` | `0` | Sum. |
| `mean/1,2` | `nil` | Arithmetic mean (float). |
| `median/1,2` | `nil` | Middle of the sorted values; mean of the two middles for even counts. |
| `quantile/2,3` | `nil` | Linear interpolation at index `(n - 1) * p` of the sorted values; `p` MUST be in `[0, 1]` (otherwise `FunctionClauseError`). |
| `variance/1,2` | `nil`; also `nil` for one element | Sample variance with `n - 1` denominator. |
| `deviation/1,2` | `nil` | Square root of `variance/2`. |

### 5.2 Grouping and shaping

- `group/2` — `Enum.group_by/2`: a map from key to the elements with that key, in input order.
- `rollup/3` — `group/2` followed by applying the reducer to each group's list: a map from key to reduced value.
- `bin/1,2` — histogram bins. Options: `:thresholds` — an integer count `n` (default 10), producing `n - 1` interior thresholds evenly spaced over the domain and hence `n` bins, or an explicit list of thresholds producing `length + 1` bins; `:domain` — `[min, max]`, defaulting to the data extent. Returns `[%{x0, x1, values}]` where each value is placed in the first bin with `x0 <= v < x1`, a value equal to the last `x1` goes in the last bin, and values outside the domain are dropped; `values` keep input order. `[]` yields `[]`.
- `cross/2,3` — the Cartesian product of two lists as `{a, b}` tuples, or as `combine.(a, b)` when a two-arity function is given.
- `range/2,3` — `start, stop, step = 1`: `max(0, ceil((stop - start) / step))` values `start + i * step`, so the result is empty when `stop` is not beyond `start` in the direction of `step`; negative steps count down. `step` MUST be non-zero (otherwise `FunctionClauseError`).
- `ticks/3` — `start, stop, count > 0`: nice tick values. The step is `10^k` times 1, 2, 5 or 10, chosen from `|stop - start| / count` with the d3 thresholds `sqrt(2)`, `sqrt(10)`, `sqrt(50)`; ticks run from `ceil(start / step) * step` to `floor(stop / step) * step` inclusive, rounded to 10 decimals, and are `[]` when no multiple of the step lies inside the span. A zero span returns `[start]`; `start > stop` returns the ticks of the reversed span in descending order. `count` MUST be positive (otherwise `FunctionClauseError`).
- `sort/2,3` — `Enum.sort_by/3` on the accessor, `:asc` (default) or `:desc`.
- `unique/1,2` — `Enum.uniq/1`, or `Enum.uniq_by/2` with an accessor.

### 5.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Data.min/1` | `min(data, nil)`. |
| `Visualize.Data.min/2` | Minimum by accessor; `nil` for `[]`. |
| `Visualize.Data.max/1` | `max(data, nil)`. |
| `Visualize.Data.max/2` | Maximum by accessor; `nil` for `[]`. |
| `Visualize.Data.extent/1` | `extent(data, nil)`. |
| `Visualize.Data.extent/2` | `{min, max}` by accessor; `nil` for `[]`. |
| `Visualize.Data.sum/1` | `sum(data, nil)`. |
| `Visualize.Data.sum/2` | Sum by accessor; `0` for `[]`. |
| `Visualize.Data.mean/1` | `mean(data, nil)`. |
| `Visualize.Data.mean/2` | Mean by accessor; `nil` for `[]`. |
| `Visualize.Data.median/1` | `median(data, nil)`. |
| `Visualize.Data.median/2` | Median by accessor; `nil` for `[]`. |
| `Visualize.Data.quantile/2` | `quantile(data, p, nil)`. |
| `Visualize.Data.quantile/3` | Interpolated `p`-quantile by accessor; `nil` for `[]`. |
| `Visualize.Data.variance/1` | `variance(data, nil)`. |
| `Visualize.Data.variance/2` | Sample variance; `nil` for fewer than two values. |
| `Visualize.Data.deviation/1` | `deviation(data, nil)`. |
| `Visualize.Data.deviation/2` | Sample standard deviation; `nil` for fewer than two values. |
| `Visualize.Data.group/2` | Map from key to element list. |
| `Visualize.Data.rollup/3` | Map from key to reduced group. |
| `Visualize.Data.bin/1` | `bin(data, [])`. |
| `Visualize.Data.bin/2` | Histogram bins `%{x0, x1, values}` (5.2). |
| `Visualize.Data.cross/2` | Cartesian product as tuples. |
| `Visualize.Data.cross/3` | Cartesian product combined by a function. |
| `Visualize.Data.range/2` | `range(start, stop, 1)`. |
| `Visualize.Data.range/3` | Arithmetic sequence from `start` toward `stop` by `step`. |
| `Visualize.Data.ticks/3` | Nice tick values between `start` and `stop` (5.2). |
| `Visualize.Data.sort/2` | `sort(data, accessor, :asc)`. |
| `Visualize.Data.sort/3` | Sort by accessor in `:asc` or `:desc` order. |
| `Visualize.Data.unique/1` | `unique(data, nil)`. |
| `Visualize.Data.unique/2` | Distinct elements by accessor, first occurrence kept. |
