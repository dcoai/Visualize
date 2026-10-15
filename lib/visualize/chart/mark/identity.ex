defmodule Visualize.Chart.Mark.Identity do
  @moduledoc false
  # Which thing each element of a moving mark draws (spec/14 §3.10, D-176): `data-vis-id`,
  # `<frame>.<mark>.<identity>`, on every element of a mark whose style — its own stack, or
  # any style its data may choose — carries a motion part. The identity is the
  # row's in the board's form (spec/15 §13.2): the slot's declared identity (D-167), else
  # the inference a pick uses, written `field=value` with several fields joined by `&` in
  # name order; a row with neither is its ordinal among the mark's elements, `#n`. A mark
  # without motion writes nothing, so it draws byte for byte as before.

  alias Visualize.Chart.Style
  alias Visualize.Chart.Style.Motion
  alias Visualize.Event
  alias Visualize.IR.Element

  @doc false
  # The bound elements with their identities, when the mark moves; as they are otherwise.
  @spec stamp([Element.t()], [map()], map()) :: [Element.t()]
  def stamp(elements, children, ctx) do
    if moves?(ctx) do
      schema = Event.schema_of(ctx.frame.schemas, ctx.mark)
      prefix = "#{ctx.frame.name}.#{ctx.index}."

      elements
      |> Enum.zip(children)
      |> Enum.with_index()
      |> Enum.map(fn {{element, child}, i} ->
        text = text(Event.identity(ctx.mark, Map.get(child, :datum) || %{}, schema), i)
        Element.put_attr(element, "data-vis-id", prefix <> text)
      end)
    else
      elements
    end
  end

  # Whether the mark moves: its own style carries a motion part, or its stack names a style
  # by data and any style the frame knows — the design's, the theme's palette — carries one.
  # It is a fact of the design, not of the rows drawn now, so a mark's elements carry their
  # identities before a row first chooses a moving style, and a canvas knows what each
  # showed when one does.
  defp moves?(%{static: static, by_data: nil}), do: Motion.moves?(static)

  defp moves?(%{static: static, frame: frame}) do
    Motion.moves?(static) or
      Enum.any?(Map.keys(frame.styles), fn name ->
        frame.styles |> Style.node(name) |> Motion.moves?()
      end)
  end

  defp text({field, value}, _i), do: pair(field, value)

  defp text(%{} = fields, _i) when map_size(fields) > 0 do
    fields
    |> Enum.sort_by(fn {field, _} -> to_string(field) end)
    |> Enum.map_join("&", fn {field, value} -> pair(field, value) end)
  end

  defp text(_none, i), do: "##{i}"

  defp pair(field, value), do: "#{field}=#{string(value)}"

  # A value as its text; one with no text of its own as Elixir writes it.
  defp string(value) do
    if String.Chars.impl_for(value), do: to_string(value), else: inspect(value)
  end
end
