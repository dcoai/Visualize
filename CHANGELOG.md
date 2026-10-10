# Changelog

All notable changes to Visualize are recorded here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Note.** This file is written for a consumer of the library, so it says what changed in
> the surface and in behaviour, not what changed in the repository. What the library *is*,
> module by module, lives in [`spec/`](spec/README.md), which is the source of truth for
> that and is not restated here.

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

[0.2.4]: https://gitlab.conet.yarina.org/dco-tek/visualize/-/tags/v0.2.4
[0.2.0]: https://gitlab.conet.yarina.org/dco-tek/visualize/-/tags/v0.2.0
[0.1.0]: https://gitlab.conet.yarina.org/dco-tek/visualize/-/tags/v0.1.0
