defmodule Visualize.Chart.FrameCentreLabelTest do
  @moduledoc """
  #489: `{:frame, :center}` anchors a frame label at the plot's centre — the polar origin
  in a `:polar` frame, whatever the `r` scale's range, and the plot's middle in a cartesian
  one — anchored at its middle, with no baseline and no outward direction of its own
  (spec/14 §6.3). The validator accepts it and the JSON form carries it (§10, §11).
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.{Frame, Validator}

  @size {300, 200}
  @margin %{top: 20, right: 30, bottom: 40, left: 10}

  defp design(kind, scales, labels, styles \\ %{}) do
    %{
      version: 2,
      sources: %{},
      styles: styles,
      frames: %{main: %{kind: kind, margin: @margin, scales: scales}},
      labels: labels
    }
  end

  defp texts(design) do
    design
    |> Chart.from_map!()
    |> Frame.new(size: @size)
    |> Frame.generate()
    |> Map.fetch!(:children)
    |> Enum.filter(&(&1.style[:class] == "label"))
  end

  # The polar group's translate: the origin a centred mark is drawn about.
  defp polar_origin(design) do
    design
    |> Chart.from_map!()
    |> Frame.new(size: @size)
    |> Frame.generate()
    |> Map.fetch!(:children)
    |> Enum.find_value(fn
      %{style: %{class: "polar"}, transform: %{operations: [{:translate, x, y}]}} -> {x, y}
      _other -> nil
    end)
  end

  # The plot is 260 × 140 inside the margin.
  @plot_centre {130.0, 70.0}

  describe "in a :polar frame" do
    for range <- [[0, 60], [50, 60], [20, 30]] do
      test "the label sits at the polar origin when r's range is #{inspect(range)}" do
        scales = %{
          angle: %{kind: :linear, domain: [0, 1]},
          r: %{kind: :linear, domain: [0, 100], range: unquote(range)}
        }

        d = design(:polar, scales, [%{anchor: {:frame, :center}, text: "mid"}])
        [text] = texts(d)

        assert {text.attrs.x, text.attrs.y} == @plot_centre
        assert polar_origin(d) == @plot_centre
        assert text.style.text_anchor == :middle
        # No baseline of its own: the point is the text's baseline.
        refute Map.has_key?(text.attrs, :dy)
      end
    end

    test "{:data, [0, 0]} is the origin only when r's range starts at zero, which is why the anchor exists" do
      scales = %{
        angle: %{kind: :linear, domain: [0, 1]},
        r: %{kind: :linear, domain: [0, 100], range: [50, 60]}
      }

      [data, centre] =
        texts(
          design(:polar, scales, [
            %{anchor: {:data, [0, 0]}, text: "data"},
            %{anchor: {:frame, :center}, text: "centre"}
          ])
        )

      {cx, cy} = @plot_centre
      # Radius zero maps to 50 up the first spoke.
      assert {data.attrs.x, data.attrs.y} == {cx, cy - 50}
      assert {centre.attrs.x, centre.attrs.y} == {cx, cy}
    end
  end

  describe "in a :cartesian frame" do
    test "the label sits at the plot's middle, its dx and dy added" do
      scales = %{x: %{kind: :linear, domain: [0, 3]}, y: %{kind: :linear, domain: [0, 10]}}

      [text] =
        texts(
          design(:cartesian, scales, [%{anchor: {:frame, :center}, text: "c", dx: 2, dy: -5}])
        )

      assert {text.attrs.x, text.attrs.y} == {132.0, 65.0}
      assert text.style.text_anchor == :middle
    end

    test "it has no outward direction: a style's margins leave it where it is" do
      scales = %{x: %{kind: :linear, domain: [0, 3]}, y: %{kind: :linear, domain: [0, 10]}}
      label = %{anchor: {:frame, :center}, text: "c"}

      [plain] = texts(design(:cartesian, scales, [label]))

      [styled] =
        texts(
          design(:cartesian, scales, [Map.put(label, :style, :out)], %{
            out: %{margin_x: 6, margin_y: 4}
          })
        )

      assert styled.attrs == plain.attrs
    end
  end

  test "the validator accepts it and the JSON form carries it" do
    d = design(:cartesian, %{}, [%{anchor: {:frame, :center}, text: "c"}])
    assert Validator.validate(d) == :ok

    {:ok, json} = d |> Chart.from_map!() |> Chart.to_json()
    assert json =~ ~s("$frame":"center")
    assert {:ok, back} = Chart.from_json(json)
    assert hd(Chart.to_map(back).labels).anchor == {:frame, :center}
  end
end
