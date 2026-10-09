defmodule Visualize.Render.RasterGoldenTest do
  @moduledoc """
  Raster goldens of the gallery (spec/12 §6, #474, #481): every stored design
  (`Visualize.Designs`) rasterised by `Visualize.Render.to_png/2` with the bundled DejaVu Sans
  and no system fonts, so the pictures are the same on every host, and compared with
  `test/support/raster/<name>.png` within a per-pixel tolerance. Regenerate only when a
  design's picture changes on purpose, or a resvg release moves pixels past the tolerance.
  They are rendered by resvg CLI 0.48.1, the release CI pins (spec/12 §4), and the tests that
  render are tagged `:resvg`:

      VISUALIZE_RESVG=/path/to/resvg MIX_ENV=test mix run -e 'Application.put_env(:visualize, :resvg, System.fetch_env!("VISUALIZE_RESVG")); ExUnit.start(autorun: false); Code.require_file("test/visualize/render/raster_golden_test.exs"); Visualize.Render.RasterGoldenTest.write!()'
  """
  use ExUnit.Case, async: true

  alias Visualize.{Chart, Designs, PNGPixels, Render}

  @dir "test/support/raster"

  @fonts [
    font_dirs: ["test/support/fonts"],
    system_fonts: false,
    generic_families: [sans_serif: "DejaVu Sans"]
  ]

  # A pixel matches when each channel is within this of the golden's; a design matches when
  # at most this fraction of its pixels do not (spec/12 §6).
  @channel_tolerance 8
  @pixel_fraction 0.001

  @doc "The design's PNG and its warnings, as the goldens are rendered."
  def render(name) do
    {:ok, png, warnings} =
      name
      |> Designs.apply()
      |> Chart.generate(root: true, resolve: :literal)
      |> Render.to_png([scale: 1, background: "#ffffff"] ++ @fonts)

    {png, warnings}
  end

  def write! do
    File.mkdir_p!(@dir)

    for name <- Designs.names() do
      {png, []} = render(name)
      File.write!(path(name), png)
    end

    :ok
  end

  defp path(name), do: Path.join(@dir, "#{name}.png")

  @tag :resvg
  test "every design rasterises without warnings with the bundled font" do
    for name <- Designs.names() do
      assert {_png, []} = render(name), "#{name}"
    end
  end

  @tag :resvg
  test "every design matches its golden within the per-pixel tolerance" do
    for name <- Designs.names() do
      {png, _warnings} = render(name)
      {w, h, pixels} = PNGPixels.decode(png)
      {gw, gh, golden} = PNGPixels.decode(File.read!(path(name)))
      assert {w, h} == {gw, gh}, "#{name}: #{w}×#{h}, golden #{gw}×#{gh}"

      differing = PNGPixels.differing(pixels, golden, @channel_tolerance)
      allowed = trunc(w * h * @pixel_fraction)
      assert differing <= allowed, "#{name}: #{differing} pixels differ (#{allowed} allowed)"
    end
  end

  test "there is one golden per design, and no other" do
    stored = @dir |> File.ls!() |> Enum.map(&Path.rootname(&1, ".png")) |> Enum.sort()
    assert stored == Designs.names() |> Enum.map(&to_string/1) |> Enum.sort()
  end

  # The gallery's pie (#485): slices separated by a 2-wide stroke in the background colour,
  # labelled in the background colour, bold, over them; `label` is the label style's
  # extra keys. Its picture is asserted against itself rather than stored: the stored set is
  # the metresis panel types, one golden per `Visualize.Designs` name.
  def pie(label) do
    rows =
      for {{name, value}, i} <-
            Enum.with_index([{"Chrome", 64.5}, {"Safari", 18.8}, {"Edge", 4.9}, {"Other", 6.4}]),
          do: %{name: name, value: value, index: i}

    design = %{
      version: 2,
      sources: %{slices: %{fields: [:name, :value, :index]}},
      styles: %{
        slice: %{fill: {:field, :index}, stroke: :background, stroke_width: 2},
        slice_label:
          Map.merge(
            %{extends: :label, fill: :background, font_size: 12, font_weight: :bold},
            label
          )
      },
      frames: %{
        main: %{
          kind: :polar,
          margin: %{top: 0, right: 0, bottom: 0, left: 0},
          scales: %{color: %{kind: :ordinal}}
        }
      },
      marks: [
        %{
          type: :arc,
          data: :slices,
          channels: %{value: :value},
          style: :slice,
          label: %{text: [{:field, :name}], anchor: :middle, style: :slice_label}
        }
      ]
    }

    {:ok, applied} = Chart.apply(Chart.from_map!(design), sources: %{slices: rows})

    {:ok, png, []} =
      applied
      |> Chart.generate(root: true, resolve: :literal)
      |> Render.to_png([scale: 1, background: "#ffffff"] ++ @fonts)

    png
  end

  @tag :resvg
  test "a pie's labels are not stroked by its slices: the picture is the one with no stroke on the labels (#485)" do
    {w, h, labelled} = PNGPixels.decode(pie(%{}))
    {^w, ^h, unstroked} = PNGPixels.decode(pie(%{stroke: :none}))
    assert PNGPixels.differing(labelled, unstroked, @channel_tolerance) == 0

    # A halo the label style asks for is drawn: the picture changes by more than the
    # tolerance allows, so the comparison above would see an inherited outline.
    {^w, ^h, halo} = PNGPixels.decode(pie(%{stroke: "#000000", stroke_width: 2}))
    assert PNGPixels.differing(labelled, halo, @channel_tolerance) > w * h * @pixel_fraction
  end

  @tag :resvg
  test "the tolerance catches a picture that changed" do
    {png, []} = render(:bar)
    {_w, _h, pixels} = PNGPixels.decode(png)
    {w, h, other} = PNGPixels.decode(elem(render(:stacked_bar), 0))
    assert PNGPixels.differing(pixels, other, @channel_tolerance) > w * h * @pixel_fraction
  end
end
