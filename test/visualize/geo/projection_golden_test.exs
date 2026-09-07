defmodule Visualize.Geo.ProjectionGoldenTest do
  @moduledoc """
  Behaviour-preservation golden for every projection type.

  `test/support/projection_golden.txt` records `project/3` and, where the forward
  projection succeeds, `invert/3` over a fixed lon/lat grid. It was generated before
  the `Geo.Projection` split (#7) so the refactor is provably output-identical.
  Regenerate only when projection maths changes on purpose:

      mix run -e 'Visualize.Geo.ProjectionGoldenTest.write!()'
  """
  use ExUnit.Case, async: true

  alias Visualize.Geo.Projection

  @golden "test/support/projection_golden.txt"

  @types ~w(mercator transverse_mercator equirectangular cylindrical_equal_area miller
            gall_peters orthographic stereographic gnomonic azimuthal_equal_area
            azimuthal_equidistant albers conic_conformal conic_equal_area conic_equidistant
            bonne polyconic mollweide sinusoidal eckert1 eckert2 eckert3 eckert4 eckert5
            eckert6 hammer kavrayskiy7 wagner4 wagner6 fahey collignon loximuthal
            natural_earth equal_earth robinson winkel_tripel aitoff van_der_grinten)a

  @lons [-170, -120, -60, -15, 0, 15, 60, 120, 170]
  @lats [-80, -60, -30, -5, 0, 5, 30, 60, 80]

  def types, do: @types

  def render do
    for type <- @types, lon <- @lons, lat <- @lats do
      proj = Projection.new(type) |> Projection.scale(100) |> Projection.translate(0, 0)

      case Projection.project(proj, lon, lat) do
        nil ->
          "#{type} #{lon} #{lat} -> nil"

        {x, y} ->
          inv =
            case Projection.invert(proj, x, y) do
              nil -> "nil"
              {ilon, ilat} -> "#{fmt(ilon)} #{fmt(ilat)}"
            end

          "#{type} #{lon} #{lat} -> #{fmt(x)} #{fmt(y)} | #{inv}"
      end
    end
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  def write!, do: File.write!(@golden, render())

  # Nine decimals: far below the projections' own iteration tolerances, so a genuine
  # change in the maths shows and float noise from reordering an expression does not.
  # Adding 0.0 folds a negative zero into a positive one: the sign of zero depends on
  # whether the compiler could see the operand's type, so it is not a property of the maths.
  defp fmt(x) when is_float(x), do: :erlang.float_to_binary(x + 0.0, decimals: 9)
  defp fmt(x) when is_integer(x), do: fmt(x * 1.0)

  test "every projection type projects and inverts exactly as recorded" do
    assert File.read!(@golden) == render()
  end

  test "the golden covers every projection type" do
    recorded =
      @golden |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&hd(String.split(&1)))

    assert Enum.sort(Enum.uniq(recorded)) == Enum.sort(Enum.map(@types, &Atom.to_string/1))
  end
end
