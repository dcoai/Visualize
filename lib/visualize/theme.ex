defmodule Visualize.Theme do
  @moduledoc """
  The colours, font and sizes a chart draws with (spec/08 §7).

  A theme is a struct of named *slots*: `:series_1` … `:series_n` for the categorical
  colours, `:axis`, `:grid`, `:text` and `:background`, and `:font_family`, `:font_size`,
  `:label_size` and `:title_size`. Nothing in the library carries a colour literal;
  every axis, mark and component reads its values through `resolve/3`, in the mode its
  render target needs:

    * `:literal` - the stored value, which a canvas needs
    * `:css` - a custom-property reference with the literal as its fallback,
      `var(--vis-axis, #666666)`, which the SVG output carries so a stylesheet can
      override it from any ancestor (D-55)

  `stylesheet/1` writes a `.vis-theme-<name>` rule declaring every slot, so a consumer
  switches every chart under an element of that class without touching Elixir.

  ## Examples

      iex> Visualize.Theme.resolve(Visualize.Theme.default(), :axis, :css)
      "var(--vis-axis, #666666)"
      iex> Visualize.Theme.resolve(Visualize.Theme.dark(), {:series, 11}, :literal)
      "#7fb3e6"
      iex> Visualize.Theme.new(font_family: "Inter, sans-serif").font_family
      "Inter, sans-serif"

  """

  alias Visualize.Backend

  @light_series ~w(#3b6fa8 #d9730d #c8373b #2f8f86 #3f8a37 #a8891a #8f5f99 #c9527f #8a6a4f #6f7480)
  @dark_series ~w(#7fb3e6 #f7a35c #f47c7c #6fd3c8 #86d67c #f2d15b #c99bd6 #ffb3c1 #cfa98b #b7bcc6)

  defstruct name: :default,
            series: @light_series,
            axis: "#666666",
            grid: "#e0e0e0",
            text: "#333333",
            background: "#ffffff",
            font_family: "sans-serif",
            font_size: 10,
            label_size: 12,
            title_size: 16

  @typedoc "A slot name, or `{:series, i}` for the i-th series colour, cycling."
  @type slot :: atom() | {:series, pos_integer()}

  @typedoc "How a slot renders: a CSS reference with fallback, or the stored value."
  @type mode :: :css | :literal

  @type t :: %__MODULE__{
          name: atom(),
          series: [String.t(), ...],
          axis: String.t(),
          grid: String.t(),
          text: String.t(),
          background: String.t(),
          font_family: String.t(),
          font_size: number(),
          label_size: number(),
          title_size: number()
        }

  @colour_slots [:axis, :grid, :text, :background]
  @size_slots [:font_size, :label_size, :title_size]
  @fixed_slots @colour_slots ++ [:font_family] ++ @size_slots

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
      background: "#1b1e24"
    }
  end

  @doc """
  `default/0` with the given fields replaced.

  An unknown field raises `KeyError`; an empty `series` raises `ArgumentError`.
  """
  @spec new(keyword() | map()) :: t()
  def new(fields), do: merge(default(), fields)

  @doc "The theme with the given fields replaced; the checks of `new/1` apply."
  @spec merge(t(), keyword() | map()) :: t()
  def merge(%__MODULE__{} = theme, fields) do
    theme = struct!(theme, fields)

    if theme.series == [] do
      raise ArgumentError, "series: a theme needs at least one colour"
    end

    theme
  end

  @doc "The theme's slot names: `:series_1` to `:series_n`, then the fixed slots."
  @spec slots(t()) :: [atom()]
  def slots(%__MODULE__{series: series}) do
    Enum.map(1..length(series)//1, &series_atom/1) ++ @fixed_slots
  end

  @doc "The theme's colour slots — the series, then axis, grid, text and background (spec/08 §7.1)."
  @spec colour_slots(t()) :: [atom(), ...]
  def colour_slots(%__MODULE__{series: series}) do
    Enum.map(1..length(series)//1, &series_atom/1) ++ @colour_slots
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

  Sizes are numbers under `:literal` and gain `px` under `:css`.
  """
  @spec resolve(t(), slot(), mode()) :: String.t() | number()
  def resolve(%__MODULE__{} = theme, {:series, i}, mode) do
    resolve(theme, series_slot(theme, i), mode)
  end

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
