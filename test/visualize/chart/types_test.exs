defmodule Visualize.Chart.TypesTest do
  @moduledoc """
  The type check of a binding (spec/14 §7.4, spec/15 §4.3, #582, D-153): every field a mark
  reads through a scale against what the scale's kind needs — in the pure check, in
  application's schema step, in the board's binding check, and in the cell state the
  runtime and the builder draw for a wrong binding.
  """
  use ExUnit.Case, async: true

  alias Visualize.Board
  alias Visualize.Board.{Binding, Draw, State}
  alias Visualize.Chart
  alias Visualize.Chart.Validator
  alias Visualize.Data.{Delivery, Schema}

  # One mark reading `t` on x and `v` on y, with the two scales' kinds given.
  defp design(x, y, extra \\ %{}) do
    Map.merge(
      %{
        version: 2,
        sources: %{primary: %{fields: [:t, :v, :k]}},
        frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: x}, y: %{kind: y}}}},
        marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      },
      extra
    )
  end

  defp schema(types), do: Schema.new!(Map.new(types, fn {f, t} -> {f, %{type: t}} end))

  # A slot and a field are named by their strings (spec/14 §1.4, D-195).
  defp mismatch(path, field, expected, given),
    do: {path, {:type_mismatch, "primary", Atom.to_string(field), expected, given}}

  @x [:marks, 0, :channels, :x]
  @y [:marks, 0, :channels, :y]

  describe "check_types/2: every mismatch class" do
    test "a time scale needs a time: a number, a category or text is reported" do
      for given <- [:number, :category, :text] do
        types = %{primary: schema(t: given, v: :number)}

        assert Chart.check_types(design(:time, :linear), types) ==
                 {:error, [mismatch(@x, :t, :time, given)]}
      end

      assert Chart.check_types(design(:time, :linear), %{primary: schema(t: :time, v: :number)}) ==
               :ok
    end

    test "every numeric kind needs a number: a category or text is reported" do
      numeric =
        [:linear, :log, :power, :sqrt, :symlog, :radial, :quantize, :quantile, :threshold] ++
          [:sequential, :diverging]

      for kind <- numeric, given <- [:category, :text] do
        types = %{primary: schema(t: :number, v: given)}

        assert Chart.check_types(design(:linear, kind), types) ==
                 {:error, [mismatch(@y, :v, :number, given)]},
               "#{kind} took #{given}"

        assert Chart.check_types(design(:linear, kind), %{primary: schema(t: :number, v: :number)}) ==
                 :ok
      end
    end

    test "band and ordinal need a category: a number or a time is reported, text is not" do
      for kind <- [:band, :ordinal], given <- [:number, :time] do
        types = %{primary: schema(t: given, v: :number)}

        assert Chart.check_types(design(kind, :linear), types) ==
                 {:error, [mismatch(@x, :t, :category, given)]}
      end

      for kind <- [:band, :ordinal], given <- [:category, :text] do
        assert Chart.check_types(design(kind, :linear), %{primary: schema(t: given, v: :number)}) ==
                 :ok
      end
    end

    test "a schema's time is instants: a numeric scale reports it, and a tick is a number (D-154)" do
      for kind <- [:linear, :log, :power, :sqrt, :symlog] do
        assert Chart.check_types(design(kind, :linear), %{primary: schema(t: :time, v: :number)}) ==
                 {:error, [mismatch(@x, :t, :number, :time)]}
      end

      # `Visualize.Feed.Signals` describes its integer tick as a `:number` window field.
      tick = Visualize.Feed.Signals.new(Visualize.Signals.new(:sine, [:t, :v])).schema
      assert Chart.check_types(design(:linear, :linear), %{primary: tick}) == :ok

      assert Chart.check_types(design(:time, :linear), %{primary: tick}) ==
               {:error, [mismatch(@x, :t, :time, :number)]}
    end

    test "a feed of DateTimes under :time, bound to a linear axis, is reported by application" do
      schema = schema(t: :time, v: :number)
      rows = for s <- 0..2, do: %{t: DateTime.add(~U[2026-10-12 00:00:00Z], s), v: s, k: "a"}
      source = Delivery.new(rows, schema: Schema.version(schema))

      assert {:error, [mismatch(@x, :t, :number, :time)]} ==
               Chart.apply(design(:linear, :linear),
                 sources: %{primary: source},
                 describe: fn :primary -> {:ok, schema} end
               )
    end

    test "a rows' types are how values are written: instants on a numeric scale are reported" do
      rows = %{primary: %{t: :time, v: :number}}

      assert Chart.check_types(design(:linear, :linear), rows) ==
               {:error, [mismatch(@x, :t, :number, :time)]}

      assert Chart.check_types(design(:time, :linear), %{primary: %{t: :number, v: :number}}) ==
               {:error, [mismatch(@x, :t, :time, :number)]}

      # A band takes a value of any type, so rows never fault one.
      for given <- [:number, :time, :text, :category] do
        assert Chart.check_types(design(:band, :linear), %{primary: %{t: given, v: :number}}) ==
                 :ok
      end

      # A field named as a string is read in either spelling.
      assert Chart.check_types(design(:linear, :linear), %{primary: %{"t" => :text}}) ==
               {:error, [mismatch(@x, :t, :number, :text)]}
    end

    test "every fault is reported, by path, and an untyped field or slot is not checked" do
      types = %{primary: schema(t: :category, v: :time)}

      assert Chart.check_types(design(:linear, :band), types) ==
               {:error,
                [mismatch(@x, :t, :number, :category), mismatch(@y, :v, :category, :time)]}

      assert Chart.check_types(design(:linear, :linear), %{primary: schema(k: :category)}) == :ok
      assert Chart.check_types(design(:linear, :linear), %{other: schema(t: :category)}) == :ok
      assert Chart.check_types(%{}, %{}) == :ok
      assert Chart.check_types(%{marks: :nope, frames: 3}, %{}) == :ok
    end

    test "a chart struct is read as its map" do
      {:ok, chart} = Chart.from_map(design(:linear, :linear))

      assert Chart.check_types(chart, %{primary: schema(t: :category)}) ==
               {:error, [mismatch(@x, :t, :number, :category)]}
    end
  end

  describe "check_types/2: where a field reaches a scale" do
    test "a mark's scales rename the scale a channel names" do
      d =
        design(:linear, :linear)
        |> put_in([:frames, :main, :scales, :when], %{kind: :time})
        |> put_in([:marks, Access.at(0), :scales], %{x: :when})

      assert Chart.check_types(d, %{primary: schema(t: :number)}) ==
               {:error, [mismatch(@x, :t, :time, :number)]}
    end

    test "an adopted scale is checked as the frame that owns it declares it" do
      d =
        design(:linear, :linear)
        |> put_in([:frames, :top], %{kind: :cartesian, scales: %{x: %{kind: :band}}})
        |> put_in([:frames, :main, :scales, :x], {:frame, :top, :x})
        |> put_in([:marks, Access.at(0), :frame], :main)

      assert Chart.check_types(d, %{primary: schema(t: :number)}) ==
               {:error, [mismatch(@x, :t, :category, :number)]}
    end

    test "a series reaches the color scale, and so does a field on the style's color" do
      d =
        design(:linear, :linear)
        |> put_in([:frames, :main, :scales, :color], %{kind: :ordinal})
        |> put_in([:marks, Access.at(0), :channels, :series], :k)
        |> put_in([:marks, Access.at(0), :style], %{stroke: {:field, :v}})

      assert Chart.check_types(d, %{primary: schema(t: :number, v: :number, k: :number)}) ==
               {:error,
                [
                  mismatch([:marks, 0, :channels, :series], :k, :category, :number),
                  mismatch([:marks, 0, :style], :v, :category, :number)
                ]}
    end

    test "an offset family's field reaches its offset scale" do
      d =
        design(:band, :linear)
        |> put_in([:frames, :main, :scales, :x_offset], %{kind: :band})
        |> put_in([:marks, Access.at(0), :offset], %{x: :v})

      assert Chart.check_types(d, %{primary: schema(t: :category, v: :number)}) ==
               {:error, [mismatch([:marks, 0, :offset, :x], :v, :category, :number)]}
    end

    test "a polar frame reads x as the angle and y as the radius" do
      d =
        design(:linear, :linear)
        |> put_in([:frames, :main], %{
          kind: :polar,
          scales: %{angle: %{kind: :band}, r: %{kind: :linear}}
        })

      assert Chart.check_types(d, %{primary: schema(t: :number, v: :category)}) ==
               {:error,
                [mismatch(@x, :t, :category, :number), mismatch(@y, :v, :number, :category)]}
    end

    test "steps that keep every field are read through; any other is not checked" do
      kept =
        put_in(design(:linear, :linear), [:marks, Access.at(0), :data], %{
          source: :primary,
          transforms: [%{op: :filter, field: :v, test: :gt, value: 0}, %{op: :sort, by: :t}]
        })

      assert Chart.check_types(kept, %{primary: schema(t: :category)}) ==
               {:error, [mismatch(@x, :t, :number, :category)]}

      binned =
        put_in(design(:linear, :linear), [:marks, Access.at(0), :data], %{
          source: :primary,
          transforms: [%{op: :bin, field: :t, thresholds: [1]}]
        })

      assert Chart.check_types(binned, %{primary: schema(t: :category)}) == :ok
    end

    test "a variable kind, a variable data and a constant are not checked" do
      var = Chart.var(:kind)

      assert Chart.check_types(
               put_in(design(:linear, :linear), [:frames, :main, :scales, :x, :kind], var),
               %{primary: schema(t: :category)}
             ) == :ok

      assert Chart.check_types(
               put_in(design(:linear, :linear), [:marks, Access.at(0), :data], Chart.var(:d)),
               %{primary: schema(t: :category)}
             ) == :ok

      assert Chart.check_types(
               put_in(design(:linear, :linear), [:marks, Access.at(0), :channels, :x], 3),
               %{primary: schema(t: :category)}
             ) == :ok
    end
  end

  describe "apply/2 checks the types where a schema is bound" do
    # The design over two fields, as the rows hold them.
    defp applied(x, y), do: put_in(design(x, y), [:sources, :primary, :fields], [:t, :v])

    @rows [%{t: ~U[2026-10-11 12:00:00Z], v: 1}, %{t: ~U[2026-10-11 12:01:00Z], v: 2}]

    test "a slot with no contract reports a mismatch at the read's path, never drawn" do
      s = schema(t: :category, v: :number)
      rows = [%{t: "a", v: 1}, %{t: "b", v: 2}]

      assert Chart.apply(applied(:linear, :linear),
               sources: %{primary: Delivery.new(rows, schema: Schema.version(s))},
               describe: fn :primary -> {:ok, s} end
             ) == {:error, [mismatch(@x, :t, :number, :category)]}
    end

    test "with a contract, the mismatch is reported beside the contract's faults" do
      s = Schema.new!(%{t: %{type: :number}, v: %{type: :category}})

      d =
        put_in(applied(:linear, :linear), [:sources, :primary, :requires], %{v: [:label]})

      assert {:error, errors} =
               Chart.apply(d,
                 sources: %{primary: Delivery.new([%{t: 1, v: "a"}], schema: s.version)},
                 describe: fn :primary -> {:ok, s} end
               )

      assert errors == [
               mismatch(@y, :v, :number, :category),
               {[:sources, "primary", :requires, "v"],
                {:missing_attribute, "primary", "v", :label}}
             ]

      assert Validator.format(hd(errors)) ==
               ~s(marks[0].channels.y: field "v" of slot "primary" is a category, and the design ) <>
                 "reads it as a number"
    end

    test "a schema that does not resolve leaves the types unchecked, and the frame raises" do
      delivery = Delivery.new(@rows, schema: "unknown")

      assert_raise ArgumentError, ~r/a number is needed/, fn ->
        Chart.apply(applied(:linear, :linear), sources: %{primary: delivery})
      end
    end

    test "rows of the wrong type with no schema still raise, as direct misuse always has" do
      assert_raise ArgumentError, ~r/a number is needed/, fn ->
        Chart.apply(applied(:linear, :linear), sources: %{primary: @rows})
      end
    end
  end

  describe "the board's binding check (spec/15 §4.3)" do
    defp store do
      %{{:composite, 1} => design(:linear, :linear)}
    end

    defp board do
      Board.from_map!(%{
        cells: %{
          a: %{x: 0, y: 0, w: 6, h: 3, ref: {:composite, 1}},
          b: %{x: 6, y: 0, w: 6, h: 3, ref: {:composite, 1}}
        }
      })
    end

    test "required sources carry each slot's reads" do
      {:ok, required} = Board.required_sources(board(), store())

      assert required[{"a", "primary"}].reads == [{@x, "t", :number}, {@y, "v", :number}]
    end

    test "each bound slot's mismatches are reported under its cell" do
      {:ok, required} = Board.required_sources(board(), store())
      binding = Binding.new(%{{:a, :primary} => :names, {:b, :primary} => :latency})

      schemas = %{
        names: schema(t: :category, v: :number),
        latency: schema(t: :time, v: :number)
      }

      assert Binding.check(binding, required, schemas) ==
               {:error,
                [
                  {[:cells, "a" | @x], {:type_mismatch, "primary", "t", :number, :category}},
                  {[:cells, "b" | @x], {:type_mismatch, "primary", "t", :number, :time}}
                ]}

      [error | _] = elem(Binding.check(binding, required, schemas), 1)
      assert Board.format_error(error) =~ ~s(cells.a.marks[0].channels.x: field "t" of slot)
    end

    test "a schema wanted only for the type check is no fault where it cannot be had" do
      {:ok, required} = Board.required_sources(board(), store())
      binding = Binding.new(%{{:a, :primary} => :names, {:b, :primary} => :names})

      assert Binding.check(binding, required, %{}) == :ok
      assert Binding.check(binding, required, fn :names -> {:error, :down} end) == :ok
    end

    test "check_types/3 takes plain types, as a sample's rows show them" do
      {:ok, required} = Board.required_sources(board(), store())
      binding = Binding.new(%{{:a, :primary} => :stamps, {:b, :primary} => :numbers})

      types = %{stamps: %{t: :time, v: :number}, numbers: %{t: :number, v: :number}}

      assert Binding.check_types(binding, required, types) ==
               {:error, [{[:cells, "a" | @x], {:type_mismatch, "primary", "t", :number, :time}}]}

      assert Binding.check_types(Binding.new(), required, types) == :ok
    end
  end

  describe "the invalid state (spec/15 §8.4)" do
    @errors [{[:marks, 0, :channels, :x], {:type_mismatch, "primary", "t", :number, :category}}]

    test "a wrong binding is a bad state, drawn with its first fault" do
      assert State.role({:invalid, @errors}) == :bad

      assert State.words({:invalid, @errors}) ==
               ~s(Wrong binding: marks[0].channels.x: field "t" of slot "primary" is a category, ) <>
                 "and the design reads it as a number"

      svg = State.render({:invalid, @errors}, Visualize.Theme.default(), {400, 200})
      assert svg =~ ~s(data-vis-state="invalid")
      assert svg =~ "Wrong binding"
    end

    test "the runtime calls an application's type fault invalid, and any other down" do
      assert Draw.state({:apply, @errors}, nil, nil, nil) == {:invalid, @errors}

      other = [{[:sources, "primary"], {:no_schema, "primary"}}]
      assert Draw.state({:apply, other}, nil, nil, nil) == {:down, {:apply, other}}
    end
  end
end
