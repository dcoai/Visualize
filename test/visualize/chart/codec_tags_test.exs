defmodule Visualize.Chart.CodecTagsTest do
  # The recurrence guard of #645 (spec/14 §11.2, D-182): the one table of `$` tags is what
  # the encoders write and the readers read. Every live tag round-trips through its JSON,
  # the samples here cover exactly the table's live tags — a tag added to the table without
  # a sample, or a sample of a tag the table lacks, fails — and any other `$` key in a
  # one-key object is refused at its path, never read as data.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Board
  alias Visualize.Board.Snapshot
  alias Visualize.Chart
  alias Visualize.Chart.{Codec, Fact, Fragment, Use, Var}
  alias Visualize.Chart.Codec.Tags
  alias Visualize.Chart.Validator.Types

  # A plain-words name, as a document's names are.
  defp word, do: StreamData.string(?a..?z, min_length: 1, max_length: 8)
  defp name, do: StreamData.map(word(), &String.to_atom/1)

  defp at(map, path, value), do: put_in(map, Enum.map(path, &Access.key(&1, %{})), value)

  defp style(path, value), do: at(%{version: 3}, [:styles, :s | path], value)

  # A design map's JSON and back, held to the table on the way in, as `from_json/2` reads.
  defp json_round_trip(map) do
    json = map |> Codec.encode() |> Jason.encode!()
    {:ok, term} = json |> Jason.decode!() |> Tags.read(3)
    {json, Codec.decode(term)}
  end

  # One generator of a design map per tag a design writes: the map, its JSON, and back.
  defp design_samples do
    %{
      "$var" => StreamData.map(name(), &style([:fill, :color], %Var{name: &1})),
      "$field" => StreamData.map(name(), &style([:fill, :color], {:field, &1})),
      "$generate" =>
        StreamData.map(name(), &style([:fill, :color], {:generate, &1, [{:field, :tenant}]})),
      "$paint" => StreamData.map(name(), &style([:fill, :color], {:paint, &1})),
      "$ramp" =>
        StreamData.one_of([
          StreamData.map(
            StreamData.float(min: 0.0, max: 1.0),
            &style([:fill, :color], {:ramp, :status, &1})
          ),
          StreamData.constant(
            at(%{version: 3}, [:frames, :main, :scales, :c], %{
              kind: :ordinal,
              range: {:ramp, :status}
            })
          )
        ]),
      "$color" => StreamData.map(name(), &style([:fill, :color], {:color, &1})),
      "$blend" =>
        StreamData.constant(style([:fill, :color], {:blend, [{:color, :red}, {:color, :blue}]})),
      "$contrast" =>
        StreamData.member_of([
          style([:fill, :color], {:contrast, :under}),
          style([:fill, :color], {:contrast, {:color, :red}})
        ]),
      "$steps" =>
        StreamData.constant(
          at(%{version: 3}, [:theme, :colors, :red], %{100 => "#fde8e8", 500 => "#d62728"})
        ),
      "$colors" =>
        StreamData.constant(
          at(%{version: 3}, [:frames, :main, :scales, :c], %{
            kind: :ordinal,
            range: %{"ok" => {:color, :good}, "fail" => {:color, :bad}}
          })
        ),
      "$series" =>
        StreamData.map(StreamData.integer(1..9), &style([:fill, :color], {:series, &1})),
      "$unit" =>
        StreamData.map(
          StreamData.member_of([:px, :pt, :mm, :em]),
          &style([:stroke, :width], {2, &1})
        ),
      "$scale" =>
        StreamData.map(
          StreamData.member_of([:min, :max]),
          &%{version: 3, marks: [%{type: :area, channels: %{y0: {:scale, &1}}}]}
        ),
      "$axis" => StreamData.map(name(), &label({:axis, &1})),
      # A frame point is one of the plot's five, looked up, never made (spec/14 §9.4).
      "$frame" =>
        StreamData.map(StreamData.member_of(Types.frame_points()), &label({:frame, &1})),
      "$data" =>
        StreamData.map(
          StreamData.tuple({StreamData.integer(), StreamData.integer()}),
          fn {x, y} -> label({:data, [x, y]}) end
        ),
      "$adopted" =>
        StreamData.map(
          name(),
          &at(%{version: 3}, [:frames, :inset, :scales, :x], {:frame, &1, :x})
        ),
      "$keys" =>
        StreamData.map(
          StreamData.list_of(name(), min_length: 1, max_length: 4),
          &%{
            version: 3,
            marks: [
              %{
                type: :area,
                data: %{source: :s, transforms: [%{op: :stack, fields: [:a], order: {:keys, &1}}]}
              }
            ]
          }
        ),
      "$fact" =>
        StreamData.map(
          name(),
          &%{
            version: 3,
            labels: [%{anchor: :title, text: [%Fact{source: :p, field: &1, key: :unit}]}]
          }
        ),
      "$time" =>
        StreamData.map(
          StreamData.integer(0..2_000_000_000),
          &var_default(DateTime.from_unix!(&1))
        ),
      "$atom" => StreamData.map(name(), &var_default/1)
    }
    |> Map.merge(Map.new(Visualize.Color.Typed.ops(), &op_sample/1))
  end

  defp op_sample(op) do
    {"$#{op}",
     StreamData.map(
       StreamData.integer(1..9),
       &style(
         [:fill, :color],
         {op, {:color, :red}, if(op == :shade, do: &1 * 100, else: &1 / 10)}
       )
     )}
  end

  defp label(anchor), do: %{version: 3, labels: [%{anchor: anchor, text: "t"}]}
  defp var_default(value), do: %{version: 3, vars: %{v: %{default: value}}}

  # The tags a design does not write, each written and read by the document that does.
  @other ~w($use $id $datum $absent $version)

  test "the samples cover exactly the table's live tags" do
    assert Enum.sort(Map.keys(design_samples()) ++ @other) == Enum.sort(Tags.live())
  end

  property "every tag a design writes round-trips through the table" do
    for {tag, sample} <- design_samples() do
      check all(map <- sample, max_runs: 20) do
        {json, back} = json_round_trip(map)
        assert json =~ ~s("#{tag}":)
        assert back == map
      end
    end
  end

  test "a use site and an id round-trip through a fragment document" do
    use = %Use{id: {:use, 4}, ref: {:composite, 2}, vars: %{v: 1}, local: %{}}
    fragment = %{composite: %{id: {:composite, 1}, uses: [use]}}
    {:ok, json} = Fragment.to_json(fragment)
    assert json =~ ~s("$use":) and json =~ ~s("$id":) and json =~ ~s("$version":)
    assert Fragment.from_json(json) == {:ok, fragment}
  end

  test "a datum drill variable round-trips through a board document" do
    {:ok, board} =
      Board.from_map(%{
        version: 3,
        cells: %{
          a: %{
            x: 0,
            y: 0,
            w: 4,
            h: 3,
            ref: {:composite, 1},
            drill: %{board: :self, vars: %{service: {:datum, :k}}}
          }
        }
      })

    {:ok, json} = Board.to_json(board)
    assert json =~ ~s("$datum":"k")
    assert Board.from_json(json) == {:ok, board}
  end

  test "an absent field is the snapshot's tag, and the snapshot is held to the table" do
    json = ~s({"$version": 3, "cells": {"a": {"slots": {"s": {"rows": {"$abset": true}}}}}})
    assert {:error, [{path, {:unknown_tag, "$abset"}}]} = Snapshot.from_json(json)
    assert path == ["cells", "a", "slots", "s", "rows"]
    assert "$absent" in Tags.live()
  end

  property "any other `$` key of a one-key object is refused at its path" do
    check all(
            tag <- StreamData.map(word(), &("$" <> &1)),
            tag not in Tags.live() and not Map.has_key?(Tags.retired(), tag) and
              not Map.has_key?(Tags.renamed(), tag),
            depth <- StreamData.integer(0..3)
          ) do
      {:ok, json} = Chart.to_json(Chart.from_map!(chart()))
      path = Enum.map(1..depth//1, &"k#{&1}")
      value = Enum.reduce(Enum.reverse(path), %{tag => 1}, &%{&1 => &2})
      doc = json |> Jason.decode!() |> put_in(["vars"], %{"v" => %{"default" => value}})

      assert Chart.from_json(Jason.encode!(doc)) ==
               {:error, [{["vars", "v", "default" | path], {:unknown_tag, tag}}]}
    end
  end

  test "a retired tag is refused with what replaced it, and the words say so" do
    {:ok, json} = Chart.to_json(Chart.from_map!(chart()))

    doc =
      json
      |> Jason.decode!()
      |> put_in(["vars"], %{"v" => %{"default" => %{"$styles" => "roles"}}})

    assert {:error, [error]} = Chart.from_json(Jason.encode!(doc))
    assert {["vars", "v", "default"], {:retired_tag, "$styles", _why}} = error
    assert Chart.Validator.format(error) =~ ~s(vars.v.default: "$styles" was removed in #644)
  end

  test "`$scale` is not retired: an area's baseline at its scale's end is still written" do
    assert "$scale" in Tags.live()
    refute Map.has_key?(Tags.retired(), "$scale")
  end

  describe "data whose keys start with `$`" do
    test "is escaped, so a data map that spells a tag round-trips as itself" do
      for data <- [%{"$atom": "x"}, %{"$field": "sha"}, %{"$price": 3}, %{"$$twice": 1, b: 2}] do
        {json, back} = json_round_trip(var_default(data))
        refute json =~ ~s({"$atom":"x"})
        assert back == var_default(data)
      end

      assert Codec.decode_term(Codec.encode_term(%{"$atom": "x"})) == %{"$atom": "x"}
    end

    test "a board's and a snapshot's names that start with `$` are escaped too" do
      {:ok, board} = Board.from_map(%{version: 3, vars: %{"$v": 1}, cells: %{}})
      {:ok, json} = Board.to_json(board)
      assert json =~ ~s("$$v":1)
      assert Board.from_json(json) == {:ok, board}
    end

    test "a document before version 3 reads its `$` data keys as it always did" do
      {:ok, json} = Chart.to_json(Chart.from_map!(chart()))
      data = %{"$price" => 3}
      doc = json |> Jason.decode!() |> Map.put("version", 2)
      doc = put_in(doc, ["vars"], %{"v" => %{"default" => data}})
      assert {:ok, chart} = Chart.from_json(Jason.encode!(doc))
      assert chart.vars.v.default == %{"$price": 3}
    end
  end

  defp chart do
    %{
      version: 3,
      sources: %{hosts: %{fields: [:t, :v]}},
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{x: %{kind: :linear, domain: [0, 2]}, y: %{kind: :linear, domain: [0, 4]}}
        }
      },
      marks: [%{type: :symbol, data: :hosts, channels: %{x: :t, y: :v}}]
    }
  end
end
