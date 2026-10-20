defmodule Examples.Sources do
  @moduledoc """
  The data of `/sources` (spec/08 §6, #781, work item #834): data in the shapes a host holds
  it — an Nx tensor, an Explorer data frame, a feed asked for a window box — and the facts a
  quantity carries, as values the page (`ExamplesWeb.SourcesLive`) draws.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design
  alias Examples.Sources.Vehicles
  alias Explorer.DataFrame
  alias Visualize.{Chart, Feed, Quantity, Unit}

  # -- an Nx tensor -----------------------------------------------------------------------

  @doc """
  Two hundred samples of a 2-D normal, a `{200, 2}` tensor drawn with a fixed key, so the
  page is the same on every visit.
  """
  @spec samples() :: Nx.Tensor.t()
  def samples do
    {samples, _key} = Nx.Random.normal(Nx.Random.key(7), 0.0, 1.0, shape: {200, 2})
    samples
  end

  @doc """
  A random walk as a `{60, 2}` tensor, its step and the walk's sum to it, computed in Nx:
  the shape a line chart's tuple rows read.
  """
  @spec walk() :: Nx.Tensor.t()
  def walk do
    {steps, _key} = Nx.Random.normal(Nx.Random.key(11), 0.0, 1.0, shape: {60})
    Nx.stack([Nx.iota({60}), Nx.cumulative_sum(steps)], axis: 1)
  end

  # -- an Explorer data frame -------------------------------------------------------------

  @doc "Sales by region and quarter as an Explorer data frame: its columns named by strings."
  @spec sales() :: DataFrame.t()
  def sales do
    regions = ["North America", "Europe", "Asia Pacific", "Latin America", "Middle East"]
    base = [420, 360, 510, 180, 140]

    rows =
      for {region, b} <- Enum.zip(regions, base), q <- 1..4 do
        %{"region" => region, "quarter" => "Q#{q}", "revenue" => b * 1000 + q * 15_000}
      end

    DataFrame.new(rows)
  end

  @doc """
  Revenue by region, a bar each: the `:sum` step over the frame's rows, the `y` axis
  measured in US dollars, the region labels turned and centered on their tick.
  """
  @spec sales_design() :: map()
  def sales_design do
    Design.fold([
      chart(meta: %{name: "Revenue by region", description: ["The quarters summed per region"]}),
      source(:sales, [:region, :quarter, :revenue], types: %{revenue: :number}),
      style(:region, extends: :label, text_angle: -30, vertical_align: :middle),
      cartesian(margin: %{top: 12, right: 16, bottom: 70, left: 64}),
      band_scale(:x, padding: 0.25),
      linear_scale(:y, domain: [0, :auto], nice: true),
      axis(:x, :bottom, style: :region),
      axis(:y, :left, ticks: 4, grid: true, measure: %{unit: "{iso4217:USD}"}),
      rect(sum(from(:sales), :revenue, by: :region, as: :total), %{
        x0: :region,
        x1: :region,
        y0: 0,
        y1: :total
      })
    ])
  end

  @doc "`sales_design/0` over the frame, drawn as a document `<svg>`."
  @spec sales_svg() :: String.t()
  def sales_svg do
    {:ok, applied} = Chart.apply(sales_design(), sources: %{sales: sales()}, size: {440, 280})
    Chart.render(applied, root: true, id: "sources-sales")
  end

  @doc "Each region's total as the `:sum` step makes it, from the frame's rows."
  @spec totals() :: %{String.t() => number()}
  def totals do
    sales()
    |> DataFrame.to_rows()
    |> Enum.group_by(& &1["region"], & &1["revenue"])
    |> Map.new(fn {region, values} -> {region, Enum.sum(values)} end)
  end

  @doc "The frame's rows of one quarter, what the function components draw."
  @spec quarter(String.t()) :: DataFrame.t()
  def quarter(q), do: DataFrame.filter_with(sales(), &Explorer.Series.equal(&1["quarter"], q))

  # -- a density ----------------------------------------------------------------------------

  @size {360, 220}

  @doc """
  The density of the tensor's samples, rings filled by value, under two closed outlines:
  `:cardinal_closed` through six points, and `:basis_closed` within it.
  """
  @spec density_design() :: map()
  def density_design do
    Design.fold([
      chart(
        meta: %{name: "Density", description: ["The samples' density, and two closed curves"]}
      ),
      source(:points, [:px, :py], types: %{px: :number, py: :number}),
      source(:outline, [:x, :y, :curve], types: %{x: :number, y: :number}),
      style(:ring, fill: {:field, :value}, stroke: %{color: :background, width: 0.5}),
      style(:cardinal,
        stroke: %{color: :series_2, width: 2},
        fill: :none,
        curve: :cardinal_closed
      ),
      style(:basis,
        stroke: %{color: :series_3, width: 1.5, dash: [4, 3]},
        fill: :none,
        curve: :basis_closed
      ),
      cartesian(margin: %{top: 0, right: 0, bottom: 0, left: 0}),
      linear_scale(:x, domain: [0, elem(@size, 0)], range: [0, elem(@size, 0)]),
      linear_scale(:y, domain: [0, elem(@size, 1)], range: [0, elem(@size, 1)]),
      sequential_scale(:color, domain: [0, :auto]),
      path(density(from(:points), [:px, :py], bandwidth: 16, thresholds: 6), %{path: :path},
        style: :ring
      ),
      line(filter(from(:outline), :curve, test: :eq, value: "cardinal"), %{x: :x, y: :y},
        style: :cardinal
      ),
      line(filter(from(:outline), :curve, test: :eq, value: "basis"), %{x: :x, y: :y},
        style: :basis
      )
    ])
  end

  @doc "The samples placed in the plot's pixels, as the `:density` step reads them."
  @spec points() :: [map()]
  def points do
    {w, h} = @size

    for {a, b} <- Visualize.Data.Table.rows(samples()),
        do: %{px: w / 2 + 45 * a, py: h / 2 + 30 * b}
  end

  @doc "Six points around the samples, each closed curve drawn through them."
  @spec outline() :: [map()]
  def outline do
    {w, h} = @size

    for curve <- ["cardinal", "basis"], i <- 0..5 do
      a = i * :math.pi() / 3
      r = if curve == "cardinal", do: 1.0, else: 0.8
      %{x: w / 2 + r * 130 * :math.cos(a), y: h / 2 + r * 85 * :math.sin(a), curve: curve}
    end
  end

  @doc "`density_design/0` over the samples, drawn as a document `<svg>`."
  @spec density_svg() :: String.t()
  def density_svg do
    {:ok, applied} =
      Chart.apply(density_design(),
        sources: %{points: points(), outline: outline()},
        size: @size
      )

    Chart.render(applied, root: true, id: "sources-density")
  end

  # -- quantities ---------------------------------------------------------------------------

  @quantities [:temperature, :duration, :length, :ratio, :angle, :count, :information, :currency]

  @doc """
  The facts of each quantity (spec/05 §4): `{quantity, kind, bounds, as a gauge, as a
  counter}`, the last two `Quantity.additivity/2` — may values be summed across series,
  and over time.
  """
  @spec quantities() :: [{atom(), atom(), tuple(), map(), map()}]
  def quantities do
    for q <- @quantities do
      {q, Quantity.kind(q), Quantity.bounds(q), Quantity.additivity(q, :gauge),
       Quantity.additivity(q, :counter)}
    end
  end

  @doc "The `metric_kind` each of `/board`'s telemetry feeds declares in its schema."
  @spec metric_kinds() :: [{String.t(), atom() | nil}]
  def metric_kinds do
    for {name, feed} <- Visualize.Feed.Telemetry.feeds(Examples.BoardDemo.Telemetry),
        {_version, schema, _supports} = Feed.describe(feed),
        {field, attrs} <- schema.fields,
        Map.has_key?(attrs, :metric_kind),
        do: {"#{name}.#{field}", attrs.metric_kind}
  end

  @doc """
  Currency as a unit (D-155): the currency of a code, the minor units of three, and the
  answer to converting one currency into another.
  """
  @spec currency() :: map()
  def currency do
    %{
      code: Unit.currency("{iso4217:USD}"),
      per: Unit.currency("{iso4217:EUR}/kW/h"),
      minor: for(iso <- ~w(USD JPY BHD), do: {iso, Unit.minor_units(iso)}),
      convert: Unit.conversion("{iso4217:USD}", "{iso4217:EUR}"),
      ratio: Quantity.bounds(:ratio, "%")
    }
  end

  # -- a window box -------------------------------------------------------------------------

  @doc """
  The vehicles feed asked three ways, each finished by `Visualize.Feed.finish/3` since the
  feed supports only its time window: `[{label, box, rows}]` — the window, the window and
  an `x` region, and the latest row of each vehicle in that region.
  """
  @spec boxes(DateTime.t()) :: [{String.t(), map(), [map()]}]
  def boxes(now \\ DateTime.utc_now()) do
    feed = Vehicles.new(fn -> now end)
    {_version, schema, supports} = Feed.describe(feed)
    window = [DateTime.add(now, -300), now]

    for {label, box} <- [
          {"The window", %{ranges: %{t: window}}},
          {"A region of it", %{ranges: %{t: window, x: [0, 50]}}},
          {"The latest in the region", %{ranges: %{t: window, x: [0, 50]}, latest: true}}
        ] do
      {:ok, delivery} = Feed.fetch(feed, window, nil)
      finished = Feed.finish(delivery, schema, supports: supports, window: box)
      {label, box, finished.rows}
    end
  end

  @doc "The vehicles' rows as a small scatter, `x` across and `y` up, a color per vehicle."
  @spec box_svg([map()], String.t()) :: String.t()
  def box_svg(rows, id) do
    design =
      Design.fold([
        chart(meta: %{name: "Vehicles"}),
        source(:vehicles, [:t, :vehicle, :x, :y], types: %{t: :time, x: :number, y: :number}),
        cartesian(margin: %{top: 8, right: 8, bottom: 22, left: 28}),
        linear_scale(:x, domain: [0, 100]),
        linear_scale(:y, domain: [0, 100]),
        ordinal_scale(:color, domain: Vehicles.names()),
        axis(:x, :bottom, ticks: 4),
        axis(:y, :left, ticks: 4),
        rule(take(from(:vehicles), 1), %{x: 50}, style: [:annotation, :dashed]),
        circle(:vehicles, %{x: :x, y: :y},
          style: %{fill: {:field, :vehicle}},
          options: %{radius: 2.5}
        )
      ])

    {:ok, applied} = Chart.apply(design, sources: %{vehicles: rows}, size: {220, 180})
    Chart.render(applied, root: true, id: id)
  end
end
