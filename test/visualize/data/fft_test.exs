defmodule Visualize.Data.FFTTest do
  @moduledoc """
  `Visualize.Data.FFT` (spec/08 §9, #375): the transform's properties — a tone peaks at its
  bin, a constant is DC alone, Parseval holds — and its cost, by count.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Data.FFT
  alias Visualize.Work

  doctest FFT

  describe "fft/1" do
    property "a pure sine of k cycles over N samples peaks at bin k, and Parseval holds" do
      check all(
              exponent <- integer(3..9),
              k <- integer(1..3),
              amplitude <- float(min: 0.5, max: 10.0),
              max_runs: 60
            ) do
        n = Integer.pow(2, exponent)
        k = min(k, div(n, 2) - 1)
        samples = for i <- 0..(n - 1), do: amplitude * :math.sin(2 * :math.pi() * k * i / n)
        terms = FFT.fft(samples)
        magnitudes = FFT.magnitudes(terms)

        assert length(terms) == n
        # The one-sided half: the mirror bin n − k carries the same magnitude.
        half = Enum.take(magnitudes, div(n, 2))
        assert Enum.max_by(Enum.with_index(half), &elem(&1, 0)) |> elem(1) == k

        energy = Enum.sum(Enum.map(samples, &(&1 * &1)))
        spectral = Enum.sum(Enum.map(magnitudes, &(&1 * &1))) / n
        assert_in_delta energy, spectral, 1.0e-9 * max(1.0, energy)
      end
    end

    test "a constant is DC alone; a length that is not a power of two raises" do
      [{dc, dc_im} | rest] = FFT.fft(List.duplicate(2, 8))
      assert dc == 16.0 and dc_im == 0.0
      assert Enum.all?(rest, fn {re, im} -> abs(re) < 1.0e-12 and abs(im) < 1.0e-12 end)

      assert_raise ArgumentError, ~r/power of two/, fn -> FFT.fft([1, 2, 3]) end
    end
  end

  describe "spectrum/3" do
    test "reads a tone's amplitude at its frequency under every window" do
      every = 1 / 256
      values = for i <- 0..511, do: 3 * :math.sin(2 * :math.pi() * 32 * i * every)

      for window <- FFT.windows() do
        lines = FFT.spectrum(values, every, window: window)
        assert length(lines) == 256
        peak = Enum.max_by(lines, & &1.magnitude)
        assert peak.frequency == 32.0
        assert_in_delta peak.magnitude, 3.0, 0.01
      end

      # An offset leaks from the DC line into its neighbors under a window; detrended, the
      # tone alone stands.
      offset = Enum.map(values, &(&1 + 40))
      leaked = FFT.spectrum(offset, every)
      assert Enum.at(leaked, 1).magnitude > 10
      flat = FFT.spectrum(offset, every, detrend: true)
      assert Enum.at(flat, 0).magnitude < 0.01 and Enum.at(flat, 1).magnitude < 0.01
      assert_in_delta Enum.max_by(flat, & &1.magnitude).magnitude, 3.0, 0.01

      # The newest power of two: 300 values take the last 256.
      assert FFT.spectrum(Enum.take(values, 300), every) |> length() == 128
      assert FFT.spectrum([1.0], every) == []
      assert_raise ArgumentError, ~r/samples/, fn -> FFT.spectrum(values, every, samples: 100) end
      assert_raise ArgumentError, ~r/window/, fn -> FFT.spectrum(values, every, window: :flat) end
    end

    # The cost's growth by count, not by clock (spec/08 §9.2, spec/12 §6, D-114): four
    # times the samples is 4 · 12/10 = 4.8 times the work of an n log n transform and
    # sixteen times a quadratic one's. It is 4.4.
    test "four times the samples is under six times the work" do
      values = fn n -> for i <- 0..(n - 1), do: :math.sin(i / 7) + rem(i * 7919, 101) / 100 end
      {small, _} = Work.reductions(fn -> FFT.spectrum(values.(1024), 0.01) end)
      {large, lines} = Work.reductions(fn -> FFT.spectrum(values.(4096), 0.01) end)

      assert length(lines) == 2048

      assert large < small * 6,
             "4096 points cost #{Float.round(large / small, 2)}x 1024's reductions"
    end

    # A live spectrum costs milliseconds (spec/08 §9.2): stated, not gated — run with
    # `mix test --only benchmark`.
    @tag :benchmark
    test "a 1024-point and a 4096-point spectrum, best of three" do
      for n <- [1024, 4096] do
        values = for i <- 0..(n - 1), do: :math.sin(i / 7) + :rand.uniform()
        us = Enum.min(for _ <- 1..3, do: elem(:timer.tc(fn -> FFT.spectrum(values, 0.01) end), 0))
        IO.puts("\n#{n}-point spectrum: #{Float.round(us / 1000, 2)} ms")
        assert us > 0
      end
    end
  end
end
