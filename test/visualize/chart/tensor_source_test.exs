defmodule Visualize.Chart.TensorSourceTest do
  @moduledoc """
  An `Nx` tensor bound to a design's slot (spec/14 §7.3, D-214, #830): read column by
  column in the slot's declared field order, a width that differs a fault at the slot, a
  slot that declares no fields refusing it — never an empty drawing. A map or keyword list
  of column tensors is columns, as a map of lists is.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.Validator

  defp design(fields \\ [:x, :y], type \\ :line) do
    %{
      version: 2,
      sources: %{pts: %{fields: fields, types: %{x: :number, y: :number}}},
      frames: %{
        main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}
      },
      marks: [%{type: type, data: :pts, channels: %{x: :x, y: :y}}]
    }
  end

  defp tensor, do: Nx.tensor([[1, 4.0], [2, 5.0], [3, 6.0]])
  defp lists, do: %{x: [1, 2, 3], y: [4.0, 5.0, 6.0]}

  defp render(source, fields \\ [:x, :y], type \\ :line) do
    {:ok, applied} = Chart.apply(design(fields, type), sources: %{pts: source}, size: {300, 200})
    Chart.render(applied)
  end

  describe "a rank-2 tensor bound to a slot that declares its fields" do
    test "the #830 example draws, the same as the rows it holds" do
      svg = render(tensor())
      assert svg =~ "<path"
      assert svg == render(lists())
    end

    test "the columns are named in the declared order" do
      {:ok, applied} = Chart.apply(design([:y, :x]), sources: %{pts: tensor()})
      assert applied.sources["pts"] == %{"y" => [1.0, 2.0, 3.0], "x" => [4.0, 5.0, 6.0]}
    end

    test "every point of a :circle mark is drawn" do
      svg = render(tensor(), [:x, :y], :circle)
      assert length(Regex.scan(~r/<circle\b/, svg)) == 3
      assert svg == render(lists(), [:x, :y], :circle)
    end

    test "a width other than the declared fields is a fault at the slot" do
      wide = Nx.tensor([[1, 2, 3], [4, 5, 6]])

      assert Chart.apply(design(), sources: %{pts: wide}) ==
               {:error, [{[:sources, "pts"], {:width, 2, 3}}]}

      assert Validator.format({[:sources, "pts"], {:width, 2, 3}}) =~
               "is 3 columns wide — a tensor's columns or a tuple row's elements — and the " <>
                 "slot declares 2 fields"
    end

    test "a tensor of another rank is a fault at the slot" do
      assert Chart.apply(design(), sources: %{pts: Nx.tensor([[[1, 2]]])}) ==
               {:error, [{[:sources, "pts"], {:rank, 3}}]}
    end

    test "a delivery carrying a tensor binds as the tensor does" do
      delivery = Visualize.Data.Delivery.new(tensor())
      {:ok, applied} = Chart.apply(design(), sources: %{pts: delivery})
      assert applied.sources["pts"] == %{"x" => [1.0, 2.0, 3.0], "y" => [4.0, 5.0, 6.0]}
    end
  end

  describe "a rank-1 tensor" do
    test "is one column, read by a slot of one field" do
      d = %{
        version: 2,
        sources: %{v: %{fields: [:v]}},
        frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear}}}},
        marks: [%{type: :rule, data: :v, channels: %{x: :v}}]
      }

      {:ok, applied} = Chart.apply(d, sources: %{v: Nx.tensor([1, 2, 3])})
      assert applied.sources["v"] == %{"v" => [1, 2, 3]}
    end

    test "is a width fault for a slot of two fields" do
      assert Chart.apply(design(), sources: %{pts: Nx.tensor([1, 2])}) ==
               {:error, [{[:sources, "pts"], {:width, 2, 1}}]}
    end
  end

  test "a slot that declares no fields refuses a tensor" do
    d = design() |> put_in([:sources, :pts], %{fields: []}) |> Map.put(:marks, [])

    assert {:error, [{[:sources, "pts"], {:type, :named_rows}} = fault]} =
             Chart.apply(d, sources: %{pts: tensor()})

    assert Validator.format(fault) =~ "rows with named fields"
  end

  describe "columns that are tensors" do
    test "a map of rank-1 tensors draws what the map of lists draws" do
      columns = %{x: Nx.tensor([1, 2, 3]), y: Nx.tensor([4.0, 5.0, 6.0])}
      assert render(columns) == render(lists())
    end

    test "a keyword list of rank-1 tensors, mixed with a list, draws the same" do
      assert render(x: Nx.tensor([1, 2, 3]), y: [4.0, 5.0, 6.0]) == render(lists())
    end
  end

  test "the builder's preview types a tensor's columns by the slot's fields" do
    timed =
      design()
      |> put_in([:frames, :main, :scales, :x], %{kind: :time})
      |> put_in([:sources, :pts], %{fields: [:x, :y]})

    pool = %{pts: tensor()}

    assert [{[:marks, 0, :channels, :x], {:type_mismatch, _, _, :time, :number}}] =
             Chart.Builder.Preview.type_faults(timed, pool, nil)
  end

  describe "a compiled chart's tick" do
    test "names a tensor by its slot's fields, as application does" do
      {:ok, %{"main" => compiled}} = Chart.compile(design(), sources: %{pts: lists()})

      assert Chart.Compiled.svg(compiled, %{pts: tensor()}) ==
               Chart.Compiled.svg(compiled, %{pts: lists()})
    end

    test "svg/2, which returns no chart, raises naming the slot for a tensor it cannot read" do
      {:ok, %{"main" => compiled}} = Chart.compile(design(), sources: %{pts: lists()})

      assert_raise ArgumentError, ~r/sources\.pts.*3 columns wide/, fn ->
        Chart.Compiled.svg(compiled, %{pts: Nx.tensor([[1, 2, 3]])})
      end
    end

    test "a tick fed a tensor it cannot read carries the fault, and raises nothing (D-232)" do
      {:ok, %{"main" => compiled}} = Chart.compile(design(), sources: %{pts: lists()})

      {_payload, faulted} = Chart.Compiled.tick(compiled, %{pts: Nx.tensor([[1, 2, 3]])}, at: 0)
      assert Chart.Compiled.faults(faulted) == [{[:sources, "pts"], {:width, 2, 3}}]

      {_group, faulted} = Chart.Compiled.step(compiled, %{pts: Nx.tensor([[[1, 2]]])}, at: 0)
      assert Chart.Compiled.faults(faulted) == [{[:sources, "pts"], {:rank, 3}}]
    end
  end
end
