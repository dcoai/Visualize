defmodule Visualize.Chart.InferredDomainTest do
  @moduledoc """
  #490, D-124: a `:text` mark's position channel that is a literal number, on a scale whose
  domain is inferred, holds that domain open at the number — inference reads a constant as
  data (spec/14 §4.3) — so the validator reports it as `{:feeds_domain, scale, n}`
  (§10.1). The check is scoped to `:text`: a rule or an area at a constant baseline is
  what an author means the domain to reach, and stays valid.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.Frame
  alias Visualize.Chart.Validator

  # A series over `t` 100..199 in one cartesian frame, `x` and `y` inferred, plus `marks`.
  defp design(marks, scales \\ %{}) do
    %{
      version: 2,
      sources: %{s: %{fields: [:t, :v]}},
      frames: %{
        main: %{
          kind: :cartesian,
          scales: Map.merge(%{x: %{kind: :linear}, y: %{kind: :linear}}, scales)
        }
      },
      marks: [%{type: :line, data: :s, channels: %{x: :t, y: :v}} | marks]
    }
  end

  defp text(channels, extra \\ %{}),
    do: Map.merge(%{type: :text, data: :s, channels: channels, label: %{text: ["n"]}}, extra)

  defp rows, do: for(t <- 100..199, do: %{t: t, v: rem(t, 7) + 10})

  # The domain the frame realises, the design taken as it is: a faulty one is built
  # unchecked, as a frame drew it before the validator saw it.
  defp x_domain(design) do
    frame = Frame.new(struct!(Chart, design), sources: %{s: rows()})
    frame.scales.x.domain
  end

  test "a text at a constant x on an inferred x domain is a fault, and it does widen the domain" do
    faulty = design([text(%{x: 0, y: 12})])

    assert {:error, [{[:marks, 1, :channels, :x], {:feeds_domain, :x, 0}}, y_fault]} =
             Validator.validate(faulty)

    # `y` is inferred too, and 12 is inside the data's own extent, but it is still a constant
    # read as data: the check is about what the design says, not what the rows happen to be.
    assert y_fault == {[:marks, 1, :channels, :y], {:feeds_domain, :y, 12}}

    # Why: the realised domain runs from the constant, not from the series.
    assert x_domain(faulty) == [0, 199]
  end

  test "{:scale, :min} and a field read the domain and feed nothing to it" do
    fixed = design([text(%{x: {:scale, :min}, y: :v})])
    assert :ok = Validator.validate(fixed)
    assert x_domain(fixed) == [100, 199]
  end

  test "an inferred end is enough: [:auto, hi] and [lo, :auto] are both reported" do
    for domain <- [[:auto, 500], [0, :auto]] do
      d = design([text(%{x: 300, y: :v})], %{x: %{kind: :linear, domain: domain}})

      assert {:error, [{[:marks, 1, :channels, :x], {:feeds_domain, :x, 300}}]} =
               Validator.validate(d)
    end
  end

  test "a fixed domain holds a text at a constant without a report" do
    d =
      design([text(%{x: 150, y: 12})], %{
        y: %{kind: :linear, domain: [0, 20]},
        x: %{kind: :linear, domain: [100, 199]}
      })

    assert :ok = Validator.validate(d)
  end

  test "a rule or an area at a constant baseline on an inferred domain stays valid" do
    rule = %{type: :rule, data: :s, channels: %{y: 0}}
    area = %{type: :area, data: :s, channels: %{x: :t, y: :v, y0: 0}}
    d = design([rule, area])

    assert :ok = Validator.validate(d)

    # The baseline is held in the domain, as the author means it to be.
    frame = Frame.new(Chart.from_map!(d), sources: %{s: rows()})
    assert hd(frame.scales.y.domain) == 0
  end

  test "a renamed scale is reported under the name the mark reads" do
    d =
      design(
        [text(%{x: :t, y: 5}, %{scales: %{y: :count}})],
        %{count: %{kind: :linear}}
      )

    assert {:error, [{[:marks, 1, :channels, :y], {:feeds_domain, :count, 5}}]} =
             Validator.validate(d)
  end

  test "an adopted scale is followed to the frame that owns it" do
    two = fn owner_domain ->
      %{
        version: 2,
        sources: %{s: %{fields: [:t, :v]}},
        layout: %{rows: [1, 1]},
        frames: %{
          a: %{
            kind: :cartesian,
            cell: [0, 0],
            scales: %{
              x: %{kind: :linear, domain: owner_domain},
              y: %{kind: :linear, domain: [0, 20]}
            }
          },
          b: %{
            kind: :cartesian,
            cell: [0, 1],
            scales: %{x: {:frame, :a, :x}, y: %{kind: :linear, domain: [0, 20]}}
          }
        },
        marks: [
          %{type: :line, frame: :a, data: :s, channels: %{x: :t, y: :v}},
          text(%{x: 0, y: 12}, %{frame: :b})
        ]
      }
    end

    assert {:error, [{[:marks, 1, :channels, :x], {:feeds_domain, :x, 0}}]} =
             Validator.validate(two.(:auto))

    assert :ok = Validator.validate(two.([0, 199]))
  end

  test "in a polar frame the positions are angle and r" do
    d = %{
      version: 2,
      sources: %{s: %{fields: [:t, :v]}},
      frames: %{
        main: %{
          kind: :polar,
          scales: %{angle: %{kind: :linear, domain: [0, 10]}, r: %{kind: :linear}}
        }
      },
      marks: [text(%{x: :t, y: 40})]
    }

    assert {:error, [{[:marks, 0, :channels, :y], {:feeds_domain, :r, 40}}]} =
             Validator.validate(d)
  end

  test "the line names the constant, the scale and the remedies" do
    assert Validator.format({[:marks, 1, :channels, :x], {:feeds_domain, :x, 0}}) ==
             "marks[1].channels.x: a text at the constant 0 holds scale :x's inferred domain " <>
               "open: place it at {:scale, :min} or {:scale, :max}, as a frame label, or declare the domain"
  end
end
