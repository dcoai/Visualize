defmodule Examples.Tenants do
  @moduledoc """
  The tenant chat of `/tenants` (spec/14 §3.13, spec/15 §10, #654, D-177): a team chat whose
  messages come from two tenants, run as a board.

  Every viewer sees each message in its **sender's** tenant style. A design cannot hold
  that style — it is the tenants' data, and it is known only when the chart is drawn — so
  the design stores a call, `generate(:tenant_style, [{:field, :tenant}])`, and the host's
  generators (`Examples.Tenants.Generators`, registered in the examples' configuration)
  answer it per message. The viewer is the board's `assigns:`, and `tenant_style` gives the
  viewer's own tenant's messages a heavier outline. The *Messages* cell paints a bar per
  tenant with `generate(:brand_color, [{:field, :tenant}])`.

  A board is started per visitor, linked to the page, as the detail board is.
  """

  import Visualize.Color, only: [color: 1, intensity: 2]
  import Visualize.Generators, only: [generate: 2]

  alias Examples.BoardDemo.Fixed
  alias Visualize.Board
  alias Visualize.Board.{Binding, Server}

  # The host's data: each tenant's name, brand color and message style.
  @tenants %{
    "acme" => %{name: "Acme", brand: :royalblue, dash: nil},
    "globex" => %{name: "Globex", brand: :darkorange, dash: [5, 3]}
  }

  @messages [
    {"Ana", "acme", "Morning! Is the deploy still on for ten?"},
    {"Ben", "globex", "Yes, our side is ready."},
    {"Ana", "acme", "Great, I'll watch the error rate."},
    {"Chen", "globex", "Ping me if the queue backs up."},
    {"Dee", "acme", "Queue is flat. Looks good from here."},
    {"Ben", "globex", "Rolling out to the second region now."},
    {"Ana", "acme", "Thanks, both!"}
  ]

  @doc "The tenants by id."
  @spec tenants() :: %{String.t() => map()}
  def tenants, do: @tenants

  @doc """
  A tenant's message style for a viewer (the host's own function, which the generator
  calls): a pale fill of the brand, an outline in it — dashed for Globex — and a heavier
  outline when the viewer is of the same tenant.
  """
  @spec style(String.t(), String.t() | nil) :: map()
  def style(tenant, viewer) do
    %{brand: brand, dash: dash} = Map.fetch!(@tenants, tenant)
    stroke = %{color: color(brand), width: if(tenant == viewer, do: 2.5, else: 1)}

    %{
      fill: color(brand) |> intensity(0.15),
      stroke: if(dash, do: Map.put(stroke, :dash, dash), else: stroke)
    }
  end

  @doc "A tenant's brand color, a typed color."
  @spec brand(String.t()) :: tuple()
  def brand(tenant), do: color(Map.fetch!(@tenants, tenant).brand)

  @doc "The transcript's rows: each message, its sender's tenant, and the bubble's side."
  @spec messages() :: [map()]
  def messages do
    for {{sender, tenant, text}, i} <- Enum.with_index(@messages, 1) do
      {x0, x1} = if tenant == "acme", do: {0, 0.78}, else: {0.22, 1}
      %{id: "m#{i}", sender: sender, tenant: tenant, text: text, x0: x0, x1: x1}
    end
  end

  @doc "The messages per tenant."
  @spec counts() :: [map()]
  def counts do
    messages()
    |> Enum.frequencies_by(& &1.tenant)
    |> Enum.sort()
    |> Enum.map(fn {tenant, n} -> %{tenant: tenant, name: @tenants[tenant].name, messages: n} end)
  end

  @doc "The transcript design: a bubble per message, styled by its sender's tenant."
  @spec transcript() :: map()
  def transcript do
    %{
      version: 3,
      meta: %{name: "Transcript", description: "Each message in its sender's tenant style"},
      sources: %{messages: %{fields: [:id, :sender, :tenant, :text, :x0, :x1]}},
      styles: %{message: %{opacity: 1}},
      frames: %{
        main: %{
          kind: :cartesian,
          margin: %{top: 8, right: 8, bottom: 8, left: 8},
          scales: %{x: %{kind: :linear, domain: [0, 1]}, y: %{kind: :band, padding: 0.2}}
        }
      },
      marks: [
        %{
          type: :rect,
          data: :messages,
          channels: %{x0: :x0, x1: :x1, y0: :id, y1: :id},
          # The sender's tenant style over the message's own (spec/14 §3.6, §3.13).
          style: [:message, generate(:tenant_style, [{:field, :tenant}])],
          label: %{
            text: "\#{field(:sender)}: \#{field(:text)}",
            anchor: :middle,
            fit: :truncate
          }
        }
      ]
    }
  end

  @doc "The messages-per-tenant design: a bar per tenant in its brand color."
  @spec per_tenant() :: map()
  def per_tenant do
    %{
      version: 3,
      meta: %{name: "Messages", description: "Messages per tenant, in each tenant's brand"},
      sources: %{counts: %{fields: [:tenant, :name, :messages]}},
      frames: %{
        main: %{
          kind: :cartesian,
          margin: %{top: 10, right: 10, bottom: 30, left: 30},
          scales: %{x: %{kind: :band, padding: 0.3}, y: %{kind: :linear, domain: [0, 5]}},
          axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left, ticks: 5}]
        }
      },
      marks: [
        %{
          type: :rect,
          data: :counts,
          channels: %{x0: :name, x1: :name, y0: 0, y1: :messages},
          style: %{fill: generate(:brand_color, [{:field, :tenant}])}
        }
      ]
    }
  end

  @doc """
  A cell's design applied as the board applies it for `viewer` — its rows, the examples'
  generators (from the configuration) and the viewer in `assigns:` — so the page's
  *Why it looks as it does* panel explains each element with the generator calls that drew
  it (spec/14 §3.13, §17.3). `cell` is `"transcript"` or `"counts"`.
  """
  @spec applied(String.t(), String.t()) :: Visualize.Chart.Applied.t()
  def applied("transcript", viewer),
    do: apply_cell(transcript(), %{messages: Enum.reverse(messages())}, viewer)

  def applied("counts", viewer), do: apply_cell(per_tenant(), %{counts: counts()}, viewer)

  defp apply_cell(design, sources, viewer) do
    {:ok, applied} =
      Visualize.Chart.apply(design,
        sources: sources,
        assigns: %{viewer: viewer},
        size: {640, 300}
      )

    applied
  end

  @doc "The board as a value (spec/15 §1)."

  @spec value() :: Board.t()
  def value do
    Board.from_map!(%{
      meta: %{name: "Tenant chat", description: "Two tenants, one conversation"},
      cells: %{
        transcript: %{x: 0, y: 0, w: 8, h: 5, ref: {:composite, 1}, title: "Transcript"},
        counts: %{x: 8, y: 0, w: 4, h: 5, ref: {:composite, 2}, title: "Messages"}
      }
    })
  end

  @doc "The board's components by id."
  @spec store() :: %{{:composite, pos_integer()} => map()}
  def store, do: %{{:composite, 1} => transcript(), {:composite, 2} => per_tenant()}

  @doc """
  A tenant chat board for one viewer, started linked to the caller — the page that shows it
  — with the viewer's tenant in its `assigns:`.
  """
  @spec start(String.t()) :: {:ok, pid()} | {:error, term()}
  def start(viewer) when is_map_key(@tenants, viewer) do
    Server.start_link(
      board: value(),
      store: store(),
      binding:
        Binding.new(%{{:transcript, :messages} => :messages, {:counts, :counts} => :counts}),
      feeds: %{
        # Newest first: a band scale lays its first category at the bottom, so the
        # conversation reads down the cell, the newest message last.
        messages:
          Fixed.new(Enum.reverse(messages()), %{
            id: %{type: :category},
            sender: %{type: :category},
            tenant: %{type: :category},
            text: %{type: :category},
            x0: %{type: :number},
            x1: %{type: :number}
          }),
        counts:
          Fixed.new(counts(), %{
            tenant: %{type: :category},
            name: %{type: :category},
            messages: %{type: :number}
          })
      },
      assigns: %{viewer: viewer},
      tick: 5000
    )
  end
end

defmodule Examples.Tenants.Generators do
  @moduledoc """
  The examples' generators (spec/14 §3.13): ordinary Elixir over the host's tenant data,
  registered in the examples' configuration (`config :visualize, generators: [...]`).
  """
  use Visualize.Generators

  defgenerator tenant_style(tenant, ctx) do
    Examples.Tenants.style(tenant, ctx.assigns[:viewer])
  end

  defgenerator(brand_color(tenant, _ctx), do: Examples.Tenants.brand(tenant))
end
