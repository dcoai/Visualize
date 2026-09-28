defmodule Visualize.Chart.Build do
  @moduledoc """
  The builder for the declarative layer (spec/14 §16, D-78).

  Every function here returns a *fragment* — a design map carrying the keys that one
  function sets and no others — and the pipe is `Visualize.Chart.compose/2`: a design is
  the fold of its fragments, which is `Visualize.Chart.compose/1` over the list. Nothing
  validates, defaults or realises anything, so the fold is a fragment too and becomes a
  chart through `Visualize.Chart.from_map/1` or an applied chart through
  `Visualize.Chart.apply/2`, which is where it must validate.

  What the builder adds over the literal map is the schema. Each function sets its node's
  required keys from its positional arguments and takes the node's remaining keys as
  `opts`, checked against `Visualize.Chart.Schema.describe/1`: an option that is not a key
  of that node kind raises `ArgumentError` at the call rather than reaching the validator
  as a path in a design fifty lines long. A mark's channels and options are checked the
  same way against `Visualize.Chart.Schema.channels/1` and `Visualize.Chart.Schema.options/1`
  of its type.

  The mark, transform and scale functions are not written here: they are generated from
  the schema at compile time (spec/14 §16.6, D-79), one documented function per mark type
  (`line/3`, `rect/3`, …), per transform op (`bin/3`, `stack/3`, `treemap/2`, …) and per
  scale kind (`linear_scale/2`, `time_scale/2`, `band_scale/2`, … — every kind takes the
  suffix because `band` is a mark type as well). A type added to the schema grows the
  builder with no edit to it; `mark/4` and `scale/3` remain for a type that is a value.

  `var/2` declares a variable and its default under the design's `vars`;
  `Visualize.Chart.var/1` builds the `%Visualize.Chart.Var{}` term that *uses* one. They
  are different modules and different arities, so a caller may import both.

  ## Examples

      iex> import Visualize.Chart.Build
      iex> {:ok, design} =
      ...>   Visualize.Chart.compose([
      ...>     chart(meta: %{name: "Uptime"}),
      ...>     source(:primary, [:t, :v]),
      ...>     cartesian(),
      ...>     time_scale(:x),
      ...>     linear_scale(:y, domain: [0, :auto]),
      ...>     axis(:x, :bottom, ticks: 4),
      ...>     line(:primary, %{x: :t, y: :v}),
      ...>     title(["Uptime"])
      ...>   ])
      iex> design.marks
      [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      iex> design.frames.main.scales
      %{x: %{kind: :time}, y: %{kind: :linear, domain: [0, :auto]}}
      iex> {:ok, _chart} = Visualize.Chart.from_map(design)

  """

  alias Visualize.Chart.{Migration, Schema, Var}

  @typedoc "A design map carrying the keys one builder function sets (spec/14 §16.1)."
  @type fragment :: %{optional(atom()) => term()}

  @typedoc "A mark's data: a source name, or the `:data` node `from/1` starts (spec/14 §5.4)."
  @type data :: atom() | map()

  @typedoc "A node's remaining keys, as a keyword list or a map."
  @type opts :: keyword() | map()

  # The mark, transform and scale functions are the schema's, emitted at compile time
  # (spec/14 §16.6, D-79).
  use Visualize.Chart.Build.Generate

  # -- the design and its declarations (spec/14 §16.2) ------------------------------------

  @doc "As `chart/1` with no options."
  @spec chart() :: fragment()
  def chart, do: chart([])

  @doc """
  The seed a design is folded onto: the current schema version (spec/14 §9).

  `opts` are the remaining keys of the `:design` node (spec/14 §2.1).
  """
  @spec chart(opts()) :: fragment()
  def chart(opts), do: node(:design, %{version: Migration.current()}, opts)

  @doc "As `source/3` with no options."
  @spec source(atom(), [atom()]) :: fragment()
  def source(name, fields), do: source(name, fields, [])

  @doc """
  One typed slot under `sources` (spec/14 §2.3): the fields the design reads from it.

  `opts` are the slot's remaining keys, `default:` among them.
  """
  @spec source(atom(), [atom()], opts()) :: fragment()
  def source(name, fields, opts) do
    %{sources: %{name => node(:source, %{fields: fields}, opts)}}
  end

  @doc "As `var/3` with no options."
  @spec var(atom(), term()) :: fragment()
  def var(name, default), do: var(name, default, [])

  @doc """
  The *declaration* of a variable and its default under `vars` (spec/14 §2.4).

  `Visualize.Chart.var/1` builds the term that uses one; this declares it.
  """
  @spec var(atom(), term(), opts()) :: fragment()
  def var(name, default, opts) do
    %{vars: %{name => node(:var, %{default: default}, opts)}}
  end

  @doc "As `style/3` with no further keys."
  @spec style(atom(), opts()) :: fragment()
  def style(name, keys), do: style(name, keys, [])

  @doc """
  One named style under `styles` (spec/14 §3.1).

  `keys` and `opts` are both style keys, `opts` merged over `keys`; every one is checked.
  """
  @spec style(atom(), opts(), opts()) :: fragment()
  def style(name, keys, opts) do
    %{styles: %{name => node(:style, %{}, Map.merge(Map.new(keys), Map.new(opts)))}}
  end

  @doc "As `gradient/3` with no options."
  @spec gradient(atom(), :linear | :radial) :: fragment()
  def gradient(name, kind), do: gradient(name, kind, [])

  @doc """
  One named paint under `defs` (spec/14 §2.7): a gradient of the kind, `opts` its remaining
  keys. `stops:` takes `%{offset, colour, opacity}` maps, or `{offset, colour}` and
  `{offset, colour, opacity}` tuples, which read as the maps.

      iex> Visualize.Chart.Build.gradient(:area, :linear, stops: [{0, :series_1, 0.8}, {1, :series_1, 0.1}])
      %{defs: %{area: %{kind: :linear, stops: [%{offset: 0, colour: :series_1, opacity: 0.8}, %{offset: 1, colour: :series_1, opacity: 0.1}]}}}
  """
  @spec gradient(atom(), :linear | :radial, opts()) :: fragment()
  def gradient(name, kind, opts) do
    opts = opts |> Map.new() |> Map.update(:stops, [], fn stops -> Enum.map(stops, &stop/1) end)
    %{defs: %{name => node(:gradient, %{kind: kind}, opts)}}
  end

  defp stop({offset, colour}), do: %{offset: offset, colour: colour}
  defp stop({offset, colour, opacity}), do: %{offset: offset, colour: colour, opacity: opacity}
  defp stop(%{} = stop), do: stop

  @doc """
  The value a `:colour` key takes to refer to a gradient of `defs` (spec/14 §3.2).

      iex> Visualize.Chart.Build.paint(:area)
      {:paint, :area}
  """
  @spec paint(atom()) :: {:paint, atom()}
  def paint(name) when is_atom(name), do: {:paint, name}

  @doc """
  The grid the design's frames are placed on (spec/14 §2.8, #384): `columns` and `rows`
  as weights, `gap` in pixels between cells. A frame takes its place with `cell:`.

      iex> Visualize.Chart.Build.layout(columns: [4, 3, 2, 1], gap: 8)
      %{layout: %{columns: [4, 3, 2, 1], gap: 8}}
  """
  @spec layout(opts()) :: fragment()
  def layout(opts), do: %{layout: node(:layout, %{}, opts)}

  @doc "The design's theme: a name, or an inline `:theme` node (spec/14 §2.5)."
  @spec theme(atom() | map()) :: fragment()
  def theme(theme), do: %{theme: theme}

  # -- the frame (spec/14 §16.3) ----------------------------------------------------------

  @doc "As `cartesian/2` under the name `:main`, with no options."
  @spec cartesian() :: fragment()
  def cartesian, do: cartesian(:main, [])

  @doc """
  A `:cartesian` frame (spec/14 §4.1).

  `opts` are the frame's keys; its scales, axes and legend are their own fragments
  (`scale/3`, `axis/3`, `legend/2`). A frame carries no size — the render gives it (§4.2).
  """
  @spec cartesian(atom() | opts()) :: fragment()
  def cartesian(name) when is_atom(name), do: cartesian(name, [])
  def cartesian(opts), do: cartesian(:main, opts)

  @doc """
  A named `:cartesian` frame (spec/14 §4.1): a design holds its frames by name, and a
  design that declares one names it `:main` unless it says otherwise.
  """
  @spec cartesian(atom(), opts()) :: fragment()
  def cartesian(name, opts), do: frame(name, :cartesian, opts)

  @doc "As `polar/1` with no options."
  @spec polar() :: fragment()
  def polar, do: polar(:main, [])

  @doc "A `:polar` frame (spec/14 §4.6): `angle` and `r` are its scales."
  @spec polar(atom() | opts()) :: fragment()
  def polar(name) when is_atom(name), do: polar(name, [])
  def polar(opts), do: polar(:main, opts)

  @doc "A named `:polar` frame (spec/14 §4.1)."
  @spec polar(atom(), opts()) :: fragment()
  def polar(name, opts), do: frame(name, :polar, opts)

  @doc "As `geo/1` with no options."
  @spec geo() :: fragment()
  def geo, do: geo(:main, [])

  @doc """
  A `:geo` frame (spec/14 §4.6).

  The projection is the frame's `projection:` key, a `:projection` node.
  """
  @spec geo(atom() | opts()) :: fragment()
  def geo(name) when is_atom(name), do: geo(name, [])
  def geo(opts), do: geo(:main, opts)

  @doc "A named `:geo` frame (spec/14 §4.1)."
  @spec geo(atom(), opts()) :: fragment()
  def geo(name, opts), do: frame(name, :geo, opts)

  @doc "As `facet/1` with no options."
  @spec facet() :: fragment()
  def facet, do: facet(:main, [])

  @doc """
  A `:facet` frame (spec/14 §4.6).

  `by:` and `columns:`, the keys of the `:facet` node, are lifted into the frame's `facet`
  key: a `:facet` frame and its `facet` node name the same thing.
  """
  @spec facet(atom() | opts()) :: fragment()
  def facet(name) when is_atom(name), do: facet(name, [])
  def facet(opts), do: facet(:main, opts)

  @doc "A named `:facet` frame (spec/14 §4.6)."
  @spec facet(atom(), opts()) :: fragment()
  def facet(name, opts) do
    {facet, rest} = opts |> Map.new() |> Map.split([:by, :columns])
    frame(name, :facet, if(facet == %{}, do: rest, else: Map.put(rest, :facet, facet)))
  end

  @doc """
  The fragments, each in the frame `name` (spec/14 §16.3, #383).

  The frame functions take a name — `cartesian/2`, `polar/2` — but `scale/3`, `axis/3`,
  `legend/2` and the generated scale functions declare the design's one frame, and a named
  twin of each would double the builder's surface for no new meaning. This says it once:
  each fragment's frame is renamed to `name`, and every mark and every label it carries is
  given `frame: name` unless it already says one (spec/14 §5.1, §6.1). A list in and a list
  out, so it stands in a fold where its fragments would.

      iex> import Visualize.Chart.Build
      iex> in_frame(:now, [polar(), linear_scale(:r, domain: [0, 4]), line(:load, %{x: :t, y: :v})])
      [
        %{frames: %{now: %{kind: :polar}}},
        %{frames: %{now: %{scales: %{r: %{kind: :linear, domain: [0, 4]}}}}},
        %{marks: [%{type: :line, data: :load, channels: %{x: :t, y: :v}, frame: :now}]}
      ]

  A fragment carrying more than one frame raises `ArgumentError`: this function says which
  frame a thing belongs to, and a fragment already holding two has nothing to be told.
  """
  @spec in_frame(atom(), [fragment()]) :: [fragment()]
  def in_frame(name, fragments) when is_atom(name) and is_list(fragments),
    do: Enum.map(fragments, &framed(&1, name))

  defp framed(fragment, name) when is_map(fragment) and not is_struct(fragment) do
    fragment
    |> renamed(name)
    |> bound(:marks, name)
    |> bound(:labels, name)
  end

  defp renamed(%{frames: frames} = fragment, name)
       when is_map(frames) and not is_struct(frames) do
    case Map.values(frames) do
      [node] ->
        %{fragment | frames: %{name => node}}

      several ->
        raise ArgumentError,
              "in_frame(#{inspect(name)}, …) takes a fragment of one frame; this one has " <>
                "#{length(several)} (#{inspect(Map.keys(frames))})"
    end
  end

  defp renamed(fragment, _name), do: fragment

  defp bound(fragment, key, name) do
    case Map.fetch(fragment, key) do
      {:ok, nodes} when is_list(nodes) -> %{fragment | key => Enum.map(nodes, &says(&1, name))}
      _absent -> fragment
    end
  end

  defp says(node, name) when is_map(node) and not is_struct(node),
    do: Map.put_new(node, :frame, name)

  defp says(node, _name), do: node

  @doc "As `scale/3` with no options."
  @spec scale(atom(), atom()) :: fragment()
  def scale(name, kind), do: scale(name, kind, [])

  @doc "One declared scale of the frame (spec/14 §4.3); `opts` are its remaining keys."
  @spec scale(atom(), atom(), opts()) :: fragment()
  def scale(name, kind, opts) do
    %{frames: %{main: %{scales: %{name => node(:scale, %{kind: kind}, opts)}}}}
  end

  @doc "As `adopt/3` reading the same name in the other frame (spec/14 §4.3)."
  @spec adopt(atom(), atom()) :: fragment()
  def adopt(name, frame), do: adopt(name, frame, name)

  @doc """
  A scale adopted from another frame (spec/14 §4.3, #384): this frame reads `frame`'s
  `scale` under `name`, so the node is said once and the domain is shared, while the
  range stays this frame's own.

      iex> import Visualize.Chart.Build
      iex> in_frame(:day, [adopt(:y, :year)])
      [%{frames: %{day: %{scales: %{y: {:frame, :year, :y}}}}}]
  """
  @spec adopt(atom(), atom(), atom()) :: fragment()
  def adopt(name, frame, scale) when is_atom(name) and is_atom(frame) and is_atom(scale),
    do: %{frames: %{main: %{scales: %{name => {:frame, frame, scale}}}}}

  @doc "As `axis/3` with no options."
  @spec axis(atom(), atom()) :: fragment()
  def axis(scale, side), do: axis(scale, side, [])

  @doc "One axis of the frame, drawing `scale` on `side` (spec/14 §4.4)."
  @spec axis(atom(), atom(), opts()) :: fragment()
  def axis(scale, side, opts) do
    %{frames: %{main: %{axes: [node(:axis, %{scale: scale, side: side}, opts)]}}}
  end

  @doc "As `legend/2` with no options."
  @spec legend(atom()) :: fragment()
  def legend(scale), do: legend(scale, [])

  @doc "The frame's legend, explaining `scale` (spec/14 §4.5)."
  @spec legend(atom(), opts()) :: fragment()
  def legend(scale, opts), do: %{frames: %{main: %{legend: node(:legend, %{scale: scale}, opts)}}}

  # -- marks and labels (spec/14 §16.4) ---------------------------------------------------

  @doc "As `mark/4` with no options."
  @spec mark(atom(), data(), opts() | Var.t()) :: fragment()
  def mark(type, data, channels), do: mark(type, data, channels, [])

  @doc """
  One mark of the design (spec/14 §5.1): a type, its data, its channels.

  `data` is a source name or the `:data` node `from/1` starts. A key of `channels` that is
  not a channel of the type, and a key of an `options:` option that is not an option of the
  type, raise `ArgumentError` (spec/14 §5.2, §5.3); a `%Visualize.Chart.Var{}` standing for
  the whole node passes through unchecked. Which required channels a node must carry is the
  validator's word, not the builder's (D-69, D-78).
  """
  @spec mark(atom(), data(), opts() | Var.t(), opts()) :: fragment()
  def mark(type, data, channels, opts) do
    base = %{type: type, data: data, channels: channels(type, channels)}
    %{marks: [node(:mark, base, options(type, opts))]}
  end

  @doc "As `label/3` with no options."
  @spec label(term(), list()) :: fragment()
  def label(anchor, text), do: label(anchor, text, [])

  @doc "One label of the frame: a text at an anchor (spec/14 §6.1)."
  @spec label(term(), list(), opts()) :: fragment()
  def label(anchor, text, opts) do
    %{labels: [node(:label, %{anchor: anchor, text: text}, opts)]}
  end

  @doc "As `title/2` with no options."
  @spec title(list()) :: fragment()
  def title(text), do: title(text, [])

  @doc "The design's title: `label/3` at the `:title` anchor (spec/14 §6.3)."
  @spec title(list(), opts()) :: fragment()
  def title(text, opts), do: label(:title, text, opts)

  # -- data nodes and transforms (spec/14 §16.5) ------------------------------------------

  @doc """
  The `:data` node of a mark reading `source` (spec/14 §5.4) — a node, not a fragment.

  It carries no `transforms` key, so a mark that reads its source directly and one built
  by `from/1` alone are the same map; the generated appenders — one per transform op (spec/14 §16.6) — add the steps.
  """
  @spec from(atom()) :: map()
  def from(source) when is_atom(source), do: %{source: source}

  # -- the schema's word on every key -----------------------------------------------------

  defp frame(name, kind, opts), do: %{frames: %{name => node(:frame, %{kind: kind}, opts)}}

  defp step(source, base, opts) when is_atom(source), do: step(from(source), base, opts)

  defp step(data, base, opts) when is_map(data) do
    transform = node(:transform, base, opts)
    Map.update(data, :transforms, [transform], &(&1 ++ [transform]))
  end

  defp channels(type, %Var{} = var) do
    _ = Schema.channels(type)
    var
  end

  defp channels(type, channels) do
    %{required: required, optional: optional} = Schema.channels(type)
    channels = Map.new(channels)
    reject!(Map.keys(channels) -- (required ++ optional), "a channel", type)
    channels
  end

  defp options(type, opts) do
    opts = Map.new(opts)

    case Map.fetch(opts, :options) do
      {:ok, %Var{}} -> opts
      {:ok, options} -> Map.put(opts, :options, mark_options(type, options))
      :error -> opts
    end
  end

  defp mark_options(type, options) do
    options = Map.new(options)
    reject!(Map.keys(options) -- Schema.options(type), "an option", type)
    options
  end

  defp reject!([], _what, _type), do: :ok

  defp reject!(keys, what, type) do
    raise ArgumentError,
          "#{list(keys)} is not #{what} of a #{inspect(type)} mark (spec/14 §5.2, §5.3)"
  end

  # A node's remaining keys, checked against the schema: the builder's arity checking.
  defp node(kind, base, opts) do
    opts = Map.new(opts)

    case Map.keys(opts) -- Enum.map(Schema.describe(kind), & &1.key) do
      [] ->
        Map.merge(base, opts)

      unknown ->
        raise ArgumentError,
              "#{list(unknown)} is not a key of a #{inspect(kind)} node (spec/14 §14.12)"
    end
  end

  defp list(keys), do: Enum.map_join(keys, ", ", &inspect/1)
end
