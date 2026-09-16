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

    A `{name, layer}` pair keeps its name; a bare layer is named by its position. A
    fragment — a map, or a `%Visualize.Chart{}` as the map it is — becomes an inline-only
    use; an id `{kind, n}` becomes a use referring to it, so a host may start the builder
    over entries of its own library.
    """
    @spec seed([term()]) :: {[Use.t()], labels()}
    def seed(host_layers) do
      host_layers
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {layer, index}, {uses, labels} ->
        {name, site} = named(layer, index)
        use = struct!(Use, Map.put(site, :id, {:use, index + 1}))
        {uses ++ [use], Map.put(labels, use.id, name)}
      end)
    end

    # An id is a pair too; it is told from a `{name, layer}` pair by its integer.
    defp named({kind, n}, index) when is_atom(kind) and is_integer(n),
      do: {to_string(index), site({kind, n})}

    defp named({name, layer}, _index), do: {to_string(name), site(layer)}
    defp named(layer, index), do: {to_string(index), site(layer)}

    defp site({kind, n}) when is_atom(kind) and is_integer(n), do: %{ref: {kind, n}}
    defp site(%Chart{} = chart), do: %{ref: nil, local: Chart.to_map(chart)}
    defp site(map) when is_map(map), do: %{ref: nil, local: map}

    @doc """
    An entry as the inline sites a copy of it is (spec/14 §18.17): a composite's sites,
    each holding what its use contributed — the referenced fragment (flattened, when it is
    a composite) stacked under the use's `local`, the use's `mask`, `vars` and `key` kept
    — labelled with the referenced entry's name, or the composite's own for a site it
    declares in place, with the composite's own vars and signals; any other body as one
    inline site named for the entry. The sites carry no id: the caller issues one each
    among the stack they join.
    """
    @spec copies(
            %{kind: atom(), name: String.t() | nil, fragment: map()},
            (Fragment.id() -> {:ok, map()} | :error),
            (Fragment.id() -> String.t() | nil)
          ) :: {[{Use.t(), String.t()}], map(), map()}
    def copies(%{fragment: %{composite: %{uses: uses} = composite}} = entry, fetch, name_of)
        when is_list(uses) do
      resolve = flattening(fetch)
      own = Map.get(entry, :name) || "local"

      sites =
        for %Use{} = use <- uses do
          {body, name} =
            case use.ref do
              nil ->
                {use.local, own}

              ref ->
                case resolve.(ref) do
                  {:ok, fragment} -> {Chart.stack([fragment, use.local]), name_of.(ref)}
                  :error -> {use.local, nil}
                end
            end

          {%Use{id: nil, ref: nil, local: body, mask: use.mask, vars: use.vars, key: use.key},
           name || "#{elem(use.ref, 0)} #{elem(use.ref, 1)}"}
        end

      {sites, Map.get(composite, :vars, %{}), Map.get(composite, :signals, %{})}
    end

    def copies(%{kind: kind, name: name, fragment: fragment}, _fetch, _name_of) do
      {[{%Use{id: nil, ref: nil, local: fragment}, name || "new #{kind}"}], %{}, %{}}
    end

    @doc """
    An entry as a stack (spec/14 §19.9): a composite's sites, labelled by the store's
    names, with its vars and its signals (§19.10); any other body as one inline site named
    for the entry.
    """
    @spec open(%{kind: atom(), name: String.t() | nil, fragment: map()}, (Fragment.id() ->
                                                                            String.t() | nil)) ::
            {[Use.t()], labels(), map(), map()}
    def open(%{fragment: %{composite: %{uses: uses} = composite}}, name_of) when is_list(uses) do
      labels =
        Map.new(uses, fn
          %Use{id: id, ref: nil} -> {id, "local"}
          %Use{id: id, ref: ref} -> {id, name_of.(ref) || "#{elem(ref, 0)} #{elem(ref, 1)}"}
        end)

      {uses, labels, Map.get(composite, :vars, %{}), Map.get(composite, :signals, %{})}
    end

    def open(%{kind: kind, name: name, fragment: fragment}, _name_of) do
      use = %Use{id: {:use, 1}, ref: nil, local: fragment}
      {[use], %{use.id => name || "new #{kind}"}, %{}, %{}}
    end

    @doc "The stack as a composite: what saving sends and a composite stores (spec/14 §19.6)."
    @spec structure([Use.t()], map()) :: map()
    def structure(uses, vars), do: %{composite: %{uses: uses, vars: vars}}

    @doc "As `structure/2`, with the chart's signals when it has any (spec/14 §19.10)."
    @spec structure(list(), map(), map()) :: map()
    def structure(uses, vars, signals) when map_size(signals) == 0, do: structure(uses, vars)

    def structure(uses, vars, signals),
      do: %{composite: %{uses: uses, vars: vars, signals: signals}}

    @doc """
    The lowest tier that holds the stack (D-99): one bare inline site is its body, values
    and nothing else; anything more — a ref, a mask, a binding, a second site, a var — is
    structure.
    """
    @spec body([Use.t()], map()) :: map()
    def body([%Use{ref: nil, mask: [], vars: vars, local: local}], stack_vars)
        when map_size(vars) == 0 and map_size(stack_vars) == 0,
        do: local

    def body(uses, vars), do: structure(uses, vars)

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
        case Use.resolve(shown(use), flattening(fetch)) do
          {:ok, fragment} ->
            {layers ++ [{label(labels, use), fragment}], missing}

          {:missing, ref, fragment} ->
            {layers ++ [{label(labels, use), fragment}], missing ++ [{use.id, ref}]}
        end
      end)
    end

    defp shown(%Use{mask: :all} = use), do: %{use | mask: []}
    defp shown(use), do: use

    # The panels read a site that refers to a composite as what the composite flattens to
    # (§19.9): its sites are its own affair. One that reaches itself is a mask here, as a
    # missing entry is; the design's fault names the cycle.
    defp flattening(fetch) do
      fn id ->
        case fetch.(id) do
          {:ok, %{composite: _} = composite} ->
            case Composite.flatten(composite, fetch) do
              {:ok, flat, _report} -> {:ok, flat}
              {:error, _cycle} -> :error
            end

          other ->
            other
        end
      end
    end

    @doc """
    The enabled uses as the layers the design is stacked from — `{id, fragment}` in stack
    order, each resolved and placed where the design keeps its kind (spec/14 §18.15,
    §19.6) — so `Visualize.Chart.explain/1` over them says which use gave every value. A
    name-keyed site with no key has nowhere to be placed and is left out, as `design/3`
    leaves it out.

        iex> uses = [
        ...>   %Visualize.Chart.Use{id: {:use, 1}, ref: nil, local: %{frame: %{kind: :cartesian}}},
        ...>   %Visualize.Chart.Use{id: {:use, 2}, ref: nil, key: :primary, local: %{source: %{fields: [:t]}}},
        ...>   %Visualize.Chart.Use{id: {:use, 3}, ref: nil, mask: :all, local: %{theme: :dark}}
        ...> ]
        iex> Visualize.Chart.Builder.Stack.placed(uses, fn _id -> :error end)
        [{{:use, 1}, %{frame: %{kind: :cartesian}}}, {{:use, 2}, %{sources: %{primary: %{fields: [:t]}}}}]
    """
    @spec placed([Use.t()], (Fragment.id() -> {:ok, map()} | :error)) :: [{Use.id(), map()}]
    def placed(uses, fetch) do
      for use <- uses,
          enabled?(use),
          {:ok, layer} <- [Composite.place(shown_fragment(use, fetch), use)],
          do: {use.id, layer}
    end

    defp shown_fragment(use, fetch) do
      case Use.resolve(shown(use), flattening(fetch)) do
        {:ok, fragment} -> fragment
        {:missing, _ref, fragment} -> fragment
      end
    end

    @doc """
    The path a design path has inside a use: a site of one kind holds its body under the
    kind's key (spec/14 §19.3), so the design's `sources.primary` is a `source` site's
    `[:source]`, and a design-level site's path is its own (§18.15).

        iex> use = %Visualize.Chart.Use{id: {:use, 1}, ref: nil, key: :primary, local: %{source: %{fields: [:t]}}}
        iex> Visualize.Chart.Builder.Stack.local_path(use, fn _id -> :error end, [:sources, :primary])
        [:source]
        iex> Visualize.Chart.Builder.Stack.local_path(use, fn _id -> :error end, [:sources, :primary, :fields])
        [:source, :fields]
        iex> mark = %Visualize.Chart.Use{id: {:use, 2}, ref: nil, local: %{mark: %{type: :line}}}
        iex> Visualize.Chart.Builder.Stack.local_path(mark, fn _id -> :error end, [:marks, 3, :channels])
        [:mark, :channels]
        iex> house = %Visualize.Chart.Use{id: {:use, 3}, ref: nil, local: %{frame: %{kind: :cartesian}}}
        iex> Visualize.Chart.Builder.Stack.local_path(house, fn _id -> :error end, [:frame, :size])
        [:frame, :size]
    """
    @spec local_path(Use.t(), (Fragment.id() -> {:ok, map()} | :error), [term()]) :: [term()]
    def local_path(use, fetch, path) do
      case {Fragment.wrapped(shown_fragment(use, fetch)), path} do
        {{:style, _}, [:styles, _key | rest]} -> [:style | rest]
        {{:source, _}, [:sources, _key | rest]} -> [:source | rest]
        {{:var, _}, [:vars, _key | rest]} -> [:var | rest]
        {{:gradient, _}, [:defs, _key | rest]} -> [:gradient | rest]
        {{:mark, _}, [:marks, _index | rest]} -> [:mark | rest]
        {{:label, _}, [:labels, _index | rest]} -> [:label | rest]
        {{:scale, _}, [:frame, :scales, _key | rest]} -> [:scale | rest]
        {{:axis, _}, [:frame, :axes, _index | rest]} -> [:axis | rest]
        _own -> path
      end
    end

    @doc """
    The design the stack stands for: the enabled uses as a composite over the stack's own
    vars, flattened through the store, every id at a reference site resolved, so the frame
    can draw it (spec/14 §19.6).
    """
    @spec design([Use.t()], map(), (Fragment.id() -> {:ok, map()} | :error)) ::
            {:ok, map(), Composite.report()} | {:error, term()}
    def design(uses, vars, fetch) do
      composite = structure(Enum.filter(uses, &enabled?/1), vars)

      case Composite.flatten(composite, fetch) do
        {:ok, design, report} -> {:ok, design, report}
        {:error, _} = error -> error
      end
    end

    @doc """
    Each site that carries variables: the free variables of its fragment *before* the
    site's bindings — the names the fragment itself uses — and what the site binds them
    to, for the Variables tab's per-site rows (spec/14 §19.4, §19.10).
    """
    @spec sites([Use.t()], labels(), (Fragment.id() -> {:ok, map()} | :error)) :: [
            %{
              index: non_neg_integer(),
              id: Use.id(),
              label: String.t(),
              free: [Chart.free_var()],
              vars: map()
            }
          ]
    def sites(uses, labels, fetch) do
      uses
      |> Enum.with_index()
      |> Enum.flat_map(fn {use, index} ->
        label = label(labels, use)
        {_status, fragment} = unbound(use, fetch)

        case Chart.free_vars([{label, fragment}]) do
          [] -> []
          free -> [%{index: index, id: use.id, label: label, free: free, vars: use.vars}]
        end
      end)
    end

    @doc """
    What a site contributes before its mask — the referenced body, or nothing, under its
    local — so the context panel can offer every key the mask could remove (spec/14 §19.5).
    """
    @spec unmasked(Use.t(), (Fragment.id() -> {:ok, map()} | :error)) :: map()
    def unmasked(%Use{} = use, fetch) do
      case Use.resolve(%{use | mask: [], vars: %{}}, flattening(fetch)) do
        {:ok, fragment} -> fragment
        {:missing, _ref, fragment} -> fragment
      end
    end

    defp unbound(use, fetch) do
      case Use.resolve(%{shown(use) | vars: %{}}, flattening(fetch)) do
        {:ok, fragment} -> {:ok, fragment}
        {:missing, _ref, fragment} -> {:missing, fragment}
      end
    end

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

    @doc """
    The kinds *new fragment of a kind* offers, the composite first and never a design: a
    design is the deployed tier, and a composite deploys to one (spec/14 §19.6, §19.8).
    """
    @spec kinds() :: [atom(), ...]
    def kinds,
      do: [
        :composite,
        :theme,
        :style,
        :frame,
        :scale,
        :axis,
        :source,
        :var,
        :gradient,
        :mark,
        :label
      ]

    @doc "The empty, valid fragment of a kind, for *new fragment of a kind* (spec/14 §19.8)."
    @spec empty(atom()) :: map()
    def empty(:composite), do: %{composite: %{uses: [], vars: %{}}}
    def empty(:theme), do: %{theme: %{}}
    def empty(:frame), do: %{frame: %{}}

    def empty(kind) when kind in [:style, :scale, :source, :axis, :mark, :label, :var],
      do: %{kind => %{}}

    def empty(kind), do: %{kind => %{}}
  end
end
