defmodule Visualize.Theme do
  @moduledoc """
  The colours, font and sizes a chart draws with (spec/08 §7).

  A theme is a struct of named *slots*: `:series_1` … `:series_n` for the categorical
  colours, `:axis`, `:grid`, `:text`, `:background` and `:surface` — the plane the data is laid
  on, between the background and the grid — the five **roles** `:good`, `:warning`, `:bad`,
  `:info` and `:neutral`, and `:font_family`, `:font_size`, `:label_size` and `:title_size`.
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
  fixed points on the status ramp: `:good` is `{:ramp, :status, 0}`, `:warning` is `0.5`
  and `:bad` is `1`. Every ramp and role is checked against its contract — hue order,
  lightness direction, a neutral midpoint — when a theme is built by `new/1` or `merge/2`,
  and a theme that breaks one raises `ArgumentError` naming the ramp and the term broken.

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
  alias Visualize.Theme.Contract

  @light_series ~w(#3b6fa8 #d9730d #c8373b #2f8f86 #3f8a37 #a8891a #8f5f99 #c9527f #8a6a4f #6f7480)
  @dark_series ~w(#7fb3e6 #f7a35c #f47c7c #6fd3c8 #86d67c #f2d15b #c99bd6 #ffb3c1 #cfa98b #b7bcc6)

  # The ramps of spec/08 §7.2, chosen in CIE LCh to hold the contracts of §7.5 with room.
  @light_ramps %{
    status: ~w(#4ca34b #bd7407 #c23238),
    thermal: ~w(#0e68ad #e8e8e8 #c02e31),
    diverging: ~w(#b35806 #ededed #62448e),
    sequential: ~w(#e9f2fc #5e95d3 #004580)
  }
  @dark_ramps %{
    status: ~w(#4f924c #db8e1c #ff8f8a),
    thermal: ~w(#7fb3e6 #3a3f48 #f47c7c),
    diverging: ~w(#f7a35c #3a3f48 #c1acee),
    sequential: ~w(#273b4f #457cb1 #aad1f9)
  }
  # Blue → orange → red: the status order survives the commonest colour-vision deficiencies.
  @safe_status ~w(#5996d6 #cd6012 #b92931)

  @light_roles %{info: "#3b6fa8", neutral: "#6f7480"}
  @dark_roles %{info: "#7fb3e6", neutral: "#b7bcc6"}

  defstruct name: :default,
            series: @light_series,
            axis: "#666666",
            grid: "#e0e0e0",
            text: "#333333",
            background: "#ffffff",
            surface: "#eef2f6",
            ramps: @light_ramps,
            roles: @light_roles,
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
          roles: %{optional(:info | :neutral) => String.t()},
          font_family: String.t(),
          font_size: number(),
          label_size: number(),
          title_size: number()
        }

  @colour_slots [:axis, :grid, :text, :background, :surface]
  # The status roles stand on the status ramp; the rest are the theme's `roles`.
  @status_roles [good: 0, warning: 0.5, bad: 1]
  @role_slots [:good, :warning, :bad, :info, :neutral]
  # WCAG AA for normal text.
  @aa 4.5
  @size_slots [:font_size, :label_size, :title_size]
  @fixed_slots @colour_slots ++ @role_slots ++ [:font_family] ++ @size_slots
  @builtin [:default, :dark, :colour_safe]

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
      roles: @dark_roles
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
  The built-in theme of a name — `:default`, `:dark` or `:colour_safe` — or `nil`.

      iex> Visualize.Theme.builtin(:colour_safe).name
      :colour_safe
      iex> Visualize.Theme.builtin(:house)
      nil

  """
  @spec builtin(atom()) :: t() | nil
  def builtin(:default), do: default()
  def builtin(:dark), do: dark()
  def builtin(:colour_safe), do: colour_safe()
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
  `default/0` with the given fields replaced; `ramps` and `roles` are merged key by key.

  An unknown field raises `KeyError`; an empty `series`, or a ramp or role that breaks its
  contract (spec/08 §7.5), raises `ArgumentError`.
  """
  @spec new(keyword() | map()) :: t()
  def new(fields), do: merge(default(), fields)

  @doc """
  The theme with the given fields replaced, `ramps` and `roles` merged key by key over the
  theme's own; the checks of `new/1` apply.
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
  # The theme with the fields replaced, `ramps` and `roles` merged over the theme's own,
  # and nothing checked: `merge/2`'s first half, and what the validator measures.
  @spec build(t(), keyword() | map()) :: t()
  def build(%__MODULE__{} = theme, fields) do
    fields = Map.new(fields)
    {ramps, fields} = Map.pop(fields, :ramps, %{})
    {roles, fields} = Map.pop(fields, :roles, %{})
    theme = struct!(theme, fields)

    %{
      theme
      | ramps: merged(theme.ramps, ramps, :ramps),
        roles: merged(theme.roles, roles, :roles)
    }
  end

  defp merged(own, given, _key) when is_map(given), do: Map.merge(own || %{}, given)
  defp merged(own, given, key) when is_list(given), do: merged(own, Map.new(given), key)

  defp merged(_own, given, key) do
    raise ArgumentError, "#{key}: a map of name to value, got #{inspect(given)}"
  end

  @doc """
  `:ok`, or `{:error, subject, message}` for the first ramp or role of the theme that
  breaks its meaning contract (spec/08 §7.5) — `subject` is `{:ramp, name}` or
  `{:role, name}` and `message` names the term broken with the values measured.

  The check `new/1` and `merge/2` raise on, for a caller that reports instead.

      iex> Visualize.Theme.check(Visualize.Theme.dark())
      :ok
      iex> theme = %{Visualize.Theme.default() | ramps: %{status: ~w(#c23238 #bd7407 #4ca34b)}}
      iex> {:error, {:ramp, :status}, message} = Visualize.Theme.check(theme)
      iex> message =~ "good (0) must be green or blue"
      true

  """
  @spec check(t()) :: :ok | {:error, {:ramp | :role, atom()}, String.t()}
  def check(%__MODULE__{ramps: ramps, roles: roles})
      when is_map(ramps) and is_map(roles) do
    Contract.check(ramps, roles)
  end

  @doc """
  Every ramp and role of the theme that breaks its meaning contract (spec/08 §7.5), as
  `{subject, message}` in the order `check/1` reads them — the contract run on each alone,
  so a theme editor names every fault where it is and not only the first (spec/14 §20.4).

      iex> theme = %{Visualize.Theme.default() | ramps: %{status: ~w(#c23238 #bd7407 #4ca34b)}, roles: %{neutral: "#ff0000"}}
      iex> theme |> Visualize.Theme.violations() |> Enum.map(&elem(&1, 0))
      [{:ramp, :status}, {:role, :neutral}]
      iex> Visualize.Theme.violations(Visualize.Theme.dark())
      []

  """
  @spec violations(t()) :: [{{:ramp | :role, atom()}, String.t()}]
  def violations(%__MODULE__{ramps: ramps, roles: roles}) when is_map(ramps) and is_map(roles) do
    ramp_faults =
      for name <- ordered(ramps, Contract.ramps()),
          {:error, subject, message} <- [Contract.check(Map.take(ramps, [name]), %{})],
          do: {subject, message}

    role_faults =
      for name <- ordered(roles, Contract.roles()),
          {:error, subject, message} <- [Contract.check(%{}, Map.take(roles, [name]))],
          do: {subject, message}

    ramp_faults ++ role_faults
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

    case Map.get(theme.ramps || %{}, name) do
      [_, _ | _] = anchors -> anchors
      _missing -> Map.fetch!(@light_ramps, name)
    end
  end

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

  def resolve(%__MODULE__{} = theme, {:ramp, :status, t}, mode) when is_number(t) do
    case Enum.find(@status_roles, fn {_role, at} -> at == t end) do
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
    "var(#{css_name(slot)}, #{css_value(kind, value)})"
  end

  @doc "The custom-property name of a slot atom: `--vis-` and the slot with `_` as `-`."
  @spec css_name(atom()) :: String.t()
  def css_name(slot) when slot in @fixed_slots, do: "--vis-" <> hyphenated(slot)

  def css_name(slot) when is_atom(slot) do
    case series_index(slot) do
      k when is_integer(k) and k >= 1 -> "--vis-" <> hyphenated(slot)
      _ -> raise ArgumentError, "unknown theme slot #{inspect(slot)}; see Visualize.Theme.slots/1"
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
      for slot <- slots(theme) do
        {kind, value} = value(theme, slot)
        "  #{css_name(slot)}: #{css_value(kind, value)};"
      end

    ".vis-theme-#{name} {\n" <> Enum.join(lines, "\n") <> "\n}\n"
  end

  defp value(theme, slot) when slot in @colour_slots, do: {:colour, Map.fetch!(theme, slot)}
  defp value(theme, :font_family), do: {:font, theme.font_family}
  defp value(theme, slot) when slot in @size_slots, do: {:size, Map.fetch!(theme, slot)}

  defp value(theme, slot) when slot in [:good, :warning, :bad],
    do: {:colour, ramp(theme, :status, Keyword.fetch!(@status_roles, slot))}

  # A theme that lacks a role takes the default theme's, never a series colour (§7.5).
  defp value(theme, slot) when slot in [:info, :neutral],
    do: {:colour, Map.get(theme.roles || %{}, slot) || Map.fetch!(@light_roles, slot)}

  defp value(%{series: series}, slot) do
    n = length(series)

    case series_index(slot) do
      k when is_integer(k) and k >= 1 and k <= n ->
        {:colour, Enum.at(series, k - 1)}

      _ ->
        raise ArgumentError, "unknown theme slot #{inspect(slot)}; see Visualize.Theme.slots/1"
    end
  end

  defp css_value(:size, n), do: "#{n}px"
  defp css_value(_kind, value), do: value

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
