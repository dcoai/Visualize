defmodule Visualize.Scale.ProtocolTest do
  @moduledoc """
  The recurrence guard for #13: every scale kind the facade constructs answers all nine
  protocol operations (spec/03 §1.3), and `Axis` draws every continuous one.
  """
  use ExUnit.Case, async: true

  alias Visualize.Axis
  alias Visualize.Scale

  @t0 ~U[2024-01-01 00:00:00Z]
  @t1 ~U[2024-01-02 00:00:00Z]
  @noon ~U[2024-01-01 12:00:00Z]

  # {name, constructed scale, a domain value, a range value}
  defp scales do
    [
      {"linear", Scale.linear() |> Scale.domain([0, 10]) |> Scale.range([0, 100]), 5, 50},
      {"log", Scale.log() |> Scale.domain([1, 1000]) |> Scale.range([0, 3]), 10, 1.0},
      {"log/2", Scale.log(2) |> Scale.domain([1, 8]) |> Scale.range([0, 3]), 4, 2.0},
      {"power", Scale.power() |> Scale.domain([-10, 10]) |> Scale.range([0, 100]), -5, 25},
      {"sqrt", Scale.sqrt() |> Scale.domain([0, 100]) |> Scale.range([0, 10]), 25, 5},
      {"symlog", Scale.symlog() |> Scale.domain([-100, 100]) |> Scale.range([0, 1]), 0, 0.5},
      {"time", Scale.time() |> Scale.domain([@t0, @t1]) |> Scale.range([0, 24]), @noon, 12},
      {"radial", Scale.radial() |> Scale.domain([0, 360]), 90, :math.pi() / 2},
      {"ordinal", Scale.ordinal() |> Scale.domain([:a, :b]) |> Scale.range([1, 2]), :b, 2},
      {"band", Scale.band() |> Scale.domain([:a, :b]) |> Scale.range([0, 100]), :b, 50},
      {"quantize", Scale.quantize() |> Scale.domain([0, 100]) |> Scale.range([:lo, :hi]), 75,
       :hi},
      {"quantile", Scale.quantile() |> Scale.domain([1, 2, 3, 4]) |> Scale.range([:lo, :hi]), 4,
       :hi},
      {"threshold", Scale.threshold() |> Scale.domain([50]) |> Scale.range([:lo, :hi]), 75, :hi},
      {"sequential", Scale.sequential(:blues) |> Scale.domain([0, 10]), 5, "#"},
      {"diverging", Scale.diverging(:rdbu) |> Scale.domain([-1, 0, 1]), 0, "#"}
    ]
  end

  test "every scale module declares the behaviour" do
    for {_name, scale, _v, _r} <- scales() do
      behaviours = scale.__struct__.__info__(:attributes) |> Keyword.get_values(:behaviour)
      assert Visualize.Scale.Behaviour in List.flatten(behaviours), inspect(scale.__struct__)
    end
  end

  test "all nine operations are answered by every scale kind" do
    for {name, scale, value, _r} <- scales() do
      assert %{} = Scale.domain(scale, scale.domain), name
      assert %{} = Scale.nice(scale), name
      assert %{} = Scale.padding(scale, 0.1), name
      assert %{} = Scale.clamp(scale, true), name
      assert is_number(Scale.bandwidth(scale)), name
      assert is_list(Scale.ticks(scale)), name
      assert is_list(Scale.ticks(scale, 3)), name
      refute is_nil(Scale.apply(scale, value)), name
      _ = Scale.invert(scale, 0.5)
    end
  end

  test "apply/2 maps the sample value" do
    for {name, scale, value, expected} <- scales() do
      case expected do
        "#" -> assert "#" <> _ = Scale.apply(scale, value), name
        n when is_number(n) -> assert_in_delta Scale.apply(scale, value), n, 1.0e-9, name
        atom -> assert Scale.apply(scale, value) == atom, name
      end
    end
  end

  test "discrete and discretising scales answer nil from invert/2" do
    for name <- ~w(ordinal band quantize quantile threshold sequential diverging) do
      {_, scale, _, _} = Enum.find(scales(), &(elem(&1, 0) == name))
      assert Scale.invert(scale, 0.5) == nil, name
    end
  end

  test "discretising scales tick at their thresholds" do
    quantize = Scale.quantize() |> Scale.domain([0, 100]) |> Scale.range([:a, :b, :c, :d])
    assert Scale.ticks(quantize) == [25.0, 50.0, 75.0]

    quantile = Scale.quantile() |> Scale.domain([1, 2, 3, 4, 5, 6, 7, 8]) |> Scale.range([1, 2])
    assert Scale.ticks(quantile) == [4.5]

    threshold = Scale.threshold() |> Scale.domain([30, 10, 20]) |> Scale.range([:a, :b, :c, :d])
    assert Scale.ticks(threshold) == [10, 20, 30]
  end

  test "the five formerly non-conforming modules keep scale/2 as an alias" do
    power = Scale.power() |> Scale.domain([0, 4]) |> Scale.range([0, 1])
    assert Scale.Power.scale(power, 2) == Scale.Power.apply(power, 2)

    symlog = Scale.symlog()
    assert Scale.Symlog.scale(symlog, 0.5) == Scale.Symlog.apply(symlog, 0.5)

    quantize = Scale.quantize() |> Scale.range([:a, :b])
    assert Scale.Quantize.scale(quantize, 0.9) == :b

    quantile = Scale.quantile() |> Scale.domain([1, 2, 3]) |> Scale.range([:a, :b])
    assert Scale.Quantile.scale(quantile, 3) == :b

    threshold = Scale.threshold() |> Scale.domain([1]) |> Scale.range([:a, :b])
    assert Scale.Threshold.scale(threshold, 1) == :b
  end

  test "continuous scales store two-element lists whichever shape they were given" do
    for mod <- [Scale.Power, Scale.Symlog, Scale.Quantize] do
      assert mod.new() |> mod.domain({1, 2}) |> Map.fetch!(:domain) == [1, 2]
      assert mod.new() |> mod.domain([1, 2]) |> Map.fetch!(:domain) == [1, 2]
    end

    for mod <- [Scale.Power, Scale.Symlog] do
      assert mod.new() |> mod.range({3, 4}) |> Map.fetch!(:range) == [3, 4]
    end
  end

  test "Axis renders every continuous scale, and its domain line spans the real range" do
    for name <- ~w(linear log power sqrt symlog time) do
      {_, scale, _, _} = Enum.find(scales(), &(elem(&1, 0) == name))
      scale = Scale.range(scale, [0, 300])
      svg = scale |> Axis.bottom() |> Axis.render()
      assert svg =~ "<path", name
      assert svg =~ "H300", name
      assert svg =~ ~s(class="tick"), name
    end
  end

  test "a diverging colour scale ticks over its whole domain" do
    scale = Scale.diverging(:rdbu) |> Scale.domain([-10, 0, 10])
    assert Scale.ticks(scale, 5) == [-10.0, -5.0, 0.0, 5.0, 10.0]
  end

  test "Quantile.apply/2 reaches the last bucket" do
    # The bucket search's base case returned 0 instead of the index it had reached, so a
    # value above every threshold mapped to the first range element.
    scale = Scale.quantile() |> Scale.domain([1, 2, 3, 4]) |> Scale.range([:a, :b, :c])
    assert Scale.Quantile.quantiles(scale) == [2.0, 3.0]
    assert Scale.apply(scale, 1) == :a
    assert Scale.apply(scale, 2.5) == :b
    assert Scale.apply(scale, 4) == :c
  end
end
