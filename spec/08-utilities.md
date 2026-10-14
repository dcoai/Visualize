# Utilities

**Status:** Implemented

This document specifies the general-purpose modules used across the library: `Visualize.Color` (parsing, colour spaces and manipulation) with `Visualize.Color.Vision` (colour-vision simulation, §1.8), `Visualize.Interpolate` (interpolator factories), `Visualize.Ease` (easing curves), `Visualize.Random` (seeded random variates), `Visualize.Data` (statistics and data shaping), `Visualize.Data.Table` (tabular sources as rows), `Visualize.Data.Schema` and `Visualize.Data.Delivery` (what a feed says about its fields, and one answer of a feed, §10), `Visualize.Feed` and its monitor and providers (how a feed is asked, §11), `Visualize.Feed.Conformance` (the test every provider runs, §12) and `Visualize.Theme` (the colours, font and sizes every mark draws with). All are pure except `Random`, which reads and advances the calling process's `:rand` state, and the feeds of §11, whose providers are other processes.

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
| `to_lab/1` | `%{l, a, b, opacity}`: sRGB to XYZ through the D50-adapted matrix and white point of `lab/4` (d3-color's), so the two are each other's inverse — `lab/4` of `to_lab/1` is the colour again, and a grey has `a = b = 0` (D-135). |
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

### 1.8 Colour-vision simulation

**Implemented** (#563, D-139). `Visualize.Color.Vision` simulates how a colour reads to a person with one of the three dichromacies, so a palette can be judged by eye for the readers it would fail. It is a pure colour transform and is used for judging only — nothing in the library draws through it on its own.

The model is **Machado, Oliveira and Fernandes (2009)**, "A Physiologically-based Model for Simulation of Color Vision Deficiency", *IEEE Transactions on Visualization and Computer Graphics* 15(6), 1291–1298, at **severity 1.0** — full dichromacy. A colour is decoded from sRGB to linear RGB (the sRGB transfer function of IEC 61966-2-1: `c / 12.92` for `c ≤ 0.04045`, else `((c + 0.055) / 1.055)^2.4`), multiplied by the deficiency's matrix, clamped to `0..1`, and encoded back; the opacity is kept. The matrices are the paper's published severity-1.0 matrices:

| Deficiency | Matrix (rows R, G, B) |
|---|---|
| `:protanopia` (no L cones) | `[0.152286, 1.052583, −0.204868]`, `[0.114503, 0.786281, 0.099216]`, `[−0.003882, −0.048116, 1.051998]` |
| `:deuteranopia` (no M cones) | `[0.367322, 0.860646, −0.227968]`, `[0.280085, 0.672501, 0.047413]`, `[−0.011820, 0.042940, 0.968881]` |
| `:tritanopia` (no S cones) | `[1.255528, −0.076749, −0.178779]`, `[−0.078411, 0.930809, 0.147602]`, `[0.004733, 0.691367, 0.303900]` |

Each row sums to 1, so every grey is its own simulation — a property the tests hold. `:none` is the identity. Machado's model was chosen over Brettel, Viénot and Mollon (1997), which is more exact for tritanopia but splits each deficiency into two half-planes, and over Viénot, Brettel and Mollon (1999), a single projection that cannot grade severity: one matrix per deficiency is cheap enough to run over every colour of a preview on every edit, and the same model at a severity below 1 would simulate the anomalous trichromacies later with no new code path (D-139).

| Function | Contract |
|---|---|
| `Visualize.Color.Vision.deficiencies/0` | `[:protanopia, :deuteranopia, :tritanopia]` |
| `Visualize.Color.Vision.matrix/1` | the deficiency's 3×3 matrix as three rows, from the table above |
| `Visualize.Color.Vision.simulate/2` | `simulate(colour, deficiency)`: a `%Visualize.Color{}` as the deficiency sees it, opacity kept; `:none` is the colour; any other atom raises `ArgumentError` |
| `Visualize.Color.Vision.recolour/2` | `recolour(text, deficiency)`: every `#rrggbb` and `#rgb` colour literal in a text — an SVG's attribute values, a style — replaced by its simulation as `#rrggbb`; a `#` that is a reference, `url(#id)`, is left alone |

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
- `lttb/2,3` and `m4/2,3` — **shape-preserving downsampling** of a series (#448): a subsequence of the input elements, never new ones, so a tooltip over a kept point reads a real datum. The accessor returns `{x, y}`; without one the elements are `{x, y}` tuples. A datum is **defined** when both `x` and `y` are numbers; any other datum is a **gap**. The defined data split at the gaps into **runs**, and both functions reduce each run separately and keep exactly **the first element of every run of gaps**, in place — so a line drawn over the result still breaks where the input broke (spec/04's `defined/2`). Both are one pass over the input plus a constant amount per element: O(n) time, and O(n) space for the random access a run's buckets need. Both read the elements in input order and expect `x` ascending within a run, as a series is; neither sorts.
  - `lttb(data, n, accessor)` — **Largest-Triangle-Three-Buckets** (Steinarsson 2013, *Downsampling Time Series for Visual Representation*, §4.2). `n` is an integer `>= 3` (otherwise `FunctionClauseError`). Input of `n` or fewer elements, gaps counted, is returned unchanged. A single run of `L > n` elements keeps exactly `n`: its first and last, and one per bucket of the `n − 2` buckets that split the interior evenly — bucket `i` (`0 ≤ i < n − 2`) is the interior indices `[floor(i·e) + 1, floor((i + 1)·e) + 1)` with `e = (L − 2) / (n − 2)` — choosing in each the element that forms the **largest triangle** with the element chosen in the bucket before it (the first element, for bucket `0`) and the **mean** point of the bucket after it (indices `[floor((i + 1)·e) + 1, min(floor((i + 2)·e) + 1, L))`, which for the last bucket holds the last element); a tie keeps the earliest. With gaps, a run of `L` defined elements out of `D` in all has the budget `b = max(min(L, 2), floor(n · L / D))`: a run with `b ≥ L` is kept whole, `b = 2` keeps its first and last, and otherwise LTTB with `b`. The total is therefore about `n` and exactly `n` without gaps.
  - `m4(data, width, accessor)` — **M4** (Jugel et al. 2014, *M4: A Visualization-Oriented Time Series Data Aggregation*): per pixel column, the first, last, minimum-`y` and maximum-`y` elements. `width` is an integer `>= 1` (otherwise `FunctionClauseError`), the column count. The columns split the **defined `x` extent** `[x_min, x_max]` evenly: a defined datum's column is `min(width − 1, floor((x − x_min) / (x_max − x_min) · width))`, every datum column `0` when `x_min == x_max`. A **column visit** is a maximal stretch of consecutive defined elements of one run in one column; each visit keeps its first, its last, its earliest least `y` and its earliest greatest `y`, deduplicated and in input order — so at most four per visit, and a run whose every visit has four or fewer elements is kept whole. Drawn as a line on a plot `width` pixels wide whose `x` scale spans `[x_min, x_max]`, the result covers every pixel column the input covers with the same vertical extent and the same entry and exit points, which is why it is lossless at that resolution: a peak is never dropped.

  Neither has an Nx path. LTTB's choice in a bucket depends on the choice in the bucket before it, a serial dependency a vectorised pass cannot express; M4 needs a segmented argmin and argmax per column, which Nx offers no primitive for; and both keep whole elements, which a tensor does not hold, so the cost an Nx path would save — the arithmetic — is not the cost of the call, which is reading the accessor over every element. `Visualize.Shape.LineNx`'s optional-Nx pattern (spec/04 §10.1) is therefore deferred until a measurement shows the arithmetic, not the reading, is what a reduction costs; the benchmark of #448 (a tagged test, not a gate) is that measurement's baseline.

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
| `Visualize.Data.lttb/2` | `lttb(data, n, nil)`: the elements are `{x, y}` tuples. |
| `Visualize.Data.lttb/3` | Largest-Triangle-Three-Buckets to about `n` elements, each run of gaps kept as its first element (5.2); unchanged at `n` or fewer elements; `n >= 3`. |
| `Visualize.Data.m4/2` | `m4(data, width, nil)`: the elements are `{x, y}` tuples. |
| `Visualize.Data.m4/3` | Per pixel column of `width` over the defined `x` extent, each column visit's first, last, least-`y` and greatest-`y` elements, each run of gaps kept as its first element (5.2); `width >= 1`. |

## 6. Data.Table

`Visualize.Data.Table` turns the shapes chart data arrives in into the list of rows every generator consumes ([04-shapes-and-curves](04-shapes-and-curves.md) §1). The `table` package (the `Table.Reader` protocol and its `List` and `Map` impls) is an optional dependency like Nx (D-52): a host that has it reads Explorer frames and any other struct implementing the protocol; without it lists, column maps and tensors still work and a struct source raises `UndefinedFunctionError` at `Table.to_rows/1`.

### 6.1 Sources

`Visualize.Data.Table.rows/1` accepts, and distinguishes by shape:

| Source | Rows |
|---|---|
| A list of rows (maps or tuples) | The list itself: no copy, no traversal. |
| A keyword list whose values are equal-length lists | One map per index, keyed by the keys. A keyword list is read as columns before rows, as `table` reads a list; `[{:a, [1]}]` is therefore one column. A keyword list whose lists differ in length is rows. |
| A map whose values are equal-length lists | One map per index, keyed by the map's keys (atoms or strings, as given). Any other non-empty plain map raises `ArgumentError`. |
| `%Nx.Tensor{}` of rank 2 | One tuple per row in column order, which is what the default `Visualize.Shape.Line` accessors read. Rank 1 yields the list of values; any other rank raises `ArgumentError`. |
| `%Visualize.Data.Delivery{}` | The rows of the source it carries, read by this same table: a delivery is a feed's answer, its rows beside the facts of the answer (§10.4, #535). |
| Any other struct | `Table.to_rows/1`: rows keyed by the reader's column names as it spells them (Explorer: strings), whether the reader traverses by rows or by columns. A struct with no `Table.Reader` impl raises `Protocol.UndefinedError`; a reader answering `:none` raises `ArgumentError`. |

`[]`, `%{}` and the empty keyword list yield `[]`. A rank-1 tensor bound to a dense series stays a first-class source for `Visualize.Shape.LineNx` and the binary path; `Visualize.Data.Table.rows/1` does not stand between them.

### 6.2 Column names

A source names its columns with atoms or strings and a caller writes accessors in either. `Visualize.Data.Table.get/2` reads the row by the given spelling first, then by the other: an atom name falls back to `Atom.to_string/1`, a string name to the atom key that spells the same. No atom is ever created. `nil` when neither is a key, so a missing column behaves as an absent map key does in [04-shapes-and-curves](04-shapes-and-curves.md) §1.1. `Visualize.Data.Table.accessor/1` is `fn row -> get(row, name) end`, and returns a 1-arity function unchanged so a generator normalises every accessor form through one call. A tuple row has no names: `get/2` raises `BadMapError`.

### 6.3 Time columns

`Visualize.Data.Table.time_columns/1` names the columns a time scale could be inferred from: every key of every map row, sorted by term order (a row without the key contributes `nil`), kept when the column has at least one non-`nil` value and every value is `nil` or `temporal?/1`. `Visualize.Data.Table.temporal?/1` is true for `DateTime`, `Date` and `NaiveDateTime` and for a string one of `DateTime.from_iso8601/1`, `NaiveDateTime.from_iso8601/1` or `Date.from_iso8601/1` parses; anything else, including a bare year or a non-ISO date, is false. Detection reads the whole column, not the first row as Tucan does: every row is visited and every string parsed, so the cost is the size of the table, and a column that starts temporal and stops being so is not temporal. Tuple rows have no names and yield `[]`.

`Visualize.Data.Table.column_types/1` (#369) types every named column of a table as spec/14 §2.3's four, reading the whole column as `time_columns/1` does: a column whose non-`nil` values are all `temporal?/1` is `:time`; all numbers, `:number`; all strings (none temporal), `:text`; all atoms or booleans, `:category`; a column with no non-`nil` value, or with values of more than one of those shapes, has no type and is left out. The result is a map from name to type, `%{}` for an empty table or tuple rows. It is a suggestion for a tool to pre-fill a design's `types`, never something the layer reads at render.

### 6.4 Functions

| Function | Contract |
|---|---|
| `Visualize.Data.Table.rows/1` | The row list of any source in 6.1; a list of rows is returned as-is. |
| `Visualize.Data.Table.get/2` | The named column of a map row by either spelling of the name (6.2); `nil` when absent. |
| `Visualize.Data.Table.accessor/1` | `fn row -> get(row, name) end`; a function is returned unchanged. |
| `Visualize.Data.Table.time_columns/1` | The names whose whole column is temporal (6.3). |
| `Visualize.Data.Table.column_types/1` | Every named column's type — `:time`, `:number`, `:category`, `:text` — read whole; a mixed or empty column is left out (6.3). |
| `Visualize.Data.Table.temporal?/1` | Whether a value is a `DateTime`, `Date`, `NaiveDateTime` or ISO 8601 string. |

## 7. Theme

`Visualize.Theme` names the colours, font and sizes a chart draws with, so that no axis, mark or component carries a colour literal and a consumer restyles every chart from one place — a theme struct in Elixir, or CSS custom properties in a stylesheet (D-55). Ggity's `Theme` and Tucan's themes are the precedent; the CSS half is this library's own, because its output lives in a page.

### 7.1 Struct and slots

`%Visualize.Theme{name, series, axis, grid, text, background, surface, ramps, roles, font_family, font_size, label_size, title_size}`. `name` is an atom naming the theme (`:default`, `:dark`, `:colour_safe`, `:print`, or the consumer's own); `series` is a non-empty list of colour strings; `axis`, `grid`, `text`, `background` and `surface` are colour strings; `ramps` maps each of the four ramp names of 7.5 to its list of anchor colour strings; `roles` maps `:info` and `:neutral` to a colour string each (7.5); `font_family` is a CSS font-family string; the three sizes are numbers in user units (pixels). Every field is plain data — strings, numbers, atoms, lists and maps — so a theme can be stored and compared as a value. Its stored form — a versioned document read back through the same gates as a design — is `Visualize.Chart.Theme` (spec/14 §9.3, D-139).

A *slot* names one value of a theme:

| Slot | Field | Used for |
|---|---|---|
| `:series_1` … `:series_n`, or `{:series, i}` | `series` | the i-th categorical colour; `{:series, i}` cycles, so on a ten-colour theme `{:series, 11}` is `:series_1`, and `i` is any positive integer |
| `:axis` | `axis` | domain lines and tick lines |
| `:grid` | `grid` | grid lines, tree links, and any mark that sits behind the data |
| `:text` | `text` | tick labels, axis titles and any label beside a mark |
| `:background` | `background` | the colour the chart is drawn on: separators between marks, and — with `text` — one of the two inks a label drawn over a mark chooses between (7.3) |
| `:surface` | `surface` | the plane a chart's data is laid on, between the background and the grid: a map's ocean, and any field that is neither the page nor a data colour and has the grid drawn over it (#422) |
| `:good`, `:warning`, `:bad` | `ramps.status` | the **status roles**: the `status` ramp at 0, 0.5 and 1 (7.5) — success, caution and failure |
| `:info`, `:neutral` | `roles` | the remaining roles: something to note that is neither good nor bad, and a state with no judgement (7.5) |
| `:font_family` | `font_family` | every text |
| `:font_size` | `font_size` | tick labels |
| `:label_size` | `label_size` | mark labels and axis titles |
| `:title_size` | `title_size` | chart titles |

`slots/1` lists a theme's slots in that order, `:series_1` to `:series_n` first. `series_slot/2` is the `:series_k` atom that `{:series, i}` cycles to. A slot that is none of these, or `:series_k` with `k > n` or `k < 1`, raises `ArgumentError` in every function that takes a slot.

Beside the slots, a **ramp position** `{:ramp, name, t}` names the colour at `t` (a number in `0..1`) along one of the theme's ramps (7.5). It is a colour wherever a slot is one, through the same `resolve/3`, but it is not a slot: a ramp is continuous, so there is no list of its positions to name.

### 7.2 Built-in themes

| Field | `default/0` | `dark/0` |
|---|---|---|
| `name` | `:default` | `:dark` |
| `series` | `#3b6fa8 #d9730d #c8373b #2f8f86 #3f8a37 #a8891a #8f5f99 #c9527f #8a6a4f #6f7480` | `#7fb3e6 #f7a35c #f47c7c #6fd3c8 #86d67c #f2d15b #c99bd6 #ffb3c1 #cfa98b #b7bcc6` |
| `axis` | `#666666` | `#a0a4ab` |
| `grid` | `#e0e0e0` | `#33373f` |
| `text` | `#333333` | `#e6e6e6` |
| `background` | `#ffffff` | `#1b1e24` |
| `surface` | `#eef2f6` | `#23272f` |
| `ramps.status` | `#4ca34b #bd7407 #c23238` | `#4f924c #db8e1c #ff8f8a` |
| `ramps.thermal` | `#0e68ad #e8e8e8 #c02e31` | `#7fb3e6 #3a3f48 #f47c7c` |
| `ramps.diverging` | `#b35806 #ededed #62448e` | `#f7a35c #3a3f48 #c1acee` |
| `ramps.sequential` | `#e9f2fc #5e95d3 #004580` | `#273b4f #457cb1 #aad1f9` |
| `roles.info` | `#3b6fa8` | `#7fb3e6` |
| `roles.neutral` | `#6f7480` | `#b7bcc6` |
| `font_family` | `sans-serif` | `sans-serif` |
| `font_size` | `10` | `10` |
| `label_size` | `12` | `12` |
| `title_size` | `16` | `16` |

Both palettes are ten hues in the order of d3's `category10` — blue, orange, red, teal, green, yellow, purple, pink, brown, grey — each adjusted until it holds at least 3:1 (`Visualize.Color.contrast/2`, §1.5) against its own background; `text` holds at least 4.5:1 and `axis` at least 3:1. Neither palette is a d3 scheme, because every d3 categorical scheme has a colour under 2.1:1 on white (`category10`'s olive is 2.0:1), and a theme that promises contrast cannot ship one unchanged. 7.4 states the floors.

The ramps of both palettes were chosen in CIE LCh to meet the contracts of 7.5 with room: on the light theme the status roles step down in lightness from 60 to 56 to 45 L*, each at 3:1 or better on white, and on the dark theme up from 55 to 66 to 72 L*, so the role that must be noticed, `:bad`, is the one furthest from the page on both.

**The colour-vision-safe theme.** `colour_safe/0` is `default/0` with the name `:colour_safe` and one ramp changed: `status` runs **blue → orange → red**, `#5996d6 #cd6012 #b92931`, in place of green → amber → red. Red against green is the distinction the commonest colour-vision deficiencies lose (about one man in twelve), and blue against orange survives all three of them; the lightness still falls by 6 L* or more at each step (60, 54, 42), each at 3:1 or better on white, so a reader who sees no hue at all still reads the order. Its other ramps are the default's — blue against red (`thermal`) and orange against purple (`diverging`) already survive — and so is its categorical `series`: a palette that is both colour-vision-safe and holds 3:1 on white (7.4) has too few hues to be a ten-colour palette, and the series promise *distinct*, never a meaning. Safety is a whole theme, chosen once, not a switch on one ramp, so every role and ramp position a design names follows it with no change to the design.

**The print theme.** `print/0` is paper (spec/15 §12.4, D-150): `default/0` with the name `:print`, a white `background` and a white `surface` (`#ffffff`), so a printer lays no ink under the data, near-black `text` (`#111111`) and `axis` (`#333333`), a `grid` of `#c8c8c8`, dark enough to survive a photocopy, and the colour-safe theme's `status` ramp. A printed page is read in whatever light and by whatever eyes it reaches, often in greyscale, where the status ramp's falling lightness and each role's glyph carry the order without hue. Its series and its other ramps and roles are the default's, so it passes every contract of 7.5.

`surface` is a step off the background towards the grid — a cool grey on the light theme, a step above `#1b1e24` on the dark — so a field reads as a plane under the data without becoming a data colour. `new/1` is `default/0` with the given keyword fields replaced, so a host theme that names no `surface` takes the light one, as it takes every other field it leaves out; `merge/2` replaces the fields of any theme. `ramps` and `roles` are merged key by key rather than replaced, so `new(ramps: %{status: […]})` keeps the default's other three ramps and `merge(dark(), roles: %{info: …})` keeps the dark `neutral`. An unknown field raises `KeyError`; an empty `series` raises `ArgumentError`; a ramp or role that breaks its contract raises `ArgumentError` (7.5). `builtin/1` is the built-in theme of a name — `:default`, `:dark`, `:colour_safe` or `:print` — or `nil`, and is what a design's `theme: name` resolves through (spec/14 §2.5).

### 7.3 Resolution

`resolve(theme, slot, mode)` is the one door through which anything reads a theme, and the mode is what the render target needs:

- `:literal` — the slot's value as stored: a colour or font string, or a number for a size. A canvas colour is a literal, so every canvas backend resolves this way.
- `:css` — a CSS custom-property reference with the literal as its fallback: `var(--vis-axis, #666666)`, `var(--vis-series-3, #c8373b)`, `var(--vis-font-size, 10px)` (a size gains `px`). What the SVG output carries.

A role is a slot like any other: `:warning` resolves to `var(--vis-warning, #bd7407)` and `stylesheet/1` declares it, so a stylesheet switches the roles with the rest of the theme. **A ramp position** `{:ramp, name, t}` resolves to its colour (7.5) as a **literal in both modes**, as the contrast ink does: CSS has no custom property for each of a continuum of positions. The positions the status roles stand at are the exception — `{:ramp, :status, 0}`, `0.5` and `1` resolve exactly as `:good`, `:warning` and `:bad` do, in both modes — so a role and its position never disagree, not even under a stylesheet. A `t` outside `0..1` is clamped to it; a `t` that is not a number, or a ramp name not of 7.5, raises `ArgumentError`.

`css_name/1` is the property name of a slot atom: `--vis-` and the slot with `_` as `-` (`:series_1` → `--vis-series-1`, `:font_family` → `--vis-font-family`, `:good` → `--vis-good`). `mode/1` maps a backend — a module, `:svg`, `:canvas` or `nil`, resolved by `Visualize.Backend.resolve/1` (spec/02 §3.2) — to the mode: `Visualize.Backend.SVG` is `:css`, every other backend `:literal`. `Visualize.Axis.render/2` applies it (spec/05 §1.6) and the style grammar of the declarative layer resolves through the same call.

The reference carries its fallback rather than the root declaring the property (D-55). A declaration on the `<svg>` — inline or in a `<style>` — would beat every ancestor rule in the cascade, so a consumer could not switch a theme from a class without `!important`; with the fallback form a chart rendered outside any stylesheet (a standalone `.svg`, an `<img>`) still draws in its theme, and a rule on any ancestor, `.night { --vis-axis: #a0a4ab }`, overrides it. `stylesheet/1` writes that rule for a whole theme — `.vis-theme-<name> {` then one `  --vis-<slot>: <value>;` line per slot of `slots/1`, sizes with `px`, then `}` — so a consumer that includes `stylesheet(dark())` in its CSS switches every chart under an element with `class="vis-theme-dark"` without touching Elixir.

**The contrast ink** (#486, D-123). `ink(theme, under)` is the colour a text drawn on `under` should take: the theme's `text` or its `background`, whichever has the higher contrast ratio against `under` by `Visualize.Color.contrast/2` — `text` on a tie — always as the slot's **literal**, never a reference. When the higher of the two is under 4.5:1 (WCAG AA for text), it is `#000000` or `#ffffff` instead, whichever contrasts more, and one of those two always holds 4.58:1 or better against any colour, so the ink always meets AA against the colour it is chosen for. `under` is a colour string `Visualize.Color.parse/1` reads, a `%Visualize.Color{}`, or `nil` for "nothing under the text" — the theme's own `background` — and a string it cannot parse is `nil`; a slot whose own value does not parse is skipped. It is a literal because the choice is made between literals: a `var(--vis-text, …)` that a stylesheet re-pointed would undo it. The style grammar's `:contrast` value resolves through it (spec/14 §3.2, §5.5).

### 7.4 Contrast


A theme MUST hold, by `Visualize.Color.contrast/2` against its own `background`: `text` at least 4.5:1 (WCAG AA for text), `axis` at least 3:1 (WCAG non-text contrast), every `series` colour at least 3:1, and `grid` at least 1.2:1 — visible, and faint on purpose. `surface` MUST differ from `grid`: the grid is drawn over the surface (a map's graticule over its ocean), and a surface equal to it would swallow every line (#422). Both built-in themes do; a theme from `new/1` is not checked, since a house palette is the consumer's choice. Across the colour schemes of `Visualize.Scale.Color.schemes/0`, every colour parses with `Visualize.Color.parse/1` and every scheme has at least one colour at 3:1 or better against the dark background and at 2.5:1 or better against the light one (`set2`, a pastel scheme, tops out at 2.6:1 on white), so any scheme has a usable colour on either theme; a scheme's lightest colours vanish on the light theme (`blues` opens at 1.04:1 on white) and its darkest on the dark (`blues` closes at 1.8:1 on `#1b1e24`), which is why the built-in themes carry their own palettes (7.2). `test/visualize/theme_contrast_test.exs` holds both themes and every scheme to this.

### 7.5 Ramps and roles

**Implemented** (#533, D-135). A palette position promises *distinct*, never a meaning: `:series_3` is red on both built-in themes, but nothing makes it so on a host's, and a status chart coloured success, warning and failure through series slots can come out orange, grey and light blue. Some colours carry meaning a reader brings with them — the stop-light, cold blue and hot red, below and above a target — so a theme carries that meaning as **ramps**, and the library, not the theme's author, fixes what each one means.

**Ramps.** A ramp is a list of two or more anchor colours, evenly spaced along `0..1`, and the colour at `t` is interpolated between the two anchors about it in **CIE Lab** (`Visualize.Color.interpolate_lab/3`), so any number of ordered levels fits and a theme never runs out of positions. A position that falls on an anchor is that anchor as written. Four ramps are standard, each with its **meaning contract**:

| Ramp | Meaning | Contract |
|---|---|---|
| `status` | good → caution → bad, the stop-light | hue order: the colour at 0 is green or blue, at 0.5 amber, at 1 red, and the hue of every chromatic anchor falls monotonically from the first to the last; lightness monotonic |
| `thermal` | cold → neutral → hot | the colour at 0 is blue, at 0.5 neutral, at 1 red |
| `diverging` | below → at → above a midpoint | the colours at 0 and 1 are chromatic and at least 60° of hue apart; the colour at 0.5 is neutral |
| `sequential` | less → more, one quantity | one hue family; lightness monotonic |

Monotonic means either way: the contract fixes that lightness carries the order, and leaves which way to the theme. The built-in themes run `status` and `sequential` **away from their background** — light → dark on the light themes, dark → light on the dark one — so the low end recedes and the high end, and the role that must be noticed, `:bad`, stands out; a host theme should do the same, and `test/visualize/theme_ramps_test.exs` holds the built-ins to it, but it is not a contract, because a host that changes only its `background` keeps the default's ramps and must still build. A theme tunes a ramp's tones — dark mode, print, a brand — but cannot reorder its hues or its lightness, because a design that colours by meaning has to read the same on every theme.

**The contracts' terms**, in CIE LCh (`Visualize.Color.to_hcl/1`) against the D50 white point, and their tolerances:

- **Hue regions** are arcs of LCh hue: **red** below 45° or from 345°, **amber** 45° to 100° (orange through gold), **green** 100° to 200° (yellow-green through teal), **blue** 200° to 315° (cyan-blue through violet-blue). Measured: pure sRGB red is 41°, orange 71°, yellow 100°, green 134°, cyan 197°, blue 301°. A status's falling hue is read with red's arc taken below zero, so green (≈ 135°) → amber (≈ 68°) → red (≈ 30°) and blue (≈ 262°) → orange (≈ 55°) → red both fall.
- **Chromatic** is a chroma of at least **20** C*: below that a hue is a tint a reader cannot name, and a hue contract on it would be noise. **Neutral** is a chroma of at most **10** C*: a light grey reads as no hue at that, and the built-in midpoints are 0.0 to 6.3.
- **Monotonic lightness** is every step between consecutive anchors moving the same way by at least **3 L***. Interpolation in Lab is linear between anchors, so lightness along the whole ramp is monotonic exactly when it is across the anchors. One L* is about one just-noticeable difference under ideal viewing; three makes the order visible on a screen, not only on a meter. A ramp whose lightness is monotonic is the one a reader who sees no hue can still read in order, which is why the contract is on lightness as well as hue.
- **One hue family** is every anchor of at least **10** C* lying within a **45°** arc of hue: the tightest round arc that admits every ColorBrewer single-hue scheme of `Visualize.Scale.Color` (`blues`, the widest, spans 42.9°; `reds` 14.0°) and refuses a multi-hue one (`viridis` spans 226°). An anchor paler than that is a near-white or near-black end whose hue is unstable and is not held to the arc. A multi-hue sequential scheme is still a scale's to use — `range: :viridis` (spec/14 §4.3) — but it is not a theme's `sequential` ramp, whose meaning is one quantity growing.

**Roles** are the meaning vocabulary: `:good` = `status(0)`, `:warning` = `status(0.5)`, `:bad` = `status(1)`, plus `:info` and `:neutral`, the names design systems give their semantic tokens (Material, Bootstrap, Carbon, Primer: success, warning, danger, info, neutral). The three status roles are **fixed points on the `status` ramp**, not colours of their own, so within a theme a role and its ramp position cannot disagree; a theme sets them by setting `status`. `:info` and `:neutral` are the theme's `roles` and have contracts too: `:info` is a chromatic blue, `:neutral` is neutral. A role names a meaning, never a colour, which is what lets data name it — a feed's state `"down"` can say `:bad`, and every theme renders `:bad` as its own red.

**Contracts are checked when a theme is constructed.** `new/1` and `merge/2` — and so an inline theme in a design (spec/14 §2.5) — check every ramp and role and raise `ArgumentError` naming the theme, the ramp or role, and the term it breaks: `theme :house: ramp :status breaks its contract: lightness must change one way along the ramp, by at least 3 L* a step (its ends say it falls); anchor 2 "#e0a030" (L* 70.8) moves 10.7 L* the wrong way from anchor 1 "#4ca34b" (L* 60.2)`. A ramp name not of the four, a role key not `:info` or `:neutral` — `:good`, `:warning` and `:bad` included, with a message saying to set `status` — a ramp of fewer than two anchors, and an anchor `Visualize.Color.parse/1` cannot read are refused the same way. `check/1` is the same check returning `{:error, subject, message}`, `subject` `{:ramp, name}` or `{:role, name}`, for a caller that reports rather than raises — the validator (spec/14 §10.1). `violations/1` runs it on each ramp and role alone and lists every one that breaks, for a caller that shows each fault where it is — the theme editor (spec/14 §20.4). The built-in themes hold every contract, and `test/visualize/theme_ramps_test.exs` holds them to it. A struct written literally, `%Visualize.Theme{…}`, is not checked: it is the escape hatch, as the contrast floors of 7.4 are not checked on a host's theme.

**Fallback.** A theme that lacks a ramp or a role — a struct whose `ramps` or `roles` map leaves a key out — takes the **default theme's**, never a series colour: a series colour carries no meaning, so falling back to one would break the very promise the ramp exists to keep.

**Precedence.** Where a colour comes from, highest first: a **literal** the design writes, or the **design's colour scale** (`range: [...]`, `range: {:ramp, name}`, spec/14 §4.3) — both deliberate choices; then the **theme's** rendering of a role or a ramp position the design names; then the theme's default. A feed's schema, when it comes (#531), sits between the last two: it names meanings, and the theme renders them.

**Cues** (#560, D-142). Every role also carries a glyph and a dash, `cue/1`, which the library fixes as it fixes the hue order — `:good` a `:circle` and a solid stroke, `:warning` a `:triangle` and `"6 3"`, `:bad` a `:cross` and `"2 3"`, `:info` a `:square` and `"8 3 2 3"`, `:neutral` a `:diamond` and `"1 4"` — so a status reads without its hue ([14-declarative-chart](14-declarative-chart.md) §21.7).

### 7.6 Functions

| Function | Contract |
|---|---|
| `Visualize.Theme.default/0` | The light theme of 7.2. |
| `Visualize.Theme.dark/0` | The dark theme of 7.2. |
| `Visualize.Theme.colour_safe/0` | The colour-vision-safe variant of the light theme of 7.2. |
| `Visualize.Theme.print/0` | The print theme of 7.2: white paper, dark ink, the colour-safe status ramp (spec/15 §12.4). |
| `Visualize.Theme.builtin/1` | `builtin(name)`: the built-in theme of `:default`, `:dark`, `:colour_safe` or `:print`, else `nil` (7.2). |
| `Visualize.Theme.new/1` | `default/0` with the given keyword fields replaced, `ramps` and `roles` merged; contracts checked (7.2, 7.5). |
| `Visualize.Theme.merge/2` | The theme with the given keyword fields replaced, `ramps` and `roles` merged; contracts checked (7.2, 7.5). |
| `Visualize.Theme.check/1` | `:ok`, or `{:error, subject, message}` for the first ramp or role that breaks its contract (7.5). |
| `Visualize.Theme.violations/1` | Every ramp and role that breaks its contract, `{subject, message}` each, in the order `check/1` reads them: the contract run on each alone, so a theme editor names every fault and not only the first (7.5, spec/14 §20.4). |
| `Visualize.Theme.ramp/3` | `ramp(theme, name, t)`: the literal colour at `t` along the named ramp, Lab-interpolated, `t` clamped to `0..1`; the default theme's ramp when the theme lacks it (7.5). |
| `Visualize.Theme.ramp_names/0` | `[:status, :thermal, :diverging, :sequential]` (7.5). |
| `Visualize.Theme.role_names/0` | `[:good, :warning, :bad, :info, :neutral]` (7.5). |
| `Visualize.Theme.cue/1` | `cue(role)`: `%{glyph: symbol_type, dash: String.t() \| nil}`, the role's glyph and dash (`nil` solid) of 7.5; raises `ArgumentError` for anything but a role. |
| `Visualize.Theme.slots/1` | The theme's slot names in the order of 7.1. |
| `Visualize.Theme.colour_slots/1` | The theme's colour slots alone — the series, then axis, grid, text, background and surface, then the five roles — for a control that offers a colour as a slot (spec/14 §19.10). |
| `Visualize.Theme.series_slot/2` | `series_slot(theme, i)`: the `:series_k` atom the positive index `i` cycles to (7.1). |
| `Visualize.Theme.resolve/3` | The slot's value as a literal or as a CSS reference with the literal fallback; a ramp position `{:ramp, name, t}` as its literal, a status role's position as the role (7.3). |
| `Visualize.Theme.css_name/1` | The custom-property name of a slot atom (7.3). |
| `Visualize.Theme.mode/1` | `:css` for the SVG backend, `:literal` for any other (7.3). |
| `Visualize.Theme.ink/2` | `ink(theme, under)`: the literal of `text` or `background`, whichever contrasts more with `under`, else black or white when neither reaches 4.5:1 (7.3). |
| `Visualize.Theme.stylesheet/1` | The `.vis-theme-<name>` rule declaring every slot (7.3). |


## 8. Signals

**Implemented** (#244). A signal is a *generated source*: a description from which `Visualize.Signals` yields rows, pure and deterministic for a tick, so a chart under design has feeds that move without a host supplying any. A deployed design still binds to the host's pool (spec/14 §7.3) under the same names; signals are the builder's stand-in for it.

### 8.1 A signal

| Key | Type | Default | Notes |
|---|---|---|---|
| `kind` | `:sine \| :square \| :random \| :discrete` | required | the wave every value column follows; `:discrete` is a counter — non-negative integers stepping up by one per tick, wrapping past `max` |
| `fields` | `[atom()]` | required | the columns: the **first is the clock** and carries the tick number, a `:number` (spec/14 §2.3, #369) — a tick is a count, not an instant; every other is a value column |
| `window` | `pos_integer()` | `24` | the rows a tick yields — the last `window` ticks, ending at the tick |
| `period` | `number()` | `12` | ticks per cycle of a `:sine` or a `:square` |
| `min`, `max` | `number()` | `0`, `100` | the value range: a sine swings between them, a square alternates them, a random draws within them, a discrete counts from `min` to `max` |
| `seed` | `integer()` | `0` | for `:random`, so a chart replays the same feed |

Value columns differ from each other: the *n*-th value column (0-based) of a sine or a square is shifted by `n / count` of a cycle, so two columns are never the same line; a random column draws its own stream from `seed` and the column's index; a discrete column starts `n` higher.

### 8.2 The rows

`rows(signal, tick)` yields `window` rows, one per tick from `tick − window + 1` to `tick` in order — a tick below `0` yields no row, so the window fills over its first ticks — each a map of the signal's fields: the time column the tick, and each value column its kind's value at that tick:

- `:sine` — `min + (max − min) · (1 + sin(2π (t / period + phase))) / 2`, so at tick `0` the first column stands at the midpoint;
- `:square` — `max` for the first half of a cycle, `min` for the second, the column's phase applied;
- `:random` — a value in `[min, max)` from `:rand.uniform_real/0` under a seed derived from `seed`, the column's index and the tick, so the same tick always draws the same value;
- `:discrete` — `min + rem(t + n, max − min + 1)`.

The window **slides**: tick 25 over a window of 24 yields ticks 2..25, and the next tick drops 2 and adds 26. `pool(signals, tick)` yields a pool, name to rows, for a map of named signals, ready for `Visualize.Chart.apply/2`. `rows(signal, from, to)` yields one row per tick from `max(from, 0)` to `to`, whatever the signal's `window` — no row when `to` is below that — which is how `Visualize.Feed.Signals` serves a window of ticks (§11.6).

### 8.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Signals.kinds/0` | The four kinds, in the order of 8.1. |
| `Visualize.Signals.new/2` | `new(kind, fields)` — a signal of the kind over the fields with 8.1's defaults; `new/3` takes the remaining keys as options. |
| `Visualize.Signals.new/3` | As `new/2` with options. |
| `Visualize.Signals.rows/2` | `rows(signal, tick)`: the window of rows ending at the tick (8.2). |
| `Visualize.Signals.rows/3` | `rows(signal, from, to)`: one row per tick from `max(from, 0)` to `to` (8.2). |
| `Visualize.Signals.pool/2` | `pool(signals, tick)`: `rows/2` of every signal of a map, under its name. |

## 9. FFT

### 9.1 The transform

`Visualize.Data.FFT` (#375) is the fast Fourier transform in pure Elixir: a radix-2 Cooley–Tukey decimation in time over lists, `O(N log N)`, with no native code. `fft/1` takes a sequence whose length is a power of two — numbers read as real, `{re, im}` pairs as complex — and returns the `N` complex terms `X_k = Σ x_n e^{−2πi kn/N}` as `{re, im}` pairs; any other length raises `ArgumentError`. `magnitudes/1` is `sqrt(re² + im²)` of every term. Parseval holds: the sum of the squared magnitudes over `N` equals the sum of the squared samples, to floating precision.

### 9.2 Windows and the spectrum

`window/2` tapers a sequence by `:hann` (`0.5 − 0.5 cos(2πi/(N−1))`), `:hamming` (`0.54 − 0.46 cos(2πi/(N−1))`) or `:none` — a sequence shorter than four is not tapered, the Hann of two points being all zeros; `windows/0` lists them, `:hann` first. `spectrum/3` is the reading a chart draws: `spectrum(values, every, opts)` takes the newest `samples` values — the option, a power of two, else the largest power of two not above the count — subtracts their mean when `detrend: true` (#376; an offset otherwise leaks from the DC line into its neighbours under a window), tapers them, transforms them and returns `samples / 2` lines `%{frequency, magnitude, phase}`: `frequency` is `k / (samples · every)` in hertz for `every` seconds between samples; `magnitude` the one-sided amplitude `|X_k| · 2 / (samples · gain)` with the window's mean gain divided out, so a sine of amplitude `A` reads `A` at its frequency whatever the taper, the DC line not doubled; `phase` the argument of `X_k`. Fewer than two values, or fewer than `samples`, yield `[]`. A 4096-point spectrum costs single-digit milliseconds, a 1024-point one about two. The test suite holds the cost's growth by count, not by clock (#462): four times the samples is under six times the work in reductions, as `n log n` gives and a quadratic transform's sixteen does not; the millisecond figures are a `:benchmark` test, stated rather than gated ([12-testing-and-conformance](12-testing-and-conformance.md) §6).

### 9.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Data.FFT.fft/1` | The `N` complex terms of a sequence whose length is a power of two (9.1). |
| `Visualize.Data.FFT.magnitudes/1` | `sqrt(re² + im²)` of every term. |
| `Visualize.Data.FFT.window/2` | `window(values, kind)`: the sequence tapered by `:hann`, `:hamming` or `:none` (9.2). |
| `Visualize.Data.FFT.windows/0` | The three window kinds, `:hann` first. |
| `Visualize.Data.FFT.spectrum/2` | As `spectrum/3` with no options. |
| `Visualize.Data.FFT.spectrum/3` | `spectrum(values, every, opts)`: the one-sided amplitude spectrum of the newest power of two of values sampled every `every` seconds (9.2). |

## 10. Feeds: schemas and deliveries

A feed is anything that answers a chart's source slot with rows (spec/14 §7.2). What the numbers *are* — a unit, a label, the order of a set of states, what a state means — is a fact about the feed, whoever draws it, and it is not repeated with every row: a feed has a **schema**, identified by a **version**, and each of its answers, a **delivery**, names the version it was produced under and never carries the schema itself (#535, D-136). This section is the data layer of that: the schema value, how its version is computed, the cache that holds schemas by version, and the delivery. How a design states what it needs from a schema and reads it is spec/14 §7.4; how a feed is asked for a schema and its rows is the feed behaviour's (§11, #537).

### 10.1 The schema

`Visualize.Data.Schema` is a feed's schema: `%Visualize.Data.Schema{fields, version}`, where `fields` maps a field name — an atom or a string, as the feed's rows spell it — to its **description**, a map of the keys below, and `version` is the content hash of 10.2. `Visualize.Data.Schema.new/1` is the only constructor: it takes the map of descriptions, checks it, and returns `{:ok, schema}` or `{:error, errors}` with every fault found, each `{path, reason}` in the shape of spec/14 §10.1 — the path from the schema to the value, `[:latency, :unit]` — ordered by path. `Visualize.Data.Schema.new!/1` returns the schema or raises `ArgumentError` with every fault formatted by `Visualize.Data.Schema.format_error/1`.

A description says what a field **means**, never how it is drawn:

| Key | Value | For a field of type | Meaning |
|---|---|---|---|
| `type` | `:time`, `:number`, `:category` or `:text` | required, every field | what the column is, spec/14 §2.3's four. A `:time` field holds **instants** — `DateTime`, `NaiveDateTime` or `Date` values, or ISO 8601 strings, what a time scale takes (spec/14 §4.3) — and never numbers: a count of ticks, a sequence number or an offset is `:number` (D-154) |
| `unit` | a UCUM code | `:number` | the unit the values are in: a [UCUM](https://ucum.org) code `Visualize.Unit.parse/1` reads (`"s"`, `"ms"`, `"By"`, `"%"`, `"Cel"`, `"{request}/s"`; spec/05 §4.1) |
| `quantity` | one of `Visualize.Quantity.all/0` | `:number` | what the unit measures: `:duration`, `:information`, `:temperature`, … (spec/05 §4.2) |
| `label` | a string | every type | the field's name for a person: `"Request time"` |
| `order` | a non-empty list of distinct strings, atoms or numbers | `:category` | the states in their order, first to last |
| `status` | a map from a state to a role, an atom | `:category` | what each state means: `%{"ok" => :good, "warn" => :warning, "fail" => :bad}` |
| `polarity` | `:higher_is_better`, `:lower_is_better` or `:neutral` | `:number` | which way the values are better; `:neutral` reads the distance from `target` either way |
| `target` | a number | `:number` | the value the field is measured against |
| `continuity` | a positive number | every type | the longest gap between two readings that is still one run: beyond it a line breaks. It is measured along the window field (below): seconds for a `:time` one, the field's own units for a `:number` one (D-154) |
| `window` | a boolean | `:time` or `:number` | `true`: the field a window is over — the feed's own clock, its rows ordered and windowed by it (§11.2, D-154). At most one field says `true`; `false` says a field is not the window field, though it is the schema's only `:time` field. A `:time` window field holds `DateTime`, `NaiveDateTime` or `Date` values, which a window compares, not ISO 8601 strings |
| `metric_kind` | `:gauge`, `:counter` or `:rate` | `:number` | how the values were measured, which refines what the quantity's additivity allows (spec/05 §4.2, D-155): a `:gauge` is a level sampled at instants and never sums over time; a `:counter` holds the increments of an accumulating count, which sum over time when the quantity sums at all; a `:rate` is per unit time and integrates rather than sums. Absent, the quantity's defaults hold |
| `bounds` | `[min, max]`, each a number or `nil`, `min` below `max` when both are given | `:number` | where the field's values physically lie, overriding its quantity's bounds (spec/05 §4.2): a **display hint** an axis may anchor at, never validation — a value outside them is not refused |
| `identity` | a boolean | `:category`, `:text` or `:number` | `true`: the field's value **names a thing**, and every row with that value is about the same thing — a service, a car, a host's interface (below, D-167). Compared by equality. Several fields may say `true`, together one composite identity |

`Visualize.Data.Schema.attributes/0` is the thirteen keys in that order, the vocabulary spec/14 §7.4's contract names, so a slot's `requires` can require `identity` of a field as it requires a `unit`.

**Identity** (#622, #625, D-167). Which rows are about the same thing is a fact about the feed, like its units, so the feed declares it: `identity: true` on each field whose value names the entity a row is about. Nothing else in visualize decides it — not a mark's `series`, not the order of the schema's `:category` fields — since a guess silently merges two entities that share a colour or splits one whose label changed.

- **The fields.** `identity: true` is allowed on a `:category`, a `:text` or a `:number` field — a service's name, a free-form job id, a numeric device id — and never on a `:time` field, which says *when*, not *what* (`{:invalid_for, :time}`). It is a boolean (`{:type, :boolean}`), and `false` is the same as absent: `new/1` drops `identity: false` from the description it keeps, so the two spellings are one schema of one version, and a field that has the attribute declares identity. A schema with no field saying `true` declares no identity, and everything that reads one falls back as it did before (spec/15 §13.2).
- **Composite.** Several fields may say `true`, and the identity is all of them together: `host` and `iface` name one interface, and `%{host: "mx1", iface: "eth0"}` is a different thing from `%{host: "mx1", iface: "eth1"}`. `Visualize.Data.Schema.identity/1` is the declared fields, as the schema spells them, ordered by name as a string: `[]` for none.
- **The identity value.** `Visualize.Data.Schema.identity/2` gives a row's identity under a schema: **bare** for one field — `"frog-1"` — and **a map** from field to value for several — `%{host: "mx1", iface: "eth0"}`, keyed as the schema spells the fields. Each field is read by either spelling of its name (6.2). It is `nil` when the schema declares no identity, or when the row has no value (`nil` or absent) for one of the declared fields: a row that does not say what it is about names nothing. Two rows are about the same thing exactly when their identity values are equal and not `nil`, which is what a reduction to each entity's latest row (§11, #626) groups by.
- **Scope.** An identity is scoped to its feed. The same field name in two feeds names the same entity only where a board says so (`links:`, spec/15 §13.2), or where the names already agree, as a selection reads them today.
- **Stability.** A feed that declares identity gives every row a value for each declared field, which the conformance kit checks of every delivery (§12.3). A later schema version that declares other identity fields is a different account of what the rows are about, which `compatibility/2` reports (below).

**The window field** is the field a feed's windows are over (§11.2): the one field described `window: true`, else the schema's one `:time` field when it has exactly one and does not describe it `window: false`; otherwise the schema has none. `Visualize.Feed.window_field/1` answers it. So a feed whose rows are stamped with instants and have one `:time` field says nothing, and a feed whose clock is a number — a signal's tick, a sequence number — says `window: true` on it (D-154). The two meanings `:time` once had, an instant and a tick, are two types now: a time scale draws the first and a numeric scale the second, and the window works over either.

A design draws the meanings through its scales (spec/14 §4.3, #565, D-143): `status` is an `:ordinal` colour scale's range as it stands — `range: fact(:events, :severity, :status)`, a map from a state to a role — and `target` and `polarity` are a `:threshold` colour scale's `domain` and `polarity` over `range: {:ramp, :status}`, so a reading on the better side of the target is `:good` and one beyond it `:bad`; `target` is also a `:rule` at `y` (spec/14 §5.2), the target line.

**A measure is checked against the vocabulary** (#595, D-157), as an axis's measure is (spec/14 §4.4), so a misspelt unit or an unknown quantity is refused where the feed describes itself, not found later, or never, when a chart draws it:

- **`unit`** is a non-empty string (else `{:type, :unit}`) that `Visualize.Unit.parse/1` reads (spec/05 §4.1), else `{:unit, code, reason}` with `parse/1`'s reason: `"mss"` is `{:unit, "mss", {:unknown_atom, "mss"}}`. A symbol a person types (`°C`, `KB`) is not a code; a feed reads it with `Visualize.Unit.parse_alias/1` before describing itself.
- **`quantity`** is an atom other than `nil`, `true` and `false` (else `{:type, :name}`) that is one of `Visualize.Quantity.all/0` (spec/05 §4.2), else `{:unknown_quantity, quantity}`.
- **The pair.** A field that gives both, each of them good, is checked through `Visualize.Quantity.resolve/1`: a unit whose dimension is not its quantity's is `{:quantity, quantity, code}` at `[name, :quantity]` — `unit: "By", quantity: :duration` — the reason the validator gives an axis's measure (spec/14 §10.1). A `:ratio` or a `:count` takes any dimensionless unit and a `:currency` a code of one currency alone, as `resolve/1` says. A unit alone, or a quantity alone, needs no pair check: the one implies the other.

Two keys are checked here only as far as this library owns them:

- **`status`**'s roles are the theme's vocabulary (#533: `:good`, `:warning`, `:bad`, `:info`, `:neutral`), whose names are meanings every theme must honour. They are carried here as atoms and not checked against a list, so a role #533 adds needs no change to the schema. When the description also gives `order`, every state `status` names MUST be one of `order`'s.
- **`continuity`** is carried for the cell that draws a feed (#531 §3: gaps follow it); no mark reads it yet.

**No colour.** A schema describes meaning, and colour is the theme's to choose from it (#533, #531's revision of 2026-10-11): a key `color`, `colour`, `colors`, `colours`, `palette`, `fill` or `stroke` in a description is the fault `{:colour_key, key}`, whose line says so and names the keys that carry the meaning instead (`status`, `order`, `polarity`, `quantity`). A literal colour is something only a design writes, as a deliberate choice; data never does.

The faults of `new/1`:

| Reason | Meaning |
|---|---|
| `{:type, :schema}` | at `[]`: the schema is not a map of descriptions |
| `{:type, :name}` | at `[name]`: a field name that is not an atom (other than `nil`, `true`, `false`) or a non-empty string |
| `{:duplicate_field, other}` | at `[name]`: the field is named twice, as an atom and as the string that spells it (`:v` and `"v"`), which are one column (6.2); reported at the later of the two by term order |
| `{:type, :description}` | at `[name]`: the description is not a map |
| `:unknown_key` | at `[name, key]`: a key that is not one of the thirteen |
| `{:colour_key, key}` | at `[name, key]`: a colour, which a schema never names |
| `:required` | at `[name, :type]`: the description gives no `type` |
| `{:enum, allowed}` | at `[name, :type]`, `[name, :polarity]` or `[name, :metric_kind]`: a value not among the allowed |
| `{:unit, code, reason}` | at `[name, :unit]`: a string `Visualize.Unit.parse/1` does not read, with its reason (D-157) |
| `{:unknown_quantity, quantity}` | at `[name, :quantity]`: an atom that is not one of `Visualize.Quantity.all/0` (D-157) |
| `{:quantity, quantity, code}` | at `[name, :quantity]`: the unit does not measure the quantity, by `Visualize.Quantity.resolve/1` (D-157) |
| `{:invalid_for, type}` | at `[name, key]`: a key the field's type does not take — a `unit` on a `:category` field, an `order` on a `:number` one, a `window` on a `:category` or `:text` one, an `identity` on a `:time` one |
| `{:type, expected}` | at `[name, key]`: a value of the wrong shape, `expected` one of `:unit`, `:name`, `:string`, `:order`, `:status`, `:number`, `:positive`, `:boolean`, `:bounds` |
| `{:duplicate_window, other}` | at `[name, :window]`: the field says `window: true` and so does `other`; a feed's windows are over one field. Reported at the later of the two by term order |
| `:duplicate` | at `[name, :order, i]`: a state `order` lists twice |
| `:not_in_order` | at `[name, :status, state]`: a state `status` names that `order` does not list |

`Visualize.Data.Schema.fetch/2` reads a field's description by either spelling of its name (6.2), `{:ok, description}` or `:error`; `Visualize.Data.Schema.fetch/3` reads one attribute of it, `{:ok, value}` or `:error` when the field or the attribute is absent.

**Compatibility** (#605, D-159). Two schemas can describe the same data in different words: a process's live feed and a store's history of one metric spell their fields differently (`:t` and `"t"`), label them from different sources, and the store knows facts the process does not (`polarity`, `bounds`, `metric_kind`). Their versions differ, yet the rows of one can be read as rows of the other. `Visualize.Data.Schema.compatibility(schema, other)` says whether they can: `:ok`, or `{:error, faults}` with every fault, each `{field, reason}`, `field` spelt as `schema` spells it, ordered by the field's name as a string. The rule is **per field of `schema`**; `other`'s extra fields are not faults:

| Reason | Meaning |
|---|---|
| `:missing` | `other` has no field of that name, compared as strings (`:t` ≡ `"t"`, 6.2) |
| `{:type, a, b}` | `other`'s field is of type `b`, where `schema`'s is `a` |
| `{:unit, a, b}` | a `:number` field whose units cannot be converted: `other`'s unit `b` to `schema`'s `a` by `Visualize.Unit.conversion/2` (spec/05 §4.1) — a different dimension, a different currency, or one unit absent (`nil`) facing a present one, whose dimension is unknown. Two absent units are compatible |
| `{:identity, a, b}` | the two schemas declare different identity fields (D-167): `a` is whether `schema` declares `identity: true` on the field and `b` whether `other` does, booleans, an absent `identity` reading `false`. Checked for every field either schema declares as identity, so a field only `other` declares is a fault too, spelt as `other` spells it |

**Identity is compared because rows are grouped by it.** A process's live feed that says a row is about a `host` and a history that says it is about a `host` and an `iface` count different things, and each entity's latest row (§11, #626) over a `Combine` of them would be wrong. That is the one exception to the field-by-field rule: an identity field only `other` declares is a fault, since reading `other`'s rows as `schema`'s would merge the entities `other` tells apart. No other attribute is compared: a label, a quantity a unit already implies, a fact such as `polarity`, `bounds` or `order` is what each feed knows, and reading `other`'s rows as `schema`'s keeps `schema`'s. Compatibility is not symmetric otherwise: `other` may have fields `schema` lacks. `Visualize.Feed.Combine` (§11.5) uses it, and a connector can ask it before combining.

### 10.2 The version: a content hash

A schema's version is a **content hash** of its fields and their descriptions, so an unchanged schema has the same version wherever and whenever it is computed — on another node, under another release of this library or of OTP — and any change of content, a renamed state or a new label, is a new version. It is a 64-character lowercase hexadecimal string, the SHA-256 of a canonical encoding:

- The encoding begins with the line `visualize.schema/1\n`, which names the encoding itself: a change to the rules below is a deliberate change of this line and therefore of every version, never a silent one.
- **A field name is encoded as its string**: `:latency` and `"latency"` are one column (6.2) and give one version, so a feed that names its fields with strings across a wire and one that names them with atoms in process agree.
- **A value is encoded by its own tag, length-prefixed**: an atom as `a<n>:<name>` and a string as `s<n>:<bytes>`, `n` the byte size in decimal — so `:ok` and `"ok"` are different states, as they are different values in a row; an integer as `i<decimal>;`; a float as `f<shortest>;`, the shortest decimal that reads back as the same float (`:erlang.float_to_binary(f, [:short])`), so `1` and `1.0` are different values; a list as `l<n>:` and its elements in order, since order is meaning in `order`.
- **A map is encoded with its entries sorted by the encoding of their keys**, as `m<n>:` and each key's encoding followed by its value's. Nothing depends on a map's iteration order, which the runtime does not promise, nor on term order between different types.
- Nothing is encoded through `:erlang.term_to_binary/2`, whose external format may change between OTP releases (its atom encoding did) and whose `:deterministic` option promises only one release.

The fields map is a map like any other, so the schema is `m<n>:` and its fields by name. The schema `%{v: %{type: :number}}` is therefore the bytes `visualize.schema/1\nm1:s1:vm1:a4:typea6:number`, and its version is `39b0c8eff6adfa6c6c9ada7fb3ee3a308675a1a5869afcd1ef1aca19378d0a81`, which any SHA-256 tool gives for those bytes. `Visualize.Data.Schema.version/1` returns a schema's version, which `new/1` computes once. The test suite pins the version of one schema as a literal string, so a change to the encoding fails a test before it changes a version in the field.

### 10.3 The cache

Schemas are cached by `{feed, version}`: a delivery whose version is already known costs a map lookup and nothing more, and a delivery with a version not seen before makes the holder ask the feed for its schema once (#531 review A). `Visualize.Data.Schema.Cache` is that cache as a **value** — `%Visualize.Data.Schema.Cache{entries}`, a map from `{feed, version}` to schema — not a process and not a table: the thing that owns it (a board's process, #531 §2; for now the caller of `Visualize.Chart.apply/2`, spec/14 §7.3) holds it in its own state and passes it in, and gets the grown cache back. A feed is any term that names one, as the pool of spec/14 §7.2 names a source.

`Visualize.Data.Schema.Cache.new/0` is the empty cache and `new/1` one holding a list of `{feed, schema}` pairs; `put/3` adds a schema for a feed under its own version; `fetch/3` is `{:ok, schema}` or `:error` for a feed and a version. `Visualize.Data.Schema.Cache.resolve/4` takes the cache, a feed, a version and a **describe** function — `(feed -> {:ok, schema} | {:error, reason})`, the pull side of the feed behaviour (#537), or `nil` — and returns:

- `{:ok, schema, cache}`, the cache unchanged, when the version is cached: describe is not called;
- `{:ok, schema, cache}` with the schema added, when describe answers the version asked for: it is called **once**;
- `{:error, {:schema_version, feed, version, got}, cache}` when describe answers a schema of another version `got`: the delivery is older or newer than the feed's present schema and is not described by it. The answer is still cached under its own version, so the next delivery, which names it, costs nothing;
- `{:error, {:describe, feed, reason}, cache}` when describe answers `{:error, reason}`;
- `{:error, {:unknown_schema, feed, version}, cache}` when the version is not cached and there is no describe.

The cache never evicts: a schema is a few hundred bytes and a feed's versions change when its catalog does, so its owner replaces the value when it wants it smaller.

### 10.4 The delivery

`%Visualize.Data.Delivery{}` is one answer of a feed: the rows, and the facts of this answer that are not facts of the data — a handful of terms per delivery, never per row (#531 review C, §1 of the further considerations).

| Field | Value | Default |
|---|---|---|
| `rows` | any source of 6.1 other than a delivery: a row list, a column map, a tensor, a `Table.Reader` struct | required |
| `window` | `[from, to]`, the window actually served, or `nil` | `nil` |
| `resolution` | the spacing of the rows as served — seconds, or a name such as `:minute` — or `nil` | `nil` |
| `capped` | whether the feed stopped short of the window it was asked for | `false` |
| `reduced_by` | `:feed` when the feed reduced the rows to a budget, `:visualize` when this library did, or `nil` | `nil` |
| `schema` | the version (10.2) of the schema the rows were produced under, or `nil` | `nil` |

`Visualize.Data.Delivery.new/2` takes the rows and the other fields as a keyword list, and raises `ArgumentError` for a key that is not a field or a value that is not one of the field's (`window` of other than two, `capped` not a boolean, `reduced_by` other than the three, `schema` not a string, `rows` a delivery). A delivery is **one more source shape**: `Visualize.Data.Table.rows/1` reads it as the rows of the source it carries (6.1), so it goes wherever a source goes, and `Visualize.Data.Delivery.source/1` is that source — any other source returned as it is. `Visualize.Chart.apply/2` binds a delivery as the source it carries, and a compiled chart's `tick/3`, `step/3`, `render/2` and `svg/2` take one per slot as they take any source (spec/14 §7.3, §12.4); what the schema version means to them is spec/14 §7.4 and §12.1.

A delivery is data like a design: a struct with no function in it, which a codec can hold (#531's *a chart is data, not JSON*).

### 10.5 Functions

| Function | Contract |
|---|---|
| `Visualize.Data.Schema.new/1` | `{:ok, schema}` for a map of field descriptions that holds (10.1), else `{:error, errors}` by path. |
| `Visualize.Data.Schema.new!/1` | The schema, or `ArgumentError` listing every fault. |
| `Visualize.Data.Schema.version/1` | The schema's version, the SHA-256 of its canonical encoding as 64 hex digits (10.2). |
| `Visualize.Data.Schema.fetch/2` | A field's description by either spelling of its name, `{:ok, description}` or `:error`. |
| `Visualize.Data.Schema.fetch/3` | One attribute of a field's description, `{:ok, value}` or `:error`. |
| `Visualize.Data.Schema.attributes/0` | The thirteen description keys, `:type` first (10.1). |
| `Visualize.Data.Schema.identity/1` | The fields the schema declares `identity: true`, as it spells them, ordered by name as a string; `[]` for none (10.1). |
| `Visualize.Data.Schema.identity/2` | A row's identity under the schema: the bare value for one identity field, a map for several, `nil` when it declares none or the row lacks a value for one (10.1). |
| `Visualize.Data.Schema.compatibility/2` | `:ok` when another schema's rows read as this one's, else `{:error, [{field, reason}]}`: `:missing`, `{:type, a, b}`, `{:unit, a, b}`, `{:identity, a, b}` (10.1). |
| `Visualize.Data.Schema.format_error/1` | One fault of `new/1` as a line a person reads. |
| `Visualize.Data.Schema.Cache.new/0` | The empty cache. |
| `Visualize.Data.Schema.Cache.new/1` | A cache holding `{feed, schema}` pairs, each under its own version. |
| `Visualize.Data.Schema.Cache.put/3` | The cache with a feed's schema added under its version. |
| `Visualize.Data.Schema.Cache.fetch/3` | `{:ok, schema}` or `:error` for a feed and a version. |
| `Visualize.Data.Schema.Cache.resolve/4` | A feed's schema at a version: cached, or asked of `describe` once and cached (10.3). |
| `Visualize.Data.Delivery.new/1` | `new(rows, [])`: a delivery of the rows and no other fact. |
| `Visualize.Data.Delivery.new/2` | A delivery of the rows with the given facts, checked (10.4). |
| `Visualize.Data.Delivery.source/1` | The source a delivery carries; any other source as it is. |

## 11. Feeds: the behaviour, the monitor and two providers

**Implemented** (#537, D-140). §10 is what a feed's answer *is*: a schema by version, and a delivery. This section is how a feed is asked: `Visualize.Feed`, a behaviour every provider implements; what visualize does itself when a provider does less than it was asked; `Visualize.Feed.Monitor`, the loop that asks the feeds, takes their pushes and hands a chart one delivery per slot per tick; `Visualize.Feed.Combine`, one feed made of several by window (live data and its history in one slot); and two providers that prove the contract — `Visualize.Feed.Signals` (generated, pull) and `Visualize.Feed.Telemetry` (in-process `:telemetry`, push). A board (#531 §1, #540) binds feeds to its cells' slots; it never knows which kind of provider fills one.

### 11.1 The behaviour

A **feed** is a struct whose module implements `Visualize.Feed`. Providers are modules and processes, not data types, so the contract is a behaviour rather than a protocol (#531 review F): a feed value names the provider and whatever it needs to answer — a signal, a collector process and a metric, a URL. `Visualize.Feed.describe/1`, `fetch/3`, `subscribe/2` and `unsubscribe/2` dispatch to the struct's module.

| Callback | Returns | |
|---|---|---|
| `describe(feed)` | `{version, schema, supports}` or `{:error, reason}` | required |
| `fetch(feed, window, budget)` | `{:ok, %Visualize.Data.Delivery{}}` or `{:error, reason}` | required |
| `subscribe(feed, pid)` | `{:ok, ref}` or `{:error, reason}` | optional: a feed whose `supports` names `:push` |
| `unsubscribe(feed, ref)` | `:ok` | optional, with `subscribe/2` |

- **`describe/1`** answers the feed's present schema (§10.1), its version (§10.2, `Visualize.Data.Schema.version/1` of that schema) and `supports`, the list of the capabilities it honours — a subset of `Visualize.Feed.capabilities/0`, `[:window, :budget, :push]`. Every capability is optional: **the minimum feed gives rows**.
- **`fetch/3`** answers the rows for a **window** and a **budget**. A window is `nil` (whatever the feed holds, or its own default span) or `[from, to]`, the bounds values of the feed's window field (§10.1, §11.2) — instants for a `:time` one, numbers for a `:number` one — and either bound `nil` for open; a budget is `nil` or a positive integer, the most rows the cell wants. Both are **requests**: a feed that does not name `:window` or `:budget` in `supports` may ignore them, and visualize finishes the job (§11.2). The delivery names the version it was produced under (`schema`) and the window it actually served (`window`); `capped` is `true` when the feed could not reach back to the window's `from`.
- **`subscribe/2`** asks a push feed to send its updates to `pid` (§11.3) and answers the reference those messages carry; `unsubscribe/2` stops them. A feed that does not push implements neither, and `Visualize.Feed.subscribe/2` on it is `{:error, :no_push}`.
- **Errors are values.** Every callback answers `{:error, reason}` for a feed that cannot answer — a provider that is down, a window it cannot read — and never raises for it; the monitor turns the value into the cell's state (§11.4). A reason is the provider's own term.

`Visualize.Feed.describer/1` turns a map of feeds by name into the `describe` function of §10.3 — `fn name -> {:ok, schema} | {:error, reason} end` — which `Visualize.Data.Schema.Cache.resolve/4` and `Visualize.Chart.apply/2`'s `describe:` take.

### 11.2 Requests, not requirements: visualize finishes the job

A small source works unchanged, and a large one implements the window and the budget so that it does not ship raw points (#531's further considerations, §1). `Visualize.Feed.finish(delivery, schema, opts)` is what visualize does with a delivery a feed did not finish, given the schema it was produced under and the request — `supports:`, `window:`, `budget:`, and `reduce:` (`:lttb`, the default, or `:m4`). It is pure, and a delivery that needs nothing comes back as it is, its source untouched (a tensor stays a tensor).

- **The window field** is the field the feed's windows are over (§10.1, `Visualize.Feed.window_field/1`): the field described `window: true`, else the schema's one `:time` field. A schema with neither has no window field. The window is over the window field's values, which are instants for a `:time` field and numbers for a `:number` one (D-154).
- **A window applies to a window field of its kind.** A window whose bounds are instants applies to a `:time` window field, one whose bounds are numbers to a `:number` one, and a window with no bound to either (`Visualize.Feed.Window.applies?/2`). A request whose window does not apply to a feed's window field is a request for the feed's own span: the monitor asks such a feed with `nil` and does not trim it (§11.4), which is how a board's window of instants meets a feed over ticks (spec/15 §1.5).
- **Trimming.** When the request has a window, `supports` lacks `:window` and the schema has a window field the window applies to, the rows are those whose window field is within the window — both bounds inclusive, a `nil` bound open, a row with no value dropped — and the delivery's `window` becomes the request's, intersected with what the feed said it served. Values compare by `Visualize.Feed.Window.compare/2`: numbers by value, and `DateTime`, `NaiveDateTime` and `Date` each by their own `compare/2`; a window and a column are of one kind. A schema with no window field cannot be trimmed: such a feed honours its window itself or is shown whole.
- **Reducing.** When the request has a budget, `supports` lacks `:budget` and there are more rows than the budget, the rows are reduced by `Visualize.Data.lttb/3` or `m4/3` (§5.2) and `reduced_by` becomes `:visualize`. The reduction keeps the shape of every series: the rows are **grouped** by the values of the schema's `:category` fields (a feed's tags), and within each group every `:number` field other than the window field is reduced as `y` against the window field as `x` (a number as itself, a `DateTime` as its Unix microseconds, a `NaiveDateTime` and a `Date` as their Gregorian seconds and days), or against the row's position in the group when the schema has no window field. The rows kept are the **union** of every field's choice, in their original order — so a row is kept whole, a tooltip reads a real datum, and a peak of any field survives. The budget is shared evenly: each group's field gets `max(3, div(budget, groups × fields))` points under LTTB and `max(1, div(budget, 4 × groups × fields))` pixel columns under M4, so the union stays within about the budget. A schema with no `:number` field is not reduced.
- **A budget-honouring feed is not reduced again**, whatever it returned; a feed that names `:budget` and ships more than the budget is wrong, which the conformance kit (§12) says, not something visualize hides. A window works the same way.

### 11.3 Push: the messages and their order

A push feed sends a subscriber two kinds of message, each tagged so a process that owns many feeds tells them apart:

| Message | Meaning |
|---|---|
| `{:visualize_feed, ref, {:schema, version, schema}}` | the feed's schema is now `schema`, of `version` |
| `{:visualize_feed, ref, {:delivery, delivery}}` | rows new since the last delivery sent to this subscriber, `delivery.schema` naming the version they were produced under |

`ref` is the reference `subscribe/2` answered. A pushed delivery is an **increment**: its rows are appended to what the subscriber holds, and its `window` is the span they cover. Two rules order them (#531 review A):

- **Schema before data.** A provider sends `{:schema, version, schema}` before the first delivery that names `version`, and the subscribe handshake sends the present schema first, before `subscribe/2` returns. Between two processes the BEAM delivers messages in the order they were sent, so a schema never trails its data, and a reconnect re-primes the cache.
- **An unknown version still falls back to `describe`.** A delivery whose version the subscriber does not hold — a message lost across hosts, a subscriber that joined mid-stream — is resolved through `Visualize.Data.Schema.Cache.resolve/4` with the feed's `describe`. Push never depends on the order for correctness, only for cost.

### 11.4 The monitor: who runs the loop

`Visualize.Feed.Monitor` subscribes where a feed can push, polls where it cannot, and hands a chart one finished delivery per slot. It is a **value, not a process**, as the schema cache is (§10.3, D-136): `%Visualize.Feed.Monitor{}` is held in the state of the process that owns the feeds — the board process of #540, a LiveView today — which calls it from its own callbacks. A monitor process would be a second owner of the window and of "now", which belong to the board (#531's further considerations, §2–3), and a process boundary between the board and its feeds' rows would copy every delivery once more. The owner's process is the one that subscribes, so the pushes arrive in its mailbox.

- **`new(feeds, opts)`** is a monitor over a map of feeds by slot name — the pool's names (spec/14 §7.2), so the deliveries are a pool and the cache's feeds are the names `Visualize.Chart.apply/2` uses. It calls nothing. Options: `window:` and `budget:` (the request, `nil` by default), `reduce:` (`:lttb`), `every:` (the poll interval of a pull feed in the owner's milliseconds, `1000`), `stale_after:` (milliseconds without an answer before a feed is stale, `nil` for never) and `limit:` (the most rows held for a feed whose rows cannot be trimmed by a window field, `100_000`).
- **`tick(monitor, now: ms)`** runs the loop once, at `now` on the owner's monotonic clock in milliseconds (`System.monotonic_time(:millisecond)` when absent). For each feed, in name order:
  1. **Describe** a feed not yet described, or one that is down and due a retry: `describe/1`, its schema put in the cache under its name, its `supports` kept; a push feed is subscribed with the owner (`self()`).
  2. **Fetch** when the feed holds nothing yet, when the window has moved past what it holds (below), or, for a feed that does not push, when its poll is due (`every` after the last). A fetched delivery **replaces** what the feed held.
  3. **Drain** the pushes buffered since the last tick, in arrival order, each **merged** into what the feed holds. With a window field, the rows **strictly after** the value the holding covers to are appended; a row at or before it is a **late** row (spec/15 §8.5, D-146), kept and placed by its window field unless the holding already has that very row, so a push that overlaps a fetch adds nothing twice and a reading that arrives late is not lost. A numeric window field is placed as an instant is (D-154). Without a window field every row is appended and the holding keeps the newest `limit`, `capped` when it cut.
  4. **Resolve** every version the feed's deliveries name, cached or asked of the feed's `describe` once (§11.3); a delivery that names none is taken as produced under the schema the feed described. A delivery whose version cannot be resolved is not used, and its reason is the feed's `error`.
  5. **Finish** what the feed holds for the window and the budget (§11.2): the holding is **put in order** — a stable sort by the window field, done only when it is out of order, so rows that tie keep their order — and trimmed to the window, so a push feed's rows do not grow past it, and the delivery handed out is the holding reduced to the budget. A reduction (`lttb`, `m4`) reads its rows in `x` order, and a fetched delivery out of order is therefore ordered before it is reduced.
- **Coalescing.** A push is buffered by `handle_message(monitor, message)`, which the owner calls from `handle_info/2` — `{:ok, monitor}` for a feed message, `:ignore` for any other — and does nothing else; the next tick drains every push since the last in one merge, one trim and one reduction. Pushes between two frames therefore cost one merge, whatever their rate. This is the data-rate/frame-rate split the gallery's runs already make (spec/14 §12.6, #300, #361): data arrives at its own rate, and the frame rate decides how often it is drawn. There is no other backpressure.
- **The window moves.** `window(monitor, window)` sets the request. **Each feed is asked the window that applies to it** (§11.2): the request where it applies to the feed's window field or the feed has none, else `nil`, the feed's own span — and a feed asked `nil` is neither trimmed by the window nor refetched when it moves. So a monitor over feeds of both kinds — a board's — takes one window of instants, and a feed over ticks keeps its own span and its own present (D-154). A pull feed fetches at the next tick; a push feed fetches only when the new window starts before what it holds covers — older data is the feed's to give — and is otherwise trimmed, since its pushes extend the end. So a live tail whose window slides each tick costs no fetch. `refetch(monitor)` asks **every** feed again at the next tick, push feeds included, whatever they hold: the board calls it when a person sets a window (spec/15 §8.2), since a narrower window may be served at a finer resolution. `budget/2` sets the budget, refinished at the next tick.
- **The answers are values.** `deliveries(monitor)` is the finished delivery of every feed that has one, by name — a pool for `Visualize.Chart.apply/2` or a compiled chart's `tick/3`; `cache(monitor)` is the schema cache holding every version they name, for `apply/2`'s `schemas:`, so no describe runs there; `status(monitor)` is each feed's state:

  | State | When |
  |---|---|
  | `:loading` | nothing answered yet |
  | `:live` | answered within `stale_after` |
  | `:stale` | the last answer is older than `stale_after` |
  | `{:down, reason}` | the last describe, subscribe or fetch answered `{:error, reason}`; the last delivery is still handed out |

  "No data yet" is `:live` with no rows, and "capped" is the delivery's `capped`: the five cell states of #531 (§5 of the further considerations), each a value a cell draws deliberately, never a blank chart or a raise. `errors(monitor)` is each feed's last unresolved delivery reason, if any. A schema change is seen by the compiled chart, whose `stale?/2` (spec/14 §12.1) says to recompile.
- **`put(monitor, name, feed)`** replaces or adds a feed — a rebinding — and `remove/2` drops one; `stop(monitor)` unsubscribes every push feed and is the monitor's end. A provider that stops is seen as `:stale` when `stale_after` is set, and as `{:down, reason}` at its next describe or fetch.

### 11.5 Live plus history in one slot

**A combining feed, in visualize** (the acceptance of #537). "The last hour from `:telemetry`, older data from metresis, one chart" is one slot whose rows come from two stores. Choosing *which* stores is the connector's — it knows that Exio's telemetry and metresis's capture are the same metric — but routing a window across them, merging the answers and deduplicating the seam is the same for every host and every pair of feeds, so writing it once here is what keeps two connectors from drifting. `Visualize.Feed.Combine.new(feeds)` is one feed over a list of feeds, freshest first:

- **Routing by window.** `fetch(combine, window, budget)` asks the first feed for the window. What it served starts at its delivery's `window` `from` (else its earliest row); the part of the window before that is asked of the next feed, and so on, until the window is covered or the feeds run out. A `nil` window asks the first feed for whatever it holds and each next feed for everything before what the last one served.
- **The seam.** Each feed's rows are trimmed to the half-open window it was asked for, `[from, served)`, so a row at the seam comes from the fresher feed only. The rows are concatenated oldest first; the delivery's `window` runs from the earliest served to the first feed's end, `capped` when the last feed asked could not reach the window's `from`.
- **The first feed's schema, whole** (#605, D-159). A delivery names one version, and the combination's is the **first** (freshest) feed's: `describe/1` answers the first feed's `{version, schema}` — its version, labels and facts, nothing merged from the later feeds — with the supports below. A merged schema would need a version of its own while the first feed's pushes, which pass straight through (below), name the first's, so the monitor would see two schemas for one slot.
- **Compatible schemas.** Every later feed's schema must be **compatible** with the first's (§10.1: `Visualize.Data.Schema.compatibility/2`): for each field of the first schema, a field of the same name compared as strings, of the same type, and for a `:number` field a unit that converts into the first's. Their versions may differ, as a process's live feed and a store's history of one metric always do. **The window field must be the same field too**: routing asks each later feed for a window over its own window field (§11.2, `Visualize.Feed.window_field/1`), so a later feed whose window field, compared as a string, is not the first's would be fetched over the wrong field. That is a rule of the combination, not of `compatibility/2`, which stays field by field. Otherwise `describe/1` answers `{:error, {:combine_schema, faults}}` listing **every** incompatibility of every later feed, each `{position, field, reason}`: `position` the later feed's index in the list (the first feed is `0`), `field` spelt as the first schema spells it, and `reason` `:missing`, `{:type, a, b}`, `{:unit, a, b}` or `{:identity, a, b}` (§10.1), or `{:window, first, later}` at the first's window field when the later feed's window field `later` is not the first's `first` (`nil` when it has none), ordered by position and then field. A schema with no window field (§11.2), which routing needs, is `{:error, :combine_window_field}`; a feed that cannot describe gives the first such error. Routing works over a `:number` window field as over a `:time` one: two feeds over ticks combine as two over instants do (D-154).
- **Rows in the first's words.** Before routing and the seam trim, each row of a later feed whose version differs from the first's is read as the first schema's: a column the later schema describes under a name the first has is re-keyed to the first's spelling, and its number, when the two units differ, converted exactly into the first's unit through `Visualize.Unit.convert/3` (`nil` and non-numbers pass as they are); a column the later schema describes and the first does not is dropped; a column neither schema describes is left as it is. When the window field is a `:number` in different units, the window asked of a later feed is converted into its unit and the `window` it served back into the first's. The first feed's rows, and the rows of a later feed of the first's own version, are never touched.
- **Capabilities.** A combination honours `:window` (it trims every part) and pushes when its first feed does: `subscribe/2` subscribes the first feed, whose pushes name the first's version — the combination's — so they reach the monitor unchanged. It does not name `:budget`; the budget is passed to every part as a request, and the monitor reduces the union.

### 11.6 Two providers

**`Visualize.Feed.Signals`** is a signal (§8) as a feed: `new(signal, opts)` with `describe:` (descriptions merged over the defaults, field by field), `tick:` (the feed's present tick, `0`), or `every:` (milliseconds per tick, read from `clock:`, a function of no argument in milliseconds, `System.monotonic_time(:millisecond)` by default, from `origin:`, the clock when the feed was made), and `limit:` (the most rows one fetch serves, `10_000`). `at(feed, tick)` moves a ticked feed. Its schema describes the first field, the tick, as its window field — `%{type: :number, window: true, label: "Tick"}`: the signal's clock, counted in ticks, which is a number and not an instant (spec/14 §2.3, #369; D-154) — and every other field `:number`, under whatever `describe:` adds (a `unit`, a `label`). It names `[:window]`: a window `[from, to]` is ticks, served as `Visualize.Signals.rows/3` from `max(from, 0)` to `min(to, tick)`, the newest `limit` of them and `capped` beyond; a `nil` window is `rows/2` at the tick, the signal's own window. A budget is a request it leaves to the monitor, which reduces each value column against the tick. It does not push: the monitor polls it at `every`, which is its data rate.

**`Visualize.Feed.Telemetry`** is an in-process `:telemetry` provider, a `GenServer`: `start_link(metrics: definitions)` takes a list of `Telemetry.Metrics` definitions — read by their fields (`name`, `event_name`, `measurement`, `tags`, `tag_values`, `keep`, `unit`, `description`, `reporter_options`) and their struct's name, with **no dependency on `telemetry_metrics`** — attaches one handler for their events and collects. `:telemetry` is an **optional** dependency, called directly under `@compile {:no_warn_undefined, :telemetry}` (D-50): a host without it builds warning-free and never starts the provider.

- **One feed per metric.** `feeds(server)` is a map from each metric's name, joined with dots (`"vm.memory.total"`), to `%Visualize.Feed.Telemetry{server, metric}`; `feed(server, name)` is one. Two definitions of one name — a summary and a counter of `phoenix.endpoint.stop.duration`, as a dashboard often has — are each keyed by their kind as well (`"….duration:summary"`, `"….duration:counter"`), and both keep the plain name as their label. A metric is one family of series, so each is its own slot: its schema is `t` (`:time`, label `"Time"`, a `DateTime`: the schema's one `:time` field, so its window field with nothing said), `value` (`:number`, labelled with the definition's `description`, else its name; its `unit` the definition's through `Visualize.Unit.from_telemetry/1` and its `quantity` that unit's, `Visualize.Quantity.of_unit/1`) and each of its `tags` (`:category`). A unit the mapping refuses — `:native`, or an atom outside spec/05 §4.1's table — leaves `value` with no `unit` and no `quantity` rather than a guess. One design (a latency line over `[:t, :value]`) then binds any metric.
- **A definition's facts** (#608, D-160). `value` also says how it was measured: its `metric_kind` is inferred from the definition's struct — a **counter** or a **sum** is `:counter`, since each row is a running total; a **last value**, **summary** or **distribution** is `:gauge`, since each row is a measurement. What only the application knows it says beside the definition, in the definition's `reporter_options` under `:visualize`, Telemetry.Metrics' place for a reporter's own options: `reporter_options: [visualize: [polarity: :lower_is_better, bounds: [0, nil], target: 250]]`. The keys are exactly `polarity`, `bounds`, `target` and `metric_kind`, each a fact of `value` as §10.1 defines it; an explicit `metric_kind` overrides the inference. The label is still the definition's `description` and the unit its `unit`; neither is set here, and facts for the tag fields are not taken. The schema is built through `Visualize.Data.Schema.new/1`, so a fact is checked as any feed's is: an invalid value (`polarity: :up`) or any other key is a **startup error** — `init/1` answers `{:stop, {:telemetry_facts, metric, errors}}`, `metric` the metric's name as `feeds/1` keys it and `errors` §10.1's `{path, reason}` faults (an unknown key is `{[:value, key], :unknown_key}`), so `start_link/1` fails naming the metric rather than serving a schema that lies. Because a `Visualize.Feed.Combine` describes itself with its first feed's schema whole (§11.5), these facts are how a store's knowledge of a metric reaches a chart that puts a live `Feed.Telemetry` feed in front of the store's history: a connector that knows the store's facts writes them into the definition, and the combination shows them.
- **The rows.** A handler runs in the process that emits the event, as a reporter's does: it applies `keep`, reads the measurement (a key, or a function of the measurements and, at arity 2, the metadata), skips `nil`, takes the tags from `tag_values` and sends them to the collector. The collector stamps each with its own clock in microseconds, strictly increasing (so the seam of §11.4 is exact: a fetch serves up to the last stamp, and every later push is after it), and keeps a row `%{t: DateTime, value: v}` plus the tags. A **counter** row's value is the count of events so far for its tags, and a **sum**'s the running total, as a reporter shows them; a **last value**, **summary** or **distribution** row's value is the measurement. A counter's `unit` is `"1"`, whatever the definition says, since it counts events.
- **Retention.** Each metric keeps its newest `keep:` rows (`10_000`). The collector covers from its start until it first drops a row, then from its oldest row; a fetch whose `from` is before that is `capped`, and its `window` starts where the collector's data does — which is what `Combine` routes the rest of the window by.
- **The capabilities** are `[:window, :push]`. A fetch serves the rows within a window of `DateTime` bounds (a bound of another kind is `{:error, {:window, window}}`), up to now; a budget is left to the monitor. Every `every:` milliseconds (`1000`; `nil` for only on `flush/1`) the collector sends each subscriber of a metric the rows new since the last flush, one delivery per metric; `flush/1` does it at once. The subscribe handshake sends the schema first; a subscriber that exits is dropped. The collector detaches its handler when it stops.
- **Calls are values.** A feed whose collector is not running answers `{:error, :noproc}`, and one that stops during a call `{:error, {:down, reason}}`: the call monitors the collector rather than linking a caller's fate to it.

### 11.7 Functions

| Function | Contract |
|---|---|
| `Visualize.Feed.capabilities/0` | `[:window, :budget, :push]` (11.1). |
| `Visualize.Feed.describe/1` | The feed's `{version, schema, supports}`, or `{:error, reason}`. |
| `Visualize.Feed.fetch/3` | `fetch(feed, window, budget)`: `{:ok, delivery}` or `{:error, reason}`; the window and the budget are requests. |
| `Visualize.Feed.subscribe/2` | `{:ok, ref}`, the feed's pushes sent to the pid (11.3); `{:error, :no_push}` for a feed that does not push. |
| `Visualize.Feed.unsubscribe/2` | Stops a subscription; `:ok`. |
| `Visualize.Feed.describer/1` | A map of feeds by name as §10.3's describe function. |
| `Visualize.Feed.window_field/1` | The field described `window: true`, else the schema's one `:time` field, or `nil` (10.1, 11.2). |
| `Visualize.Feed.window_type/1` | The window field's type, `:time` or `:number`, or `nil`: the kind of window that applies to it (11.2). |
| `Visualize.Feed.finish/3` | `finish(delivery, schema, opts)`: trimmed to the window and reduced to the budget where `supports:` lacks them (11.2). |
| `Visualize.Feed.Window.compare/2` | `:lt`, `:eq` or `:gt` between two times of one kind. |
| `Visualize.Feed.Window.within?/2` | Whether a time lies within a window, bounds inclusive, `nil` open. |
| `Visualize.Feed.Window.trim/3` | `trim(rows, field, window)`: the rows whose `field` lies within the window. |
| `Visualize.Feed.Window.before/4` | `before(rows, field, from, upper)`: the rows whose `field` lies in `[from, upper)`, the seam of a combination (11.5). |
| `Visualize.Feed.Window.newer/3` | `newer(rows, field, time)`: the rows whose `field` lies strictly after the time, the seam of a push (11.4). |
| `Visualize.Feed.Window.intersect/2` | The intersection of two windows, `nil` for everything. |
| `Visualize.Feed.Window.latest/2` | The later of two times, a `nil` ignored. |
| `Visualize.Feed.Window.earliest/2` | The earlier of two times, a `nil` ignored. |
| `Visualize.Feed.Window.time?/1` | Whether a value is one a window can be over: a number or an instant. |
| `Visualize.Feed.Window.instant?/1` | Whether a value is an instant: a `DateTime`, a `NaiveDateTime` or a `Date`. |
| `Visualize.Feed.Window.applies?/2` | `applies?(window, type)`: whether a window's bounds are values of a window field of the type, `:time` or `:number` (11.2). |
| `Visualize.Feed.Window.position/1` | A time as a number: itself, a `DateTime`'s Unix microseconds, a `NaiveDateTime`'s and a `Date`'s Gregorian seconds and days. |
| `Visualize.Feed.Monitor.new/1` | `new(feeds, [])`. |
| `Visualize.Feed.Monitor.new/2` | A monitor over feeds by name, calling nothing (11.4). |
| `Visualize.Feed.Monitor.tick/1` | `tick(monitor, [])`: `now` read from the monotonic clock. |
| `Visualize.Feed.Monitor.tick/2` | One turn of the loop at `now:`: describe, fetch, drain, resolve, finish. |
| `Visualize.Feed.Monitor.refetch/1` | Every feed fetched again at the next tick, push feeds included (11.4). |
| `Visualize.Feed.Monitor.handle_message/2` | `{:ok, monitor}` with a push buffered or a schema cached, `:ignore` for any other message. |
| `Visualize.Feed.Monitor.window/2` | The monitor with a new window, refetching only what the window needs. |
| `Visualize.Feed.Monitor.budget/2` | The monitor with a new budget. |
| `Visualize.Feed.Monitor.put/3` | A feed added or replaced under a name. |
| `Visualize.Feed.Monitor.remove/2` | A feed dropped, unsubscribed. |
| `Visualize.Feed.Monitor.deliveries/1` | The finished delivery of every feed that has one, by name: a pool. |
| `Visualize.Feed.Monitor.status/1` | Each feed's state: `:loading`, `:live`, `:stale` or `{:down, reason}`. |
| `Visualize.Feed.Monitor.errors/1` | Each feed's last unresolved delivery reason. |
| `Visualize.Feed.Monitor.cache/1` | The schema cache holding every version the deliveries name. |
| `Visualize.Feed.Monitor.stop/1` | Every push feed unsubscribed; `:ok`. |
| `Visualize.Feed.Combine.new/1` | One feed over several, freshest first, routed by window (11.5). |
| `Visualize.Feed.Combine.describe/1` | The first part's `{version, schema}` with the combination's supports; `{:error, {:combine_schema, [{position, field, reason}]}}` for later parts whose schemas are not compatible (11.5), `{:error, :combine_window_field}`, or a part's own error. |
| `Visualize.Feed.Signals.new/1` | `new(signal, [])`: a signal as a feed at tick `0`. |
| `Visualize.Feed.Signals.new/2` | A signal as a feed (11.6). |
| `Visualize.Feed.Signals.at/2` | A ticked feed moved to a tick. |
| `Visualize.Feed.Telemetry.start_link/1` | The collector over `metrics:` definitions, attached (11.6). |
| `Visualize.Feed.Telemetry.child_spec/1` | The collector as a supervisor's child, `{Visualize.Feed.Telemetry, metrics: definitions}`. |
| `Visualize.Feed.Telemetry.feeds/1` | Each metric's feed, by its dotted name. |
| `Visualize.Feed.Telemetry.feed/2` | One metric's feed. |
| `Visualize.Feed.Telemetry.flush/1` | Every subscriber sent the rows new since the last flush, now. |

## 12. Feeds: the conformance kit

**Implemented** (#538, D-145). "Two hosts can't drift" holds only if every provider honours §10–§11 the same way; without a shared test each provider reads the contract for itself. `Visualize.Feed.Conformance` is that test: the library's own reading of the contract as checks, shipped in `lib/` so a provider's suite runs it wherever the provider lives — `Visualize.Feed.Signals` and `Visualize.Feed.Telemetry` in this repository, metresis's feed in metresis. It drives a feed through the behaviour alone (`Visualize.Feed.describe/1`, `fetch/3`, `subscribe/2`, `unsubscribe/2`) and knows nothing of the provider.

### 12.1 Two layers: findings, and the tests that report them

- **The checks are functions that answer values.** `Visualize.Feed.Conformance.check(check, feed, opts)` runs one check and answers a list of **findings**, `[]` for a feed that passes; `check(feed, opts)` runs all six in the order of 12.3 and concatenates them. A finding is `{check, reason}`, `check` the check's name and `reason` a term naming the fault (12.3), and `format/1` words one as a line a person reads. Because a finding is a value, the kit itself is tested as any function is: against a deliberately broken feed, each flaw producing the finding it should.
- **The tests are a macro.** `use Visualize.Feed.Conformance, opts` inside a module that has called `use ExUnit.Case` expands to one `describe` block (named by `name:`, `"feed conformance"` by default, so one module can check several feeds) holding one `test` per check, named for it. Each test evaluates the `feed:` expression in the test process, runs `check/3` and, when there are findings, `flunk`s with every one formatted, one per line. Outside an `ExUnit.Case` module, `describe` and `test` are undefined and the module does not compile; a `name:` that is not a string literal, a missing `feed:` and an unknown option are an `ArgumentError` as the `use` expands.
- **The kit references no ExUnit function** (D-145). `describe`, `test` and `flunk` appear only in the code the macro returns, which is compiled in the caller's module, where `use ExUnit.Case` imported them. The kit's own module calls nothing of ExUnit, so it compiles in every environment of every consumer with no guard, loads in a `MIX_ENV=prod` build (scripts/consumer_check.exs asserts it, spec/12 §4), and costs a consumer's runtime nothing it does not call.

### 12.2 The options

| Option | Value | Default |
|---|---|---|
| `feed:` | an expression giving the feed under test. It is evaluated afresh in **each** generated test, in the test process, so it may call `start_supervised!/1` and the test module's own functions | required |
| `windows:` | the windows a fetch is probed with, a list of §11.1's windows. A feed that names `:window` needs at least one with a bound | `[nil]` |
| `budgets:` | the budgets each window is probed with | `[nil, 5]` |
| `push:` | a function of the feed that makes it push at least one delivery to its subscribers — emit an event and flush, append a row. A feed that names `:push` needs one | `nil` |
| `down:` | an expression giving a feed of the same provider that **cannot** answer — its process not running, its store gone. When given, the errors check holds its every callback to an error value | `nil` |
| `timeout:` | milliseconds a callback may take before it is a finding, and the most the push check waits for the first push | `1000` |
| `quiet:` | milliseconds of silence that end a push, and the wait for a push after unsubscribing | `100` |
| `name:` | the `describe` block's name | `"feed conformance"` |

`check/2` and `check/3` take the same options, with `feed:` and `down:` as values rather than expressions, and `feed:` given as the function's argument. An option the kit does not know is an `ArgumentError`, at compile time for the macro.

**Every callback runs in a process of its own.** The kit calls each callback, and the `push:` function, in a process it monitors, with the caller in its `$callers` (so a sandboxed repository or a mock's allowance follows the call, as it follows a `Task`). A callback that raises or exits is the finding `{:raised, call, reason}`, and one that has not answered within `timeout:` is `{:timeout, call}`, its process killed — where `call` names what was asked: `:describe`, `{:fetch, window, budget}`, `:subscribe`, `:unsubscribe` or `:push`. So a check always completes with its findings, whatever the feed does, and a raise is reported as a fault of the contract (§11.1: errors are values) rather than as a crash of the test.

### 12.3 The checks

Each check is named, and each names its findings. A **request** is `{window, budget}`; **served** is a delivery's `window`. A check that cannot begin — its describe answered an error — reports `{:describe_error, reason}` and stops.

**`:describe` — a valid schema and a stable version.** `describe/1` answers `{version, schema, supports}` (§11.1), the schema a `%Visualize.Data.Schema{}` that `Visualize.Data.Schema.new/1` accepts from its own fields, and the version the content hash of that schema (§10.2) — so the same schema gives the same version, wherever it is computed. A second describe of the same feed answers the same version and an equal schema. **The window field is declared** (§10.1, D-154): a feed that names `:window` in `supports` has a window field — a field described `window: true`, or a single `:time` field — since a window's bounds are values of it and the monitor, `Combine` and this kit read it to place, route and check rows.

| Reason | Meaning |
|---|---|
| `{:not_described, answer}` | the answer is not `{version, %Schema{}, supports}` or `{:error, reason}` |
| `{:schema_invalid, errors}` | `Schema.new/1` refuses the schema's fields, with its errors other than a measure's |
| `{:measure, field, reason}` | `Schema.new/1` refuses a field's measure (§10.1, D-157): `reason` is `{:unit, code, reason}`, `{:unknown_quantity, quantity}` or `{:quantity, quantity, code}`, one finding per fault, so the feed's author reads which field's unit or quantity is wrong apart from the schema's other faults |
| `{:version, given, computed}` | the version is not the schema's content hash |
| `{:unstable, first, second}` | a second describe answered another version, or another schema under the same one |
| `{:no_window_field, times}` | the feed names `:window` and its schema has no window field: `times` is its `:time` fields, none or several, none of them described `window: true` |

**`:deliveries` — well formed and honest.** Every request of `windows:` × `budgets:` is fetched, and each delivery is held to §10.4 and to what it says it served. The window field is §10.1's; a schema without one skips the clauses that need it.

- **Well formed.** The answer is `{:ok, %Delivery{}}` — an error for a probe window is a finding, since the kit's windows are ones the feed is meant to answer. Its fields hold their kinds: `rows` a row list or column map whose rows are maps (a tensor or a `Table.Reader` struct is read through `Visualize.Data.Table.rows/1`), `window` `nil` or `[from, to]` of times or `nil` with `from` not after `to`, `capped` a boolean, `reduced_by` `nil` or `:feed`, `schema` a string, `resolution` `nil`, a positive number or an atom. Every row's fields are fields the schema describes, by either spelling. **Every value is of its field's type where the type decides it** (D-154): the window field holds a value of its own type — an instant (`Visualize.Feed.Window.instant?/1`) for a `:time` one, a number for a `:number` one — or `nil`, and every other `:time` field holds an instant as a time scale reads one (`Visualize.Data.Table.temporal?/1`: a `DateTime`, `NaiveDateTime` or `Date`, or an ISO 8601 string) or `nil`. A tick written under `:time` is the case this catches: a time scale cannot draw it, and a numeric scale bound to a `:time` field is a type fault (spec/14 §7.4).
- **Every row says what it is about** (D-167). Of a schema that declares identity (§10.1), every row of every delivery has a value, not `nil`, for each declared identity field, by either spelling: a row with no identity cannot be grouped with the rest of its entity, and `latest` (#626) would drop it or merge it with others. A schema that declares none is not held to this.
- **Versioned.** The delivery names the version describe answered: a delivery the feed produced must say what it was produced under (§11.1), and the kit's describe and fetch are moments apart.
- **The served window is the truth.** Every row's time lies within `served`. And `served` covers everything the feed holds in it: an **open fetch** — `[nil, to]`, `to` the served window's end, no budget — is asked as well, and every row it serves within both served windows, up to the earlier end, must be in the delivery (a row arriving between the two fetches lies after that end and is not counted). A budgeted or reduced delivery is not held to this clause.
- **`capped` is the truth** (§10.4: the feed stopped short of the window it was asked for). Of a request whose window has a `from`: a capped delivery's `served` starts after that `from`; an uncapped one holds every row the open fetch serves from `from` on — the feed held nothing in the asked window before where it says it started. A request with no `from` asks for the feed's own span, so its `capped` is the feed's word.
- **`reduced_by` is the truth.** A feed never answers `:visualize`, which only `finish/3` writes. `:feed` is only for a request with a budget, from a feed that names `:budget`, and with fewer rows than the same window fetched with no budget; `nil` with a budget means no fewer rows than with none.
- **`resolution` is consistent.** A positive number is the spacing of the rows in the window field's own units — seconds for a `DateTime` or a `NaiveDateTime`, days for a `Date`, the values themselves for numbers — and `:second`, `:minute`, `:hour`, `:day` and `:week` are those spans in seconds; another atom is carried unchecked. Within each series — the rows sharing the values of every `:category` field, as §11.2 groups them — no two consecutive distinct times are closer than the resolution: a delivery never claims to be coarser than its rows.

| Reason | Meaning |
|---|---|
| `{:fetch_error, request, reason}` | a probe answered `{:error, reason}` |
| `{:not_a_delivery, request, answer}` | a probe answered something other than `{:ok, %Delivery{}}` |
| `{:malformed, request, field, value}` | a field of the delivery, or a row (`field` `:rows`), not of its kind |
| `{:version, request, named, described}` | the delivery names another version, or none |
| `{:undescribed_field, request, field}` | a row holds a field the schema does not describe |
| `{:window_value, request, value}` | a row's window field holds a value not of its type: not an instant for a `:time` field, not a number for a `:number` one |
| `{:not_an_instant, request, field, value}` | a row's `:time` field other than the window field holds a value that is not an instant |
| `{:no_identity, request, field}` | a row has no value, or `nil`, for the declared identity field `field`; one finding per field, ordered by name as a string |
| `{:outside_served, request, time, served}` | a row whose time lies outside the window the delivery says it served |
| `{:missing, request, count, served}` | `count` rows the feed holds within the served window are not in the delivery |
| `{:capped, request, served}` | `capped` is `true` and `served` reaches the asked `from` |
| `{:uncapped, request, count}` | `capped` is `false` and the feed holds `count` rows between the asked `from` and where it served from |
| `{:reduced_by, request, by}` | `reduced_by` is `:visualize`, or `:feed` with no budget, from a feed that does not name `:budget`, or with as many rows as with no budget |
| `{:unrecorded_reduction, request, count, whole}` | `reduced_by` is `nil` and the budget served `count` rows of the `whole` |
| `{:resolution, request, gap, resolution}` | two consecutive rows of one series `gap` apart, closer than the resolution |

**`:supports` — the declared capabilities are true.** `supports` is a list of distinct members of `Visualize.Feed.capabilities/0`, and each it names is honoured:

- **`:window`**: of every request with a window, `served` lies within the asked window and so does every row's time. It needs a probe: `windows:` with a bound.
- **`:budget`**: of every request with a budget, the delivery has at most that many rows. It needs a budget in `budgets:`.
- **`:push`**: `subscribe/2` answers `{:ok, ref}` (and is unsubscribed at once). It needs `push:`, without which the push check cannot run.
- And what is not named is not done: a feed that does not name `:push` answers `subscribe/2` with an error, so a monitor polls it rather than waiting for pushes that would arrive unannounced.

| Reason | Meaning |
|---|---|
| `{:supports, supports}` | `supports` is not a list of distinct capabilities |
| `{:no_probe, capability}` | a named capability the options give nothing to probe: no bounded window, no budget, no `push:` |
| `{:window_served, request, served}` | a `:window` feed served a window not within the one asked |
| `{:window_row, request, time}` | a `:window` feed served a row outside the window asked |
| `{:over_budget, request, count}` | a `:budget` feed served `count` rows, more than the budget |
| `{:push_refused, reason}` | a `:push` feed's `subscribe/2` answered `{:error, reason}` |
| `{:push_undeclared, answer}` | a feed that does not name `:push` answered `subscribe/2` with `answer`, not an error |

**`:push` — the schema before the data.** For a feed that names `:push` (otherwise the check has nothing to do): the kit subscribes its own process. Before `subscribe/2` returns, the present schema is already in the mailbox, the first message under the reference (§11.3's handshake). Then `push:` runs, and the kit collects the messages under the reference — waiting up to `timeout:` for the first delivery, then until `quiet:` passes with none. Every schema message's version is its schema's content hash, and **every delivery names a version whose schema arrived before it** — the handshake's, or one pushed since: a delivery under a new version is preceded by its schema. Each pushed delivery is well formed (as above) and its rows lie within its own `window`. The kit unsubscribes at the end.

| Reason | Meaning |
|---|---|
| `{:subscribe_error, reason}` | `subscribe/2` answered an error, so nothing could be checked |
| `{:handshake, got}` | the first message was not the schema — `got` is `:nothing` or the message |
| `{:schema_message, version, computed}` | a pushed schema whose version is not its content hash |
| `{:before_schema, version}` | a delivery naming a version whose schema had not arrived |
| `{:not_a_message, message}` | a message under the reference that is neither a schema nor a delivery |
| `{:no_delivery, timeout}` | `push:` ran and no delivery arrived within `timeout:` |
| `{:malformed, :push, field, value}` | a pushed delivery's field not of its kind |
| `{:outside_served, :push, time, window}` | a pushed row outside the delivery's own window |

**`:errors` — errors are values, never crashes** (§11.1). The feed is fetched with windows it cannot read — `[:not, :a_time]`, and windows of the other kind than its window field (a `DateTime` window for a `:number` window field, a numeric one for a `:time` one) — and each answers `{:ok, %Delivery{}}` (a feed that does not honour windows may ignore one) or `{:error, reason}`; `unsubscribe/2` with a reference it never answered answers `:ok`. With `down:`, the feed that cannot answer answers `describe/1`, `fetch(feed, nil, nil)` and, where its module subscribes, `subscribe/2` with `{:error, reason}`, and `unsubscribe/2` with `:ok`. A raise or an exit anywhere is `{:raised, call, reason}`, as everywhere.

| Reason | Meaning |
|---|---|
| `{:not_a_value, call, answer}` | a callback answered outside its contract — neither its success nor `{:error, reason}` |
| `{:answered_down, call, answer}` | the `down:` feed answered a callback with a success |

**`:unsubscribe` — unsubscribing stops pushes.** For a push feed: subscribe, take the handshake, unsubscribe — which answers `:ok` — then run `push:` and wait `quiet:`: nothing more arrives under the reference. For a feed that does not push, `Visualize.Feed.unsubscribe/2` answers `:ok`.

| Reason | Meaning |
|---|---|
| `{:unsubscribe, answer}` | `unsubscribe/2` answered something other than `:ok` |
| `{:pushed_after_unsubscribe, count}` | `count` messages arrived under the reference after it was unsubscribed |

Common to every check: `{:raised, call, reason}`, `{:timeout, call}` and `{:describe_error, reason}`.

### 12.4 Run here

`Visualize.Feed.Signals` runs the kit over windows that reach before the signal's start, past its present tick and beyond its `limit:` (so `capped`), and `Visualize.Feed.Telemetry` over a collector with a fixed clock, windows before its start (capped) and within its rows, a `push:` that emits an event and flushes, and a `down:` feed whose collector is not running. A fake feed in the test support, honest unless given a flaw, holds the kit to its negatives: the honest feed passes every check, and each flaw — an unstable version, a version that is not the hash, a served window that leaves out its own rows, a missing row, a `capped` with no shortfall and an uncapped delivery that stopped short, an unrecorded reduction, a resolution finer than claimed, a window or a budget overrun, a delivery before its schema, a fetch that raises, pushes after unsubscribing, a `:time` field written as numbers, a window feed with no window field — fails the check it targets with the finding that names it.

### 12.5 Functions

| Function | Contract |
|---|---|
| `Visualize.Feed.Conformance.__using__/1` | `use Visualize.Feed.Conformance, opts`: one ExUnit test per check, in a `describe` block, in a module that uses `ExUnit.Case` (12.1). |
| `Visualize.Feed.Conformance.checks/0` | The six checks in their order: `[:describe, :deliveries, :supports, :push, :errors, :unsubscribe]`. |
| `Visualize.Feed.Conformance.check/2` | `check(feed, opts)`: every check's findings, concatenated in the order of `checks/0`. |
| `Visualize.Feed.Conformance.check/3` | `check(check, feed, opts)`: one check's findings, `[]` for a feed that passes (12.3). |
| `Visualize.Feed.Conformance.format/1` | One finding as a line a person reads. |
