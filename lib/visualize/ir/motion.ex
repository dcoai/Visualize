defmodule Visualize.IR.Motion do
  @moduledoc """
  What every backend writes of an element's motion (spec/02 §2.1, spec/14 §3.10, D-176).

  An element's style may carry `:transition`, the list of `{property, duration, easing}` a
  style's `transition` part resolves to — `property` `:fill`, `:stroke` or `:opacity`,
  `duration` in milliseconds, `easing` a `Visualize.Ease` name — and the element the
  attribute `"data-vis-id"`, the identity the motion is keyed by. SVG writes the motion as
  CSS (`css_easing/1`, `css_properties/1`, `oklch/1`), a canvas as a motion span the hooks
  run (`span/3`, `json/1`); both ease along the same samples of one curve (`samples/1`).

  ## Examples

      iex> Visualize.IR.Motion.css_easing(:linear)
      "linear"
      iex> Visualize.IR.Motion.samples(:quad_in) |> Enum.take(3)
      [0, 0.0025, 0.01]
      iex> Visualize.IR.Motion.css_properties(:stroke)
      ["stroke", "stroke-width", "stroke-opacity"]
      iex> Visualize.IR.Motion.oklch("#ffffff")
      "oklch(1 0 0)"
      iex> Visualize.IR.Motion.oklch("var(--vis-red, #c23238)")
      "oklch(from var(--vis-red, #c23238) l c h / alpha)"
  """

  alias Visualize.{Color, Ease}
  alias Visualize.IR.{Element, Paint, Path}

  @typedoc "A property a transition moves."
  @type property :: :fill | :stroke | :opacity

  @typedoc "A resolved transition: what moves, for how long, along which curve."
  @type transition :: [{property(), number(), atom()}]

  # The easing is sampled at t = 0, 0.05, …, 1: CSS's `linear()` and the hooks read the
  # same points (spec/14 §3.10).
  @steps 20

  @doc """
  The easing's 21 values at `t = 0, 0.05, …, 1`, each rounded to 4 decimals; `[0, 1]` for
  `:linear`, which two points draw exactly.
  """
  @spec samples(atom()) :: [number()]
  def samples(:linear), do: [0, 1]

  def samples(easing) do
    curve = Ease.by_name(easing)
    for i <- 0..@steps, do: tidy(curve.(i / @steps))
  end

  @doc "The easing as CSS: `linear`, or `linear()` of `samples/1`."
  @spec css_easing(atom()) :: String.t()
  def css_easing(:linear), do: "linear"

  def css_easing(easing),
    do: "linear(" <> Enum.map_join(samples(easing), ", ", &Path.format_number/1) <> ")"

  @doc "The CSS properties a property moves."
  @spec css_properties(property()) :: [String.t()]
  def css_properties(:fill), do: ["fill", "fill-opacity"]
  def css_properties(:stroke), do: ["stroke", "stroke-width", "stroke-opacity"]
  def css_properties(:opacity), do: ["opacity"]

  @doc """
  The CSS `transition` value of a resolved transition: each CSS property a property moves,
  its duration and its easing, joined by commas.
  """
  @spec css_transition(transition()) :: String.t()
  def css_transition(transition) do
    Enum.map_join(transition, ", ", fn {property, duration, easing} ->
      ease = css_easing(easing)

      Enum.map_join(css_properties(property), ", ", fn css ->
        "#{css} #{Path.format_number(duration)}ms #{ease}"
      end)
    end)
  end

  @doc """
  A colour as `oklch()`, so CSS interpolates it in OKLab (spec/14 §3.10): a literal
  `Visualize.Color.parse/1` reads as its coordinates, an `oklch(…)` as it is, anything
  else — a theme's `var(--vis-…, literal)`, a transform's `color-mix(…)` — as the relative
  colour `oklch(from <value> l c h / alpha)`. `:none`, `:current_color`, a paint and any
  value that is not a string pass through.
  """
  @spec oklch(term()) :: term()
  def oklch("oklch(" <> _ = colour), do: colour

  def oklch(colour) when is_binary(colour) do
    case Color.parse(colour) do
      nil ->
        "oklch(from #{colour} l c h / alpha)"

      parsed ->
        %{l: l, c: c, h: h, opacity: a} = Color.to_oklch(parsed)
        # A grey has no hue: `0`, which is what CSS reads a powerless hue as.
        h = if c < 1.0e-4, do: 0, else: h
        c = if c < 1.0e-4, do: 0, else: c
        coords = Enum.map_join([tidy(l), tidy(c), tidy(Float.round(h * 1.0, 2))], " ", &num/1)
        if a < 1, do: "oklch(#{coords} / #{num(tidy(a))})", else: "oklch(#{coords})"
    end
  end

  def oklch(other), do: other

  @doc """
  The arguments of a motion span (spec/09 §3.3.5): `[id, box, transitions]` for an element
  that names its identity, drawn with `style`, its effective style — its own over what its
  groups give it. An element whose style moves nothing has a span too, with no
  transitions: a hook then knows what it shows when a later stream moves it.
  """
  @spec span(String.t(), Element.t(), map()) :: list()
  def span(id, %Element{} = element, style) do
    [id, box(element), transitions(Map.get(style, :transition) || [])]
  end

  defp box(element) do
    case Paint.bounds(element) do
      {x, y, w, h} -> [x, y, w, h]
      nil -> nil
    end
  end

  @doc "The resolved transition as the canvas encoders write it: `[[property, duration, samples], …]`."
  @spec transitions(transition()) :: [list()]
  def transitions(transition) do
    for {property, duration, easing} <- transition,
        do: [Atom.to_string(property), duration, samples(easing)]
  end

  @doc """
  A span's arguments as JSON text: lists, strings, numbers and `nil`, numbers formatted as
  path data is, every string escaped — the text the `:json` command and the binary record
  both carry (spec/09 §3.3.5, §4.3.15).
  """
  @spec json(term()) :: String.t()
  def json(value), do: value |> encode() |> IO.iodata_to_binary()

  defp encode(nil), do: "null"

  defp encode(list) when is_list(list),
    do: ["[", list |> Enum.map(&encode/1) |> Enum.intersperse(","), "]"]

  defp encode(n) when is_number(n), do: Path.format_number(n)
  defp encode(atom) when is_atom(atom), do: encode(Atom.to_string(atom))
  defp encode(string) when is_binary(string), do: ["\"", escape(string), "\""]

  defp escape(string) do
    for <<c::utf8 <- string>>, into: "" do
      case c do
        ?" -> ~S(\")
        ?\\ -> ~S(\\)
        c when c < 0x20 -> "\\u" <> String.pad_leading(Integer.to_string(c, 16), 4, "0")
        c -> <<c::utf8>>
      end
    end
  end

  defp tidy(n) do
    rounded = Float.round(n * 1.0, 4)
    if rounded == trunc(rounded), do: trunc(rounded), else: rounded
  end

  defp num(n), do: Path.format_number(n)
end
