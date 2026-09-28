defmodule Visualize.Chart.Composite do
  @moduledoc """
  A fragment whose content is a list of use sites, and how it becomes a design
  (spec/14 §19.6, D-103).

      %{composite: %{
        uses: [%Visualize.Chart.Use{...}, ...],   # in stack order, the higher later
        vars: %{color_1: %{default: :series_1}}   # the composite's own variables
      }}

  **Save writes structure**: this is what the store holds. **Flatten is a deployment
  verb**: `flatten/2` resolves every use through a store — `ref → local → mask → bind`
  — recursively where a use refers to another composite, and stacks the result into a flat
  design in §13's shape, with no ids and no uses. A composite that reaches itself through
  any chain of uses is refused as an `extends` cycle is (§3.5).

  A ref the store no longer holds is a **mask of everything** at that site (§19.2); the
  design still flattens, and the missing ids are returned so a host that wants strictness
  has them.

  **Every site is placed by its kind** (§19.6): a positional kind writes its key, a frame
  cascades into `frame`, a list kind appends by its own identity, and a name-keyed kind —
  style, scale, source, var — lands under the site's `key`. A name-keyed site with no key
  is not placed, and is reported as `keyless` beside `missing`.
  """

  alias Visualize.Chart
  alias Visualize.Chart.{Fragment, Refs, Use}

  # The kinds a document keys by name (§19.3).
  @named [:style, :scale, :source, :var, :gradient]

  # The document version flatten writes: a design is the deployed tier (§19.8), and the
  # tier is written at the version this library writes (§9).
  @version Visualize.Chart.Migration.current()

  @typedoc """
  What `flatten/2` reports beside the design: every ref no store could find — a site's,
  by the site's id, or a reference inside the design, by its path — and every name-keyed
  site this composite holds that has no key to be declared under.
  """
  @type report :: %{
          missing: [{Use.id() | [atom() | non_neg_integer()], Fragment.id()}],
          keyless: [Use.id()]
        }

  @doc "Whether a fragment is a composite: one key, `composite`, holding uses."
  @spec composite?(term()) :: boolean()
  def composite?(%{composite: %{uses: uses}}) when is_list(uses), do: true
  def composite?(_fragment), do: false

  @doc """
  A composite resolved through a store and stacked: a flat design (spec/14 §19.6).

  `fetch` returns `{:ok, fragment}` or `:error` for an id — a store's `get`, partially
  applied. The composite's own `vars` are the base layer, so a variable a use was renamed
  to (§19.4) has its declaration; each use resolves in order and cascades by §8.2.

  Returns `{:ok, design, report}`, or `{:error, {:cycle, [id]}}` when a composite reaches
  itself, naming the chain.
  """
  @spec flatten(map(), (Fragment.id() -> {:ok, map()} | :error)) ::
          {:ok, map(), report()} | {:error, {:cycle, [Fragment.id()]}}
  def flatten(fragment, fetch) do
    case flatten(fragment, fetch, []) do
      {:ok, flat, report} ->
        # The one rule for ids at reference sites (§19.6): what leaves here carries none.
        {resolved, unresolved} = Refs.resolve(flat, fetch)
        missing = report.missing ++ Enum.map(unresolved, fn {path, id} -> {path, id} end)
        {:ok, resolved, %{report | missing: missing}}

      {:error, _} = error ->
        error
    end
  end

  defp flatten(%{composite: %{uses: uses} = composite}, fetch, trail) when is_list(uses) do
    # The composite's own vars are the lowest layer — when it has any, so a composite
    # declaring none flattens to exactly what its sites give.
    base =
      case Map.get(composite, :vars, %{}) do
        vars when map_size(vars) == 0 -> []
        vars -> [%{vars: vars}]
      end

    uses
    |> Enum.reduce_while({:ok, [], []}, fn use, {:ok, resolved, missing} ->
      case layer(use, fetch, trail) do
        {:ok, contribution, more} ->
          {:cont, {:ok, [{use, contribution} | resolved], missing ++ more}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, resolved, missing} ->
        {layers, keyless} = resolved |> Enum.reverse() |> placed()
        {:ok, Chart.stack(base ++ layers), %{missing: missing, keyless: keyless}}

      {:error, _} = error ->
        error
    end
  end

  # A fragment that is not a composite flattens to itself: a design is already flat.
  defp flatten(fragment, _fetch, _trail) when is_map(fragment),
    do: {:ok, fragment, %{missing: [], keyless: []}}

  # A composer of one name-keyed kind — every site a style, say, and none of them keyed —
  # stacks its bodies as bodies, and its result is a style for the site that holds it to
  # place (§19.6, "within a kind, the same operation"). Anything else is a design-level
  # composite: every site is placed by its kind, and a name-keyed one with no key is
  # reported and left out.
  defp placed(resolved) do
    kinds =
      resolved
      |> Enum.map(fn {_use, c} -> c |> Fragment.wrapped() |> kind_of() end)
      |> Enum.uniq()

    keyed? = Enum.any?(resolved, fn {use, _c} -> use.key != nil end)

    case kinds do
      [kind] when kind in @named and not keyed? ->
        {Enum.map(resolved, fn {_use, c} -> c end), []}

      _mixed ->
        # A design-level composite: version is the deployed tier's, written here (§19.8).
        {layers, keyless} = Enum.reduce(resolved, {[], []}, &place_one/2)
        {[%{version: @version} | layers], keyless}
    end
  end

  defp kind_of({kind, _body}), do: kind
  defp kind_of(nil), do: nil

  defp place_one({use, contribution}, {layers, keyless}) do
    case place(contribution, use) do
      {:ok, layer} -> {layers ++ [layer], keyless}
      :keyless -> {layers, keyless ++ [use.id]}
    end
  end

  @doc """
  A flat document as sites, one kind each (spec/14 §18.12): its theme, its meta, its frame
  without the scales and axes, then one keyed site per style, scale, source and var, one
  site per mark, per label and per axis, in the order the document is read. `flatten/2` of
  the result is the document again, `version` aside, which flatten writes. Each site comes
  with a label a person reads.

      iex> document = %{version: 2, theme: :dark, styles: %{series: %{stroke: "#111"}},
      ...>   frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear}}, axes: [%{scale: :x, side: :bottom}]}},
      ...>   marks: [%{id: :m, type: :line}]}
      iex> {uses, labels} = Visualize.Chart.Composite.decompose(document)
      iex> Enum.map(uses, &{&1.id, Map.keys(&1.local), &1.key})
      [{{:use, 1}, [:theme], nil}, {{:use, 2}, [:frames], nil}, {{:use, 3}, [:style], :series}, {{:use, 4}, [:scale], :x}, {{:use, 5}, [:axis], nil}, {{:use, 6}, [:mark], nil}]
      iex> labels[{:use, 3}]
      "style series"
  """
  @spec decompose(map()) :: {[Use.t()], %{Use.id() => String.t()}}
  def decompose(document) when is_map(document) and not is_struct(document) do
    # A design holds its frames by name (spec/14 §2.1, #383). **One** frame is decomposed
    # into its own site plus a site per scale and per axis, as the singular frame was; a
    # design of **several** is a site per frame, each whole, since a scale site is keyed by
    # the scale's name alone and two frames may key one name (§4.3). Frames in the builder
    # are #386.
    frames =
      case Map.get(document, :frames, %{}) do
        frames when is_map(frames) and not is_struct(frames) ->
          Enum.sort_by(frames, fn {name, _} -> to_string(name) end)

        _none ->
          []
      end

    parts =
      case frames do
        [{_name, frame}] when is_map(frame) -> frame
        _several -> %{}
      end

    sites =
      one(:theme, document) ++
        one(:meta, document) ++
        one(:layout, document) ++
        frame_sites(frames) ++
        keyed(:style, Map.get(document, :styles, %{})) ++
        keyed(:scale, Map.get(parts, :scales, %{})) ++
        keyed(:source, Map.get(document, :sources, %{})) ++
        keyed(:var, Map.get(document, :vars, %{})) ++
        keyed(:gradient, Map.get(document, :defs, %{})) ++
        each(:axis, Map.get(parts, :axes, [])) ++
        each(:mark, Map.get(document, :marks, [])) ++
        each(:label, Map.get(document, :labels, []))

    sites
    |> Enum.with_index(1)
    |> Enum.reduce({[], %{}}, fn {{label, site}, n}, {uses, labels} ->
      use = struct!(Use, Map.put(site, :id, {:use, n}))
      {uses ++ [use], Map.put(labels, use.id, label)}
    end)
  end

  # A node that declares nothing is no site: a document read from `to_map/1` carries every
  # design key, and an empty `meta` or `layout` is the schema's default rather than
  # something a person wrote (spec/14 §2.1, §18.12).
  defp one(key, document) do
    case Map.fetch(document, key) do
      {:ok, value} when value == %{} -> []
      {:ok, value} -> [{to_string(key), %{ref: nil, local: %{key => value}}}]
      :error -> []
    end
  end

  # The one frame without the parts that became their own sites, or a site per frame.
  defp frame_sites([{name, frame}]) when is_map(frame),
    do: frame_site(name, Map.drop(frame, [:scales, :axes]))

  defp frame_sites(several),
    do: Enum.flat_map(several, fn {name, frame} -> frame_site(name, frame) end)

  defp frame_site(_name, frame) when is_map(frame) and map_size(frame) == 0, do: []

  defp frame_site(name, frame), do: [{"frame", %{ref: nil, local: %{frames: %{name => frame}}}}]

  defp keyed(kind, declared) when is_map(declared) do
    declared
    |> Enum.sort_by(fn {name, _body} -> to_string(name) end)
    |> Enum.map(fn {name, body} ->
      {"#{kind} #{name}", %{ref: nil, local: %{kind => body}, key: name}}
    end)
  end

  defp keyed(_kind, _other), do: []

  defp each(kind, elements) when is_list(elements) do
    elements
    |> Enum.with_index(1)
    |> Enum.map(fn {element, n} ->
      {"#{kind} #{identity(element, n)}", %{ref: nil, local: %{kind => element}}}
    end)
  end

  defp each(_kind, _other), do: []

  defp identity(%{id: id}, _n), do: to_string(id)
  defp identity(%{scale: scale, side: side}, _n), do: "#{scale} #{side}"
  defp identity(_element, n), do: to_string(n)

  @doc """
  A site's contribution placed in the design by its kind (spec/14 §19.6): a wrapper body
  becomes the layer that declares it where the design keeps that kind — a name-keyed one
  under the site's `key` — and anything else cascades as it is.

      iex> Visualize.Chart.Composite.place(%{style: %{stroke_width: 5}}, %Visualize.Chart.Use{id: {:use, 1}, ref: nil, key: :series})
      {:ok, %{styles: %{series: %{stroke_width: 5}}}}

      iex> Visualize.Chart.Composite.place(%{mark: %{id: :m, type: :line}}, %Visualize.Chart.Use{id: {:use, 1}, ref: nil})
      {:ok, %{marks: [%{id: :m, type: :line}]}}

      iex> Visualize.Chart.Composite.place(%{scale: %{kind: :linear}}, %Visualize.Chart.Use{id: {:use, 1}, ref: nil})
      :keyless

      iex> Visualize.Chart.Composite.place(%{theme: :dark, frames: %{main: %{}}}, %Visualize.Chart.Use{id: {:use, 1}, ref: nil})
      {:ok, %{theme: :dark, frames: %{main: %{}}}}
  """
  @spec place(map(), Use.t()) :: {:ok, map()} | :keyless
  def place(contribution, %Use{key: key}) do
    case Fragment.wrapped(contribution) do
      {kind, _body} when kind in @named and is_nil(key) ->
        :keyless

      {:style, body} ->
        {:ok, %{styles: %{key => body}}}

      {:scale, body} ->
        {:ok, %{frames: %{main: %{scales: %{key => body}}}}}

      {:source, body} ->
        {:ok, %{sources: %{key => body}}}

      {:var, body} ->
        {:ok, %{vars: %{key => body}}}

      {:gradient, body} ->
        {:ok, %{defs: %{key => body}}}

      {:mark, body} ->
        {:ok, %{marks: [body]}}

      {:label, body} ->
        {:ok, %{labels: [body]}}

      {:axis, body} ->
        {:ok, %{frames: %{main: %{axes: [body]}}}}

      _other ->
        {:ok, contribution}
    end
  end

  # One use as a layer. Its referenced body may itself be a composite, in which case it is
  # flattened first — through the trail, so a chain that returns to an id is a cycle. A
  # body the store no longer holds is a mask of everything: the site stands for its local
  # node alone, and the id is reported.
  # An inline composite — a group of the builder's tree (#380) — flattens in place, its
  # own mask and bindings over the flat result as a referenced composite's are.
  defp layer(%Use{ref: nil, local: %{composite: %{uses: uses}} = local} = use, fetch, trail)
       when is_list(uses) do
    case flatten(local, fetch, trail) do
      {:ok, flat, %{missing: nested}} -> {:ok, Use.over(%{use | local: %{}}, flat), nested}
      {:error, _} = error -> error
    end
  end

  defp layer(%Use{ref: nil} = use, _fetch, _trail), do: {:ok, Use.over(use, %{}), []}

  defp layer(%Use{ref: ref} = use, fetch, trail) do
    if ref in trail do
      {:error, {:cycle, Enum.reverse([ref | trail])}}
    else
      case fetch.(ref) do
        :error ->
          {:ok, Use.over(use, %{}), [{use.id, ref}]}

        {:ok, body} ->
          # A nested composite's keyless sites are its own affair: its result is placed
          # here, by this site's key, whatever its sites were called inside.
          case flatten(body, fetch, [ref | trail]) do
            {:ok, flat, %{missing: nested}} -> {:ok, Use.over(use, flat), nested}
            {:error, _} = error -> error
          end
      end
    end
  end
end
