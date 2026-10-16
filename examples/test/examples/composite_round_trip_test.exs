defmodule Examples.CompositeRoundTripTest do
  @moduledoc """
  #713, D-187: every gallery design decomposed into the builder's sites flattens back to
  itself (spec/14 §18.12, spec/12 §6), so the builder holds each whole and every one is a
  template — Composition, with its design-level `defaults` and list-valued styles, among them.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.Templates
  alias Visualize.Chart.{Composite, Migration}

  for module <- Templates.gallery_modules() do
    @module module
    test "#{inspect(module)} round-trips through its sites" do
      {design, _sources} = @module.design([])
      canonical = Migration.canonical(design)
      {uses, _labels} = Composite.decompose(canonical)

      assert {:ok, flat, %{missing: [], keyless: []}} =
               Composite.flatten(%{composite: %{uses: uses}}, fn _id -> :error end)

      # `version` aside, which flatten writes (spec/14 §18.12).
      assert Map.delete(Migration.canonical(flat), :version) == Map.delete(canonical, :version)
    end
  end
end
