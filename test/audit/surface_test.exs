defmodule Visualize.Audit.SurfaceTest do
  @moduledoc """
  The drift assertion, inside `mix test` so a developer sees it before CI's
  `mix vis.surface --check` does.
  """
  use ExUnit.Case, async: true

  alias Visualize.Audit

  test "API_SURFACE.md is what spec/ and lib/ render to" do
    result = Audit.run(File.cwd!())
    assert File.read!("API_SURFACE.md") == Audit.render(result)
  end

  test "nothing is declared without a definition" do
    assert Audit.run(File.cwd!()).unimplemented == []
  end
end
