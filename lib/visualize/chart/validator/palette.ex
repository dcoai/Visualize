defmodule Visualize.Chart.Validator.Palette do
  @moduledoc false
  # The validator's view of the style palette (spec/14 §2.5, §3.3, §3.6, §4.3, #637,
  # D-171): which style names a design may reference under its theme, how a stored theme's
  # palette entry is read by the style grammar, and whether a scale ranges over styles, so
  # a `{:scale, name, field}` stack entry has styles to lay.

  alias Visualize.Chart.{Fact, Var}
  alias Visualize.Chart.Validator.{Domain, Frames}
  alias Visualize.Theme
  alias Visualize.Theme.Palette

  @series ~r/^style_[1-9]\d*$/
  @kinds [:ordinal, :threshold]

  @doc false
  # The palette names a reference may take under a theme: the theme's own when the
  # validator can see it, built-in or inline; else the fixed names of the roles, the states
  # and the furniture, the style series being the host theme's to say (`open?/1`).
  @spec names(Theme.t() | :unknown) :: [atom()]
  def names(%Theme{} = theme), do: Theme.style_names(theme)
  def names(:unknown), do: Palette.names([])

  @doc false
  # Whether a name is one of a style series, `:style_k`: accepted under a theme the
  # validator cannot see, which may hold any number of them (spec/14 §3.3).
  @spec series?(term()) :: boolean()
  def series?(name) when is_atom(name), do: Regex.match?(@series, Atom.to_string(name))
  def series?(_name), do: false

  @doc false
  # A stored theme's palette entry as the style grammar reads it (spec/14 §2.5): a role's
  # `:cue` and an `extends` are the palette contract's to judge, so they are left to it.
  @spec entry(map()) :: map()
  def entry(entry) do
    entry |> Map.delete(:extends) |> Map.reject(fn {_key, value} -> value == :cue end)
  end

  @doc false
  # A styles range on a scale that has no categories or bands to give it (spec/14 §4.3).
  @spec style_range(map(), list()) :: [{list(), {:style_range, atom()}}]
  def style_range(%{kind: kind, range: {:styles, _set}}, path)
      when is_atom(kind) and kind not in @kinds,
      do: [{path ++ [:range], {:style_range, kind}}]

  def style_range(_scale, _path), do: []

  @doc false
  # Whether a scale node ranges over styles (spec/14 §3.6): an ordinal or threshold scale
  # whose range is a set of styles, a list or a map of style names — `name?` says which
  # names are — a feed's status, or a variable that application will bind.
  @spec styles?(map(), (atom() -> boolean())) :: boolean()
  def styles?(node, name?) do
    kind = Map.get(node, :kind)
    (kind in @kinds or is_struct(kind, Var)) and range?(Map.get(node, :range, :auto), name?)
  end

  @doc false
  # Every place a scale of styles is read as colour (spec/14 §3.6, #637): the frame's
  # `color` scale, a legend's scale, a mark's `scales.color` and the colour scale a
  # `{:field, f}` on a mark's fill or stroke passes through. `colourless?` says which names
  # are styles with no colour, a style that is no theme slot. A shape the walk does not
  # recognise contributes nothing: the schema walk reports it.
  @spec colour_faults(map(), map(), (atom() -> boolean())) :: [{list(), {:style_colour, atom()}}]
  def colour_faults(design, styles, colourless?) do
    frames = map_or_empty(design[:frames])

    frame_faults =
      for {name, frame} <- frames, is_map(frame) and not is_struct(frame) do
        frame_colour(name, frame, frames, colourless?)
      end

    marks =
      case design[:marks] do
        marks when is_list(marks) -> Enum.with_index(marks)
        _other -> []
      end

    mark_faults =
      for {mark, i} <- marks, is_map(mark) and not is_struct(mark) do
        mark_colour(mark, [:marks, i], frames, styles, colourless?)
      end

    List.flatten(frame_faults ++ mark_faults)
  end

  defp frame_colour(name, frame, frames, colourless?) do
    scales = map_or_empty(frame[:scales])
    path = [:frames, name]

    color =
      case Map.fetch(scales, :color) do
        {:ok, %{} = node} when not is_struct(node) ->
          fault(node, :color, path ++ [:scales, :color, :range], colourless?)

        {:ok, adopted} ->
          fault(
            Frames.declared(adopted, frames, []),
            :color,
            path ++ [:scales, :color],
            colourless?
          )

        :error ->
          []
      end

    legend =
      case map_or_empty(frame[:legend]) do
        %{scale: scale} when is_atom(scale) ->
          node = Frames.declared(scales[scale], frames, [])
          fault(node, scale, path ++ [:legend, :scale], colourless?)

        _other ->
          []
      end

    color ++ legend
  end

  defp mark_colour(mark, path, frames, styles, colourless?) do
    scales = map_or_empty(frame_of(mark[:frame], frames)[:scales])

    {name, renamed} =
      case map_or_empty(mark[:scales]) do
        %{color: name} when is_atom(name) and name not in [nil, true, false] -> {name, true}
        _other -> {:color, false}
      end

    node = Frames.declared(scales[name], frames, [])
    rename = if renamed, do: fault(node, name, path ++ [:scales, :color], colourless?), else: []

    style = Domain.cascade(mark[:style], styles)
    bound? = Enum.any?([:fill, :stroke], &match?({:field, _}, Map.get(style, &1)))
    binding = if bound?, do: fault(node, name, path ++ [:style], colourless?), else: []

    rename ++ binding
  end

  # A mark is drawn in the frame it names, or the design's only frame (spec/14 §5.1).
  defp frame_of(name, frames) when is_map_key(frames, name), do: map_or_empty(frames[name])

  defp frame_of(_name, frames) when map_size(frames) == 1,
    do: frames |> Map.values() |> hd() |> map_or_empty()

  defp frame_of(_name, _frames), do: %{}

  defp fault(%{} = node, name, path, colourless?) when not is_struct(node) do
    if colourless_range?(Map.get(node, :range), colourless?),
      do: [{path, {:style_colour, name}}],
      else: []
  end

  defp fault(_node, _name, _path, _colourless?), do: []

  defp colourless_range?({:styles, _set}, _colourless?), do: true

  defp colourless_range?([_ | _] = names, colourless?),
    do: Enum.any?(names, &colourless(&1, colourless?))

  defp colourless_range?(map, colourless?) when is_map(map) and not is_struct(map),
    do: Enum.any?(map, fn {_category, value} -> colourless(value, colourless?) end)

  defp colourless_range?(_range, _colourless?), do: false

  defp colourless(value, colourless?) when is_atom(value) and value not in [nil, true, false],
    do: colourless?.(value)

  defp colourless(_value, _colourless?), do: false

  defp map_or_empty(map) when is_map(map) and not is_struct(map), do: map
  defp map_or_empty(_other), do: %{}

  defp range?({:styles, set}, _name?), do: set in [:roles, :series]
  defp range?(%Var{}, _name?), do: true
  defp range?(%Fact{key: key}, _name?), do: key == :status
  defp range?([_ | _] = names, name?), do: Enum.all?(names, &style?(&1, name?))

  defp range?(map, name?) when is_map(map) and not is_struct(map) and map_size(map) > 0,
    do: Enum.all?(map, fn {_category, value} -> style?(value, name?) end)

  defp range?(_range, _name?), do: false

  defp style?(value, name?) when is_atom(value) and value not in [nil, true, false],
    do: name?.(value)

  defp style?(_value, _name?), do: false
end
