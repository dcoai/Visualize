defmodule Visualize.Chart.Style.Defaults do
  @moduledoc false
  # The defaults an element inherits from its containers (spec/14 §3.8, #651, D-174).
  #
  # A defaults node holds a style's parts and one entry per mark type of the same parts.
  # An element's containers are a list of such nodes, farthest first — the theme's own, the
  # design's, the frame's, the element's own (its layers' and groups') — and `layer/2` lays
  # them for an element of one kind: each container's part defaults, then its entry for the
  # kind, by the merge rule, nearest last. What it answers is the style the site's stack is
  # laid over (`Visualize.Chart.Style.node/4`).
  #
  # The library's base — what an element that carries no value for a key already draws —
  # is `base/0`. It is the root `Visualize.Theme.defaults/1` answers and `explain/2` shows,
  # and it is never laid onto an element: writing it would change bytes, not drawings.

  alias Visualize.Chart.{Schema, Style, Var}
  alias Visualize.Chart.Style.Parts

  # `text` is the part, where a text sits, so the `:text` mark has no entry (§3.8).
  @kinds Schema.mark_types() -- [:text]

  @base %{
    fill: %{opacity: 1},
    stroke: %{opacity: 1, width: 1, join: :miter, cap: :butt, placement: :center},
    font: %{
      family: :font_family,
      size: :font_size,
      weight: :normal,
      style: :normal,
      line_height: 1.2
    },
    text: %{offset: [0, 0], angle: 0},
    effect: %{type: :none, radius: 3},
    marker: %{shape: :circle, size: 64},
    curve: %{type: :linear},
    opacity: 1,
    blend: :normal
  }

  @doc false
  # The library's base: every part, as an element with no value for it draws (§3.8).
  @spec base() :: map()
  def base, do: @base

  @doc false
  # The mark types a defaults node keys an entry by.
  @spec kinds() :: [atom(), ...]
  def kinds, do: @kinds

  @doc false
  # The style the containers lay for an element of `kind` — a mark type, `:text` for a
  # label, `nil` for furniture, which takes the part defaults alone — in its parts. `%{}`
  # when no container declares anything, so the stack laid over it is what it always was.
  @spec layer([map() | nil], atom() | nil) :: map()
  def layer(containers, kind) do
    Enum.reduce(containers, %{}, fn container, laid ->
      laid |> Parts.merge(parts(container)) |> Parts.merge(entry(container, kind))
    end)
  end

  @doc false
  # What a realised frame's containers (`Visualize.Chart.Frame`'s `defaults`) and the
  # element's own `defaults` lay for an element of `kind`.
  @spec at(%{defaults: [map() | nil]}, map() | nil, atom() | nil) :: map()
  def at(%{defaults: containers}, own, kind), do: layer(containers ++ [own], kind)

  @doc false
  # Each container's contribution for an element of `kind`, farthest first: `{:parts, node}`
  # and `{:kind, node}`, the empty ones left out — what `explain/2` attributes.
  @spec contributions([{term(), map() | nil}], atom() | nil) :: [{term(), :parts | :kind, map()}]
  def contributions(containers, kind) do
    for {name, container} <- containers,
        {what, node} <- [{:parts, parts(container)}, {:kind, entry(container, kind)}],
        map_size(node) > 0,
        do: {name, what, node}
  end

  @doc false
  # A container's part defaults, in their parts: the node without its kind entries.
  @spec parts(map() | nil) :: map()
  def parts(%Var{name: name}), do: Style.unresolved!(name)

  def parts(container) when is_map(container) and not is_struct(container),
    do: container |> Map.drop(@kinds) |> Parts.normalize()

  def parts(_none), do: %{}

  @doc false
  # A container's entry for one kind, in its parts; `%{}` for none.
  @spec entry(map() | nil, atom() | nil) :: map()
  def entry(container, kind)
      when is_map(container) and not is_struct(container) and kind in @kinds do
    case Map.get(container, kind) do
      entry when is_map(entry) and not is_struct(entry) -> Parts.normalize(entry)
      _none -> %{}
    end
  end

  def entry(_container, _kind), do: %{}

  @doc false
  # `over` laid on `under`, two defaults nodes: the part defaults by the merge rule, and
  # each kind's entry by it too — how a composite's defaults go under a node's own (§19.6).
  @spec merge(map() | nil, map() | nil) :: map() | nil
  def merge(under, nil), do: under
  def merge(nil, over), do: over

  def merge(under, over) do
    entries =
      for kind <- @kinds,
          Map.has_key?(under, kind) or Map.has_key?(over, kind),
          into: %{},
          do: {kind, Parts.merge(entry(under, kind), entry(over, kind))}

    under |> parts() |> Parts.merge(parts(over)) |> Map.merge(entries)
  end

  @doc false
  # Every style node a list of containers holds — its part defaults and each kind entry —
  # for the frame to find the gradients they write in place (§3.2).
  @spec nodes([map() | nil]) :: [map()]
  def nodes(containers) do
    Enum.flat_map(containers, fn container ->
      [parts(container) | Enum.map(@kinds, &entry(container, &1))]
    end)
  end
end
