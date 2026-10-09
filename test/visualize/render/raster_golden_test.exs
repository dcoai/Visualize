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

  @tag :resvg
  test "the tolerance catches a picture that changed" do
    {png, []} = render(:bar)
    {_w, _h, pixels} = PNGPixels.decode(png)
    {w, h, other} = PNGPixels.decode(elem(render(:stacked_bar), 0))
    assert PNGPixels.differing(pixels, other, @channel_tolerance) > w * h * @pixel_fraction
  end
end
