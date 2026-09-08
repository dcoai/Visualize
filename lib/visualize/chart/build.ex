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

  `var/2` declares a variable and its default under the design's `vars`;
  `Visualize.Chart.var/1` builds the `%Visualize.Chart.Var{}` term that *uses* one. They
  are different modules and different arities, so a caller may import both.

  ## Examples

      iex> import Visualize.Chart.Build
      iex> {:ok, design} =
      ...>   Visualize.Chart.compose([
      ...>     chart(meta: %{name: "Uptime"}),
      ...>     source(:primary, [:t, :v]),
      ...>     cartesian(400, 200),
      ...>     scale(:x, :time),
      ...>     scale(:y, :linear, domain: [0, :auto]),
      ...>     axis(:x, :bottom, ticks: 4),
      ...>     mark(:line, :primary, %{x: :t, y: :v}),
      ...>     title(["Uptime"])
      ...>   ])
      iex> design.marks
      [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      iex> design.frame.scales
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

  @doc "The design's theme: a name, or an inline `:theme` node (spec/14 §2.5)."
  @spec theme(atom() | map()) :: fragment()
  def theme(theme), do: %{theme: theme}

  # -- the frame (spec/14 §16.3) ----------------------------------------------------------

  @doc "As `cartesian/3` with no options."
  @spec cartesian(number(), number()) :: fragment()
  def cartesian(width, height), do: cartesian(width, height, [])

  @doc """
  A `:cartesian` frame of the given size (spec/14 §4.1).

  `opts` are the frame's remaining keys; its scales, axes and legend are their own
  fragments (`scale/3`, `axis/3`, `legend/2`).
  """
  @spec cartesian(number(), number(), opts()) :: fragment()
  def cartesian(width, height, opts), do: frame(:cartesian, width, height, opts)

  @doc "As `polar/3` with no options."
  @spec polar(number(), number()) :: fragment()
  def polar(width, height), do: polar(width, height, [])

  @doc "A `:polar` frame of the given size (spec/14 §4.6): `angle` and `r` are its scales."
  @spec polar(number(), number(), opts()) :: fragment()
  def polar(width, height, opts), do: frame(:polar, width, height, opts)

  @doc "As `geo/3` with no options."
  @spec geo(number(), number()) :: fragment()
  def geo(width, height), do: geo(width, height, [])

  @doc """
  A `:geo` frame of the given size (spec/14 §4.6).

  The projection is the frame's `projection:` key, a `:projection` node.
  """
  @spec geo(number(), number(), opts()) :: fragment()
  def geo(width, height, opts), do: frame(:geo, width, height, opts)

  @doc "As `facet/3` with no options."
  @spec facet(number(), number()) :: fragment()
  def facet(width, height), do: facet(width, height, [])

  @doc """
  A `:facet` frame of the given size (spec/14 §4.6).

  `by:` and `columns:`, the keys of the `:facet` node, are lifted into the frame's `facet`
  key: a `:facet` frame and its `facet` node name the same thing.
  """
  @spec facet(number(), number(), opts()) :: fragment()
  def facet(width, height, opts) do
    {facet, rest} = opts |> Map.new() |> Map.split([:by, :columns])
    frame(:facet, width, height, if(facet == %{}, do: rest, else: Map.put(rest, :facet, facet)))
  end

  @doc "As `scale/3` with no options."
  @spec scale(atom(), atom()) :: fragment()
  def scale(name, kind), do: scale(name, kind, [])

  @doc "One declared scale of the frame (spec/14 §4.3); `opts` are its remaining keys."
  @spec scale(atom(), atom(), opts()) :: fragment()
  def scale(name, kind, opts) do
    %{frame: %{scales: %{name => node(:scale, %{kind: kind}, opts)}}}
  end

  @doc "As `axis/3` with no options."
  @spec axis(atom(), atom()) :: fragment()
  def axis(scale, side), do: axis(scale, side, [])

  @doc "One axis of the frame, drawing `scale` on `side` (spec/14 §4.4)."
  @spec axis(atom(), atom(), opts()) :: fragment()
  def axis(scale, side, opts) do
    %{frame: %{axes: [node(:axis, %{scale: scale, side: side}, opts)]}}
  end

  @doc "As `legend/2` with no options."
  @spec legend(atom()) :: fragment()
  def legend(scale), do: legend(scale, [])

  @doc "The frame's legend, explaining `scale` (spec/14 §4.5)."
  @spec legend(atom(), opts()) :: fragment()
  def legend(scale, opts), do: %{frame: %{legend: node(:legend, %{scale: scale}, opts)}}

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
  by `from/1` alone are the same map; the appenders below add the steps.
  """
  @spec from(atom()) :: map()
  def from(source) when is_atom(source), do: %{source: source}

  @doc "As `bin/3` with no options."
  @spec bin(data(), atom()) :: map()
  def bin(data, field), do: bin(data, field, [])

  @doc "A `:bin` step over `field` appended to the data node (spec/14 §5.4.1)."
  @spec bin(data(), atom(), opts()) :: map()
  def bin(data, field, opts), do: step(data, %{op: :bin, field: field}, opts)

  @doc "As `filter/3` with no options."
  @spec filter(data(), atom()) :: map()
  def filter(data, field), do: filter(data, field, [])

  @doc """
  A `:filter` step over `field` appended to the data node (spec/14 §5.4.1).

  `test:` and `value:` are the step's remaining keys.
  """
  @spec filter(data(), atom(), opts()) :: map()
  def filter(data, field, opts), do: step(data, %{op: :filter, field: field}, opts)

  @doc "As `stack/3` with no options."
  @spec stack(data(), [atom()]) :: map()
  def stack(data, fields), do: stack(data, fields, [])

  @doc "A `:stack` step over the series `fields` appended to the data node (spec/14 §5.4.1)."
  @spec stack(data(), [atom()], opts()) :: map()
  def stack(data, fields, opts), do: step(data, %{op: :stack, fields: fields}, opts)

  @doc "As `treemap/2` with no options."
  @spec treemap(data()) :: map()
  def treemap(data), do: treemap(data, [])

  @doc "A `:treemap` step appended to the data node (spec/14 §5.4.2)."
  @spec treemap(data(), opts()) :: map()
  def treemap(data, opts), do: step(data, %{op: :treemap}, opts)

  # -- the schema's word on every key -----------------------------------------------------

  defp frame(kind, width, height, opts) do
    base = %{kind: kind, size: %{width: width, height: height}}
    %{frame: node(:frame, base, opts)}
  end

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
