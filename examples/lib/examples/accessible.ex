defmodule Examples.Accessible do
  @moduledoc """
  Names a rendered chart for assistive technology (spec/02 §2.1, D-56): the `<svg>` gets
  `role="img"`, a `<title>` and a `<desc>` as its first children, and `aria-labelledby`
  pointing at them, so a screen reader announces the chart's title and description.
  """

  alias Visualize.SVG.Element

  @doc "The chart's `<svg>` named with the given title and description"
  def name(%Element{tag: :svg} = svg, title, description) do
    id = "vis-" <> String.downcase(Integer.to_string(:erlang.phash2({title, description}), 36))
    title_el = Element.title(%{id: id <> "-title"}) |> Element.content(title)
    desc_el = Element.new(:desc, %{id: id <> "-desc"}) |> Element.content(description)

    svg
    |> Element.attrs(%{id: id, role: "img", "aria-labelledby": "#{id}-title #{id}-desc"})
    |> Map.update!(:children, &[title_el, desc_el | &1])
  end
end
