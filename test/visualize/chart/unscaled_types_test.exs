defmodule Visualize.Chart.UnscaledTypesTest do
  @moduledoc """
  A channel read as a number with no scale between (spec/14 §7.4, D-215, #835): a size, a
  share, an angle, a radius or a pixel needs a number, so a field of another type is a
  `{:type_mismatch, …}` at the channel — in `check_types/2`, at application where a schema
  resolves, and so a board cell draws `{:invalid, errors}` rather than crashing at render.
  """
  use ExUnit.Case, async: true

  alias Visualize.Board.Draw
  alias Visualize.Chart
  alias Visualize.Data.{Delivery, Schema}

  @types %{vehicles: %{x: :number, y: :number, vehicle: :text, n: :number}}

  # One mark over `vehicles` in a frame of the given kind and scales.
  defp design(mark, kind \\ :cartesian, scales \\ %{x: %{kind: :linear}, y: %{kind: :linear}}) do
    %{
      version: 2,
      sources: %{vehicles: %{fields: [:x, :y, :vehicle, :n]}},
      frames: %{main: %{kind: kind, scales: scales}},
      marks: [Map.put(mark, :data, :vehicles)]
    }
  end

  defp mismatch(channel, field, given \\ :text),
    do:
      {[:marks, 0, :channels, channel],
       {:type_mismatch, "vehicles", Atom.to_string(field), :number, given}}

  @circle %{type: :circle, channels: %{x: :x, y: :y, value: :vehicle}, options: %{radius: 2.5}}

  describe "the #835 design" do
    test "check_types/2 refuses a circle's radius bound to a text field, at its path" do
      assert Chart.check_types(design(@circle), @types) == {:error, [mismatch(:value, :vehicle)]}

      assert Chart.check_types(design(put_in(@circle, [:channels, :value], :n)), @types) == :ok
    end

    test "application refuses it where the slot's schema resolves, and a cell is invalid" do
      schema =
        Schema.new!(%{
          x: %{type: :number},
          y: %{type: :number},
          vehicle: %{type: :text},
          n: %{type: :number}
        })

      rows = [%{x: 1, y: 2, vehicle: "v1", n: 1}]
      delivery = Delivery.new(rows, schema: schema.version)
      d = put_in(design(@circle), [:sources, :vehicles, :requires], %{vehicle: []})

      assert {:error, errors} =
               Chart.apply(d,
                 sources: %{vehicles: delivery},
                 describe: fn :vehicles -> {:ok, schema} end
               )

      assert mismatch(:value, :vehicle) in errors
      assert Draw.state({:apply, errors}, nil, nil, nil) == {:invalid, errors}
    end

    test "the fault says the design reads the field as a number" do
      {:error, [fault]} = Chart.check_types(design(@circle), @types)

      assert Visualize.Chart.Validator.format(fault) ==
               ~s(marks[0].channels.value: field "vehicle" of slot "vehicles" is text, ) <>
                 "and the design reads it as a number"
    end
  end

  describe "every channel drawn at its reading needs a number" do
    test "a symbol's size and an arc's share" do
      symbol = %{type: :symbol, channels: %{x: :x, y: :y, value: :vehicle}}
      assert Chart.check_types(design(symbol), @types) == {:error, [mismatch(:value, :vehicle)]}

      arc = %{type: :arc, channels: %{value: :vehicle}}
      assert Chart.check_types(design(arc), @types) == {:error, [mismatch(:value, :vehicle)]}
    end

    test "an arc's angles and radii outside a polar frame" do
      arc = %{
        type: :arc,
        channels: %{value: :n, start: :vehicle, end: :vehicle, inner: :vehicle, outer: :n}
      }

      assert Chart.check_types(design(arc), @types) ==
               {:error,
                [mismatch(:end, :vehicle), mismatch(:inner, :vehicle), mismatch(:start, :vehicle)]}
    end

    test "a position in a geo frame, which is a pixel" do
      circle = %{type: :circle, channels: %{x: :vehicle, y: :y}}
      geo = design(circle, :geo, %{})
      assert Chart.check_types(geo, @types) == {:error, [mismatch(:x, :vehicle)]}
    end

    test "a channel naming a scale the frame does not declare, drawn in pixels" do
      line = %{type: :line, channels: %{x: :x, y: :vehicle}}
      d = design(line, :cartesian, %{x: %{kind: :linear}})
      assert Chart.check_types(d, @types) == {:error, [mismatch(:y, :vehicle)]}
    end

    test "a time read as a pixel is a mismatch too" do
      line = %{type: :line, channels: %{x: :t, y: :y}}
      d = design(line, :cartesian, %{y: %{kind: :linear}})
      types = %{vehicles: %{t: :time, y: :number}}
      assert Chart.check_types(d, types) == {:error, [mismatch(:x, :t, :time)]}
    end
  end

  describe "the readings that are not numbers stay unchecked" do
    test "a text's content, a rect's color and a series" do
      text = %{type: :text, channels: %{x: :x, y: :y, value: :vehicle}}

      assert Chart.check_types(
               design(text, :cartesian, %{x: %{kind: :linear}, y: %{kind: :linear}}),
               @types
             ) ==
               :ok

      rect = %{type: :rect, channels: %{x0: :x, x1: :x, y0: :y, y1: :y, value: :vehicle}}
      assert Chart.check_types(design(rect), @types) == :ok

      line = %{type: :line, channels: %{x: :x, y: :y, series: :vehicle}}
      assert Chart.check_types(design(line), @types) == :ok
    end

    test "a family an offset places" do
      rect = %{
        type: :rect,
        channels: %{x0: :vehicle, x1: :vehicle, y0: 0, y1: :y},
        offset: %{x: :vehicle}
      }

      d = design(rect, :cartesian, %{y: %{kind: :linear}})
      assert Chart.check_types(d, @types) == :ok
    end

    test "a field whose type is not known" do
      assert Chart.check_types(design(@circle), %{vehicles: %{x: :number}}) == :ok
    end
  end
end
