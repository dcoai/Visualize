defmodule Visualize.Chart.Use do
  @moduledoc """
  A fragment used at a position (spec/14 §19.3, D-101).

  A layer in a composite and an entry in a style stack are the same thing: a *use* of a
  fragment at a site. The site has four parts, each written by exactly one surface, and
  they are applied in one order — `ref → local → mask → bind → stack` — so a mask removes
  what the site would otherwise say whichever part said it, and a bound variable is
  renamed before the cascade sees it wherever at the site it stands. A site the host
  seeded is nothing but its local, and is masked and bound like any other.

      %Visualize.Chart.Use{
        id:    {:use, 7},                # this site's own identity (§19.3)
        ref:   {:style, 11},             # which fragment (§19.2); nil for an inline-only site
        mask:  [:stroke],                # removed here, so a lower layer shows through (§19.5)
        vars:  %{color: var(:color_1)},  # what the fragment's variables mean here (§19.4)
        local: %{opacity: 0.8},          # added or overridden here
        origin: nil                      # the entry an unlocked site came from (#381)
      }

  A struct is a leaf of every walk (D-92), which is what keeps `Visualize.Chart.stack/1`
  from descending into a site and merging its parts.

  ## Examples

      iex> alias Visualize.Chart.Use
      iex> use = Use.new({:style, 11})
      iex> {use.ref, use.mask, use.vars, use.local}
      {{:style, 11}, [], %{}, %{}}

      iex> Visualize.Chart.Use.new({:style, 2}, [Visualize.Chart.Use.new({:style, 1})]).id
      {:use, 2}

  """

  alias Visualize.Chart
  alias Visualize.Chart.Var

  @enforce_keys [:id, :ref]
  defstruct id: nil, ref: nil, mask: [], vars: %{}, local: %{}, key: nil, origin: nil

  @typedoc "A site's own identity: unique within the composite that holds it."
  @type id :: {:use, pos_integer()}

  @typedoc "A path into a fragment: the keys from its root, as `Visualize.Chart.explain/1` gives them."
  @type path :: [atom() | non_neg_integer()]

  @type t :: %__MODULE__{
          id: id(),
          ref: Chart.Fragment.id() | nil,
          mask: [path() | atom()],
          vars: %{atom() => term()},
          local: map(),
          key: atom() | nil,
          origin: Chart.Fragment.id() | nil
        }

  @doc """
  A use of a fragment with a fresh id and the three empty parts (spec/14 §19.3).

  The id is one more than the highest among `among` — the sites this one will sit beside —
  so it is unique within its composite. A site's identity needs no more scope than that:
  nothing outside the composite refers to a site.
  """
  @spec new(Chart.Fragment.id() | nil, [t()]) :: t()
  def new(ref, among \\ []) do
    highest =
      among
      |> Enum.flat_map(&ids/1)
      |> Enum.max(fn -> 0 end)

    %__MODULE__{id: {:use, highest + 1}, ref: ref}
  end

  # Every id a site carries: its own and, for an inline composite, those inside it
  # (spec/14 §18.8, #380), so ids are unique across a whole tree.
  defp ids(%__MODULE__{id: {:use, n}, ref: nil, local: %{composite: %{uses: uses}}})
       when is_list(uses),
       do: [n | Enum.flat_map(uses, &ids/1)]

  defp ids(%__MODULE__{id: {:use, n}}), do: [n]

  @doc """
  A fragment with its variables substituted (spec/14 §19.4, D-102).

  Every `%Var{name: k}` becomes the map's value for `k` — a literal, or another `var/1`,
  which is a rename — and a variable the map does not name is left as it is. The result is
  a fragment with fewer, or differently named, variables in it, which every existing rule
  already accepts. Any other struct is a leaf.

      iex> Visualize.Chart.Use.bind(%{fill: Visualize.Chart.var(:color)}, %{color: "blue"})
      %{fill: "blue"}

      iex> fragment = %{fill: Visualize.Chart.var(:color), text: [Visualize.Chart.var(:unit)]}
      iex> Visualize.Chart.Use.bind(fragment, %{color: Visualize.Chart.var(:color_1)})
      %{fill: %Visualize.Chart.Var{name: :color_1}, text: [%Visualize.Chart.Var{name: :unit}]}
  """
  @spec bind(term(), %{atom() => term()}) :: term()
  def bind(fragment, vars) when map_size(vars) == 0, do: fragment

  def bind(%Var{name: name} = var, vars), do: Map.get(vars, name, var)
  def bind(%_{} = struct, _vars), do: struct

  def bind(map, vars) when is_map(map),
    do: Map.new(map, fn {k, v} -> {k, bind(v, vars)} end)

  def bind(list, vars) when is_list(list), do: Enum.map(list, &bind(&1, vars))

  def bind(tuple, vars) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> bind(vars) |> List.to_tuple()

  def bind(leaf, _vars), do: leaf

  @doc """
  A fragment with paths removed (spec/14 §19.5).

  A path is the keys from the fragment's root; a bare atom is a path of one. A path the
  fragment does not carry removes nothing. Masking `:all` removes everything, which is
  what disabling a layer is (D-87 restated in §19.3).

      iex> Visualize.Chart.Use.mask(%{stroke: "#111", stroke_width: 5}, [:stroke])
      %{stroke_width: 5}

      iex> Visualize.Chart.Use.mask(%{frames: %{main: %{size: %{}, margin: %{}}}}, [[:frame, :margin]])
      %{frames: %{main: %{size: %{}}}}

      iex> Visualize.Chart.Use.mask(%{a: 1}, :all)
      %{}
  """
  @spec mask(map(), [path() | atom()] | :all) :: map()
  def mask(_fragment, :all), do: %{}
  def mask(fragment, paths) when is_list(paths), do: Enum.reduce(paths, fragment, &drop(&2, &1))

  defp drop(fragment, key) when is_atom(key), do: drop(fragment, [key])
  defp drop(fragment, [key]) when is_map(fragment), do: Map.delete(fragment, key)

  defp drop(fragment, [key | rest]) when is_map(fragment) do
    case Map.fetch(fragment, key) do
      {:ok, inner} -> Map.put(fragment, key, drop(inner, rest))
      :error -> fragment
    end
  end

  defp drop(list, [index | rest]) when is_list(list) and is_integer(index) do
    List.update_at(list, index, &drop(&1, rest))
  end

  defp drop(other, _path), do: other

  @doc """
  A use site resolved to the fragment it stands for, in order: the referenced body, the
  mask, the bindings, and the local node cascaded over it (spec/14 §19.3).

  `fetch` is how the referenced body is found — a store's `get`, or any function of an id —
  and returns `{:ok, fragment}` or `:error`. A ref the fetch cannot find is a **mask of
  everything**: the site stands for its local node alone, and the id is returned so the
  caller can say so (§19.2, D-100). A `nil` ref is an inline-only site.
  """
  @spec resolve(t(), (Chart.Fragment.id() -> {:ok, map()} | :error)) ::
          {:ok, map()} | {:missing, Chart.Fragment.id(), map()}
  def resolve(%__MODULE__{ref: nil} = use, _fetch), do: {:ok, over(use, %{})}

  def resolve(%__MODULE__{ref: ref} = use, fetch) do
    case fetch.(ref) do
      {:ok, fragment} -> {:ok, over(use, fragment)}
      :error -> {:missing, ref, over(use, %{})}
    end
  end

  @doc """
  A use over a body it has already been given: the local node cascaded over it, the mask
  over the result, and the bindings over all of it — everything `resolve/2` does after the
  fetch (spec/14 §19.3). Mask and bind run after local so they speak for everything the
  site contributes: an inline-only site is nothing but its local, and is masked and bound
  like any other. A mask of everything is the whole site removed — that is what disabling
  a layer means.
  """
  @spec over(t(), map()) :: map()
  def over(%__MODULE__{mask: :all}, _fragment), do: %{}

  def over(%__MODULE__{mask: mask, vars: vars, local: local}, fragment) do
    [fragment, local]
    |> Chart.stack()
    |> mask(mask)
    |> bind(vars)
  end
end
