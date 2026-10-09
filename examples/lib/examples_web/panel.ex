defmodule ExamplesWeb.Panel do
  @moduledoc """
  One demo as one unit (#505): a bordered card holding a heading, the explanation and the
  chart it explains, so a page of demos reads as panels rather than one running column.

  Every demo of the Client-side Interactions tab is one — `/interaction` and the synced
  `/dashboard` — and the card's look lives once, in `ExamplesWeb.Layouts`, so the panels
  cannot drift. The panel adds structure only: the ids, hooks and data attributes of what
  it holds are the caller's, untouched (D-75).
  """

  use Phoenix.Component

  attr(:id, :string, default: nil, doc: "the panel's id, so a test or a link can find it")
  attr(:class, :string, default: nil, doc: "classes added to the panel's own")

  attr(:heading, :string,
    default: "h2",
    values: ~w(h2 h3),
    doc: "the heading's level: `h2` for a page's demo, `h3` for a panel inside one"
  )

  slot(:title, required: true, doc: "the heading's content")
  slot(:inner_block, required: true, doc: "the explanation and the chart")

  def panel(assigns) do
    ~H"""
    <section id={@id} class={Enum.join(["panel" | List.wrap(@class)], " ")}>
      <h2 :if={@heading == "h2"} class="panel-title">{render_slot(@title)}</h2>
      <h3 :if={@heading == "h3"} class="panel-title">{render_slot(@title)}</h3>
      {render_slot(@inner_block)}
    </section>
    """
  end
end
