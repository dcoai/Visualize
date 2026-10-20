defmodule ExamplesWeb.SourcesLive do
  @moduledoc """
  Data sources (spec/08 §6, §11, spec/05 §4, #781, work item #834): data in the shapes a
  host holds it, drawn as a host draws it. An Nx tensor through the function components
  of `Visualize.Components` written in this page's HEEx, and bound to a design's slot by
  its declared fields (D-214); an Explorer data frame bound to a design, its regions summed
  by the `:sum` step and its axis in dollars; the `:density` step and two closed curves;
  the facts a quantity carries; and a feed asked for a window box. Everything is drawn at
  mount: the page has no event of its own.
  """
  use Phoenix.LiveView

  import Visualize.Components

  alias Examples.Sources
  alias ExamplesWeb.Panel

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       samples: Sources.samples(),
       samples_svg: Sources.samples_svg(),
       walk: Sources.walk(),
       quarter: Sources.quarter("Q4"),
       sales_svg: Sources.sales_svg(),
       totals: Sources.totals(),
       density_svg: Sources.density_svg(),
       quantities: Sources.quantities(),
       metric_kinds: Sources.metric_kinds(),
       currency: Sources.currency(),
       boxes:
         for(
           {{label, box, rows}, i} <- Enum.with_index(Sources.boxes()),
           do: {label, box, length(rows), Sources.box_svg(rows, "sources-box-#{i}")}
         )
     )}
  end

  defp money(n), do: Visualize.Format.currency(n, code: "USD", locale: "en", precision: 0)

  @impl true
  def render(assigns) do
    ~H"""
    <ExamplesWeb.SiteHeader.header tab={:charts} />
    <main class="sources">
      <a href="/" class="back-link"><span>&larr;</span> Back to Charts</a>
      <h2>Data sources</h2>
      <p class="panel-note">
        A chart reads rows, and a host holds them as it likes: lists of maps, an Nx tensor, an
        Explorer data frame, a feed. <code>Visualize.Data.Table.rows/1</code>
        is the one door they all come through.
      </p>

      <div class="panels">
        <Panel.panel id="panel-tensor">
          <:title>An Nx tensor, through the function components</:title>
          <p class="panel-note">
            Two hundred normal samples, a <code>&#123;200, 2&#125;</code>
            tensor from <code>Nx.Random</code>, and a random walk summed in Nx, drawn by
            <code>Visualize.Components</code>
            written straight into this page's HEEx — no LiveComponent, no design. A rank-2
            tensor reads as one tuple per row, so the accessors take the tuple's elements:
          </p>
          <ExamplesWeb.Highlight.code lang="heex" code={tensor_code()} />
          <div class="sources-pair">
            <.scatter_plot
              data={@samples}
              x={&elem(&1, 0)}
              y={&elem(&1, 1)}
              width={320}
              height={240}
              size={3}
              title="Normal samples"
            />
            <.line_chart
              data={@walk}
              x={&elem(&1, 0)}
              y={&elem(&1, 1)}
              width={320}
              height={240}
              title="A random walk"
            />
          </div>
          <p class="panel-note">
            A design names its fields, and a tensor's tuples have none: bound to a design's
            slot, a tensor's columns take the slot's declared fields in order, so
            <code>source(:samples, [:x, :y])</code>
            reads column 0 as <code>x</code>
            and column 1 as <code>y</code>. The same samples,
            the tensor itself bound to a design's circles:
          </p>
          <div class="sources-svg">{Phoenix.HTML.raw(@samples_svg)}</div>
        </Panel.panel>

        <Panel.panel id="panel-frame">
          <:title>An Explorer data frame, bound to a design</:title>
          <p class="panel-note">
            Sales by region and quarter, an <code>Explorer.DataFrame</code>
            whose columns are named by strings, bound to a design's slot as a list of maps
            would be. The bars come from the <code>:sum</code>
            step — <code>sum(from(:sales), :revenue, by: :region, as: :total)</code>
            — the axis is measured in <code>&#123;iso4217:USD&#125;</code>, so its ticks are
            dollars, and the region labels are turned with <code>text_angle: -30</code>
            and <code>vertical_align: :middle</code>.
          </p>
          <div class="sources-svg">{Phoenix.HTML.raw(@sales_svg)}</div>
          <ul class="sources-totals">
            <li :for={{region, total} <- Enum.sort(@totals)}>{region}: {money(total)}</li>
          </ul>
          <p class="panel-note">The same frame's fourth quarter, through two function components:</p>
          <div class="sources-pair">
            <.bar_chart
              data={@quarter}
              x={& &1["region"]}
              y={& &1["revenue"]}
              width={360}
              height={220}
              title="Q4 by region"
            />
            <.pie_chart
              data={@quarter}
              value={& &1["revenue"]}
              label={& &1["region"]}
              width={260}
              height={220}
              inner_radius={50}
              title="Q4 shares"
            />
          </div>
        </Panel.panel>

        <Panel.panel id="panel-density">
          <:title>Density, and closed curves</:title>
          <p class="panel-note">
            The <code>:density</code>
            step over the tensor's samples, placed in the plot's pixels: rings at six
            thresholds, filled by value through a sequential color scale. Around them, one
            outline through six points as <code>:cardinal_closed</code>
            (solid) and one as <code>:basis_closed</code>
            (dashed), each closing on itself.
          </p>
          <div class="sources-svg">{Phoenix.HTML.raw(@density_svg)}</div>
        </Panel.panel>

        <Panel.panel id="panel-quantities">
          <:title>What a quantity says</:title>
          <p class="panel-note">
            A unit's quantity carries facts a chart and a host rely on: <code>Visualize.Quantity.kind/1</code>, where values physically lie
            (<code>bounds/1</code>, a hint for an axis, never a check), and whether values
            may be summed across series or over time (<code>additivity/2</code>), which a
            metric's kind refines.
          </p>
          <table class="sources-table">
            <tr>
              <th>quantity</th>
              <th>kind</th>
              <th>bounds</th>
              <th>a gauge sums</th>
              <th>a counter sums</th>
            </tr>
            <tr :for={{q, kind, bounds, gauge, counter} <- @quantities} data-quantity={q}>
              <td><code>{inspect(q)}</code></td>
              <td><code>{inspect(kind)}</code></td>
              <td><code>{inspect(bounds)}</code></td>
              <td>{sums(gauge)}</td>
              <td>{sums(counter)}</td>
            </tr>
          </table>
          <p class="panel-note">
            <code>bounds(:ratio, "%")</code>
            is <code>{inspect(@currency.ratio)}</code>. The
            board's telemetry feeds declare their metric kinds in their schemas:
            <span :for={{field, kind} <- @metric_kinds} class="sources-kind">
              <code>{field}</code> <code>{inspect(kind)}</code>
            </span>
          </p>
          <p class="panel-note">
            Currency is a unit: <code>Visualize.Unit.currency("&#123;iso4217:USD&#125;")</code>
            is <code>{inspect(@currency.code)}</code>, and of a price per kilowatt-hour <code>{inspect(@currency.per)}</code>. Minor units: <span :for={
              {iso, n} <- @currency.minor
            }><code>{iso}</code> {n} </span>.
            Two currencies never convert: <code>{inspect(@currency.convert)}</code>.
          </p>
        </Panel.panel>

        <Panel.panel id="panel-box">
          <:title>A feed asked for a window box</:title>
          <p class="panel-note">
            Six vehicles' positions over the last five minutes, a feed that serves only its
            time window. A request may be a <em>box</em>
            — a range of the window field and of
            any other — and may ask for each identity's latest row;
            <code>Visualize.Feed.finish/3</code>
            does what the feed does not support: trims the window, then the region <code>x</code>
            in 0–50, then keeps each vehicle's latest row.
          </p>
          <div class="sources-pair">
            <figure :for={{label, box, count, svg} <- @boxes} class="sources-box">
              {Phoenix.HTML.raw(svg)}
              <figcaption>
                <strong>{label}</strong>: {count} rows<br />
                <code>{box_text(box)}</code>
              </figcaption>
            </figure>
          </div>
        </Panel.panel>
      </div>
    </main>
    <style>
      .sources .sources-pair { display: flex; flex-wrap: wrap; gap: 1rem; align-items: flex-start; }
      .sources .sources-svg svg { max-width: 100%; height: auto; }
      .sources .sources-table { border-collapse: collapse; font-size: 0.8rem; }
      .sources .sources-table th, .sources .sources-table td { padding: 0.2rem 0.5rem; text-align: left; border-bottom: 1px solid #eee; }
      .sources .sources-kind { margin-right: 0.8rem; }
      .sources .sources-box { margin: 0; font-size: 0.8rem; }
      .sources .sources-totals { font-size: 0.85rem; columns: 2; }
    </style>
    """
  end

  defp tensor_code do
    ~S"""
    <.scatter_plot data={@samples} x={&elem(&1, 0)} y={&elem(&1, 1)} />
    <.line_chart data={@walk} x={&elem(&1, 0)} y={&elem(&1, 1)} />
    """
  end

  defp sums(%{across: across, over_time: over_time}),
    do:
      "#{if across, do: "across", else: "not across"}, #{if over_time, do: "over time", else: "not over time"}"

  defp box_text(%{ranges: ranges} = box) do
    ranges =
      ranges
      |> Enum.sort()
      |> Enum.map_join(", ", fn
        {:t, _range} -> "t: the last 5 min"
        {field, [from, to]} -> "#{field}: #{from}–#{to}"
      end)

    if box[:latest], do: "#{ranges}, latest", else: ranges
  end
end
