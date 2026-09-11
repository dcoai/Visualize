defmodule Visualize.Chart.Composite do
  @moduledoc """
  A fragment whose content is a list of use sites, and how it becomes a design
  (spec/14 §19.6, D-103).

      %{composite: %{
        uses: [%Visualize.Chart.Use{...}, ...],   # in stack order, the higher later
        vars: %{color_1: %{default: :series_1}}   # the composite's own variables
      }}

  **Save writes structure**: this is what the store holds. **Flatten is a deployment
  verb**: `flatten/2` resolves every use through a store — `ref → mask → local → bind`
  — recursively where a use refers to another composite, and stacks the result into a flat
  design in §13's shape, with no ids and no uses. A composite that reaches itself through
  any chain of uses is refused as an `extends` cycle is (§3.5).

  A ref the store no longer holds is a **mask of everything** at that site (§19.2); the
  design still flattens, and the missing ids are returned so a host that wants strictness
  has them.
  """

  alias Visualize.Chart
  alias Visualize.Chart.{Fragment, Use}

  @typedoc "What `flatten/2` reports beside the design: every ref no store could find."
  @type report :: %{missing: [{Use.id(), Fragment.id()}]}

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
  def flatten(fragment, fetch), do: flatten(fragment, fetch, [])

  defp flatten(%{composite: %{uses: uses} = composite}, fetch, trail) when is_list(uses) do
    # The composite's own vars are the lowest layer — when it has any, so a composite
    # declaring none flattens to exactly what its sites give.
    base =
      case Map.get(composite, :vars, %{}) do
        vars when map_size(vars) == 0 -> []
        vars -> [%{vars: vars}]
      end

    uses
    |> Enum.reduce_while({:ok, base, []}, fn use, {:ok, layers, missing} ->
      case layer(use, fetch, trail) do
        {:ok, resolved, more} -> {:cont, {:ok, [resolved | layers], missing ++ more}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, layers, missing} ->
        {:ok, layers |> Enum.reverse() |> Chart.stack(), %{missing: missing}}

      {:error, _} = error ->
        error
    end
  end

  # A fragment that is not a composite flattens to itself: a design is already flat.
  defp flatten(fragment, _fetch, _trail) when is_map(fragment),
    do: {:ok, fragment, %{missing: []}}

  # One use as a layer. Its referenced body may itself be a composite, in which case it is
  # flattened first — through the trail, so a chain that returns to an id is a cycle. A
  # body the store no longer holds is a mask of everything: the site stands for its local
  # node alone, and the id is reported.
  defp layer(%Use{ref: nil} = use, _fetch, _trail), do: {:ok, Use.over(use, %{}), []}

  defp layer(%Use{ref: ref} = use, fetch, trail) do
    if ref in trail do
      {:error, {:cycle, Enum.reverse([ref | trail])}}
    else
      case fetch.(ref) do
        :error ->
          {:ok, Use.over(use, %{}), [{use.id, ref}]}

        {:ok, body} ->
          case flatten(body, fetch, [ref | trail]) do
            {:ok, flat, %{missing: nested}} -> {:ok, Use.over(use, flat), nested}
            {:error, _} = error -> error
          end
      end
    end
  end
end
