defmodule Visualize.Theme do
  @moduledoc """
  The colours, font and sizes a chart draws with (spec/08 §7).

  A theme is a struct of named *slots*: `:series_1` … `:series_n` for the categorical
  colours, `:axis`, `:grid`, `:text`, `:background` and `:surface` — the plane the data is laid
  on, between the background and the grid — the five **roles** `:good`, `:warning`, `:bad`,
  `:info` and `:neutral`, and `:font_family`, `:font_size`, `:label_size` and `:title_size`.
  Its colors are one **color table** (spec/08 §7.1, D-173): the theme's own `colors` — its
  hues, such as `:red`, and names by use, the roles among them — over the default theme's
  and the CSS named colors, with the furniture and the series as names too, so
  `Visualize.Color.color(:red)` is the theme's red.
  Nothing in the library carries a colour literal; every axis, mark and component reads its
  values through `resolve/3`, in the mode its render target needs:

    * `:literal` - the stored value, which a canvas needs
    * `:css` - a custom-property reference with the literal as its fallback,
      `var(--vis-axis, #666666)`, which the SVG output carries so a stylesheet can
      override it from any ancestor (D-55)

  `stylesheet/1` writes a `.vis-theme-<name>` rule declaring every slot, so a consumer
  switches every chart under an element of that class without touching Elixir.

  ## Meaning: ramps and roles

  A series colour promises *distinct*, never a meaning. A theme also carries four
  **ramps** whose meaning the library fixes (spec/08 §7.5, D-135) — `:status` (good →
  caution → bad), `:thermal` (cold → neutral → hot), `:diverging` (below → at → above a
  midpoint) and `:sequential` (less → more) — each a list of anchor colours interpolated
  in CIE Lab. `{:ramp, name, t}` is the colour at `t` in `0..1`, and the status roles are
  by default fixed points on the status ramp: the table holds `:good` as
  `{:ramp, :status, 0}`, `:warning` as `0.5` and `:bad` as `1`. Every ramp and role is checked against its contract — hue order,
  lightness direction, a neutral midpoint — when a theme is built by `new/1` or `merge/2`,
  and a theme that breaks one raises `ArgumentError` naming the ramp and the term broken.

  ## Whole styles: the style palette

  `styles` carries the same design over to whole styles (spec/08 §7.7, D-171): style series
  `:style_1` … `:style_n`, which `{:style, i}` cycles over; the five roles as whole looks;
  the view states `:hover`, `:focused`, `:selected`, `:active`, `:disabled`, `:muted`,
  `:emphasis` and `:breakpoint`; the furniture styles `:axis`, `:grid`, `:label`, `:title`,
  `:caption`, `:value` and `:annotation`; and the modifiers `:bold`, `:italic`, `:thin`,
  `:thick`, `:dashed`, `:dotted` and `:outline`, each changing one thing (D-172). Entries
  are style nodes in their parts (`fill`, `stroke`, `font`, …) written in slots, the names
  are the library's, and each entry is held to its group's contract when a theme is built.
  `style/2` reads one, the default theme's where the theme lacks it.

  ## Examples

      iex> Visualize.Theme.resolve(Visualize.Theme.default(), :axis, :css)
      "var(--vis-axis, #666666)"
      iex> Visualize.Theme.resolve(Visualize.Theme.dark(), {:series, 11}, :literal)
      "#7fb3e6"
      iex> Visualize.Theme.new(font_family: "Inter, sans-serif").font_family
      "Inter, sans-serif"
      iex> Visualize.Theme.resolve(Visualize.Theme.default(), :warning, :literal)
      "#bd7407"
      iex> Visualize.Theme.resolve(Visualize.Theme.default(), {:ramp, :status, 0.5}, :css)
      "var(--vis-warning, #bd7407)"

  """

  alias Visualize.{Backend, Color}
  alias Visualize.Chart.{Migration, Style}
  alias Visualize.Theme.{Contract, Palette, Roles}

  @light_series ~w(#3b6fa8 #d9730d #c8373b #2f8f86 #3f8a37 #a8891a #8f5f99 #c9527f #8a6a4f #6f7480)
  @dark_series ~w(#7fb3e6 #f7a35c #f47c7c #6fd3c8 #86d67c #f2d15b #c99bd6 #ffb3c1 #cfa98b #b7bcc6)

  # The ramps of spec/08 §7.2, chosen in CIE LCh to hold the contracts of §7.5 with room.
  @light_ramps %{
    # The status ramp is defined from the theme's green, amber and red (spec/08 §7.5, #664).
    status: [{:color, :green}, {:color, :amber}, {:color, :red}],
    thermal: ~w(#0e68ad #e8e8e8 #c02e31),
    diverging: ~w(#b35806 #ededed #62448e),
    sequential: ~w(#e9f2fc #5e95d3 #004580)
  }
  @dark_ramps %{
    status: [{:color, :green}, {:color, :amber}, {:color, :red}],
    thermal: ~w(#7fb3e6 #3a3f48 #f47c7c),
    diverging: ~w(#f7a35c #3a3f48 #c1acee),
    sequential: ~w(#273b4f #457cb1 #aad1f9)
  }
  # Blue → orange → red: the status order survives the commonest colour-vision deficiencies.
  @safe_status ~w(#5996d6 #cd6012 #b92931)

  # The theme's own part of its color table (spec/08 §7.1, #663): its status hues, the hues
  # of `:info` and `:neutral`, and the five roles by use — the status three as their
  # positions on the status ramp, so a role and its position never disagree (D-135).
  @by_use %{good: {:ramp, :status, 0}, warning: {:ramp, :status, 0.5}, bad: {:ramp, :status, 1}}
  @light_colors Map.merge(@by_use, %{
                  red: "#c23238",
                  amber: "#bd7407",
                  green: "#4ca34b",
                  blue: "#3b6fa8",
                  gray: "#6f7480",
                  info: "#3b6fa8",
                  neutral: "#6f7480"
                })
  @dark_colors Map.merge(@by_use, %{
                 red: "#ff8f8a",
                 amber: "#db8e1c",
                 green: "#4f924c",
                 blue: "#7fb3e6",
                 gray: "#b7bcc6",
                 info: "#7fb3e6",
                 neutral: "#b7bcc6"
               })
  # The CSS named colors, the table's base (spec/08 §1.2, §7.1).
  @css_names Enum.map(Color.named_colors(), &String.to_atom/1)
  # A name a theme adds is written into CSS as a custom property: plain words only.
  @css_word ~r/^[a-z][a-z0-9_]*$/

  defstruct name: :default,
            series: @light_series,
            axis: "#666666",
            grid: "#e0e0e0",
            text: "#333333",
            background: "#ffffff",
            surface: "#eef2f6",
            ramps: @light_ramps,
            colors: @light_colors,
            styles: Palette.builtin(),
            font_family: "sans-serif",
            font_size: 10,
            label_size: 12,
            title_size: 16

  @typedoc "One of the four ramps whose meaning the library fixes (spec/08 §7.5)."
  @type ramp_name :: :status | :thermal | :diverging | :sequential

  @typedoc "A slot name, or `{:series, i}` for the i-th series colour, cycling."
  @type slot :: atom() | {:series, pos_integer()}

  @typedoc "A position along a ramp: `t` in `0..1`, clamped."
  @type ramp_position :: {:ramp, ramp_name(), number()}

  @typedoc """
  A name of the style palette (spec/08 §7.7): `:style_k`, a role, a state or a furniture
  name, or `{:style, i}` for the i-th style series entry, cycling.
  """
  @type style_name :: atom() | {:style, pos_integer()}

  @typedoc "How a slot renders: a CSS reference with fallback, or the stored value."
  @type mode :: :css | :literal

  @type t :: %__MODULE__{
          name: atom(),
          series: [String.t(), ...],
          axis: String.t(),
          grid: String.t(),
          text: String.t(),
          background: String.t(),
          surface: String.t(),
          ramps: %{optional(ramp_name()) => [String.t()]},
          colors: %{optional(atom()) => String.t() | Color.value()},
          styles: %{optional(atom()) => map()},
          font_family: String.t(),
          font_size: number(),
          label_size: number(),
          title_size: number()
        }

  @colour_slots [:axis, :grid, :text, :background, :surface]
  # Where the status roles stand on the status ramp, by default (spec/08 §7.5).
  @status_roles [good: 0, warning: 0.5, bad: 1]
  @role_slots [:good, :warning, :bad, :info, :neutral]
  # WCAG AA for normal text.
  @aa 4.5
  @size_slots [:font_size, :label_size, :title_size]
  @fixed_slots @colour_slots ++ @role_slots ++ [:font_family] ++ @size_slots
  @builtin [:default, :dark, :colour_safe, :print]

  @doc "The light theme: dark text and axes on white (spec/08 §7.2)."
  @spec default() :: t()
  def default, do: %__MODULE__{}

  @doc "The dark theme: light text and axes on `#1b1e24` (spec/08 §7.2)."
  @spec dark() :: t()
  def dark do
    %__MODULE__{
      name: :dark,
      series: @dark_series,
      axis: "#a0a4ab",
      grid: "#33373f",
      text: "#e6e6e6",
      background: "#1b1e24",
      surface: "#23272f",
      ramps: @dark_ramps,
      colors: @dark_colors
    }
  end

  @doc """
  The colour-vision-safe theme (spec/08 §7.2): `default/0` with its `status` ramp blue →
  orange → red, which survives the commonest colour-vision deficiencies, in place of green
  → amber → red. Every role and ramp position a design names follows it unchanged.
  """
  @spec colour_safe() :: t()
  def colour_safe do
    %__MODULE__{name: :colour_safe, ramps: %{@light_ramps | status: @safe_status}}
  end

  @doc """
  The print theme (spec/08 §7.2, spec/15 §12.4): paper. A white background and surface, so
  a printer lays no ink under the data; near-black text and axes and a grid dark enough to
  survive a photocopy; the default's series; and the colour-safe theme's blue → orange →
  red `status` ramp, since a printed page is read in whatever light and by whatever eyes
  it reaches, often in greyscale, where the ramp's falling lightness and each role's glyph
  still carry the order.
  """
  @spec print() :: t()
  def print do
    %__MODULE__{
      name: :print,
      axis: "#333333",
      grid: "#c8c8c8",
      text: "#111111",
      background: "#ffffff",
      surface: "#ffffff",
      ramps: %{@light_ramps | status: @safe_status}
    }
  end

  @doc """
  The built-in theme of a name — `:default`, `:dark`, `:colour_safe` or `:print` — or `nil`.

      iex> Visualize.Theme.builtin(:colour_safe).name
      :colour_safe
      iex> Visualize.Theme.builtin(:house)
      nil

  """
  @spec builtin(atom()) :: t() | nil
  def builtin(:default), do: default()
  def builtin(:dark), do: dark()
  def builtin(:colour_safe), do: colour_safe()
  def builtin(:print), do: print()
  def builtin(_name), do: nil

  @doc false
  # The names `builtin/1` knows, for the validator and the builder.
  @spec builtins() :: [atom(), ...]
  def builtins, do: @builtin

  @doc "The four ramps whose meaning the library fixes (spec/08 §7.5)."
  @spec ramp_names() :: [ramp_name(), ...]
  def ramp_names, do: Contract.ramps()

  @doc "The five roles: the status ramp's three fixed points, then `:info` and `:neutral`."
  @spec role_names() :: [atom(), ...]
  def role_names, do: @role_slots

  # Each role's cue besides its hue (spec/08 §7.5, spec/14 §21.7, D-142): the library's,
  # not a theme's, as the hue order is.
  @cues %{
    good: %{glyph: :circle, dash: nil},
    warning: %{glyph: :triangle, dash: "6 3"},
    bad: %{glyph: :cross, dash: "2 3"},
    info: %{glyph: :square, dash: "8 3 2 3"},
    neutral: %{glyph: :diamond, dash: "1 4"}
  }

  @doc """
  A role's cue besides its hue (spec/08 §7.5, D-142): its glyph, a symbol type, and its
  dash, a stroke pattern (`nil` for solid), so a status reads in greyscale. Fixed by the
  library for every theme. Raises `ArgumentError` for anything but a role.

      iex> Visualize.Theme.cue(:warning)
      %{glyph: :triangle, dash: "6 3"}

  """
  @spec cue(atom()) :: %{glyph: atom(), dash: String.t() | nil}
  def cue(role) do
    case Map.fetch(@cues, role) do
      {:ok, cue} ->
        cue

      :error ->
        raise ArgumentError,
              "a cue is a role's, one of #{inspect(@role_slots)}; got: #{inspect(role)}"
    end
  end

  @doc """
  The palette entry `name` as a style node in its parts (spec/08 §7.7, D-172): the theme's
  own, or the default theme's entry of that name, whole, where the theme lacks it.

  `name` is an atom of `style_names/1`, or `{:style, i}` for the i-th style series entry,
  cycling over the theme's style series. In a role's entry `:cue` — a stroke's `dash`, a
  marker's `shape` — becomes the role's dash and glyph (`cue/1`), and a solid dash leaves
  the key out. Any other name raises `ArgumentError`.

      iex> Visualize.Theme.style(Visualize.Theme.default(), :warning)
      %{fill: %{type: :solid, color: {:color, :warning}}, stroke: %{type: :solid, color: {:color, :warning}, dash: "6 3"}, marker: %{shape: :triangle}}
      iex> Visualize.Theme.style(Visualize.Theme.dark(), {:style, 12}) == Visualize.Theme.style(Visualize.Theme.dark(), :style_2)
      true
      iex> Visualize.Theme.style(Visualize.Theme.default(), :muted)
      %{opacity: 0.25}

  """
  @spec style(t(), style_name()) :: map()
  def style(%__MODULE__{} = theme, {:style, i}) when is_integer(i) and i >= 1 do
    series = theme |> own_styles() |> Palette.series()
    style(theme, Enum.at(series, rem(i - 1, length(series))))
  end

  def style(%__MODULE__{} = theme, name) when is_atom(name) do
    if name not in style_names(theme) do
      raise ArgumentError,
            "unknown palette style #{inspect(name)} of theme #{inspect(theme.name)}; see " <>
              "Visualize.Theme.style_names/1"
    end

    cued(name, composed(own_styles(theme), name))
  end

  def style(%__MODULE__{} = theme, name) do
    raise ArgumentError,
          "a palette style is a name of Visualize.Theme.style_names/1 or {:style, i}, " <>
            "i a positive integer; theme #{inspect(theme.name)} got #{inspect(name)}"
  end

  @doc """
  The theme's palette names (spec/08 §7.7): its style series `:style_1` … `:style_n` — the
  default theme's ten when it has none of its own — then the roles, the state styles and
  the furniture styles.

      iex> Visualize.Theme.default() |> Visualize.Theme.style_names() |> Enum.drop(10)
      [:good, :warning, :bad, :info, :neutral, :hover, :focused, :selected, :active, :disabled, :muted, :emphasis, :breakpoint, :axis, :grid, :label, :title, :caption, :value, :annotation, :bold, :italic, :thin, :thick, :dashed, :dotted, :outline]

  """
  @spec style_names(t()) :: [atom(), ...]
  def style_names(%__MODULE__{} = theme) do
    theme |> own_styles() |> Palette.series() |> Palette.names()
  end

  @doc false
  # Every palette entry of the theme by name, each as `style/2` answers it: what a chart
  # drawn with the theme resolves a style reference against (spec/14 §3.3, #637).
  @spec palette(t()) :: %{atom() => map()}
  def palette(%__MODULE__{} = theme) do
    own = own_styles(theme)

    theme
    |> style_names()
    |> Map.new(&{&1, cued(&1, composed(own, &1))})
  end

  # An entry as one node: a list of palette names and nodes stacked (spec/08 §7.7, #658).
  # A theme `new/1` built holds no list that cannot be composed; a struct written by hand
  # may, and its entry then lays nothing rather than raise where it is drawn.
  defp composed(own, name) do
    case Palette.compose(own, name) do
      {:ok, node} -> node
      {:error, _message} -> %{}
    end
  end

  defp own_styles(%__MODULE__{styles: styles}) when is_map(styles), do: styles
  defp own_styles(%__MODULE__{}), do: %{}

  # A role's `:cue` is its dash and glyph — a stroke's `dash`, a marker's `shape` — and a
  # solid dash is no key.
  defp cued(name, entry) do
    entry = Style.normalize(entry)

    if name in @role_slots and is_map(entry) do
      %{glyph: glyph, dash: dash} = cue(name)

      entry
      |> cue_part(:marker, :shape, glyph)
      |> cue_part(:stroke, :dash, dash)
    else
      entry
    end
  end

  defp cue_part(entry, part, key, value) do
    case entry do
      %{^part => %{^key => :cue} = map} when value == nil ->
        %{entry | part => Map.delete(map, key)}

      %{^part => %{^key => :cue} = map} ->
        %{entry | part => Map.put(map, key, value)}

      _other ->
        entry
    end
  end

  @doc """
  `default/0` with the given fields replaced; `ramps`, `colors` and `styles` are merged key by
  key.

  An unknown field raises `KeyError`; an empty `series`, or a ramp, role or palette style
  that breaks its contract (spec/08 §7.5, §7.7), raises `ArgumentError`.
  """
  @spec new(keyword() | map()) :: t()
  def new(fields), do: merge(default(), fields)

  @doc """
  The theme with the given fields replaced, `ramps`, `colors` and `styles` merged key by key
  over the theme's own; the checks of `new/1` apply.

      iex> theme = Visualize.Theme.new(name: :house, styles: %{muted: %{opacity: 0.4}})
      iex> Visualize.Theme.style(theme, :muted)
      %{opacity: 0.4}
      iex> Visualize.Theme.new(name: :house, colors: %{warning: "#f5c242"})
      ** (ArgumentError) theme :house: style :warning breaks its contract: fill {:color, :warning} is 1.65:1 against #ffffff; a role style's paint must reach 3:1 (WCAG 1.4.11, non-text contrast)

  """
  @spec merge(t(), keyword() | map()) :: t()
  def merge(%__MODULE__{} = theme, fields) do
    theme = build(theme, fields)

    if theme.series == [] do
      raise ArgumentError, "series: a theme needs at least one colour"
    end

    case check(theme) do
      :ok ->
        theme

      {:error, {kind, name}, message} ->
        raise ArgumentError,
              "theme #{inspect(theme.name)}: #{kind} #{inspect(name)} breaks its contract: " <>
                message
    end
  end

  @doc false
  # The theme with the fields replaced, `ramps`, `colors` and `styles` merged over the theme's
  # own, and nothing checked: `merge/2`'s first half, and what the validator measures.
  @spec build(t(), keyword() | map()) :: t()
  def build(%__MODULE__{} = theme, fields) do
    fields = Map.new(fields)
    {ramps, fields} = Map.pop(fields, :ramps, %{})
    # The role colors of before #663 are names of the color table (spec/08 §7.1, D-135).
    {roles, fields} = Map.pop(fields, :roles, %{})
    {colors, fields} = Map.pop(fields, :colors, %{})
    {styles, fields} = Map.pop(fields, :styles, %{})
    theme = struct!(theme, fields)

    %{
      theme
      | ramps: merged(theme.ramps, ramps, :ramps),
        colors: theme.colors |> merged(roles, :roles) |> merged(colors, :colors),
        styles: theme.styles |> merged(styles, :styles) |> normalized()
    }
  end

  defp merged(own, given, _key) when is_map(given), do: Map.merge(own || %{}, given)

  defp merged(own, given, key) when is_list(given), do: merged(own, Map.new(given), key)

  defp merged(_own, given, key) do
    raise ArgumentError, "#{key}: a map of name to value, got #{inspect(given)}"
  end

  # Palette entries in their parts, whatever spelling a host gave them (spec/14 §3.1, D-172).
  # A color written as a bare name is the typed color it names (spec/08 §7.7, #664).
  defp normalized(styles),
    do: Map.new(styles, fn {name, entry} -> {name, typed(Style.normalize(entry))} end)

  defp typed(entry) when is_map(entry) and not is_struct(entry),
    do: Migration.canonical(entry, :style)

  defp typed(entries) when is_list(entries), do: Enum.map(entries, &typed/1)
  defp typed(entry), do: entry

  @doc """
  `:ok`, or `{:error, subject, message}` for the first ramp, color or palette style of the
  theme that breaks its contract (spec/08 §7.1, §7.5, §7.7) — `subject` is `{:ramp, name}`,
  `{:color, name}` or `{:style, name}` and `message` names the term broken with the values
  measured. Ramps are read first, then the color table's entries and the `:info` and
  `:neutral` contracts, then the palette.

  The check `new/1` and `merge/2` raise on, for a caller that reports instead.

      iex> Visualize.Theme.check(Visualize.Theme.dark())
      :ok
      iex> theme = %{Visualize.Theme.default() | ramps: %{status: ~w(#c23238 #bd7407 #4ca34b)}}
      iex> {:error, {:ramp, :status}, message} = Visualize.Theme.check(theme)
      iex> message =~ "good (0) must be green or blue"
      true

  """
  @spec check(t()) :: :ok | {:error, {:ramp | :color | :style, atom()}, String.t()}
  def check(%__MODULE__{ramps: ramps} = theme) when is_map(ramps) do
    case violations(theme) do
      [] -> :ok
      [{subject, message} | _] -> {:error, subject, message}
    end
  end

  @doc """
  Every ramp, color and palette style of the theme that breaks its contract (spec/08 §7.5,
  §7.7), as
  `{subject, message}` in the order `check/1` reads them — the contract run on each alone,
  so a theme editor names every fault where it is and not only the first (spec/14 §20.4).

      iex> theme = Visualize.Theme.build(Visualize.Theme.default(), ramps: %{status: ~w(#c23238 #bd7407 #4ca34b)}, colors: %{neutral: "#ff0000"})
      iex> theme |> Visualize.Theme.violations() |> Enum.map(&elem(&1, 0))
      [{:ramp, :status}, {:color, :neutral}]
      iex> Visualize.Theme.violations(Visualize.Theme.dark())
      []

  """
  @spec violations(t()) :: [{{:ramp | :color | :style, atom()}, String.t()}]
  def violations(%__MODULE__{ramps: ramps} = theme) when is_map(ramps) do
    colors = own_colors(theme)

    # A ramp's anchors are measured as the strings they name (#664); one that names none is
    # left as written, which the contract refuses as no colour.
    resolved =
      Map.new(ramps, fn
        {name, anchors} when is_list(anchors) ->
          {name, Enum.map(anchors, &(anchor_literal(theme, &1, []) || &1))}

        other ->
          other
      end)

    ramp_faults =
      for name <- ordered(ramps, Contract.ramps()),
          {:error, subject, message} <- [Contract.check(Map.take(resolved, [name]), %{})],
          do: {subject, message}

    # Each entry of the table is a color; then `:info` and `:neutral` hold their contracts.
    entry_faults =
      for name <- colors |> Map.keys() |> Enum.sort(),
          {:error, message} <- [entry(theme, name)],
          do: {{:color, name}, message}

    broken = Enum.map(entry_faults, fn {{:color, name}, _} -> name end)

    role_faults =
      for name <- Contract.roles(),
          Map.has_key?(colors, name) and name not in broken,
          roles = %{name => table_literal(theme, name, [])},
          {:error, subject, message} <- [Contract.check(%{}, roles)],
          do: {subject, message}

    palette_faults = Palette.violations(own_styles(theme))
    broken = for {{:style, name}, _message} <- palette_faults, do: name

    # The role styles as a set and every palette color name, once the table's own entries
    # read; a table that does not cannot be measured against (#666).
    set_faults =
      if entry_faults == [] and ramp_faults == [], do: Roles.violations(theme, broken), else: []

    ramp_faults ++ entry_faults ++ role_faults ++ palette_faults ++ set_faults
  end

  # The names of a map in the contract's order, then any it does not know, sorted.
  defp ordered(map, known) do
    keys = Map.keys(map)
    Enum.filter(known, &(&1 in keys)) ++ Enum.sort(keys -- known)
  end

  @doc """
  The colour at `t` along the theme's ramp `name`, as a literal: the anchors are spread
  evenly over `0..1` and interpolated in CIE Lab, a position on an anchor is the anchor as
  written, and `t` is clamped to `0..1` (spec/08 §7.5). A theme that lacks the ramp takes
  the default theme's — never a series colour.

      iex> theme = Visualize.Theme.default()
      iex> Visualize.Theme.ramp(theme, :status, 1)
      "#c23238"
      iex> Visualize.Theme.ramp(theme, :thermal, 0.25)
      "#8da5cb"

  """
  @spec ramp(t(), ramp_name(), number()) :: String.t()
  def ramp(%__MODULE__{} = theme, name, t) when is_number(t) do
    anchors = anchors(theme, name)
    n = length(anchors) - 1
    position = (t |> max(0) |> min(1)) * n
    i = min(trunc(position), n - 1)
    u = position - i

    if u == 0 do
      Enum.at(anchors, i)
    else
      Color.interpolate_lab(
        colour!(name, Enum.at(anchors, i)),
        colour!(name, Enum.at(anchors, i + 1)),
        u
      )
      |> Color.to_hex()
    end
  end

  def ramp(%__MODULE__{}, name, t) do
    raise ArgumentError,
          "ramp #{inspect(name)}: a position is a number in 0..1, got #{inspect(t)}"
  end

  defp anchors(theme, name) do
    if name not in Contract.ramps() do
      raise ArgumentError,
            "unknown ramp #{inspect(name)}; the ramps are #{inspect(Contract.ramps())}"
    end

    anchors =
      case Map.get(theme.ramps || %{}, name) do
        [_, _ | _] = anchors -> anchors
        _missing -> Map.fetch!(@light_ramps, name)
      end

    Enum.map(anchors, &(anchor_literal(theme, &1, []) || &1))
  end

  @doc false
  # Each anchor as the colour string it is: a string as written, `{:color, name}` the
  # string its name holds in the theme's table through any chain of names; `nil` for one
  # that reaches no string — a ramp's anchor never reads a ramp, so it cannot loop (#664).
  @spec anchor_literals(t(), list()) :: [String.t() | nil]
  def anchor_literals(%__MODULE__{} = theme, anchors) when is_list(anchors),
    do: Enum.map(anchors, &anchor_literal(theme, &1, []))

  defp anchor_literal(_theme, literal, _seen) when is_binary(literal), do: literal

  defp anchor_literal(theme, {:color, name}, seen) do
    if name in seen do
      nil
    else
      case lookup(theme, name) do
        literal when is_binary(literal) -> literal
        {:color, _} = next -> anchor_literal(theme, next, [name | seen])
        %{500 => base} when is_binary(base) -> base
        _other -> nil
      end
    end
  end

  defp anchor_literal(_theme, _anchor, _seen), do: nil

  defp colour!(name, anchor) do
    (is_binary(anchor) && Color.parse(anchor)) ||
      raise ArgumentError, "ramp #{inspect(name)}: anchor #{inspect(anchor)} is not a colour"
  end

  @doc "The theme's slot names: `:series_1` to `:series_n`, then the fixed slots."
  @spec slots(t()) :: [atom()]
  def slots(%__MODULE__{series: series}) do
    Enum.map(1..length(series)//1, &series_atom/1) ++ @fixed_slots
  end

  @doc """
  The theme's colour slots — the series, then axis, grid, text, background and surface,
  then the five roles (spec/08 §7.1).
  """
  @spec colour_slots(t()) :: [atom(), ...]
  def colour_slots(%__MODULE__{series: series}) do
    Enum.map(1..length(series)//1, &series_atom/1) ++ @colour_slots ++ @role_slots
  end

  @doc """
  Every name of the theme's color table (spec/08 §7.1): its colour slots, its own and the
  default theme's `colors`, and the CSS named colors, sorted.

      iex> names = Visualize.Theme.color_names(Visualize.Theme.default())
      iex> Enum.all?([:red, :amber, :bad, :axis, :series_3, :steelblue], &(&1 in names))
      true

  """
  @spec color_names(t()) :: [atom(), ...]
  def color_names(%__MODULE__{} = theme) do
    (colour_slots(theme) ++
       Map.keys(own_colors(theme)) ++ Map.keys(@light_colors) ++ @css_names)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "The `:series_k` slot the positive index `i` cycles to over the theme's series."
  @spec series_slot(t(), pos_integer()) :: atom()
  def series_slot(%__MODULE__{series: series}, i) when is_integer(i) and i >= 1 do
    series_atom(rem(i - 1, length(series)) + 1)
  end

  def series_slot(%__MODULE__{}, i) do
    raise ArgumentError, "a series index is a positive integer, got: #{inspect(i)}"
  end

  @doc """
  The slot's value: the stored literal, or a CSS custom-property reference that falls
  back to it (spec/08 §7.3).

  Sizes are numbers under `:literal` and gain `px` under `:css`. A ramp position
  `{:ramp, name, t}` is its literal in both modes — CSS has no property for each point of a
  continuum — except where a status role stands, `{:ramp, :status, 0 | 0.5 | 1}`, which
  resolves as `:good`, `:warning` or `:bad`, so a role and its position never disagree.
  """
  @spec resolve(t(), slot() | ramp_position(), mode()) :: String.t() | number()
  def resolve(%__MODULE__{} = theme, {:series, i}, mode) do
    resolve(theme, series_slot(theme, i), mode)
  end

  # A status role's position resolves as the role while the table holds the role there.
  def resolve(%__MODULE__{} = theme, {:ramp, :status, t}, mode) when is_number(t) do
    case Enum.find(@status_roles, fn {role, at} ->
           at == t and lookup(theme, role) == {:ramp, :status, at}
         end) do
      {role, _at} -> resolve(theme, role, mode)
      nil -> ramp(theme, :status, t)
    end
  end

  def resolve(%__MODULE__{} = theme, {:ramp, name, t}, _mode), do: ramp(theme, name, t)

  def resolve(%__MODULE__{} = theme, slot, :literal) when is_atom(slot) do
    {_kind, value} = value(theme, slot)
    value
  end

  def resolve(%__MODULE__{} = theme, slot, :css) when is_atom(slot) do
    {kind, value} = value(theme, slot)
    "var(#{property(slot)}, #{css_value(kind, value)})"
  end

  @doc """
  The custom-property name of a slot atom or a color table name: `--vis-` and the name with
  `_` as `-` (spec/08 §7.3). A slot, a CSS named color or a name of the default theme's
  table; any other atom raises `ArgumentError`.
  """
  @spec css_name(atom()) :: String.t()
  def css_name(slot) when slot in @fixed_slots, do: "--vis-" <> hyphenated(slot)

  def css_name(slot) when is_atom(slot) do
    known? = slot in @css_names or Map.has_key?(@light_colors, slot)

    case series_index(slot) do
      k when is_integer(k) and k >= 1 -> "--vis-" <> hyphenated(slot)
      _ when known? -> "--vis-" <> hyphenated(slot)
      _ -> raise ArgumentError, "unknown theme slot #{inspect(slot)}; see Visualize.Theme.slots/1"
    end
  end

  # The property of a name `value/2` found: a theme's own name is written as one when it is
  # plain words, so a stylesheet can never be broken out of through a name (#660).
  defp property(slot) do
    cond do
      slot in @fixed_slots or series_index(slot) != nil -> css_name(slot)
      Regex.match?(@css_word, Atom.to_string(slot)) -> "--vis-" <> hyphenated(slot)
      true -> raise ArgumentError, "a color name is lower-case words, got #{inspect(slot)}"
    end
  end

  @doc """
  The mode a backend needs: `:css` for `Visualize.Backend.SVG`, `:literal` for any other.

  Takes what `Visualize.Backend.resolve/1` takes: a module, `:svg`, `:canvas` or `nil`.
  """
  @spec mode(module() | atom() | nil) :: mode()
  def mode(backend) do
    if Backend.resolve(backend) == Backend.SVG, do: :css, else: :literal
  end

  @doc """
  The contrast ink for a text drawn on `under` (spec/08 §7.3, D-123): the literal of the
  theme's `text` or `background`, whichever has the higher WCAG contrast ratio against it —
  `text` on a tie — or `#000000`/`#ffffff`, whichever contrasts more, when neither slot
  reaches 4.5:1. One of black and white always does, so the ink always meets WCAG AA.

  `under` is a colour string `Visualize.Color.parse/1` reads, a `%Visualize.Color{}`, or
  `nil` for nothing under the text — the theme's own background. An unreadable string is
  `nil`, and a slot whose own value does not parse is skipped.

      iex> theme = Visualize.Theme.default()
      iex> Visualize.Theme.ink(theme, "#3b6fa8")
      "#ffffff"
      iex> Visualize.Theme.ink(theme, "#ffd098")
      "#333333"
      iex> Visualize.Theme.ink(theme, nil)
      "#333333"
      iex> Visualize.Theme.ink(theme, "#777777")
      "#000000"

  """
  @spec ink(t(), String.t() | Color.t() | nil) :: String.t()
  def ink(%__MODULE__{} = theme, under) do
    under = parsed(under) || parsed(theme.background) || Color.rgb(255, 255, 255)

    slots =
      for literal <- [theme.text, theme.background],
          colour = parsed(literal),
          colour != nil,
          do: {literal, Color.contrast(colour, under)}

    case best(slots) do
      {literal, ratio} when ratio >= @aa ->
        literal

      _neither ->
        {literal, _ratio} =
          best([
            {"#000000", Color.contrast(Color.rgb(0, 0, 0), under)},
            {"#ffffff", Color.contrast(Color.rgb(255, 255, 255), under)}
          ])

        literal
    end
  end

  # The first of the highest ratio, so the earlier candidate wins a tie.
  defp best([]), do: nil

  defp best(candidates) do
    Enum.reduce(candidates, fn {_, ratio} = candidate, {_, best} = acc ->
      if ratio > best, do: candidate, else: acc
    end)
  end

  defp parsed(%Color{} = colour), do: colour
  defp parsed(string) when is_binary(string), do: Color.parse(string)
  defp parsed(_other), do: nil

  @doc """
  The `.vis-theme-<name>` CSS rule declaring every slot of the theme, one line each.

  Include it in a stylesheet and put `class="vis-theme-<name>"` on any ancestor of the
  charts that should take the theme.
  """
  @spec stylesheet(t()) :: String.t()
  def stylesheet(%__MODULE__{name: name} = theme) do
    lines =
      for slot <-
            slots(theme) ++ ((own_colors(theme) |> Map.keys() |> Enum.sort()) -- slots(theme)) do
        {kind, value} = value(theme, slot)
        ["  #{property(slot)}: #{css_value(kind, value)};" | pinned_lines(theme, slot)]
      end

    ".vis-theme-#{name} {\n" <>
      Enum.join(List.flatten(lines), "\n") <>
      "\n}\n" <>
      forced_colors(name)
  end

  # A name's pinned steps other than 500, each its own property: `--vis-red-100` (#667).
  defp pinned_lines(theme, slot) do
    case Map.get(own_colors(theme), slot) do
      %{} = steps when not is_struct(steps) ->
        for {n, literal} <- Enum.sort(steps),
            n != 500,
            do: "  #{property(slot)}-#{n}: #{css_value(:colour, literal)};"

      _other ->
        []
    end
  end

  # In high-contrast mode the furniture is the user's system colors (spec/08 §7.3, #665):
  # what the chart draws from the theme agrees with the palette the browser forces, and a
  # color derived in CSS from one of these follows it.
  @forced [
    text: "CanvasText",
    axis: "CanvasText",
    background: "Canvas",
    surface: "Canvas",
    grid: "GrayText"
  ]

  defp forced_colors(name) do
    lines =
      Enum.map_join(@forced, "\n", fn {slot, system} -> "    #{css_name(slot)}: #{system};" end)

    "@media (forced-colors: active) {\n  .vis-theme-#{name} {\n" <> lines <> "\n  }\n}\n"
  end

  defp value(theme, slot) when slot in @colour_slots, do: {:colour, Map.fetch!(theme, slot)}
  defp value(theme, :font_family), do: {:font, theme.font_family}
  defp value(theme, slot) when slot in @size_slots, do: {:size, Map.fetch!(theme, slot)}

  defp value(%{series: series} = theme, slot) do
    n = length(series)

    case series_index(slot) do
      k when is_integer(k) and k >= 1 and k <= n ->
        {:colour, Enum.at(series, k - 1)}

      _ ->
        if lookup(theme, slot) == nil,
          do:
            raise(
              ArgumentError,
              "unknown theme slot #{inspect(slot)}; see Visualize.Theme.slots/1 and color_names/1"
            ),
          else: {:colour, table_literal(theme, slot, [])}
    end
  end

  # -- the color table (spec/08 §7.1, #663) -------------------------------------------

  defp own_colors(%__MODULE__{colors: colors}) when is_map(colors), do: colors
  defp own_colors(%__MODULE__{}), do: %{}

  # A name's entry: the theme's own, the default theme's — a theme that lacks a role takes
  # the default's, never a series colour (§7.5) — or the CSS named color's hex; `nil` when
  # the table has no such name.
  defp lookup(theme, name) do
    Map.get(own_colors(theme), name) || Map.get(@light_colors, name) ||
      if(name in @css_names, do: Color.named(Atom.to_string(name)))
  end

  # A name's literal. `seen` carries the names on the way, so an entry that reaches itself
  # through another name raises rather than loops; `violations/1` reports it first.
  defp table_literal(theme, name, seen) do
    if name in seen do
      raise ArgumentError, "color #{inspect(name)} reaches itself through the color table"
    end

    case lookup(theme, name) do
      literal when is_binary(literal) -> literal
      {:ramp, ramp, t} -> ramp(theme, ramp, t)
      {:color, other} -> table_literal(theme, other, [name | seen])
      # A name's pinned steps: its own color is step 500 (#667).
      %{500 => base} when is_binary(base) -> base
      value -> Color.resolve(value, theme, :literal)
    end
  end

  @doc false
  # The literal a theme pins at step `n` of a name's scale (spec/08 §1.9, #667), `nil` when
  # it pins none there: the theme's own entry, else the default theme's.
  @spec step(t(), atom(), number()) :: String.t() | nil
  def step(%__MODULE__{} = theme, name, n) do
    case lookup(theme, name) do
      %{^n => literal} when is_binary(literal) -> literal
      _unpinned -> nil
    end
  end

  # A pinned entry: integer steps in 0..1000, 500 among them, to colour strings.
  defp steps(steps) do
    cond do
      not Map.has_key?(steps, 500) ->
        {:error,
         "pinned steps must include 500, the name's own color; got #{inspect(Map.keys(steps))}"}

      bad = Enum.find(Map.keys(steps), &(not (is_integer(&1) and &1 >= 0 and &1 <= 1000))) ->
        {:error, "a pinned step is an integer in 0..1000, got #{inspect(bad)}"}

      bad = Enum.find(Map.values(steps), &(not (is_binary(&1) and Color.parse(&1) != nil))) ->
        {:error, "a pinned step is a color string, got #{inspect(bad)}"}

      true ->
        :ok
    end
  end

  # An entry of the theme's own `colors` is a colour: a string `Visualize.Color.parse/1`
  # reads, or a color value whose names are the table's and do not reach the entry again.
  defp entry(theme, name) do
    value = Map.fetch!(own_colors(theme), name)

    cond do
      not Regex.match?(@css_word, Atom.to_string(name)) ->
        {:error, "a color name is lower-case letters, digits and _, starting with a letter"}

      is_binary(value) ->
        if Color.parse(value), do: :ok, else: {:error, "#{inspect(value)} is not a colour"}

      Color.value?(value) ->
        names_resolve(theme, value, [name])

      is_map(value) and not is_struct(value) ->
        steps(value)

      true ->
        {:error,
         "#{inspect(value)} is not a colour: a color string or a color value " <>
           "(spec/08 §1.9)"}
    end
  end

  defp names_resolve(theme, {:color, other}, seen) do
    cond do
      other in seen -> {:error, "reaches itself through #{inspect(other)}"}
      lookup(theme, other) == nil -> {:error, "names #{inspect(other)}, which is not a color"}
      true -> names_resolve(theme, lookup(theme, other), [other | seen])
    end
  end

  defp names_resolve(_theme, {:ramp, name, _t}, _seen) do
    if name in Contract.ramps(),
      do: :ok,
      else: {:error, "names the ramp #{inspect(name)}, which is not a ramp"}
  end

  defp names_resolve(theme, {:blend, list}, seen),
    do: Enum.find_value(list, :ok, &error_or_nil(names_resolve(theme, &1, seen)))

  defp names_resolve(theme, {_op, c, _t}, seen), do: names_resolve(theme, c, seen)
  defp names_resolve(theme, {:contrast, c}, seen), do: names_resolve(theme, c, seen)
  defp names_resolve(_theme, _value, _seen), do: :ok

  defp error_or_nil(:ok), do: nil
  defp error_or_nil(error), do: error

  defp css_value(:size, n), do: "#{n}px"
  defp css_value(_kind, value) when is_binary(value), do: css_escape(value)
  defp css_value(_kind, value), do: value

  # A value never ends its declaration or its rule, nor a `<style>` around the sheet
  # (spec/14 §10.3, #660): those characters are written as CSS escapes.
  defp css_escape(value) do
    String.replace(value, ["<", ">", ";", "{", "}", "\\"], fn char ->
      "\\" <> (char |> :binary.first() |> Integer.to_string(16)) <> " "
    end)
  end

  defp series_atom(k), do: :"series_#{k}"

  defp series_index(slot) do
    case Atom.to_string(slot) do
      "series_" <> rest ->
        case Integer.parse(rest) do
          {k, ""} -> k
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp hyphenated(slot), do: slot |> Atom.to_string() |> String.replace("_", "-")
end
