defmodule Visualize.RandomTest do
  @moduledoc """
  Boundary cases of spec/08 §4 (D-44): counts of zero produce nothing, not two.
  """
  use ExUnit.Case, async: true

  alias Visualize.Random

  test "binomial(0, p) is 0 and the extremes of p are exact" do
    assert Random.binomial(0, 0.5) == 0
    assert Random.binomial(20, 0) == 0
    assert Random.binomial(20, 1) == 20
    assert Random.binomial(7, 0.3) in 0..7
  end

  test "samples(fun, 0) is [] and samples(fun, n) has n elements" do
    assert Random.samples(fn -> 1 end, 0) == []
    assert Random.samples(fn -> 1 end, 3) == [1, 1, 1]
  end
end
