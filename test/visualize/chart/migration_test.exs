defmodule Visualize.Chart.MigrationTest do
  @moduledoc "Version handling of spec/14 §9."
  use ExUnit.Case, async: true

  doctest Visualize.Chart.Migration

  alias Visualize.Chart.Migration

  test "the current version passes through unchanged" do
    design = %{version: Migration.current(), frames: %{main: %{kind: :cartesian}}}
    assert Migration.migrate(design) == {:ok, design}
  end

  test "a version this library does not write is an error at [:version]" do
    assert Migration.migrate(%{version: 3}) == {:error, [{[:version], {:newer_schema, 3, 2}}]}
    assert Migration.migrate(%{version: 0}) == {:error, [{[:version], {:unsupported_version, 0}}]}
    assert Migration.migrate(%{version: "1"}) == {:error, [{[:version], {:type, :integer}}]}
    assert Migration.migrate(%{}) == {:error, [{[:version], :required}]}
    assert Migration.migrate([]) == {:error, [{[], {:type, {:node, :design}}}]}
  end

  describe "a version 1 design read from JSON (spec/14 §9, #479)" do
    @v1 %{
      "version" => 1,
      "frame" => %{
        "kind" => "cartesian",
        "size" => %{"width" => 600, "height" => 220},
        "margin" => %{"top" => 8, "right" => 8, "bottom" => 24, "left" => 40},
        "scales" => %{"x" => %{"kind" => "time"}, "y" => %{"kind" => "linear", "nice" => false}},
        "axes" => [%{"scale" => "x", "side" => "bottom", "ticks" => 5}]
      },
      "sources" => %{"points" => %{"fields" => ["t", "v", "series"]}},
      "marks" => [
        %{"type" => "line", "data" => "points", "channels" => %{"x" => "t", "y" => "v"}}
      ]
    }

    test "decodes typed and migrates: the frame is frames.main, its values atoms, its size gone" do
      assert {:ok, chart} = Visualize.Chart.from_json(Jason.encode!(@v1))
      assert chart.version == 2
      assert %{kind: :cartesian, scales: %{x: %{kind: :time}}} = chart.frames.main
      assert [%{scale: :x, side: :bottom, ticks: 5}] = chart.frames.main.axes
      refute Map.has_key?(chart.frames.main, :size)
    end

    test "a fragment read from v1 JSON is typed the same way" do
      assert {:ok, fragment} = Visualize.Chart.Fragment.from_json(Jason.encode!(@v1))
      assert %{frame: %{kind: :cartesian, axes: [%{side: :bottom}]}} = fragment
    end

    test "only a key the current schema lacks is read by its old type" do
      assert Migration.legacy_type(:design, :frame) == {:node, :frame}
      assert Migration.legacy_type(:design, :frames) == nil
      assert Migration.legacy_type(:frame, :size) == nil
    end
  end
end
