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

    # An id is a pair too; it is told from a `{name, layer}` pair by its integer. A `nil`
    # where a fragment was expected is a host that resolved a name to nothing: refused with
    # the name, so the bug is read at the line that lies (spec/14 §18.2, #272).
    defp named({kind, n}, index) when is_atom(kind) and is_integer(n),
      do: {to_string(index), site({kind, n})}

    defp named({name, nil}, _index), do: nil_layer(name)
    defp named({name, layer}, _index), do: {to_string(name), site(layer)}
    defp named(nil, index), do: nil_layer(index)
    defp named(layer, index), do: {to_string(index), site(layer)}

    defp nil_layer(name) do
      raise ArgumentError,
            "layer #{inspect(to_string(name))} is nil: the host gave a name with no fragment " <>
              "or id behind it — a library entry that was not found, or a seed that failed"
    end

    defp site({kind, n}) when is_atom(kind) and is_integer(n), do: %{ref: {kind, n}}
    defp site(%Chart{} = chart), do: %{ref: nil, local: Chart.to_map(chart)}
    defp site(map) when is_map(map), do: %{ref: nil, local: map}

    @doc """
    An entry as the inline sites a copy of it is (spec/14 §18.17): a composite's sites,
    each holding what its use contributed — the referenced fragment (flattened, when it is
    a composite) stacked under the use's `local`, the use's `mask`, `vars` and `key` kept
    — labeled with the referenced entry's name, or the composite's own for a site it
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
          body =
            case use.ref do
              nil ->
                use.local

              ref ->
                case resolve.(ref) do
                  {:ok, fragment} -> Chart.stack([fragment, use.local])
                  :error -> use.local
                end
            end

          {%Use{id: nil, ref: nil, local: body, mask: use.mask, vars: use.vars, key: use.key},
           inner_label(use, name_of, own)}
        end

      {sites, Map.get(composite, :vars, %{}), Map.get(composite, :signals, %{})}
    end

    def copies(%{kind: kind, name: name, fragment: fragment}, _fetch, _name_of) do
      {[{%Use{id: nil, ref: nil, local: fragment}, name || "new #{kind}"}], %{}, %{}}
    end

    @doc """
    The name a site of a composite is shown by (spec/14 §18.8, §18.17): a referenced
    site by its entry's name — its id when the store has none — and a site the composite
    declares in place by its kind (#380), or by `own`, the composite's name, when it
    declares several. A copy's sites are labeled so, and so are a referenced group's rows.

        iex> name_of = fn {:style, 1} -> "Styles::thick"; _id -> nil end
        iex> Visualize.Chart.Builder.Stack.inner_label(%Visualize.Chart.Use{id: {:use, 1}, ref: {:style, 1}}, name_of, "pair")
        "Styles::thick"
        iex> Visualize.Chart.Builder.Stack.inner_label(%Visualize.Chart.Use{id: {:use, 1}, ref: {:frame, 9}}, name_of, "pair")
        "frame 9"
        iex> Visualize.Chart.Builder.Stack.inner_label(%Visualize.Chart.Use{id: {:use, 1}, ref: nil, local: %{mark: %{type: :line}}}, name_of, "pair")
        "mark"
        iex> Visualize.Chart.Builder.Stack.inner_label(%Visualize.Chart.Use{id: {:use, 1}, ref: nil, local: %{version: 2}}, name_of, "pair")
        "pair"
    """
    @spec inner_label(Use.t(), (Fragment.id() -> String.t() | nil), String.t()) :: String.t()
    def inner_label(%Use{ref: nil, local: local}, _name_of, own) do
      case Map.keys(local) do
        [kind] when kind in [:frames, :theme, :meta] ->
          to_string(kind)

        _keys ->
          case Fragment.wrapped(local) do
            {kind, _body} -> to_string(kind)
            nil -> own
          end
      end
    end

    def inner_label(%Use{ref: {kind, n} = ref}, name_of, _own),
      do: name_of.(ref) || "#{kind} #{n}"

    @doc """
    An entry as a stack (spec/14 §19.9): a composite's sites, labeled by the store's
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

    @doc """
    Whether a use is the library's word — it references an entry — and so is locked in the
    chart: read-only, edited by opening the entry (spec/14 §18.8, §18.15).

        iex> Visualize.Chart.Builder.Stack.locked?(Visualize.Chart.Use.new({:style, 3}))
        true
        iex> Visualize.Chart.Builder.Stack.locked?(Visualize.Chart.Use.new(nil))
        false
    """
    @spec locked?(Use.t()) :: boolean()
    def locked?(%Use{ref: nil}), do: false
    def locked?(%Use{}), do: true

    @doc """
    A use's state toward the library (spec/14 §18.8, §19.3, #381): `:inline` with no ref and
    no origin, `:linked` with a ref and no local, `:edited` with a ref over a local — locked
    again after edits — and `:unlocked` with an origin and no ref.

        iex> alias Visualize.Chart.{Builder.Stack, Use}
        iex> Stack.linkage(Use.new({:style, 3}))
        :linked
        iex> Stack.linkage(%{Use.new({:style, 3}) | local: %{stroke: "#111"}})
        :edited
        iex> Stack.linkage(%{Use.new(nil) | origin: {:style, 3}})
        :unlocked
        iex> Stack.linkage(Use.new(nil))
        :inline
    """
    @spec linkage(Use.t()) :: :inline | :linked | :edited | :unlocked
    def linkage(%Use{ref: nil, origin: nil}), do: :inline
    def linkage(%Use{ref: nil}), do: :unlocked
    def linkage(%Use{local: local}) when map_size(local) == 0, do: :linked
    def linkage(%Use{}), do: :edited

    @doc """
    A use unlocked from its entry (spec/14 §18.8, #381): the ref moved to `origin` and the
    entry's body copied into `local` under whatever the site already held there; mask, vars
    and key stay the site's, so the chart draws as it did. A composite entry unlocks to a
    group of copies of its sites, as `copies/3` reads them, the composite's vars the
    group's; the inner sites come with `nil` ids for the caller to issue, and their labels
    and the entry's signals are returned beside the use.
    """
    @spec unlocked(
            Use.t(),
            %{kind: atom(), name: String.t() | nil, fragment: map()},
            (Fragment.id() -> {:ok, map()} | :error),
            (Fragment.id() -> String.t() | nil)
          ) :: {Use.t(), [{Use.t(), String.t()}], map()}
    def unlocked(%Use{ref: ref} = use, entry, fetch, name_of) when ref != nil do
      {sites, vars, signals} = copies(entry, fetch, name_of)

      local =
        case entry do
          %{kind: :composite} ->
            %{composite: %{uses: Enum.map(sites, &elem(&1, 0)), vars: vars}}

          _object ->
            [{%Use{local: body}, _name}] = sites
            Chart.stack([body, use.local])
        end

      labeled = if match?(%{kind: :composite}, entry), do: sites, else: []
      {%{use | ref: nil, origin: ref, local: local}, labeled, signals}
    end

    @doc """
    A use with an origin linked to it again, its local kept over the link (spec/14 §18.8,
    #381); a use with no origin has nothing to link to and is unchanged.

        iex> alias Visualize.Chart.{Builder.Stack, Use}
        iex> use = %{Use.new(nil) | origin: {:style, 3}, local: %{stroke: "#111"}}
        iex> Stack.locked(use) |> Map.take([:ref, :origin, :local])
        %{ref: {:style, 3}, origin: nil, local: %{stroke: "#111"}}
    """
    @spec locked(Use.t()) :: Use.t()
    def locked(%Use{origin: nil} = use), do: use
    def locked(%Use{origin: origin} = use), do: %{use | ref: origin, origin: nil}

    @doc """
    A use as the library has it (spec/14 §18.8, #381): its local dropped, its ref restored
    from its origin where it was unlocked, mask, vars and key kept — they are the site's.

        iex> alias Visualize.Chart.{Builder.Stack, Use}
        iex> use = %{Use.new(nil) | origin: {:style, 3}, local: %{stroke: "#111"}, mask: [:fill]}
        iex> Stack.reverted(use) |> Map.take([:ref, :origin, :local, :mask])
        %{ref: {:style, 3}, origin: nil, local: %{}, mask: [:fill]}
    """
    @spec reverted(Use.t()) :: Use.t()
    def reverted(%Use{} = use), do: %{locked(use) | local: %{}}

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
            {layers ++ [{label(labels, use), flat(fragment, fetch)}], missing}

          {:missing, ref, fragment} ->
            {layers ++ [{label(labels, use), flat(fragment, fetch)}], missing ++ [{use.id, ref}]}
        end
      end)
    end

    # An inline group's body is what it flattens to (#380), as a referenced composite's is
    # through `flattening/1`; anything else is itself.
    defp flat(%{composite: %{uses: uses}} = fragment, fetch) when is_list(uses) do
      case Composite.flatten(fragment, fetch) do
        {:ok, design, _report} -> design
        {:error, _cycle} -> %{}
      end
    end

    defp flat(fragment, _fetch), do: fragment

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
        ...>   %Visualize.Chart.Use{id: {:use, 1}, ref: nil, local: %{frames: %{main: %{kind: :cartesian}}}},
        ...>   %Visualize.Chart.Use{id: {:use, 2}, ref: nil, key: :primary, local: %{source: %{fields: [:t]}}},
        ...>   %Visualize.Chart.Use{id: {:use, 3}, ref: nil, mask: :all, local: %{theme: :dark}}
        ...> ]
        iex> Visualize.Chart.Builder.Stack.placed(uses, fn _id -> :error end)
        [{{:use, 1}, %{frames: %{main: %{kind: :cartesian}}}}, {{:use, 2}, %{sources: %{primary: %{fields: [:t]}}}}]
    """
    @spec placed([Use.t()], (Fragment.id() -> {:ok, map()} | :error)) :: [{Use.id(), map()}]
    def placed(uses, fetch) do
      Enum.flat_map(uses, fn use ->
        cond do
          not enabled?(use) ->
            []

          # An inline group is its objects, each attributed to itself (#380); the group's
          # own vars are placed as the group's, and its defaults laid under what each of its
          # objects places, as the flattening lays them (spec/14 §3.8, §18.7, #684).
          group?(use) ->
            vars = get_in(use.local, [:composite, :vars]) || %{}
            defaults = get_in(use.local, [:composite, :defaults])
            own = if map_size(vars) == 0, do: [], else: [{use.id, %{vars: vars}}]

            own ++
              for {id, layer} <- placed(children(use), fetch),
                  do: {id, Composite.scope(layer, defaults)}

          true ->
            case Composite.place(shown_fragment(use, fetch), use) do
              {:ok, layer} -> [{use.id, layer}]
              :keyless -> []
            end
        end
      end)
    end

    defp shown_fragment(use, fetch) do
      case Use.resolve(shown(use), flattening(fetch)) do
        {:ok, fragment} -> flat(fragment, fetch)
        {:missing, _ref, fragment} -> flat(fragment, fetch)
      end
    end

    @doc """
    One use's contribution placed where the design keeps its kind (spec/14 §18.8, #283):
    resolved through the flattening fetch, as `placed/2` resolves it, so a reference to a
    composite is what the composite flattens to; its mask ignored, since a disabled layer
    still declares what it declares; a missing entry its local alone; a keyless site `%{}`.

        iex> use = %Visualize.Chart.Use{id: {:use, 1}, ref: nil, mask: :all, local: %{axis: %{scale: :x, side: :bottom}}}
        iex> Visualize.Chart.Builder.Stack.contribution(use, fn _id -> :error end)
        %{frames: %{main: %{axes: [%{scale: :x, side: :bottom}]}}}
    """
    @spec contribution(Use.t(), (Fragment.id() -> {:ok, map()} | :error)) :: map()
    def contribution(%Use{} = use, fetch) do
      case Composite.place(shown_fragment(%{use | mask: []}, fetch), use) do
        {:ok, placed} -> placed
        :keyless -> %{}
      end
    end

    @doc """
    The site that copies or overrides a node the use contributes (spec/14 §18.16, #379):
    `%{local, key, mask, lifted}` — the inline site's local and key, the mask path to add
    to the owner or `nil`, and how many members were lifted — or `:error` when the use does
    not contribute the node. The node carries its `body` as the design composes it, since a
    list member's index in the design is not its index in the owner's list. A `:copy` takes a fresh id or key, avoiding `taken`; an
    `:override` keeps the node's identity and, for a node with none — a label, a mark with
    no `id` — lifts the owner's whole list and masks it at the finest path the owner's
    contribution has for it.

        iex> use = %Visualize.Chart.Use{id: {:use, 1}, ref: nil, local: %{frames: %{main: %{kind: :cartesian, axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}]}}}}
        iex> node = %{kind: :axis, path: [:frames, :main, :axes, 1], label: "frames.main.axes[1]", body: %{scale: :y, side: :left}}
        iex> Visualize.Chart.Builder.Stack.lifted(:copy, use, fn _ -> :error end, node, [])
        %{local: %{axis: %{scale: :y, side: :left}}, key: nil, mask: nil, lifted: 1}
        iex> style = %Visualize.Chart.Use{id: {:use, 2}, ref: nil, key: :series, local: %{style: %{stroke: "#111"}}}
        iex> Visualize.Chart.Builder.Stack.lifted(:copy, style, fn _ -> :error end, %{kind: :style, path: [:styles, :series], label: "styles.series"}, [:series, :series_2])
        %{local: %{style: %{stroke: "#111"}}, key: :series_3, mask: nil, lifted: 1}
        iex> labels = %Visualize.Chart.Use{id: {:use, 3}, ref: nil, local: %{labels: [%{anchor: :title, text: ["a"]}, %{anchor: :caption, text: ["b"]}]}}
        iex> Visualize.Chart.Builder.Stack.lifted(:override, labels, fn _ -> :error end, %{kind: :label, path: [:labels, 1], label: "labels[1]", body: %{anchor: :caption, text: ["b"]}}, [])
        %{local: %{labels: [%{anchor: :title, text: ["a"]}, %{anchor: :caption, text: ["b"]}]}, key: nil, mask: [:labels], lifted: 2}
    """
    @spec lifted(:copy | :override, Use.t(), (Fragment.id() -> {:ok, map()} | :error), map(), [
            atom()
          ]) ::
            %{local: map(), key: atom() | nil, mask: [atom()] | nil, lifted: pos_integer()}
            | :error
    def lifted(mode, %Use{} = use, fetch, %{kind: kind, path: path} = node, taken) do
      placed = contribution(use, fetch)

      case member(placed, path, Map.get(node, :body)) do
        nil ->
          :error

        body ->
          key = keyed_name(path)

          case {mode, identity?(kind, body)} do
            {:copy, _} ->
              %{
                local: wrap(kind, path, fresh_id(kind, body, taken)),
                key: fresh_key(key, taken),
                mask: nil,
                lifted: 1
              }

            {:override, true} ->
              %{local: wrap(kind, path, body), key: key, mask: nil, lifted: 1}

            # A site of the one kind is the whole of it: copied as it is, masked whole.
            {:override, false} ->
              case wrapped_site(use, fetch) do
                {site_kind, site_body} ->
                  %{local: %{site_kind => site_body}, key: key, mask: [site_kind], lifted: 1}

                nil ->
                  list_path = Enum.take_while(path, &is_atom/1)
                  members = List.wrap(at(placed, list_path))

                  %{
                    local: put_in_local(%{}, list_path, members),
                    key: key,
                    mask: mask_path(list_path),
                    lifted: length(members)
                  }
              end
          end
      end
    end

    defp wrapped_site(use, fetch), do: Fragment.wrapped(shown_fragment(use, fetch))

    # The node in the owner's contribution: at its path, or — a member of a list, whose
    # index in the design is not its index in the owner's list — the member equal to the
    # design's body, else the one with its identity.
    defp member(placed, path, body) do
      case Enum.split_while(path, &is_atom/1) do
        {_all, []} ->
          at(placed, path)

        {list_path, [_index | _rest]} ->
          list = List.wrap(at(placed, list_path))

          Enum.find(list, &(&1 == body)) ||
            Enum.find(list, &(body != nil and same_identity?(&1, body))) ||
            if(body == nil and length(list) == 1, do: hd(list))
      end
    end

    defp same_identity?(%{id: id}, %{id: id}), do: true
    defp same_identity?(%{scale: s, side: d}, %{scale: s, side: d}), do: true
    defp same_identity?(_a, _b), do: false

    # A node whose copy replaces the original in the cascade (spec/14 §8.2): an axis by
    # scale and side, a mark by id, a keyed kind by key, the frame and its parts key by key.
    defp identity?(:axis, %{scale: _, side: _}), do: true
    defp identity?(:mark, %{id: _}), do: true
    defp identity?(:mark, _body), do: false
    defp identity?(:label, _body), do: false
    defp identity?(_kind, _body), do: true

    defp keyed_name([:styles, name]) when is_atom(name), do: name
    defp keyed_name([:sources, name]) when is_atom(name), do: name
    defp keyed_name([:vars, name]) when is_atom(name), do: name
    defp keyed_name([:frames, _frame, :scales, name]) when is_atom(name), do: name
    defp keyed_name(_path), do: nil

    # The inline site's local for a node at a path: a site of the node's kind, a frame's
    # part as a frame site carrying that part alone.
    # A site's fragment carries the path it came from: a frame's own node, a part of one
    # (`scales`, `axes`, …) under its name, or the kind's singular wrapper (spec/14 §19.2).
    defp wrap(:frame, [:frames, frame], body), do: %{frames: %{frame => body}}
    defp wrap(:frame, [:frames], body), do: %{frames: %{main: body}}

    defp wrap(_kind, [:frames, frame, part], body) when is_atom(part),
      do: %{frames: %{frame => %{part => body}}}

    defp wrap(kind, _path, body), do: %{kind => body}

    defp fresh_id(:mark, %{id: id} = body, taken) when is_atom(id),
      do: %{body | id: fresh(id, taken)}

    defp fresh_id(_kind, body, _taken), do: body

    defp fresh_key(nil, _taken), do: nil
    defp fresh_key(key, taken), do: fresh(key, taken)

    defp fresh(name, taken) do
      2
      |> Stream.iterate(&(&1 + 1))
      |> Stream.map(&:"#{name}_#{&1}")
      |> Enum.find(&(&1 not in taken))
    end

    defp put_in_local(local, [key], value), do: Map.put(local, key, value)

    defp put_in_local(local, [key | rest], value),
      do: Map.put(local, key, put_in_local(%{}, rest, value))

    # A mask names a key, or a key of a node under one (spec/14 §19.5).
    defp mask_path(path), do: Enum.take(path, 2)

    defp at(map, []), do: map
    defp at(map, [key | rest]) when is_map(map) and is_atom(key), do: at(Map.get(map, key), rest)
    defp at(list, [i | rest]) when is_list(list) and is_integer(i), do: at(Enum.at(list, i), rest)
    defp at(_other, _path), do: nil

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
        iex> house = %Visualize.Chart.Use{id: {:use, 3}, ref: nil, local: %{frames: %{main: %{kind: :cartesian}}}}
        iex> Visualize.Chart.Builder.Stack.local_path(house, fn _id -> :error end, [:frames, :main, :margin])
        [:frames, :main, :margin]
    """
    @spec local_path(Use.t(), (Fragment.id() -> {:ok, map()} | :error), [term()]) :: [term()]
    def local_path(%Use{key: key} = use, fetch, [:frames, key | rest] = path)
        when is_atom(key) and key != nil do
      # A frame site placed under a key lands as `frames.<key>` (§19.6, #616), and its
      # fragment still calls its one frame by the entry's name.
      case shown_fragment(use, fetch) do
        %{frames: frames} when is_map(frames) and map_size(frames) == 1 ->
          [:frames, frames |> Map.keys() |> hd() | rest]

        _other ->
          by_kind(use, fetch, path)
      end
    end

    def local_path(use, fetch, path), do: by_kind(use, fetch, path)

    defp by_kind(use, fetch, path) do
      case {Fragment.wrapped(shown_fragment(use, fetch)), path} do
        {{:style, _}, [:styles, _key | rest]} -> [:style | rest]
        {{:source, _}, [:sources, _key | rest]} -> [:source | rest]
        {{:var, _}, [:vars, _key | rest]} -> [:var | rest]
        {{:gradient, _}, [:defs, _key | rest]} -> [:gradient | rest]
        {{:mark, _}, [:marks, _index | rest]} -> [:mark | rest]
        {{:label, _}, [:labels, _index | rest]} -> [:label | rest]
        {{:scale, _}, [:frames, _f, :scales, _key | rest]} -> [:scale | rest]
        {{:axis, _}, [:frames, _f, :axes, _index | rest]} -> [:axis | rest]
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

    # -- the tree (spec/14 §18.8, #380) ------------------------------------------------------

    @typedoc """
    A row of the tree: the site, its depth, its parent's id, its flat position and its
    `owner` — `nil` for a site of the tree, the referenced site's id for a row of a
    referenced group's inside (§18.8, #388), whose `index` is the owner's.
    """
    @type row :: %{
            use: Use.t(),
            depth: non_neg_integer(),
            parent: Use.id() | nil,
            index: non_neg_integer(),
            owner: Use.id() | nil
          }

    @doc "Whether a use is a container: an inline composite — a layer or a group."
    @spec group?(Use.t()) :: boolean()
    def group?(%Use{ref: nil, local: %{composite: %{uses: uses}}}) when is_list(uses), do: true
    def group?(%Use{}), do: false

    @doc "The sites an inline group holds; `[]` for an object or a referenced site."
    @spec children(Use.t()) :: [Use.t()]
    def children(%Use{ref: nil, local: %{composite: %{uses: uses}}}) when is_list(uses), do: uses
    def children(%Use{}), do: []

    @doc """
    Every site of the tree, depth first, as rows — the flat order the panel draws and a
    flat position names.

        iex> inner = [%Visualize.Chart.Use{id: {:use, 3}, ref: nil, local: %{style: %{}}}]
        iex> uses = [%Visualize.Chart.Use{id: {:use, 1}, ref: nil, local: %{composite: %{uses: inner, vars: %{}}}}, %Visualize.Chart.Use{id: {:use, 2}, ref: nil, local: %{mark: %{}}}]
        iex> for row <- Visualize.Chart.Builder.Stack.all(uses), do: {row.use.id, row.depth, row.parent, row.index}
        [{{:use, 1}, 0, nil, 0}, {{:use, 3}, 1, {:use, 1}, 1}, {{:use, 2}, 0, nil, 2}]
    """
    @spec all([Use.t()]) :: [row()]
    def all(uses) do
      uses
      |> rows(0, nil)
      |> Enum.with_index(fn row, index -> Map.merge(row, %{index: index, owner: nil}) end)
    end

    defp rows(uses, depth, parent) do
      Enum.flat_map(uses, fn use ->
        [%{use: use, depth: depth, parent: parent} | rows(children(use), depth + 1, use.id)]
      end)
    end

    @doc """
    The rows of `all/1` with each referenced group's inside beneath its row (spec/14
    §18.8, #388): the sites its entry holds, through the fetch, depth first — a group the
    entry holds followed by what it holds, a composite it references by that entry's
    sites. Those sites are the library's and their ids the entry's, not the tree's, so
    they have no flat position of their own: each row carries `owner`, the referenced
    site's id, and the owner's flat position as its `index`, so a gesture on one is a
    gesture on the group, and a flat position still indexes `all/1`. A row directly
    under the owner names it as its parent; one deeper names the entry's site holding it.
    An entry met again below itself is not opened twice.

        iex> pair = %{composite: %{uses: [%Visualize.Chart.Use{id: {:use, 1}, ref: {:frame, 1}}, %Visualize.Chart.Use{id: {:use, 2}, ref: nil, local: %{mark: %{}}}], vars: %{}}}
        iex> fetch = fn {:composite, 1} -> {:ok, pair}; _id -> :error end
        iex> uses = [%Visualize.Chart.Use{id: {:use, 1}, ref: nil, local: %{style: %{}}}, %Visualize.Chart.Use{id: {:use, 2}, ref: {:composite, 1}}]
        iex> for row <- Visualize.Chart.Builder.Stack.all(uses, fetch), do: {row.use.id, row.depth, row.index, row.owner}
        [{{:use, 1}, 0, 0, nil}, {{:use, 2}, 0, 1, nil}, {{:use, 1}, 1, 1, {:use, 2}}, {{:use, 2}, 1, 1, {:use, 2}}]
    """
    @spec all([Use.t()], (Fragment.id() -> {:ok, map()} | :error)) :: [row()]
    def all(uses, fetch) do
      uses
      |> all()
      |> Enum.flat_map(fn row ->
        case inside(row.use, fetch) do
          nil -> [row]
          held -> [row | held_rows(held, row.depth + 1, row.use.id, row, fetch, [row.use.ref])]
        end
      end)
    end

    defp held_rows(uses, depth, parent, owner, fetch, seen) do
      Enum.flat_map(uses, fn use ->
        row = %{use: use, depth: depth, parent: parent, index: owner.index, owner: owner.use.id}

        [
          row
          | held_rows(held(use, fetch, seen), depth + 1, use.id, owner, fetch, [use.ref | seen])
        ]
      end)
    end

    # What a site of an entry holds, as the tree reads it: an inline group's sites, or the
    # sites of the composite it references — once along any one path.
    defp held(%Use{ref: nil} = use, _fetch, _seen), do: children(use)

    defp held(%Use{ref: ref} = use, fetch, seen) do
      if ref in seen, do: [], else: inside(use, fetch) || []
    end

    @doc """
    The sites a referenced composite's entry holds (spec/14 §18.8, #388) — the library's,
    read-only in the chart — or `nil` for a use that is not a reference to a composite or
    whose entry the fetch cannot find.
    """
    @spec inside(Use.t(), (Fragment.id() -> {:ok, map()} | :error)) :: [Use.t()] | nil
    def inside(%Use{ref: nil}, _fetch), do: nil

    def inside(%Use{ref: ref}, fetch) do
      case fetch.(ref) do
        {:ok, %{composite: %{uses: uses}}} when is_list(uses) -> uses
        _other -> nil
      end
    end

    @doc "The flat position of a use in the tree, or `nil`."
    @spec index_of([Use.t()], Use.id() | nil) :: non_neg_integer() | nil
    def index_of(_uses, nil), do: nil

    def index_of(uses, id) do
      case Enum.find(all(uses), &(&1.use.id == id)) do
        nil -> nil
        row -> row.index
      end
    end

    @doc "The use with an id anywhere in the tree, or `nil`."
    @spec get([Use.t()], Use.id() | nil) :: Use.t() | nil
    def get(_uses, nil), do: nil

    def get(uses, id) do
      case Enum.find(all(uses), &(&1.use.id == id)) do
        nil -> nil
        row -> row.use
      end
    end

    @doc "The id of the group holding a use, or `nil` at the top."
    @spec parent_of([Use.t()], Use.id()) :: Use.id() | nil
    def parent_of(uses, id) do
      case Enum.find(all(uses), &(&1.use.id == id)) do
        nil -> nil
        row -> row.parent
      end
    end

    @doc "The tree with one use, anywhere, replaced by a function of it; a missing id changes nothing."
    @spec update([Use.t()], Use.id(), (Use.t() -> Use.t())) :: [Use.t()]
    def update(uses, id, fun) do
      Enum.map(uses, fn use ->
        if use.id == id do
          fun.(use)
        else
          case children(use) do
            [] -> use
            inner -> with_children(use, update(inner, id, fun))
          end
        end
      end)
    end

    defp with_children(%Use{local: %{composite: composite} = local} = use, inner),
      do: %{use | local: %{local | composite: %{composite | uses: inner}}}

    @doc "The tree without a use (and what it holds); a missing id changes nothing."
    @spec remove([Use.t()], Use.id()) :: [Use.t()]
    def remove(uses, id) do
      uses
      |> Enum.reject(&(&1.id == id))
      |> Enum.map(fn use ->
        case children(use) do
          [] -> use
          inner -> with_children(use, remove(inner, id))
        end
      end)
    end

    @doc """
    A use inserted as the sibling after another — at the top, at the end, for `nil` — or,
    with `{:into, id}`, appended inside that group.
    """
    @spec insert([Use.t()], Use.id() | nil | {:into, Use.id()}, Use.t()) :: [Use.t()]
    def insert(uses, nil, use), do: uses ++ [use]

    def insert(uses, {:into, id}, use) do
      update(uses, id, fn group -> with_children(group, children(group) ++ [use]) end)
    end

    def insert(uses, after_id, use) do
      case Enum.find_index(uses, &(&1.id == after_id)) do
        nil ->
          Enum.map(uses, fn site ->
            case children(site) do
              [] -> site
              inner -> with_children(site, insert(inner, after_id, use))
            end
          end)

        index ->
          List.insert_at(uses, index + 1, use)
      end
    end

    @doc """
    The ids from an anchor to a sibling, in tree order — the range a Shift+click selects
    (spec/14 §18.8, #382) — or `:error` when the two are not siblings.

        iex> alias Visualize.Chart.{Builder.Stack, Use}
        iex> uses = for n <- 1..3, do: %Use{id: {:use, n}, ref: nil, local: %{mark: %{}}}
        iex> Stack.between(uses, {:use, 3}, {:use, 1})
        {:ok, [{:use, 1}, {:use, 2}, {:use, 3}]}
        iex> Stack.between([%Use{id: {:use, 4}, ref: nil, local: %{composite: %{uses: uses, vars: %{}}}}], {:use, 4}, {:use, 1})
        :error
    """
    @spec between([Use.t()], Use.id(), Use.id()) :: {:ok, [Use.id()]} | :error
    def between(uses, anchor, id) do
      case siblings(uses, [anchor, id]) do
        {:ok, container} ->
          ids = Enum.map(container, & &1.id)
          [from, to] = Enum.sort([anchor, id], &(index_in(ids, &1) <= index_in(ids, &2)))
          {:ok, Enum.slice(ids, index_in(ids, from)..index_in(ids, to))}

        :error ->
          :error
      end
    end

    @doc """
    Sibling sites wrapped in a group at the first one's position, in their tree order
    (spec/14 §18.8, #382); `:error` when the ids are not siblings, or none.

        iex> alias Visualize.Chart.{Builder.Stack, Use}
        iex> uses = for n <- 1..3, do: %Use{id: {:use, n}, ref: nil, local: %{mark: %{}}}
        iex> group = %{Use.new(nil, uses) | local: Stack.group()}
        iex> {:ok, grouped} = Stack.grouped(uses, [{:use, 3}, {:use, 2}], group)
        iex> Enum.map(grouped, & &1.id)
        [{:use, 1}, {:use, 4}]
        iex> grouped |> List.last() |> Stack.children() |> Enum.map(& &1.id)
        [{:use, 2}, {:use, 3}]
    """
    @spec grouped([Use.t()], [Use.id()], Use.t()) :: {:ok, [Use.t()]} | :error
    def grouped(_uses, [], _group), do: :error

    def grouped(uses, ids, group) do
      case siblings(uses, ids) do
        {:ok, container} ->
          {inside, rest} = Enum.split_with(container, &(&1.id in ids))
          first = Enum.find_index(container, &(&1.id in ids))
          filled = with_children(group, inside)
          {:ok, replaced(uses, container, List.insert_at(rest, first, filled))}

        :error ->
          :error
      end
    end

    @doc """
    An inline group's sites spliced in at its position, the group gone (spec/14 §18.8,
    #382); any other site leaves the tree unchanged.
    """
    @spec ungrouped([Use.t()], Use.id()) :: [Use.t()]
    def ungrouped(uses, id) do
      Enum.flat_map(uses, fn use ->
        cond do
          use.id == id and group?(use) -> children(use)
          children(use) == [] -> [use]
          true -> [with_children(use, ungrouped(children(use), id))]
        end
      end)
    end

    @doc """
    A copy of a site and what it holds, every id fresh among the tree, with the
    `{copy, original}` id pairs so labels follow (spec/14 §18.8, #382).

        iex> alias Visualize.Chart.{Builder.Stack, Use}
        iex> inner = [%Use{id: {:use, 2}, ref: nil, local: %{mark: %{}}}]
        iex> group = %Use{id: {:use, 1}, ref: nil, local: %{composite: %{uses: inner, vars: %{}}}}
        iex> {copy, pairs} = Stack.duplicated([group], group)
        iex> {copy.id, Enum.map(Stack.children(copy), & &1.id), pairs}
        {{:use, 3}, [{:use, 4}], [{{:use, 3}, {:use, 1}}, {{:use, 4}, {:use, 2}}]}
    """
    @spec duplicated([Use.t()], Use.t()) :: {Use.t(), [{Use.id(), Use.id()}]}
    def duplicated(uses, %Use{} = use) do
      {copy, {_among, pairs}} = fresh_copy(use, {uses, []})
      {copy, Enum.reverse(pairs)}
    end

    defp fresh_copy(%Use{} = use, {among, pairs}) do
      copy = %{use | id: Use.new(nil, among).id}
      among = among ++ [copy]
      pairs = [{copy.id, use.id} | pairs]

      case children(use) do
        [] ->
          {copy, {among, pairs}}

        inner ->
          {inner_copies, state} = Enum.map_reduce(inner, {among, pairs}, &fresh_copy/2)
          {with_children(copy, inner_copies), state}
      end
    end

    # The container holding every id — the top, or a group's children — or `:error`.
    defp siblings(uses, ids) do
      rows = all(uses)

      parents =
        for id <- ids, row = Enum.find(rows, &(&1.use.id == id)), uniq: true, do: row.parent

      case parents do
        [nil] when ids != [] ->
          if(Enum.all?(ids, &get(uses, &1)), do: {:ok, uses}, else: :error)

        [parent] when parent != nil ->
          {:ok, children(get(uses, parent))}

        _other ->
          :error
      end
    end

    # The tree with one container's list replaced by another: the top, or a group's.
    defp replaced(uses, container, list) do
      if uses == container do
        list
      else
        Enum.map(uses, fn use ->
          case children(use) do
            [] -> use
            ^container -> with_children(use, list)
            inner -> with_children(use, replaced(inner, container, list))
          end
        end)
      end
    end

    defp index_in(ids, id), do: Enum.find_index(ids, &(&1 == id))

    @doc """
    A use inserted before the row at a flat position, in that row's own container — at
    the end of the top past the last row (spec/14 §18.17, #380).
    """
    @spec insert_at([Use.t()], non_neg_integer(), Use.t()) :: [Use.t()]
    def insert_at(uses, at, use) when at < 0, do: insert_at(uses, 0, use)

    def insert_at(uses, at, use) do
      case Enum.at(all(uses), at) do
        nil ->
          uses ++ [use]

        %{parent: nil, use: target} ->
          List.insert_at(uses, Enum.find_index(uses, &(&1.id == target.id)), use)

        %{parent: parent, use: target} ->
          update(uses, parent, fn group ->
            inner = children(group)

            with_children(
              group,
              List.insert_at(inner, Enum.find_index(inner, &(&1.id == target.id)), use)
            )
          end)
      end
    end

    @doc "A group's local: an inline composite with no objects."
    @spec group() :: map()
    def group, do: %{composite: %{uses: [], vars: %{}}}

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

    @doc """
    A move within the tree by flat positions (§19.3, #380): the row at `from` — a group
    with everything it holds — taken out, then put before the row that stands at `to`
    once it is out, in that row's own container; past the last row, at the end of the top.
    A row cannot land inside what it holds, since those rows are out with it.
    """
    @spec move([Use.t()], non_neg_integer(), non_neg_integer()) :: [Use.t()]
    def move(uses, from, to) when from != to and from >= 0 and to >= 0 do
      rows = all(uses)

      case Enum.at(rows, from) do
        nil ->
          uses

        %{use: moved} ->
          rest = remove(uses, moved.id)
          target = Enum.at(all(rest), to)

          cond do
            target == nil ->
              rest ++ [moved]

            target.parent == nil ->
              List.insert_at(rest, Enum.find_index(rest, &(&1.id == target.use.id)), moved)

            true ->
              update(rest, target.parent, fn group ->
                inner = children(group)

                with_children(
                  group,
                  List.insert_at(inner, Enum.find_index(inner, &(&1.id == target.use.id)), moved)
                )
              end)
          end
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
        :board,
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
    # A board with no cells and every default (spec/14 §22.1, spec/15 §1.2).
    def empty(:board), do: %{board: Visualize.Board.to_map(%Visualize.Board{})}
    def empty(:frame), do: %{frames: %{main: %{}}}

    def empty(kind) when kind in [:style, :scale, :source, :axis, :mark, :label, :var],
      do: %{kind => %{}}

    def empty(kind), do: %{kind => %{}}
  end
end
