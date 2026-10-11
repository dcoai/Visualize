# Changelog

All notable changes to Visualize are recorded here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Note.** This file is written for a consumer of the library, so it says what changed in
> the surface and in behaviour, not what changed in the repository. What the library *is*,
> module by module, lives in
> [`spec/`](https://github.com/dcoai/Visualize/blob/main/spec/README.md), which is the
> source of truth for that and is not restated here.

## [Unreleased]

`mix.exs` reads `0.2.36-dev`: the `-dev` suffix is what keeps a commit from claiming to be the
release it merely follows.

### Added

- **A theme is a stored, versioned value** (#561, D-139). `Visualize.Chart.Theme` writes a
  theme as a document — `to_map/1` is `%{version: 2, theme: node}`, `to_json/1` the stamped
  `{"$version": 2, "theme": {…}}` — and `from_map/2` and `from_json/2` read one back to a
  `%Visualize.Theme{}` under the same rules as a design: a newer theme is refused by name
  before a key is read, `limits:` bound it, an older one migrates, and a broken ramp or role
  is the validator's `{:contract, message}` at its path. A document that only names a theme
  that is not built-in is the new fault `{:unknown_theme, name}`.
- **A host ships a theme through the builder's store** (#561).
  `Visualize.Chart.Builder.Store.theme/2` loads a stored theme by the name it gives itself,
  and the builder's preview draws a design whose `theme:` names a stored theme in it.
  `Visualize.Chart.Fragment.read_json/2` is `from_json/2` with the version the document was
  stamped with.
- **The builder has a theme mode** (#562, D-139). Opening a theme entry, *New → theme*,
  or the new *Theme* button on a chart's bar puts `Visualize.Chart.Builder` in the theme
  mode: the inspector edits the theme's series colours, chrome (background, surface, text,
  axis, grid) and fonts, and can *derive from* a built-in or stored theme; the main column
  is a sheet of sample charts — series, the five roles, thermal, diverging, axes and text —
  drawn in the theme being edited, to which designs from the store can be added. *Save to
  library* keeps the theme and refuses one that is not valid. `Store.theme_entry/2` finds
  the entry a stored theme name stands for.
- **The theme mode edits ramps and roles and checks them live** (#563, D-139). Each ramp is
  drawn as the theme interpolates it, with a lightness strip and its anchors (change, add by
  resampling, remove); the status roles are marked at their fixed positions and set by the
  colour there, and `:info` and `:neutral` are colours of their own. Every edit runs the
  meaning contracts: a broken ramp or role is outlined and named in the contract's words,
  and *Save to library* refuses the theme. `Visualize.Theme.violations/1` lists every broken
  ramp and role, where `check/1` gives the first.
- **Colour-vision simulation** (#563): `Visualize.Color.Vision.simulate/2` shows a colour as
  a person with protanopia, deuteranopia or tritanopia sees it (Machado, Oliveira and
  Fernandes 2009, severity 1.0, in linear sRGB), and `recolour/2` applies it to every colour
  literal of an SVG. The theme mode's *seen with* select draws the ramps and the preview
  sheet under each deficiency.
- **Fixed:** the builder no longer raises while rendering a design whose inline theme breaks
  a contract; its colour wells draw the theme unchecked.
- **Fixed:** a non-composite chart in the builder (a style, a theme) no longer reports its
  own `version` stamp as a fault of its kind.
- **`Visualize.Board`: a dashboard as data** (#539, D-141). A board lays designs out on a
  12-column grid (metresis's, so a panel maps to a cell field for field). Each cell is
  `{x, y, w, h}` and a `{:composite, n}` reference to a component in your store, which may
  be a composite or a flat design. The cells share a UTC `window` (`%{last: seconds}` or
  `%{from, to}`), a display `zone`, board `vars` and a `sync` group, but never geometry: a
  board never flattens. Below `layout.breakpoint` (768 px) the cells stack full width in
  reading order (`arrange/2`, `boxes/2`). Board variables are the defaults of every cell's
  component variables, and a cell may override one. `to_map`/`from_map` and
  `to_json`/`from_json` round-trip a board. The JSON is stamped `"$version"`, and a newer
  board is refused as `{:newer_schema, needs, this}` before anything is read. `limits:`
  applies, and the defaults apply when it is not given. `validate/1` reports off-grid and
  overlapping cells, a bad window and wrong-kind refs. `validate/3`, given a store (a fetch
  function or an id map), adds dangling refs, cycles, components that are not designs,
  undeclared cell variables, and cells whose component cannot join the board's sync group
  (set `sync: false` on those). `required_sources/3` lists every slot keyed `{cell, slot}`
  with its `fields`, `types` and `requires` contract, so one design in two cells binds to
  two feeds. `realise/4` applies every cell at its box's size, purely.
- **`Visualize.Board.Binding`** (#539): which feed fills each `{cell, slot}`, supplied by
  your connector and never stored in the board. `check/3` reports every unbound slot,
  every contract a feed's schema cannot meet (with `apply/2`'s reasons), and every binding
  to a slot no cell declares. `pools/2` builds one pool per cell from your sources.
- **Every chart describes itself** (#557, D-142). `Visualize.Chart.Summary.new/1` reads an
  applied chart into a text alternative — its name, its kind (a line chart, a gauge, a
  treemap…), its series, each axis's range or categories, and the highest and lowest value
  it draws, each with where it is — and `text/1` writes it as sentences, values written as
  their axis writes them (its `measure`'s display unit, `prefix` and `unit`) to four
  significant digits. `table/2` is the data-table fallback: an HTML `<table>` per mark,
  visually hidden and still read, for a page to place beside the chart. `attrs/2` and
  `description/2` name and describe whatever element stands for the chart — a canvas, or
  the wrapper of a hybrid chart's layers.
- **A chart's points from the keyboard** (#558, D-142). `KeyboardHook`, the bundle's
  eleventh hook, makes a chart one tab stop: the arrow keys move between its points and
  its series, Home and End to a series' ends, a polite live region reads each point
  (`y, 3 of 51: x 2, y 54.3`) and a ring marks it over the SVG or the canvas. Escape
  hands focus back to an enclosing `data-vis-cell`, so a board can navigate its cells
  around charts. `Visualize.Hooks.Keyboard.attrs/1` writes the points once on the server
  from an applied chart; a series of more than 1,000 points is sampled evenly.
- **Reduced motion** (#559, D-142). `Visualize.Chart.compile/2` takes `motion: :reduce`,
  and `Compiled.tick/3` and `step/3` take `motion:` per tick: every scale transition and
  mark motion is then drawn at its target on the tick it changes, its state kept, so
  turning motion back on eases on from where the chart stands. `ResizeHook` now pushes
  `reduced_motion` — `prefers-reduced-motion: reduce` — with every size and again when the
  reader changes it, so the page that sizes a chart can compile it to match. A component
  with `animate` gains the class `vis-animated` and a `<style>` that stops its transition
  under that media query.
- **Status beyond hue** (#560, D-142). Every role carries a glyph and a dash besides its
  hue, fixed by the library — `Visualize.Theme.cue/1`: `:good` a circle and solid,
  `:warning` a triangle and `"6 3"`, `:bad` a cross and `"2 3"`, `:info` a square and
  `"8 3 2 3"`, `:neutral` a diamond and `"1 4"`. A `{:field, f}` binding on a `:symbol`
  mark's `symbol` or on `stroke_dasharray` reads through the frame's colour scale to the
  role and draws its cue, so a status chart reads in greyscale. The gallery's Gauge marks
  its zones with their glyphs.
- **`Visualize.Format.Auto`** (#532, D-134): tick formats derived from a scale's domain.
  `time_format/2` picks a `Visualize.Format.time/2` specifier from a time domain's span and
  the interval its ticks use — `%H:%M` within a day, `%a %H:%M` or `%a %d` within a week,
  `%b %d` within 92 days, `%b %Y` (or `%Y`) beyond. `notation/2` reads a numeric domain's
  magnitude — `:plain` below 1,000, `:grouped` below a million, `{:si, 6}` and up beyond —
  and `number/2` turns a notation into a formatter (`90,000`; `0.5M, 1M, 1.5M`, one prefix
  for the whole axis). `formatter/2` does both for a realised scale. Every function takes
  `locale:`, `"en"` by default and the only locale for now; another raises.
- **`Visualize.Axis.tick_count/2`** (#532): the tick count an axis of a given length asks
  for — one per 80 px across, per 35 px down, between 2 and 10.
- **Themes carry meaning: four ramps and five roles** (#533, D-135). A `Visualize.Theme`
  now has `ramps` — `status` (good → caution → bad), `thermal` (cold → neutral → hot),
  `diverging` (below → at → above a midpoint) and `sequential` (less → more), each a list of
  anchor colours interpolated in CIE Lab — and the roles `:good`, `:warning`, `:bad` (the
  status ramp at 0, 0.5 and 1), `:info` and `:neutral`. A design colours by meaning with a
  role (`fill: :bad`) or a ramp position (`fill: {:ramp, :thermal, 0.8}`), wherever a colour
  is accepted, and every theme renders it in its own tones. `Visualize.Theme.ramp/3` reads a
  position; roles are slots, so `stylesheet/1` declares `--vis-good` and the rest.
- **Ramp and role contracts are checked when a theme is built.** `Theme.new/1`,
  `Theme.merge/2` and an inline design theme refuse a ramp whose hues are out of order, whose
  lightness is not monotonic, or whose midpoint is not neutral, with an `ArgumentError`
  naming the theme, the ramp and what is broken; `Theme.check/1` returns the same answer
  without raising, and the validator reports it as `{:contract, message}`. The tolerances
  are in spec/08 §7.5.
- **`Visualize.Theme.colour_safe/0`** (`theme: :colour_safe`): the light theme with its
  status ramp blue → orange → red, so status reads under the commonest colour-vision
  deficiencies. `Theme.builtin/1` resolves the three built-in names.
- **Colour scales range over a theme ramp.** `range: {:ramp, :status}` on an ordinal colour
  scale spreads its domain end to end (three states draw as `:good`, `:warning`, `:bad`); on a
  threshold scale its buckets; on a sequential or diverging scale it interpolates the ramp.
  JSON writes a ramp as `{"$ramp": "status"}` and a position as `{"$ramp": ["status", 0.5]}`.
- **A feed can describe its fields: `Visualize.Data.Schema`** (#551, D-136). `new/1` takes
  a map from field name to a description of what the field *means*: `type` (required),
  `unit`, `quantity`, `label`, `order`, `status` (a state to a role such as `:good`,
  `:warning` or `:bad`), `polarity`, `target` and `continuity`. A schema never names a
  colour: `color`, `colors`, `palette`, `fill` and the like are refused, because a theme
  chooses colour from the meaning. Each schema has a `version`, a SHA-256 content hash that
  is the same on every node and under every release, so a version can cross a wire.
- **`Visualize.Data.Schema.Cache`**: schemas held by `{feed, version}` as a plain value you
  keep in your own state. `resolve/4` answers a cached version without calling anything, and
  calls the `describe` function you give it once for a version it has not seen.
- **`%Visualize.Data.Delivery{}`**: one answer of a feed, holding its rows, the window
  served, the resolution, `capped`, `reduced_by` and the schema version (never the schema).
  `Visualize.Data.Table.rows/1` reads it, so it goes wherever a source goes:
  `Visualize.Chart.apply/2`'s pool and a compiled chart's `tick/3`, `step/3`, `render/2`
  and `svg/2`.
- **A design can require and read its feed's schema** (#552, D-136). A source slot can now
  state `requires: %{latency: [:unit, :label]}`, the attributes its feed's schema must
  describe. `Visualize.Chart.fact(:primary, :latency, :label)` reads one of them anywhere a
  value goes, and inside a text as `#{fact(:primary, :latency, :unit)}`. So an axis title
  can come from the field's label and unit, and an ordinal domain from its `order`.
  `Visualize.Chart.apply/2` takes the schema cache as `schemas:` and a `describe:`
  function, resolves the schema each delivery names, and fails with the slot, the field
  and the missing attribute named (`{:missing_attribute, slot, field, key}`) instead of
  drawing a blank label. The applied chart returns `schemas`, `versions` and the grown
  `cache`. `Visualize.Chart.contract/1` lists what a design requires, for a picker.
- **`Visualize.Chart.Compiled.stale?/2`**: whether a delivery names a schema version
  other than the one the chart was compiled with. A schema change needs a recompile, as a
  resize does: `tick/3`, `step/3`, `render/2` and `svg/2` raise `ArgumentError` for a stale
  delivery, so compile again and `carry/2` the state across.
- **Sanity limits on every design reader** (#550, #541, D-137): `Visualize.Chart.from_map/2`,
  `from_map!/2`, `from_json/2` and `Visualize.Chart.Fragment.from_json/2` take
  `limits: [depth: …, items: …, ticks: …, iterations: …, counts: …]`. The defaults
  (`Visualize.Chart.Limits.defaults/0`: nesting 64, 100,000 entries in one list or map, 1,000
  axis ticks, 10,000 force iterations, 1,000,000 for bins, samples, `n`, `width` and a grid's dimensions) always
  apply and every gallery design passes them by a wide margin; a host reading designs or
  boards from elsewhere tightens them. A value over a limit is
  `{path, {:limit, name, max, given}}`, worded by `Validator.format/1` as
  `frames.main.axes[0].ticks: asks for 5000 ticks; the limit ticks is 1000`. From JSON, the
  nesting and sizes are checked before the document is decoded, so an oversized document
  makes no atoms. `Visualize.Chart.Limits.check/2` gives the verdict on a map without reading
  it. See [spec/14 §9.2](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#92-sanity-limits-on-a-document-from-elsewhere).
- **`Visualize.Chart.Migration.readable/1`**: the version gate alone, for a reader that holds
  a version before it holds a design.
- **Units by UCUM code: `Visualize.Unit`** (#536, D-138). `parse/1` and `valid?/1` check a
  UCUM code (`ms`, `kBy`, `MiBy`, `%`, `Cel`, `kW.h`, `{request}/s`) against a fixed table
  of prefixes and atoms, refusing typos such as `sec` or `kmin` with a reason;
  `symbol/2` writes a code for a reader (`B/s`, `µs`, `°C`, `kW·h`); `convert/3` scales a
  value between codes of one dimension (1,500 `ms` is 1.5 `s`) and refuses °C to °F, which
  is out of scope. `from_telemetry/1` maps a `Telemetry.Metrics` unit (`:millisecond`,
  `:kilobyte`, `{:native, :millisecond}`) to its code, without depending on
  `telemetry_metrics`.
- **Quantities and display scaling: `Visualize.Quantity`** (#536, D-138). A fixed list of
  twelve quantities (`:duration`, `:information`, `:data_rate`, `:frequency`, `:ratio`,
  `:count`, `:temperature`, `:length`, `:speed`, `:power`, `:energy`, `:pressure`), each
  with a base unit and a family to scale in. `display_unit/2` picks the unit that fits a
  domain, `formatter/3` writes a scale's ticks in it with its symbol (`0.5 s, 1 s, 1.5 s`
  for 0–1,500 ms), and `label/1` is the axis-label rule: the unit, else the quantity, else
  nothing. Information scales in decimal units (`kB`, `MB`) unless your unit is binary
  (`MiBy`) or in bits, which then keep their own family.
- **An axis `measure`** (#536, D-138): `measure: %{unit: "ms", quantity: :duration}` (either
  key alone is enough) says what the axis's values are. With no `format`, a numeric axis's
  ticks are scaled into the unit that fits and carry its symbol; when the ticks cannot say
  the unit (a count, an explicit `format`), the axis draws a title by the label rule
  unless you anchor your own label there. The validator refuses a code it cannot read and a
  unit that does not measure its quantity. The existing `unit` key is unchanged: it is still
  a literal suffix.
- **The feed behaviour: `Visualize.Feed`** (#537, D-140). A feed is a struct whose module
  implements `describe/1` (`{version, schema, supports}`, where `supports` is any of
  `[:window, :budget, :push]`) and `fetch(feed, window, budget)` (a
  `%Visualize.Data.Delivery{}`), and optionally `subscribe/2` and `unsubscribe/2`. Only rows
  are required. A window and a budget are requests: when your feed does not honour them,
  `Visualize.Feed.finish/3` trims to the window by the schema's `:time` field and reduces to
  the budget with LTTB or M4, one series per category value and every number field's peaks
  kept, and records `reduced_by: :visualize`. A push feed sends
  `{:visualize_feed, ref, {:schema, version, schema}}` before
  `{:visualize_feed, ref, {:delivery, delivery}}`, where each delivery holds the rows new
  since the last. A version the subscriber does not hold is asked of `describe` once.
  Callbacks answer `{:error, reason}` and never raise.
- **`Visualize.Feed.Monitor`**: the loop over your feeds, as a value you keep in your
  process's state (a LiveView today, a board later). Call `tick/2` each frame and
  `handle_message/2` from `handle_info/2`. It describes and subscribes your feeds, polls
  pull feeds every `every:` ms, buffers pushes until the next tick and merges them once,
  and deduplicates a push that overlaps a fetch. Pass `deliveries/1` and `cache/1` to
  `Visualize.Chart.apply/2` as `sources:` and `schemas:`. `status/1` reports each feed as
  `:loading`, `:live`, `:stale` (with `stale_after:`) or `{:down, reason}`, and the last
  delivery is still handed out while a feed is down. `window/2` moves the window: a push
  feed is fetched again only for older data.
- **`Visualize.Feed.Combine`**: one slot over several feeds, freshest first, for example
  the last hour from `:telemetry` and older data from a history store. Each feed is asked
  for the part of the window the fresher ones did not serve, and the seams are
  deduplicated. Every part must describe the same schema version.
- **`Visualize.Feed.Signals`**: a `Visualize.Signals` signal as a pull feed, honouring a
  window of ticks, with a fixed tick (`at/2`) or a clock (`every:`). It comes with
  `Visualize.Signals.rows/3`, the rows from one tick to another.
- **`Visualize.Feed.Telemetry`**: an in-process `:telemetry` collector over a list of
  `Telemetry.Metrics` definitions. Start it in your supervision tree with
  `{Visualize.Feed.Telemetry, metrics: metrics}`. Each metric is a push feed (`feeds/1`)
  with rows `%{t: DateTime, value: v}` plus its tags, and a schema giving the label, the
  UCUM unit and the quantity. A counter's value is the running count, a sum's the running
  total. `:telemetry` is now an optional dependency of visualize. If your app lacks it,
  everything else builds as before. visualize does not depend on `telemetry_metrics`.
- **A conformance kit for your feeds: `Visualize.Feed.Conformance`** (#538, D-145). Add
  `use Visualize.Feed.Conformance, feed: …, windows: […]` to an `ExUnit.Case` module and
  it writes six tests: `describe` answers a valid schema under its content hash, and the
  same one each time; every delivery is well formed and names that version, its `window`
  covers its rows and every row the feed holds there, and `capped`, `reduced_by` and
  `resolution` are true; the capabilities in `supports` are honoured, and an undeclared
  `:push` is refused; a push feed sends the schema before any delivery naming it (give
  `push:`, a function that makes it push); a window the feed cannot read is an error
  value, never a raise (give `down:` to check a feed whose provider is gone as well); and
  unsubscribing stops pushes. `Visualize.Feed.Conformance.check/2` runs the same checks
  outside a test and returns the findings as values, `[]` for a feed that passes. Each
  callback runs in its own process with you in `$callers`, so a sandboxed repository works
  and a raise is reported as a finding. The kit calls no ExUnit function itself, so it
  compiles in every environment of your app. `Visualize.Feed.Signals` and
  `Visualize.Feed.Telemetry` pass it. The LiveView guide has a new section, *Writing a
  feed*.

- **Overlays are marks** (#565, D-143): what a host drew around a chart — event markers,
  thresholds, the brush — is now part of the design, so every host that applies it draws
  the same overlays on SVG, the canvas, the binary stream and the hybrid page.
  - **A `:rule` at `y` in a cartesian frame** is a horizontal rule across the plot — a
    threshold (`channels: %{y: :value}` over a source of thresholds) or a feed's target
    (`y: fact(:primary, :latency, :target)` over `take(1)` of the feed) — labelled at its
    left end.
  - **A colour scale's `range` may be a map of colours** on an `:ordinal` scale, pinning each
    category by name: `range: %{"info" => :info, "critical" => :bad}`, or a feed's own
    meaning, `range: fact(:events, :severity, :status)`. A category the map does not name
    draws the theme's neutral `:axis` colour. In JSON it is a `"$colours"` list of pairs.
  - **`polarity` on a colour scale over a ramp** (`:higher_is_better`, `:lower_is_better`,
    `:neutral`, or `fact(:primary, :latency, :polarity)`) places the ramp's good end at the
    better end of the domain. With `kind: :threshold`, `domain: [fact(…, :target)]` and
    `range: {:ramp, :status}`, a reading beyond the feed's target is `:bad` whichever way the
    feed says is better.
  - **A variable or a fact may stand for one member of a domain list**, as the threshold
    above does.
  - **`interaction: %{brush: :x}`**: the design's own brush. The chart writes its plot area
    and its x mapping (`Visualize.Chart.Frame.brush_attrs/1`), and `BrushHook` on a container
    around it pushes `brush_select` with `"domain" => [lo, hi]` (milliseconds for a time x)
    — your handler reads the window and needs no margins and no scale to invert. The
    element's own `data-brush-type` and `data-brush-extent` still win.

### Changed

- **The builder is split into modules by area, with no change in behaviour** (#568).
  `Visualize.Chart.Builder` keeps its assigns, its message, `css/0`, `styles/1` and
  `tick/2` exactly as before; what moved is internal (`Visualize.Chart.Builder.Events.*`,
  `Editing`, `Tree`, `Selection`, `Writes`, `Workspace`, `Modes`, `ThemeMode`, none of
  them public). A test that calls the component's `handle_event/3` directly sees the same
  results; an event the builder does not handle still raises `FunctionClauseError` there.
- **A root names every chart and describes it with its summary** (#557, D-142).
  `Visualize.Chart.render/2` and `generate/2` with `root: true` title a design with no
  `meta.name` by its kind, and write the generated summary after `meta.description` in the
  `<desc>`; `summary: false` leaves the description the design's alone, and a string
  replaces the summary. `aria-labelledby` now names the `<title>` only and the new
  `aria-describedby` the `<desc>` — on `Visualize.IR.Element.root/3` and every component —
  so a screen reader says a short name and then the description. `Element.root/3` takes
  `hidden: true` for `aria-hidden`.
- **A `:symbol` mark in a polar frame keeps its glyph** (#560): only its position bends
  around the arc. Before, the glyph itself was bent and drew as a sliver.
- **A retargeted easing is shown where it starts on the tick it is retargeted** (#559):
  unchanged for any easing with a duration, and an easing of no duration now reaches its
  target on that tick instead of the next.
- **A canvas names itself, and a hybrid chart's SVG layers are hidden** (#557).
  The root wrapper of `Visualize.Backend.Canvas` and `Visualize.Backend.Hybrid.render/1` take
  `title:` and `description:` and put them on the `<canvas>` (`role="img"`, `aria-label`,
  and the description as its fallback content); `Hybrid.render_static/1` — and so a
  compiled chart's static, dynamic and backdrop documents — is `aria-hidden="true"`, one
  layer of a picture the page names.
- **A design's axis without a `format` or a tick count derives them** (#532, D-134). The
  count comes from the axis's length and the format from its scale's domain, recomputed on
  every realisation, so a time axis reads `03:00` or `Mar 05` instead of
  `2024-03-05 03:00:00Z`, an axis over thousands is grouped and one over millions carries an
  SI prefix, and a streaming window's axis changes format as its span changes. A host no
  longer computes these and passes them in as variables (or passes the width into binding to
  do it). An explicit `format`, count or list of values still wins. **What you may see:** an
  axis shorter than 800 px across or 350 px down now draws fewer than ten ticks — set
  `ticks: 10` to keep them; a numeric axis over years (`1990..2020`) is now grouped
  (`1,990`) — set `format: "d"`; and `unit: "M"` over values from 1,000 reads `1,200M`. The
  hand-built `Visualize.Axis` is unchanged: d3's ten ticks and its default label.
- **A `:sequential` or `:diverging` colour scale left at `range: :auto` now draws the theme's
  `sequential` or `diverging` ramp**, where it ran from the background to the first series
  colour. Heatmaps, contours and hexbins change colour slightly on the light theme, and follow
  the theme's own ramp on the dark one; give `range:` to keep the old colours.
- **`ramps` and `roles` merge key by key** in `Theme.new/1` and `Theme.merge/2`, and a theme
  lacking one takes the default theme's — never a series colour.
- `Theme.slots/1` and `Theme.colour_slots/1` include the five roles, after `surface`.
- **Visualize now starts `:crypto`** (`extra_applications`), for the schema version's hash.
- **A design, fragment or bundle from a newer release is refused by name** (#550, #541,
  D-137): the error is `{:newer_schema, needs, this}`, worded
  `version: needs schema v3, this is v2`, where a newer `version` used to be
  `{:unsupported_version, v}` (which now means a version below 1 only). Match the new reason
  if you handled the old one for a newer document. The refusal comes before anything else is
  read: `from_json/2` checks `"version"` before decoding a key.
- **`Visualize.Chart.Fragment.to_json/1` stamps the document with `"$version"`**, and
  `from_json/2` reads and drops it, refusing a newer one as `{:error, {:newer_schema, …}}`
  and an oversized document as `{:error, {:limits, errors}}`. Documents written before the
  stamp read as they always did, and `from_json(to_json(f))` is still `f`.
- **A bundle's provenance carries `schema`**, the version it was exported at, and
  `Visualize.Chart.Builder.Store.relocate/3` refuses a newer bundle before it puts an entry.
- **The `Visualize.Chart.Validator.path` type** may hold strings: the path of a limit fault in a JSON
  document refused before decoding uses the document's own keys.

- **A mark's `scales: %{color: name}` now reaches every colour the mark reads** (#565,
  D-143): a `{:field, f}` fill or stroke in its style reads through the renamed scale, as its
  `series` channel's validation already did, so an overlay can colour by its own scale
  without changing the series' colours. A mark that renamed `color` and coloured its style
  by a field used to read the frame's `color` scale there.
- **In a cartesian frame a `:rule` and an `:x_band` are cut to the plot area**: a rule
  outside it, or a band wholly outside it, draws nothing, and a band that crosses an edge is
  clamped to it — an event that began before the window no longer draws across the axis.
- **`BrushHook` sends `domain` whenever it can map the selection**: in a sync group, as
  before, and now under a design's brush too.

### Fixed

- **`Visualize.Chart.to_json/1` raised on a channel at its scale's own end** (#554): a
  `{:scale, :min}` or `{:scale, :max}` channel, such as an area's `y0`, had no JSON form. It is
  now written `{"$scale": "min"}` and read back as the tuple.
- **An axis's `format: :duration` read back from JSON as the string `"duration"`** (#554,
  D-144), so the axis printed that word as a format specifier instead of durations. Where a
  key may be a string or an enumerated atom, a string naming a member of the enumeration now
  reads back as the atom. Every gallery design now round-trips through `to_json/1` and
  `from_json/1`.
- **`Visualize.Color.to_lab/1` was not the inverse of `Visualize.Color.lab/4`**: it used the
  D65 sRGB matrix against the D50 white point, so a grey had a chroma of about 12 and a colour
  did not survive a round trip (`#808080` came back `#758194`). Lab, LCh, `brighter/2`,
  `darker/2`, `interpolate_lab/3` and `interpolate_hcl/3` now read true.

## [0.2.35] — 2026-10-10

### Changed

- **The documentation is the README, the guides and the changelog** (#529, D-133). The
  specification, `API_SURFACE.md` and `usage-rules.md` are no longer hexdocs pages; they still
  ship in the package and are read on GitHub. Every link to them from the README, the guides
  and this changelog is now an absolute GitHub URL, and a link to a section of the
  specification uses GitHub's heading anchor, so it opens at that section there.

## [0.2.25] — 2026-10-10

### Added

- **`Visualize.Geo.Circle`** (#525): d3-geo's `geoCircle`. `polygon/1` returns the circle of
  `radius` degrees (default 90) about a `center` `[lon, lat]` (default `[0, 0]`), every
  `precision` degrees (default 6), as a GeoJSON `Polygon` — d3-geo 3.1.1's ring point for
  point, in d3's winding, so `Visualize.Geo.Path` fills the cap about the centre under any
  projection, cut and closed at the antimeridian. A night side is
  `polygon(center: antisolar_point)`.
- **`alpha` and `ticks` on the `:force` step** (#527, D-132): the temperature a compiled
  chart reheats the layout to each tick (`0.3`) and the iterations it runs (`3`).
- **`Visualize.Layout.Force.run/1` takes `:alpha` and `:alpha_decay`** (#527): a run can
  continue a layout, from nodes that carry their `x`, `y`, `vx` and `vy`, as a reheated d3
  simulation does. The defaults are unchanged.
- **`Visualize.Chart.Frame.new/2` takes `warm:`** (#527, D-132): the force layouts a
  compiled chart carries between ticks.

### Changed

- **The cheatsheet links open its rendered page on HexDocs** (#528). `guides/cheatsheet.cheatmd`
  is ExDoc's cheatsheet format, so GitHub and GitLab show it as plain text. The README and
  the guides now link <https://hexdocs.pm/visualize/cheatsheet.html>.
- **A projection's clip hides a row; it no longer drops it** (#522, D-130). A `:projection`
  step keeps every row it is given. A point the projection clips keeps its row with `x` and
  `y` set to `nil`. A geometry that projects to nothing keeps its row with `path`, `x` and
  `y` set to `nil`. Marks draw nothing for these rows on every backend. Domains are now
  inferred over every row, whatever the viewpoint. Before, a turning globe coloured through
  an inferred `ordinal_scale(:color)` changed its land colours as it turned, and a bubble
  map's size domain depended on what was in view. Rows with a missing or non-numeric
  coordinate, or a geometry that is not a map, are still dropped. **If you count or read
  the step's output rows**, expect the clipped ones, with `nil` positions.
- **A `:line` or `:area` path that places no point draws no element** (D-130). This
  applies to a whole series a projection clips, and to a line with no rows. Before, it
  drew an empty `<path d="">`.
- **A compiled chart's force layout is warm** (#527, D-132). `Visualize.Chart.Compiled`
  keeps each `:force` step's last layout, every node's position and velocity by id, and
  each `tick/3` or `step/3` moves the graph on from it instead of laying it out again from
  scratch. A change to the step's `distance` or `strength` now perturbs the graph rather
  than replacing it with a new one, often a reflection or rotation of the last. A node new
  to the graph starts near its linked neighbours, and a node that has gone is forgotten.
  `Compiled.carry/2` carries the layout across a recompilation, so a caller that compiles
  again because a tick's marks differ keeps the graph where it was. `Visualize.Chart.apply/2`
  and `render` are unchanged: the same input lays out the same graph, cold.
- **The marks of one graph share one layout** (#527, D-132). `Visualize.Chart.Frame.new/2`
  lays out each distinct `:force` step once and holds it in the frame's new `forces`
  field, so a links mark and a nodes mark over the same step agree exactly and the
  simulation runs once per realisation, not once per mark and pass. Compiling a graph
  is about eight times cheaper.
- **A `:force` node source's `x` and `y` seed the layout** (#527). A node whose row has
  numeric `x` and `y` starts there, as d3 honours a given position.

## [0.2.4] — 2026-10-10

### Changed

- **Visualize is on Hex** (#516): depend on `{:visualize, "~> 0.2"}` rather than a git tag.
  The documentation is on [HexDocs](https://hexdocs.pm/visualize). The source, and issues
  and feedback, are at [github.com/dcoai/Visualize](https://github.com/dcoai/Visualize).

## [0.2.0] — 2026-10-10

**Upgrading from 0.1.0.** This is the first minor since the first tag, and the breaks are in
the declarative layer and the builder. The imperative pipeline (`Scale` → `Shape` →
`IR.Element` → `Render`) removes nothing. A design now holds its **frames by name** and
records **no size**: the host gives `size:` at `Visualize.Chart.apply/2`, and
`Visualize.Chart.compile/2` returns one compiled chart per frame. Stored version-1 designs
still read, because `from_map/1` and `from_json/1` migrate them, but code that *builds*
designs, reads a compiled chart, or implements `Visualize.Chart.Builder.Store` needs the edits
listed under **Breaking**. Three d3-conformance fixes in geo and stacking also move output for
the same input. Read those if you draw globes, rotate projections, or stack `:insideout`.

### Breaking

- **A design holds its frames by name, and the schema is version 2** (#383, #428). The
  design's `frame:` key is `frames: %{main: …}`, `%Visualize.Chart{}` has `frames` where it
  had `frame`, and `to_map/1` writes `version: 2` (`Visualize.Chart.Migration.current/0`).
  *Affects* code that writes design maps or fragments by hand, or matches on the struct.
  *Instead:* write `frames: %{main: %{kind: :cartesian, …}}`, and use
  `Visualize.Chart.Build.in_frame/2` to put fragments under another frame. A whole design
  that says `version: 1` still works: `from_map/1`, `from_json/1`, `apply/2` and
  `compile/2` migrate it first (#479). A fragment carries no version, so it is not migrated,
  and a fragment written with `frame:` is an unknown key. `Visualize.Chart.Applied` gains
  `frames`. Its `frame` is the first frame by name.
- **A design records no size** (#427). A frame has no `size` key and the `:size` node kind
  is gone. *Instead:* pass the host's container as `size: {width, height}` to
  `Visualize.Chart.apply/2` or `Visualize.Chart.compile/2` (or `Visualize.Chart.Frame.new/2`).
  The default is `{600, 400}`. Migration **drops** a version-1 design's `frame.size`. Such a
  design now draws at 600×400 unless you pass `size:`. A version-2 design that still says
  `size` fails validation as an unknown key.
- **`Build`'s frame functions take a name, not a size** (#427, #383).
  `Build.cartesian(width, height, opts)` and the same three-argument forms of `polar`, `geo`
  and `facet` are removed. The two-argument forms now mean `(name, opts)`, so
  `cartesian(600, 400)` raises. *Instead:* `Visualize.Chart.Build.cartesian/0`,
  `cartesian(opts)` or `cartesian(:name, opts)`, and the size at apply.
  `Visualize.Chart.Build.scale/3`, `axis/3` and `legend/2` now write into `frames.main`.
- **`Visualize.Chart.compile/2` returns one compiled chart per frame** (#431, #385). It
  returns `{:ok, %{main: compiled}}` where it returned `{:ok, compiled}`. *Instead:* match
  the frame you want (`{:ok, %{main: compiled}} = Chart.compile(design, opts)`), or map over
  the result for a design of several frames.
- **A compiled chart no longer carries its sources** (#412). The `sources` field is gone from
  `%Visualize.Chart.Compiled{}`. *Affects* code that read `compiled.sources` or matched on
  it. *Instead:* keep the rows you passed. `Compiled.render/2`, `svg/2` and `tick/3` take
  the tick's sources as before.
- **`Visualize.Chart.Builder.Store` is version 2** (#173, D-99, D-100, D-103). The 0.1.0
  callbacks were `list/0`, `get(name)` and `put(name, map)` returning `:ok`. Now:
  - Every callback takes a `context`, and an entry has an id. The callbacks are
    `list(context)`, which returns `[%{id, name, kind}]`, then `get(id, context)`,
    `put(entry, context)`, which returns `{:ok, id}`, `delete(id, context)`, and
    `import(bundle, context)`.
  - An entry is `%{id: nil | id, name, kind, fragment}`. The store issues ids as
    `{kind, n}` and never reuses one. The `name` is a `"group:sub-group:name"` label.
  - The `store` assign may be `{module, context}`.
  - `Visualize.Chart.Builder.Store.relocate/3` is a reference `import/2` over your `put/2`.
  - The kind is `Visualize.Chart.Fragment.kind/1`, one of `Visualize.Chart.Fragment.kinds/0`,
    which has no `:design` (#187). Save a composite; a design is what deploying produces.
- **The builder's save message carries structure, not a flat design** (#178, #183, D-103).
  `{on_save, id, structure}` is now a composite of `Visualize.Chart.Use` sites holding store
  ids. *Instead:* flatten it with `Visualize.Chart.flatten/2`, which returns
  `{:ok, design, report}`. Or handle the new `{on_deploy, id, design}` message, which the
  builder's *Deploy* button sends with the flat design. The tag is the `on_deploy` assign,
  default `:visualize_chart_deployed`.
- **The validator refuses designs 0.1.0 accepted** (#368, D-113; #487, D-122). A reference
  into a declaring map the design never wrote is now reported. For example, `data: :s` with
  no `sources` is `{:undeclared, :source, :s}`, where 0.1.0 treated the missing map as
  unknown. A colour channel's constant value, or a typed column, that a *declared* ordinal
  colour domain can never hold is `{:outside_domain, scale, value}`. *Instead:* declare what
  you reference, and widen the domain or drop the constant.
- **A stack's `:insideout` order is d3's `stackOrderInsideOut`** (#496, D-125). It put the
  heaviest series at the bottom, where the spec said the middle. It now takes the series in
  order of appearance (by the index of each one's peak) and places each on whichever side
  has the smaller running sum, so the earliest-peaking series sits in the middle and later
  ones outward. Any stack ordered `:insideout`, or a design's `:stack` step ordered
  `:inside_out`, stacks in a different order. *Instead:* to keep a fixed order of your own,
  use `order: {:keys, list}` (#492, below).
- **A projection's `phi` and `gamma` are d3's** (#511, D-129). `phi` now tilts the globe and
  `gamma` rolls it, with d3's axes, order and sign. What 0.1.0 called `phi` is now `gamma`
  with its sign flipped, and 0.1.0's `gamma` has no equivalent. *Instead:* a rotation
  `{λ, φ, 0}` from 0.1.0 is `{λ, 0, -φ}` now. `lambda` keeps its opposite-to-d3 sign
  (D-44), so a rotation copied from d3 keeps `φ` and `γ` and negates `λ`.
- **Projected GeoJSON is clipped on the sphere as d3-geo clips it, so winding matters**
  (#509, #510, D-127). `Visualize.Geo.Path` cuts lines and polygons at the antimeridian of
  the rotated frame, and under a `clip_angle` along the small circle. It no longer drops
  vertices. An **anticlockwise ring is the rest of the sphere**, as in d3. *Instead:* rewind
  data in RFC 7946's winding before drawing it (Natural Earth as d3 ships it needs nothing).
  The defaults change too:
  - The azimuthal clip angles are d3's: `90 + 1e-6` for the orthographic, `180 - 1e-3` for
    the azimuthal equal-area and equidistant.
  - `bounds/2` and `centroid/2` read the clipped vertices.
  - A ring that crosses nothing keeps its vertices exactly.
- **The incremental `0x60` scroll record carries its viewport** (#295, D-106). Sixteen more
  header bytes, `vx vy vw vh`, follow the offset, making a fixed 27-byte header. The shipped
  `CanvasIncrementalChart` hook reads it, so this *affects only* a host that decodes the
  stream itself. `Visualize.Backend.CanvasIncremental.encode_incremental/4` takes the
  rectangle as `viewport:`, the whole canvas by default.

### Added

#### Documentation

- **Guides** (#515): [Getting started](guides/getting_started.md),
  [Charts in LiveView](guides/liveview.md), [Designing charts](guides/designing_charts.md)
  and a [cheatsheet](guides/cheatsheet.cheatmd), under *Guides* in the docs. Every Elixir
  block in them and in the README runs in the test suite, so they cannot fall behind the
  code.
- **The README** is a short introduction: what visualize is, why, how to install it and
  run the examples, and where the documentation is.

#### Declarative charts

- **Several frames in one design** (#428, #437, #436, #438). A frame takes a `box` (fractions
  of the render's size), a `z` and a `background`. A design's `layout`
  (`Visualize.Chart.Build.layout/1`: `columns` and `rows` as weights, `gap` in pixels)
  places frames by `cell` and `span` instead of arithmetic. A frame can adopt another
  frame's scale, so two frames share a domain while each keeps its own range
  (`Visualize.Chart.Build.adopt/2`, `{:frame, :main, :x}`). A composite is placed as frames
  by its key. `Visualize.Chart.generate/2` with `root: true` renders a whole design as an
  accessible `<svg>` document (#131).
- **New marks**:
  - `:text` (#337), with edge anchors for the rectangular types.
  - `:needle` (#392, `Visualize.Shape.Needle`).
  - `:tiles` (#475; see *Geo*).
- **`series` is a channel of every mark that draws rows** (#508, D-126). Every element and
  label of a series carries `data-series`, so a legend toggle hides a series' points with its
  line.
- **New data steps**:
  - `:fold` (#240): wide columns to long rows.
  - `:take` and `:window` (#426): the newest rows or a duration back from `now:`.
  - `:spectrum` (#375): a one-sided amplitude spectrum by FFT.
  - `:lttb` and `:m4` (#448): shape-preserving downsampling.
  - `:hexbin` (#353).
  - `:projection` over a geometry column, with the Sphere (#350).
  - A graph's nodes as a second source, and `strength` and `distance` on `:force` (#352,
    D-110).
- **Polar as a coordinate transform** (#390–#393). An angle scale carries `start` and
  `sweep`. Every ordinary mark is laid out in (angle, r) and bent around the arc. A
  categorical angle closes its ring, which gives the radar. Labels take `:outward`/`:inward`
  anchors with `dr`, `rotate` in degrees or `:tangent`/`:radial` (#338), and a
  `{:frame, :center}` anchor (#489).
- **Scales**:
  - Offset scales, a band within a band, which gives grouped bars (#339, D-109).
  - A time scale's display zone (#447; see *Data and scales*).
  - `{:scale, :min}` and `{:scale, :max}` as a channel value, so an area can fill to its
    axis whatever the domain (#420).
  - A `transition` node on a scale or a mark eases a moving domain or value between ticks in
    a compiled chart (#360, #417). `Visualize.Chart.Compiled.step/3` steps one frame, and
    `Visualize.Chart.Compiled.carry/2` keeps the easing across a resize (#434).
- **Styles**:
  - Gradients in `defs`, used as `{:paint, name}`; see `Visualize.Chart.Build.gradient/3`
    and `paint/1` (#133, #219).
  - A fill style; a stroke style of single, double, inside or outside (#218); blend mode and
    shadow or blur effects (#220).
  - `font_style` and the weight words (#217).
  - Multi-line text with `line_height` (#221); `vertical_align`, `margin_x`, `margin_y` and
    `text_angle` (#222).
  - A style site takes a stack of styles (D-98).
  - `:contrast` as a colour (#486, D-123): the theme's text or background, whichever reads
    against the fill under the label, with WCAG AA guaranteed. See
    `Visualize.Theme.ink/2`.
  - A mark label's `fit`: `:truncate` or `:hide` (#138).
- **Axes and legends**: a legend outside the plot with `inside: false` (#347); `prefix` and
  `unit` on an axis or legend (#351); `format: :duration` on an axis
  (`Visualize.Format.duration/1`, #191).
- **Typed columns** (#369): a source's `types` declares each field as `:time`, `:number`,
  `:category` or `:text`. See `Visualize.Chart.column_type/3` and
  `Visualize.Data.Table.column_types/1`.
- **Sync groups share hover** (#466, D-116). A design key, `interaction: %{sync: "<group>"}`,
  makes charts on one page share a cursor. Hovering one moves the crosshair and the tooltip
  of every other member to the same x in domain units, through each chart's own scale, so
  members may differ in width and margin. No host JavaScript is needed: the frame renders
  `data-vis-sync` and `data-vis-sync-x` (`Visualize.Chart.Frame.sync_attrs/1`, also in
  `Visualize.Hooks.Crosshair.attrs/3`), and `TooltipHook` and `CrosshairHook` exchange
  `vis:sync:<group>` events on `document`. Only a linear or time x can join a group. The
  validator refuses any other kind as `{:sync, :x_scale, kind}`.
  `Visualize.Chart.Build.interaction/1` writes the key. A chart's `to_map/1` and JSON now
  carry `interaction` (default `%{}`).
- **Sync groups share the brush** (#467, D-117). A window brushed on one member shows as a
  band on every other, and only the chart brushed pushes to its server. The bus is
  `Visualize.Hooks.Sync.js_bus/0`, bundled ahead of the hooks that use it.
- **A stack order fixed by explicit keys** (#492). `Visualize.Shape.Stack.order/2` and a
  design's `:stack` step take `{:keys, list}`, the listed keys bottom first and every key
  the list leaves out above them in key order; a listed key the stack lacks is ignored.
  Every other order is computed from the data each call is given, so over an animated or
  streaming source `:inside_out` re-sorts per frame and layers swap places; a fixed order
  computed once does not. In JSON it is `{"$keys": [...]}`. A `:sort` step's `order` is
  still a direction alone.
- **Use sites and composites** (#174, #186, #188, D-101, D-102). A composite is a list of
  `Visualize.Chart.Use` sites: a reference, a local body, a mask and bindings, resolved
  `ref → local → mask → bind`. See `Visualize.Chart.bind/2`, `mask/2` and `resolve/2`, and
  `Visualize.Chart.flatten/2`, which turns a composite into a flat design through a fetch.
  `Visualize.Chart.Fragment` and `Visualize.Chart.Composite` hold the walks.
  `Visualize.Chart.Validator.validate/2` validates a fragment as its kind.
- **A public JSON codec for fragments** (#465). `Visualize.Chart.Fragment.to_json/1` and
  `from_json/1` write and read any fragment, a composite of use sites holding ids included,
  in the JSON form spec/14 §19.7 specifies (`$use`, `$id`). It is not validated as a design,
  since a fragment may be partial. A store that keeps its library in a database can now
  persist what `Store.put/2` hands it. `Chart.from_json/1` validates a whole design and so
  refuses a composite, and the codec under both was private.
- **Node paths on request** (#260, D-105). `paths: true` on `Visualize.Chart.Frame.generate/2`
  stamps `data-node` on everything a frame draws. The default render is unchanged.

#### Rendering and backends

- **`Visualize.Render.to_png/2` and `to_png!/2`** (#473, #474, #481, D-121). A root IR
  element, or the SVG string it renders to, is rasterised to a PNG by the **resvg
  command-line tool**, run as an OS process over a port.
  - **No Hex dependency.** The host installs resvg 0.45 or later (`apt install resvg` on
    Debian and Ubuntu, the upstream release tarball, or `cargo install resvg`). Name it with
    `config :visualize, :resvg, "/path/to/resvg"`, or leave it on the `PATH`.
  - **When resvg is missing or too old.** Without one, the result is
    `{:error, :no_rasterizer}`. An older one gives
    `{:error, {:rasterizer_version, found, required}}`.
  - **Isolation.** A render holds no BEAM scheduler, cannot crash the VM and writes no temp
    file.
  - **Options.** `scale:` is the device pixel ratio and `background:` a CSS colour.
    `timeout:` (default 30 s) bounds the render: on expiry resvg is killed and the result is
    `{:error, :timeout}`.
  - **Literal colours only.** Generate the SVG with `resolve: :literal`. A `var(--…)` theme
    reference returns `{:error, :css_references}`, since resvg would paint it black.
- **PNG fonts and warnings** (#474, #481). `to_png/2` takes the font configuration:
  `font_dirs:`, `system_fonts:` (default `true`) and `generic_families:` (resvg's defaults,
  where `sans-serif` is Arial). `font_family:` covers text that names none (default
  `"sans-serif"`). resvg loads the fonts on each call, so a font added to a directory is seen
  by the next render.
  - **The success value is `{:ok, png, warnings}`**, resvg's own report. There is one
    `{:missing_family, list}` per font-family list no font resolves, whose text was left
    out, and `{:rasterizer, line}` for anything else resvg printed.
  - `to_png!/2` raises when there is a warning.
  - The gallery has raster goldens, rendered with a bundled DejaVu Sans and no system fonts.
- **A compiled chart's backdrop** (#476, D-120). `Visualize.Chart.Compiled.backdrop/1`, and
  the `backdrop` key of `render/2`'s map and of `tick/3`'s payload, hold a `:tiles` mark's
  images as an SVG document. A page stacks it *beneath* the canvas, so a dense track drawn
  on the canvas sits on its basemap.
  - The attribution stays in the SVG layer over the canvas.
  - `Compiled.static/1` no longer holds a static basemap's images. A page that draws tiles
    on the hybrid split stacks the backdrop.
  - The binary stream still drops `:image` and gains no record for it.
- **A theme's `:surface` slot** (#422). It is the plane a chart's data is laid on, between
  the background and the grid: `#eef2f6` on `Visualize.Theme.default/0` and `#23272f` on
  `dark/0`. It is a colour slot like any other. `slots/1` and `colour_slots/1` list it, and
  `resolve/3` gives `var(--vis-surface, …)` on SVG and the literal on canvas. An inline
  `:theme` node takes a `surface` key. A theme from `new/1` that names none takes the light
  value, as it does for every field it leaves out.
- **A reference decoder for the binary canvas stream**
  (`Visualize.Backend.CanvasBinary.Decoder`, #291).
- **New IR primitives**: `Visualize.IR.Element.clip/3`, `filter/2`, `drop_shadow/3`,
  `gaussian_blur/1`, `tspan/2`, `put_attr/3`, and `Visualize.IR.Path.from_commands/1`.

#### LiveView and hooks

- **Frame acknowledgement** (#305, #307, #322, D-107). `CanvasIncrementalChart` and
  `CanvasBinaryChart` acknowledge each payload's `seq` when their element carries
  `data-ack`. A producer can then bound frames in flight, and a hold times out rather than
  stall. This is opt-in, and existing uses are unchanged.
- The sync-group hover and brush above need no host JavaScript beyond the shipped hooks.

#### Geo

- **Basemap tiles** (#475, #476, D-119, D-120). A `:tiles` mark draws Web-Mercator tiles
  beneath a geo frame's other marks, at the nearest zoom, over a projection fitted without
  moving its centre. See `Visualize.Geo.Tiles` (`aligned/1`, `zoom/2`, `cover/3`, `url/3`).
- `Visualize.Geo.Projection.sphere/1` (the outline of the visible globe), `fit/3` and
  `precision/2`, and `Visualize.Geo.Path.path/2`.

#### Data and scales

- **Time zones** (#447, D-115). `Visualize.Scale.Time.zone/2` (and `Visualize.Scale.zone/2`,
  or a design's `zone` key) ticks on local calendar boundaries across DST. It reads the
  zone through the host's configured `Calendar.TimeZoneDatabase`, so the library takes no
  dependency for it.
  - A zone the database cannot show raises `ArgumentError` at the setter, and in a design
    it is `{:zone, name, reason}`.
  - Without a zone, every tick is the UTC one byte for byte.
  - `Visualize.Scale.Time.local/2` converts a value into the scale's zone.
- **Downsampling**: `Visualize.Data.lttb/3` and `Visualize.Data.m4/3` (#448).
- **`Visualize.Data.FFT`** (`fft/1`, `spectrum/3`, `window/2`, #375).
- **`Visualize.Signals`** (#247): deterministic sine, square, random and discrete sources
  over a sliding window, for a chart that moves without a host feed.
- `Visualize.Format.duration/1` (#191), `Visualize.Layout.Hexbin` (#353), the closed curves
  `Visualize.Shape.Curve.basis_closed/1` and `cardinal_closed/2` (#393),
  `Visualize.Shape.Arc.angles/2` and `radii/2`, and `Visualize.Contour.cost/2` (#462).
- **A force simulation's subscribers at start** (#483): `Visualize.Layout.Force.Simulation.start_link/1`
  takes `subscribers:`, pids registered before the first tick, so a subscriber sees every
  tick from the first. `subscribe/2` still joins a running simulation.

#### Builder

- **The builder became an editor of typed fragments** (#142–#388, spec/14 §18–§19).
  - **Layout.** It ships its own stylesheet, rendered inline. `styles={false}` turns that
    off, and the host then serves `Visualize.Chart.Builder.css/0` itself (D-94). The
    workspace holds several charts beside a library tree.
  - **Library entries.** A library drop arrives linked. Unlocking it copies the body into
    the site, and a site can mask paths and bind variables.
  - **Editing.** It has a Variables tab, a style form, a data page with typed columns and
    generated signals, axes ticked per side, and "add data / add a mark / add axes" steps.
  - **Saving.** *Save* sends structure; *Deploy* sends the flat design (above).
  - **New assigns:** `on_deploy`, `source_defaults`, `tick_ms` and `styles`.
  - **Import and export.** These move bundles: `Visualize.Chart.Builder.Bundle.export/3`,
    and the store's `import/2`.
- **A referenced group expands in the builder's tree** (#388). A library composite dropped
  linked now carries the ▸ and the count of its entry's sites. Opened, it draws them beneath
  its row, muted and locked, each tagged with the entry's name.
  - They are the library's, so they take no flat position of their own. A click, a drag or
    the menu on one acts on the group.
  - A drop into the group is refused with *name is from the library — open it to edit*.
  - `Visualize.Chart.Builder.Stack.all/2` is new: the tree's rows, with each referenced
    group's inside fetched and each row naming its `owner`. So are `inside/2` and
    `inner_label/3`.

### Changed

- **A colour outside its domain is the scale's `unknown`** (#487, D-122). A `color` ordinal
  scale that gives no `unknown` now takes the theme's `:axis` colour. In 0.1.0 its `unknown`
  was `nil`, so the element got no fill: SVG painted it black and a canvas drew nothing. A
  series line outside the domain is drawn in that neutral, not in the series colour of its
  position. Say `unknown: :none` on the scale to hide such values. A missing colour is now
  bound as `:none`, which draws nothing on SVG and canvas alike.
- **The pie, sunburst and treemap components ink their labels by contrast and fit them**
  (#494, #497, D-123). Their labels are now `:contrast` with the gallery's `fit` (`:hide` on
  the pie, `:truncate` on the sunburst and treemap), so a label too big for its slice is
  hidden or cut. The markup of those labels changes. Every path and the rest of the shell are
  byte for byte as before.
- **A labelled mark is a wrapper of two groups** (#485). The elements are in a styled group
  and the labels in an unstyled sibling group, so labels no longer inherit the mark's
  stroke. The wrapper keeps the mark class, `data-node`, the tooltip attributes and the
  centring transform.
- **An area's default baseline is the y scale's zero clamped to the plot** (#420). An area
  over a domain that excludes zero no longer fills into the margin. An explicit `y0` is
  placed as given.
- **A line whose style gives a fill draws the area under it, down to the baseline** (#232),
  where it used to fill the polygon between the curve's ends.
- **A `:chord` step centres on the plot, as an arc mark does** (#488). Its `size` sets the
  radius only.
- **The builder's `layers` assign seeds the stack and does not control it** (#144, D-95).
  An unrelated host render no longer resets an editing session. A changed list is adopted.
- **The canvas hooks size the canvas to `data-width` × `data-height` at every draw** (#456).
  A resize clears it, and the incremental hook draws no scroll record until a full frame
  follows.
- **A canvas draws by the effective style** (#231, D-111). A mark whose paint sits on its
  group draws on canvas as on SVG. The binary stream gains one style record per mark group.

### Fixed

- **A drop below a closed group in the builder's stack lands where it was aimed** (#468).
  `BuilderHook` counted the drawn rows to name a drop's position, while every flat position
  the builder reads counts a closed group's rows too. So a drop between a closed group and
  the row after it landed inside the group, and a group dropped directly below itself moved.
  - A stack row now carries `data-builder-end`, the flat position past everything it holds,
    beside its `data-builder-layer`. The hook reads both instead of counting.
  - The gap before a row is its position, and the gap at the end is the last row's end.
  - A move shifts by the rows the dragged one lifts out.
- **A composite exports and imports with its references** (#470). `Fragment.refs/1` and
  `relocate/2` treated every struct as a leaf. A composite's sites are `%Use{}` structs
  holding ids in `ref`, `origin`, `local` and `vars`. So `Bundle.export/3` of a composite
  left out what its uses referenced, and an import left it pointing at the source store's
  entries. The two id walks now read a use's parts. Every other walk still stops at a
  struct (D-92).
- **A glyph carries no id** (#471). The `:linear` and `:radial` fill-style pictures and the
  `:blur` effect drew an inline `<defs>` with a fixed id. The editor shows a glyph once per
  choice and per open row, so a page repeated the id, which LiveView refuses
  (`Duplicate id found … vis-glyph-linear`). They are now translucent bands and squares,
  with no paint server and no filter. The glyph test also walks the four drawn keys it had
  skipped (`fill_style`, `effect`, `vertical_align`, `stroke_style`).
- **A version 1 design read from JSON migrates** (#479). The codec typed every key by the
  current schema, so a v1 design's `frame` kept string values and failed validation once
  migrated to `frames.main`. So JSON-stored designs from before #383 couldn't be read, which
  contradicted §9.
  - `Migration.legacy_type/2` gives a removed key its old type, and the codec reads by it,
    so the document is typed before it is migrated.
  - §14.4 also corrects `current/0` to `2`.
- **An adopted scale has a JSON form** (#480). A frame adopting another frame's scale
  (`{:frame, :main, :x}`, §4.3) had no JSON form, so `Chart.to_json/1` raised on any design
  with an adoption, and the design couldn't be stored by a host or the builder's store. It
  now encodes as `{"$adopted": ["main", "x"]}` and reads back. A tagged object is never
  read as a node.
- **The default tick label prints a float in plain decimal** (#354), never `1.0e3`.
- **A compiled chart resolves a mark's paints and carries the design's defs** (#356). A
  gradient fill was black on the canvas and unrenderable on the SVG layer.
- **The binary canvas stream encodes `line`, `polyline`, `polygon` and `ellipse`** (#290).
  The encoder silently dropped them, so an axis's ticks drew nothing on a binary canvas.
- **A contour ring always closes** (#81, D-112). A crossing never sits on a grid corner, and
  a ring closes on its exact start.
- **`compose/2` no longer merges a whole-node variable into a `:union` key** (#120, D-92). It
  could produce a struct with foreign keys.
- **`CrosshairHook` measures the chart, not its container** (#507). Its markers sat a few
  pixels off the series under an inline `<svg>` or `<canvas>`.
- **Cost**:
  - Building a path is linear in its commands; it was quadratic (#414).
  - A scroll tick costs the strip and its neighbours, not the window (#333, #404, #410,
    #423, D-108).
  - The incremental window keeps no closure, so a scroll's cost no longer doubles every
    frame (#406).
  - The `:natural`, `:basis_closed` and `:cardinal_closed` curves are linear (D-114).
- **Documented examples run** (#117, #121, D-90, D-93). Every `iex>` example under `lib/` is
  a doctest, and the three that were wrong are corrected.

## [0.1.0] — 2026-09-09

`0.1.0` is the first tag. Until it, the only way to depend on this library was
`branch: "main"`, so everything below has already reached anyone tracking that branch — the
sections are therefore written as they will read from the tag onwards: **Added** is the
surface a new consumer gets, and **Changed** and **Fixed** are what moved under a consumer
who was following `main` and now has a point to pin.

Pre-1.0. The surface can still move; a breaking change opens `0.2.0` rather than bending
the meaning of a patch.

### Added

- **The declarative chart layer — `Visualize.Chart`.** A chart is a **design**: a plain map
  of atoms, numbers, strings and `Visualize.Chart.Var` placeholders, with no functions and
  no structs in it, so a design can be stored, diffed, sent over the wire, versioned and
  edited by something other than code (D-57). The imperative pipeline —
  `Scale` → `Shape` → `IR.Element` → `Render` — is unchanged and remains the layer this one
  is written on; nothing about the chart layer is mandatory.

  - `Visualize.Chart.Schema` is the design's grammar **as data**. Every key carries a facet
    (`:data`, `:geometry`, `:channel`, `:binding`, `:style`, `:meta`) and a merge rule, so a
    validator, an editor and a composition operator all read the same description instead of
    each carrying their own copy of it (D-58). `Schema.describe/1` is what the builder's UI
    is generated from.
  - `Visualize.Chart.Validator` checks a design against the schema and reports **by path** —
    `[:marks, 2, :channels, :y]` — rather than by message, so an editor can put an error
    next to the field that caused it.
  - **Frames** own the scales. A frame declares named scales whose domains may be `:auto`,
    realises them **once** from the whole bound column, never widens them afterwards, and
    renders its own furniture — axes, grid, legend, labels — with or without data (D-60).
  - **Marks** are the generators, named: `:line`, `:area`, `:band`, `:rule`, `:x_band`,
    `:percentile_band`, `:rose`, `:symbol`, `:arc`, `:path`, `:rect`, `:circle`. A mark
    names the scale each channel family reads through (D-61, D-67), and takes its paint from
    the theme's series.
  - **Transforms** are pure steps over rows, run by the frame *before* its scales are
    realised, so a transform can change what the domains infer from (D-62):
    `:filter`, `:bin`, `:stack`, `:sum`, `:sort`, `:tree`, `:cluster`, `:pack`,
    `:partition`, `:treemap`, `:chord`, `:sankey`, `:force`, `:contour`, `:density`,
    `:delaunay`, `:voronoi`, `:projection`.
  - **Styles and themes.** A style node resolves to two outputs — literal attributes for
    SVG, and CSS custom-property references for a themed page — and binds its field
    references per element (D-63). `Visualize.Theme` carries the slots; a slot renders as
    `var(--vis-…, <literal>)`, its literal always present as the fallback, so a page that
    ships no stylesheet still draws in colour (D-55).
  - **Templates**: typed source slots and `Visualize.Chart.Var` variables, bound by
    `Chart.apply/2`. A variable's default lives in its declaration, and a stored design
    keeps what its author wrote rather than being rewritten with defaults (D-59).
  - `Chart.compile/2` splits a chart into the regions that are static and drawn once and
    those that are dynamic and carry a closure, fixes each mark's render target at
    compilation, and gives the streaming window its own plot-area canvas (D-66).
  - `Chart.to_map/1`, `from_map/1`, `to_json/1`, `from_json/1` — JSON carries what JSON
    cannot hold (dates, tuples, atoms) as tagged terms, and the round trip is the identity
    (D-57). JSON needs the optional `:jason` dependency; without it the two JSON functions
    return an error value rather than failing to compile.

- **The fragment algebra — `Visualize.Chart.Build` and the operators on it.** A **fragment**
  is a partial design, and the algebra is what makes designs composable rather than merely
  storable.

  - `Visualize.Chart.Build` builds fragments through one function per schema node — a
    function per mark type, transform op and scale kind, **generated from the schema** so
    the builder cannot drift from the grammar it builds (D-79). Every option is a key of the
    node the function builds (D-78).
  - `Chart.compose/1,2` merges fragments key by key under the schema's merge rules.
    `Chart.stack/1,2` is a **second** closed operation over the same values: a cascade, where
    a higher layer overrides a lower one and the result is itself a fragment, so a stack of
    stacks is a stack (D-81). Composition unions; a cascade overrides. They are different
    questions and now have different operators.
  - **Element identity.** A mark's or label's identity is its `id`, an axis's is
    `{scale, side}`, and a matched element is replaced whole rather than deep-merged
    (D-82) — which is what lets a layer say "this one, replaced" without saying it by list
    position.
  - `Chart.explain/1` reports **provenance**: which layer each key in the result came from,
    computed from the layers rather than carried in the fragment (D-83).
  - `Chart.free_vars/1` reports the variables a design still needs, walking exactly where
    application walks; a variable bound to another variable is an error reported by path
    (D-84).
  - `extends:` on a style derives it from a parent, flattened at the lookup rather than at
    write time, so a change to the parent reaches its children (D-80).

- **`Visualize.Chart.Builder` — an embeddable LiveComponent for building designs.** Optional
  in every sense: it needs LiveView, which is an optional dependency, and it is a component
  the host mounts rather than a route the library owns. Its only output is one message to
  the host, which owns the route, the storage (`Builder.Store`) and the meaning of saving
  (D-85). The editor's nodes, controls and widgets are generated from the schema's types,
  and a composite value is read as a literal and **never evaluated** (D-86). The stack panel
  shows the layers — disabling a layer is not deleting it — the inspector is `explain/1`
  rendered, and the parameters form is `free_vars/1` rendered, editing the builder's own copy
  of the bindings (D-87, D-88). Import and export move a design as JSON.

- **New marks:** `Visualize.Shape.Band` (a state timeline: one `:rect` per datum,
  index-aligned — D-26), `Visualize.Shape.Rule` and `Visualize.Shape.XBand` (annotations
  that take domain values and a scale, not pixels — D-27),
  `Visualize.Shape.PercentileBand` (a composition with a fixed output shape — D-28), and
  `Visualize.Shape.Rose` (`Arc` over a radial scale — D-31).

- **New scale:** `Visualize.Scale.Radial`, an angle scale whose ticks divide the turn and
  whose `nice/1` is the identity, because there is no nicer boundary on a circle than the
  one you asked for (D-30).

- **Interaction hooks — `Visualize.Hooks`.** `Zoom` and `Brush` (with one-axis selection
  helpers that work on the axes they are given — D-29), `Resize`, and the three canvas hooks
  `CanvasChart`, `CanvasBinaryChart` and `CanvasIncrementalChart` (D-40). New in this
  release: `Tooltip`, which reads the datum's own fields from data attributes the **server**
  wrote on the element (D-75); `Crosshair`, which snaps to an array the server wrote once and
  draws in an overlay it owns rather than in the patched subtree (D-76); and `Legend`, where
  an entry and its series path carry the same `data-series` and toggling hides with
  `display` (D-77). The pattern throughout: **data attributes are the contract**, and a hook
  draws outside the subtree LiveView patches.

- **Tabular ingestion — `Visualize.Data.Table.rows/1`.** One door for tabular data: row
  lists, column maps, Nx tensors, Explorer data frames and anything else implementing
  `Table.Reader` (D-52). Every generator, compute and component reads its data through it
  (D-53), so a data frame is accepted wherever a list of maps is. The `:table` package is
  optional, like Nx; without it lists, column maps and tensors still work and a struct
  source raises at the call.

- **Themes and accessibility.** `Visualize.Theme` with a light and a dark palette and a
  generated stylesheet; responsive sizing as two halves — `ResizeHook` for the round trip
  and `viewBox` scaling for everything between (D-54); and a chart that names itself, with
  `<title>`, `<desc>` and `role="img"` on the root and `aria-hidden` axes (D-56).

- **Ten preset chart components** (`Visualize.Chart.Presets`): line, bar, horizontal bar,
  pie, scatter, area, stacked bar, tree, treemap and sunburst — each a preset design plus an
  assign mapping, drawn by the chart layer into the same markup the hand-written components
  always produced (D-64), and byte-identical to their goldens.

- The specification ships with the package (`spec/`), together with `API_SURFACE.md`, a
  generated golden that lists every public function the specification declares against every
  public function `lib/` defines. A function in `lib/` with no row is `unspecified`; a row
  with no function is `unimplemented`; either fails CI. It is the contract a consumer holds
  the library to, so it ships.

- `LICENSE` — MIT — and `package/0` now declares `licenses: ["MIT"]`. Before this the
  licence was unstated to anyone who received the package.

### Changed

- **`Visualize.Render.with_backend/2` is removed** (D-2). It set a backend in the process
  dictionary for the duration of a function, so any render inside that function silently
  used a backend chosen somewhere else, and restoring the previous value needed `try/after`.
  A backend is now selected only by the `:backend` option at the call site or by
  `config :visualize, default_backend:`. **Code that rendered inside `with_backend/2` must
  thread `backend:` through instead.**

- **`Shape.Stack` returns its series in key order**, not in stacking order, and each series
  carries `index`, its position in the stack (D-22). A caller that indexed the returned list
  by stacking position must read `index` instead. `:diverging` and `:wiggle` are now ports
  of d3's `stackOffsetDiverging` and `stackOffsetWiggle`; previously `:diverging` did not
  accumulate negatives and `:wiggle` was `:silhouette` under another name.

- **A collapsed domain maps to the range midpoint** in every continuous scale, and nothing
  raises (D-49). `Linear` and `Time` previously raised `ArithmeticError` on a single-datum
  extent or an all-zero `[0, 0]` domain; `Power` and `Symlog` returned the range **start**.
  All five now return the midpoint, as d3 does — a single-datum chart draws its point in the
  middle of the axis. Callers that widened collapsed domains by hand no longer need to.

- **`:top` axis labels moved off the plot, and band ticks moved to the centre of the band**
  (D-23). A `:top` axis's labels shift by `2·(tick_size_inner + tick_padding)`; every band
  axis's ticks shift by half a band. A caller who had added `bandwidth / 2` through
  `offset/2` to centre ticks by hand is not double-shifted, but should drop the workaround.

- **Negative zero is folded** in the `d` serialisers, so a coordinate that rounds to zero
  prints `0` and never `-0` (D-32), and in the projection golden, where the sign of zero is
  not a property of the maths (D-6). Path strings that differed only in a minus sign before a
  zero are now stable across refactors.

- **One `d` serialisation.** There were two path serialisers producing different strings for
  the same path; there is now one, behind both the SVG bridge and the IR (D-12, D-34, D-71).
  The tree components' link paths therefore print in the comma-separated form (D-71, #79);
  goldens that recorded the old form were regenerated.

- **Time ticks follow d3-time**: boundary snapping on every interval, ratio-based interval
  choice, clamped month stepping and multi-year intervals (D-16). A time axis that previously
  produced unsnapped or wrongly-spaced ticks produces d3's.

- **`Format.number/2` groups the magnitude**, `Format.formatter/1` is a parser for d3-format
  specifiers, and `Format.time/2` is a one-pass strftime tokenizer (D-24, D-25) — where
  before each was an approximation.

- **The scale protocol is a behaviour**, and every scale stores lists (D-15).
  `Power`, `Symlog`, `Quantile`, `Quantize` and `Threshold` implement it, so
  `Scale.apply/2`, `ticks`, `nice`, `invert` and `bandwidth` work uniformly across every
  scale type — which is what lets `Axis` stop special-casing scale kinds.

- **`Layout.Force`'s many-body force has no `:theta`** (D-4). The option was accepted and
  ignored — there is no quadtree behind it — so it is removed rather than left inert. The
  force is exact, O(n²) per tick. Passing `:theta` is now a programmer error.

- **`Geo.Projection.clip_angle/2` clips.** The value was stored and never read, so
  orthographic globes drew the back of the world over the front (D-3). `project/3` now
  returns `nil` beyond the clip angle, and azimuthal projections take d3's per-type defaults.
  **Callers that project points beyond the horizon now receive `nil` and must handle it**;
  `Geo.Path` drops them.

- **Phoenix is optional and stays optional** (D-7, D-45). `Visualize.Components`,
  `Visualize.Components.Tree`, `Visualize.Chart.Builder` and the `Phoenix.HTML.Safe`
  implementations compile only when `Phoenix.Component` is loaded; a host without LiveView
  never fetches Phoenix. The same holds for Nx, `:jason` and `:table`, and a consumer check
  runs on every pipeline to prove it.

- `Geo.Projection` and `Backend.CanvasBinary` were split into family modules, which are
  `@doc false` internals rather than public API (D-9).

- The canvas binary format gained **f32 path records** (`path32`, `path_cubic32`), which are
  the encoder's default because canvas coordinates are pixels (D-73), and a **compact
  cubic-run record** with no sub-opcodes, because that is what every curve generator emits
  (D-74). The decoder round-trips both.

### Fixed

- **`Visualize.Components` never rendered.** The component layer called a `Scale` API that
  did not exist; every component raised. It was rewritten against the real API and is now
  held by render goldens (#43). `Visualize.Components.Tree` — tree, treemap and sunburst —
  was rewritten the same way and now honours `colors` and `label` (#44, D-46).

- **`Geo.Delaunay` was not a Delaunay triangulation.** It is now Bowyer–Watson with an
  orientation-normalised in-circle test and half-edges (D-43), which also makes
  `Geo.Voronoi` correct.

- **The hierarchy, sankey and pack layouts are now ports of d3's.** `Layout.Hierarchy` gained
  `path/2` and `stratify/2`; the tidy tree is Buchheim; `Partition` and `Treemap` keep
  zero-valued children (D-41); `Sankey` has d3's alignments and one link scale; `Pack` is
  d3's `packSiblings`/`packEnclose` with a deterministic fallback (D-42).

- **Projection rotation now inverts in reverse order**, the collision force pushes **both**
  nodes rather than one, and every computed range has a step — the `0..-1` empty-range class
  was swept out of the tree (D-44).

- **Transverse Mercator `invert/3` no longer raises.** It raised `ArithmeticError` away from
  the central meridian; it is now d3's spherical inverse, returns `nil` outside the
  hemisphere, and the forward projection clips (D-5, D-51). The projection golden records the
  inverse instead of excluding it.

- **`Line` and `Area` break into subpaths at undefined data** instead of drawing through the
  gap (D-18); `Curve.natural/1` is the natural cubic spline, solved rather than approximated
  (D-19); `Curve.basis/1` is d3's `curveBasis`, which previously skipped a B-spline segment
  and started and ended in the wrong place (D-33); the step curves emit d3-identical paths
  (D-8); `Line.x/1` and `Line.y/1` accept constants, and `LineNx` honours `:curve` (D-20).

- **`Shape.Arc` applies `corner_radius` and `pad_angle`** (D-21). Both were accepted and
  ignored.

- **Band, quantize, colour, ordinal, linear, log and symlog tick defects**, and a crash in
  `Data.ticks/3` (D-17, #24).

- **`IR.Transform.scale/2`'s pipeline form** raised `FunctionClauseError` because a guard
  ordering made its second clause unreachable (D-1). `IR.Path.transform/2` now takes a full
  affine matrix (D-35).

- **`SVG.Element.from_ir/1` renders `view_box` as `viewBox`** — attribute names go through
  one map, so casing cannot differ between the two bridges (D-11, D-34).

- **`Backend.Canvas` emits executable commands** and group styles; the `CanvasIncremental`
  and `Incremental` contracts were made to match the code; `Benchmark` measures elapsed time
  with its own clock (D-37, D-38, D-39).

- **`Hooks.js_code/0` emitted every hook twice**, as duplicate named exports, which is a
  syntax error in a JavaScript module (D-48); and `BrushHook` leaked its listeners, because
  it removed handlers it had never bound — it now stores the bound handlers and removes
  those (D-47).

- **`Contour.Density.compute/2` took minutes on its default grid.** The grid is now an
  indexed structure and the ring tracing takes each segment once; a list read by index was
  the whole cost (D-72).

- **`Shape.LineNx` warned at compile time in a consumer without Nx** — nine warnings, not
  the one first reported. Both Nx-calling modules declare `@compile {:no_warn_undefined, Nx}`
  and a consumer check fails on any `warning:` line from the library's compile (D-50).

- `Data.range/3` and a set of dead clauses across the tree; the force simulation's timer
  discipline — tagged ticks, restart keeps the state, alpha is clamped — under an ExTLA
  model that is checked in CI (D-14).

[Unreleased]: https://gitlab.conet.yarina.org/dco-tek/visualize/-/compare/v0.2.35...main
[0.2.35]: https://gitlab.conet.yarina.org/dco-tek/visualize/-/tags/v0.2.35
[0.2.25]: https://gitlab.conet.yarina.org/dco-tek/visualize/-/tags/v0.2.25
[0.2.4]: https://gitlab.conet.yarina.org/dco-tek/visualize/-/tags/v0.2.4
[0.2.0]: https://gitlab.conet.yarina.org/dco-tek/visualize/-/tags/v0.2.0
[0.1.0]: https://gitlab.conet.yarina.org/dco-tek/visualize/-/tags/v0.1.0
