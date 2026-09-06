defmodule Visualize.Audit do
  @moduledoc """
  Cross-references what `spec/` declares against what `lib/` defines, and renders the
  result as `API_SURFACE.md` through `Surfex.Golden`.

  One row per public function on either side. `specified` means both agree; `unspecified`
  is a public function no document declares; `unimplemented` is a declared function no
  source defines. The gate (`mix vis.surface --check`) is HARD on drift of the rendered
  document and deliberately not on the two backlog counts: they are the document's content.
  """

  alias Surfex.Golden
  alias Visualize.Audit.{CodeScan, SpecScan}

  @columns ["Function", "Section", "Status", "Version", "Locus"]

  @type result :: %{
          rows: [Golden.row()],
          specified: non_neg_integer,
          unspecified: [String.t()],
          unimplemented: [String.t()]
        }

  @doc "Scans `root` and joins the two sides."
  @spec run(String.t()) :: result
  def run(root) do
    code =
      root
      |> CodeScan.run()
      |> Enum.reject(& &1.hidden?)
      |> Map.new(&{"#{&1.module}.#{&1.name}/#{&1.arity}", &1})

    spec =
      root
      |> SpecScan.run()
      |> Enum.group_by(& &1.item)
      |> Map.new(fn {item, [first | _]} -> {item, first} end)

    items = code |> Map.keys() |> MapSet.new() |> MapSet.union(spec |> Map.keys() |> MapSet.new())

    rows =
      for item <- Enum.sort(items) do
        row(item, Map.get(code, item), Map.get(spec, item))
      end

    %{
      rows: rows,
      specified: Enum.count(rows, &(&1["Status"] == {:atom, :specified})),
      unspecified: for(r <- rows, r["Status"] == {:atom, :unspecified}, do: item_of(r)),
      unimplemented: for(r <- rows, r["Status"] == {:atom, :unimplemented}, do: item_of(r))
    }
  end

  @doc "The golden as data: what `render/1` hands to `Surfex.Golden.render/1`."
  @spec golden_spec(result) :: Golden.spec()
  def golden_spec(%{rows: rows} = result) do
    %{
      name: "API_SURFACE.md",
      purpose: "Every public function the specification declares, against what lib/ defines.",
      task: "vis.surface",
      gate: "api-surface-drift",
      hardness: :hard,
      prose:
        "`specified` — declared in `spec/` and defined in `lib/`. `unspecified` — defined but " <>
          "declared nowhere: write the row. `unimplemented` — declared but undefined: build it or " <>
          "delete the row. `Version` is the content hash of the definition (all clauses), so a " <>
          "row changes only when its function does.",
      columns: @columns,
      stats: [
        Golden.stat("#{length(rows)} public functions", [
          {"specified", result.specified},
          {"unspecified", length(result.unspecified)},
          {"unimplemented", length(result.unimplemented)}
        ])
      ],
      rows: rows
    }
  end

  @doc "Renders `run/1`'s result to the golden's bytes."
  @spec render(result) :: String.t()
  def render(result), do: result |> golden_spec() |> Golden.render()

  defp row(item, code, spec) do
    %{
      "Function" => {:code, item},
      "Section" => if(spec, do: {:code, spec.section}, else: :absent),
      "Status" => {:atom, status(code, spec)},
      "Version" => {:version, code && code.version},
      "Locus" => {:locus, code && code.file, nil}
    }
  end

  defp status(nil, _spec), do: :unimplemented
  defp status(_code, nil), do: :unspecified
  defp status(_code, _spec), do: :specified

  defp item_of(%{"Function" => {:code, item}}), do: item
end
