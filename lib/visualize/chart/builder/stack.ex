if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Stack do
    @moduledoc """
    The builder's stack as a list of use sites, and the pure operations over it
    (spec/14 §19.3, §19.6, §19.9).

    The builder's state is `uses` — `%Visualize.Chart.Use{}` structs in stack order — and
    everything else the panels read is derived from them: the **resolved** layers, each use
    fetched through the store and its mask, bindings and local applied (§19.3); the
    **design**, which is the enabled ones stacked (§19.6); and the **labels** a person sees,
    which are a use's entry name or the name the host gave a layer it seeded.

    A host's `layers` assign is fragments, and a fragment the host gave is seeded as an
    **inline-only** use — `ref: nil`, the fragment as `local` — so the host's contract of
    §18.2 is unchanged: it gives a stack of fragments, and the builder makes sites of them.

    Disabling a layer is `mask: :all` (D-87 restated in §19.3). Selection is a use's id,
    so it survives every insert and move without being remapped.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    alias Visualize.Chart
    alias Visualize.Chart.Builder.Store
    alias Visualize.Chart.{Composite, Fragment, Use}

    @typedoc "A use's id to the name a person sees for it."
    @type labels :: %{Use.id() => String.t()}

    @typedoc "A resolved layer, as every panel has always read one: its label and its fragment."
    @type resolved :: {String.t(), map()}

    @doc """
    A host's layers as use sites, with their labels (spec/14 §19.9).

    A `{name, fragment}` pair keeps its name; a bare fragment is named by its position; a
    `%Visualize.Chart{}` is the map it is. Each becomes an inline-only use.
    """
    @spec seed([term()]) :: {[Use.t()], labels()}
    def seed(host_layers) do
      host_layers
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {layer, index}, {uses, labels} ->
        {name, fragment} = named(layer, index)
        use = %Use{id: {:use, index + 1}, ref: nil, local: fragment}
        {uses ++ [use], Map.put(labels, use.id, name)}
      end)
    end

    defp named({name, layer}, _index), do: {to_string(name), fragment(layer)}
    defp named(layer, index), do: {to_string(index), fragment(layer)}

    defp fragment(%Chart{} = chart), do: Chart.to_map(chart)
    defp fragment(map) when is_map(map), do: map

    @doc "The name a person sees for a use: its label, or its id when it has none."
    @spec label(labels(), Use.t()) :: String.t()
    def label(labels, %Use{id: {:use, n} = id}), do: Map.get(labels, id, "use #{n}")

    @doc "Whether a use contributes to the design: anything but a mask of everything."
    @spec enabled?(Use.t()) :: boolean()
    def enabled?(%Use{mask: :all}), do: false
    def enabled?(%Use{}), do: true

    @doc "A use with its enabled state flipped: disabling is a mask of everything (§19.3)."
    @spec toggle(Use.t()) :: Use.t()
    def toggle(%Use{mask: :all} = use), do: %{use | mask: []}
    def toggle(%Use{} = use), do: %{use | mask: :all}

    @doc "The fetch a store gives resolution: an id to `{:ok, fragment}` or `:error`."
    @spec fetch(Store.store() | nil) :: (Fragment.id() -> {:ok, map()} | :error)
    def fetch(nil), do: fn _id -> :error end

    def fetch(store) do
      fn id ->
        case Store.get(store, id) do
          {:ok, entry} -> {:ok, entry.fragment}
          :error -> :error
        end
      end
    end

    @doc """
    Every use resolved to a layer the panels can read — `{label, fragment}` — and the refs
    no store could find (spec/14 §19.2, §19.3). A disabled use resolves as it would enabled:
    the panels edit what a layer says whether or not the design is drawing it, and its mask
    of everything has its whole effect in `design/2`.
    """
    @spec resolve(
            [Use.t()],
            labels(),
            (Fragment.id() -> {:ok, map()} | :error)
          ) :: {[resolved()], [{Use.id(), Fragment.id()}]}
    def resolve(uses, labels, fetch) do
      Enum.reduce(uses, {[], []}, fn use, {layers, missing} ->
        case Use.resolve(shown(use), fetch) do
          {:ok, fragment} ->
            {layers ++ [{label(labels, use), fragment}], missing}

          {:missing, ref, fragment} ->
            {layers ++ [{label(labels, use), fragment}], missing ++ [{use.id, ref}]}
        end
      end)
    end

    defp shown(%Use{mask: :all} = use), do: %{use | mask: []}
    defp shown(use), do: use

    @doc """
    The design the stack stands for: the enabled uses as a composite, flattened through
    the store, with every `{:style, n}` inlined so the frame can draw it (spec/14 §19.6).
    """
    @spec design([Use.t()], (Fragment.id() -> {:ok, map()} | :error)) ::
            {:ok, map(), [{Use.id(), Fragment.id()}]} | {:error, term()}
    def design(uses, fetch) do
      composite = %{composite: %{uses: Enum.filter(uses, &enabled?/1), vars: %{}}}

      case Composite.flatten(composite, fetch) do
        {:ok, design, %{missing: missing}} -> {:ok, inline_styles(design, fetch), missing}
        {:error, _} = error -> error
      end
    end

    # A `{:style, n}` at a style site stands for the body the store holds under it. The
    # frame resolves a stack of names and inline nodes (§3.6); an id becomes the inline node
    # here, so nothing below the builder needs a store.
    defp inline_styles(design, fetch) do
      walk(design, fn
        {:style, n} = id when is_integer(n) ->
          case fetch.(id) do
            {:ok, body} -> style_body(body)
            :error -> %{}
          end

        other ->
          other
      end)
    end

    defp style_body(%{style: body}) when is_map(body), do: body

    defp style_body(%{styles: styles}) when is_map(styles) do
      case Map.values(styles) do
        [only] -> only
        _several -> %{}
      end
    end

    defp style_body(_other), do: %{}

    defp walk(%_{} = struct, _fun), do: struct
    defp walk(map, fun) when is_map(map), do: Map.new(map, fn {k, v} -> {k, walk(v, fun)} end)
    defp walk(list, fun) when is_list(list), do: Enum.map(list, &walk(&1, fun))

    defp walk({:style, n} = id, fun) when is_integer(n), do: fun.(id)

    defp walk(tuple, fun) when is_tuple(tuple),
      do: tuple |> Tuple.to_list() |> Enum.map(&walk(&1, fun)) |> List.to_tuple()

    defp walk(leaf, fun), do: fun.(leaf)

    @doc "The position of a use in the stack, or `nil`."
    @spec index_of([Use.t()], Use.id() | nil) :: non_neg_integer() | nil
    def index_of(_uses, nil), do: nil
    def index_of(uses, id), do: Enum.find_index(uses, &(&1.id == id))

    @doc "The use with an id, or `nil`."
    @spec get([Use.t()], Use.id() | nil) :: Use.t() | nil
    def get(_uses, nil), do: nil
    def get(uses, id), do: Enum.find(uses, &(&1.id == id))

    @doc "The stack with one use replaced by a function of it; a missing id changes nothing."
    @spec update([Use.t()], Use.id(), (Use.t() -> Use.t())) :: [Use.t()]
    def update(uses, id, fun) do
      Enum.map(uses, fn use -> if use.id == id, do: fun.(use), else: use end)
    end

    @doc """
    A write into a use's `local` at a path (spec/14 §19.3): a `{:ok, value}` sets the key,
    `:error` removes it. A container the local does not carry yet is an empty node on the
    way (§18.5).
    """
    @spec write(Use.t(), [term()], atom(), {:ok, term()} | :error) :: Use.t()
    def write(%Use{local: local} = use, path, key, parsed) do
      %{use | local: write_at(local, path, key, parsed)}
    end

    @doc "A write into any fragment at a path, as `write/4` does into a use's local."
    @spec write_at(map(), [term()], atom(), {:ok, term()} | :error) :: map()
    def write_at(fragment, path, key, {:ok, value}),
      do: update_node(fragment, path, &Map.put(&1, key, value))

    def write_at(fragment, path, key, :error),
      do: update_node(fragment, path, &Map.delete(&1, key))

    defp update_node(nil, [], fun), do: fun.(%{})
    defp update_node(container, [], fun), do: fun.(container)

    defp update_node(nil, [key | _rest] = path, fun) when is_atom(key),
      do: update_node(%{}, path, fun)

    defp update_node(list, [index | rest], fun) when is_list(list) and is_integer(index),
      do: List.update_at(list, index, &update_node(&1, rest, fun))

    defp update_node(map, [key | rest], fun) when is_map(map),
      do: Map.put(map, key, update_node(Map.get(map, key), rest, fun))

    @doc "A move within the stack: list surgery, and nothing to remap (§19.3)."
    @spec move([Use.t()], non_neg_integer(), non_neg_integer()) :: [Use.t()]
    def move(uses, from, to) when from != to and from >= 0 and to >= 0 do
      if from < length(uses) and to < length(uses) do
        {use, rest} = List.pop_at(uses, from)
        List.insert_at(rest, to, use)
      else
        uses
      end
    end

    def move(uses, _from, _to), do: uses

    @doc "The kinds *new fragment of a kind* offers, the composite first (spec/14 §19.8)."
    @spec kinds() :: [atom(), ...]
    def kinds,
      do: [
        :composite,
        :design,
        :theme,
        :style,
        :frame,
        :scale,
        :axis,
        :source,
        :var,
        :mark,
        :label
      ]

    @doc "The empty, valid fragment of a kind, for *new fragment of a kind* (spec/14 §19.8)."
    @spec empty(atom()) :: map()
    def empty(:composite), do: %{composite: %{uses: [], vars: %{}}}
    def empty(:design), do: %{version: 1, frame: %{kind: :cartesian}}
    def empty(:theme), do: %{theme: %{}}
    def empty(:frame), do: %{frame: %{}}

    def empty(kind) when kind in [:style, :scale, :source, :axis, :mark, :label, :var],
      do: %{kind => %{}}

    def empty(kind), do: %{kind => %{}}
  end
end
