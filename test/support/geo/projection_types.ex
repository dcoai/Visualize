defmodule Visualize.Geo.ProjectionTypes do
  @moduledoc """
  Every projection type `Visualize.Geo.Projection.new/1` takes, for the tests that walk
  them all: the projection golden, the edge, rotation and clip tests (spec/12 §6). Test
  support, so each test file reads it compiled with the suite rather than from another
  test file, which loads in no promised order (#733).
  """

  @types ~w(mercator transverse_mercator equirectangular cylindrical_equal_area miller
            gall_peters orthographic stereographic gnomonic azimuthal_equal_area
            azimuthal_equidistant albers conic_conformal conic_equal_area conic_equidistant
            bonne polyconic mollweide sinusoidal eckert1 eckert2 eckert3 eckert4 eckert5
            eckert6 hammer kavrayskiy7 wagner4 wagner6 fahey collignon loximuthal
            natural_earth equal_earth robinson winkel_tripel aitoff van_der_grinten)a

  @doc "The projection types, in the golden's order."
  @spec all() :: [atom()]
  def all, do: @types
end
