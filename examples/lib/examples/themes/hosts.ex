defmodule Examples.Themes.Hosts do
  @moduledoc """
  The host themes of `Examples.Themes` as data (spec/08 §7.2, #792): each one's page, its
  series and its hues, and the options `Visualize.Theme.new/1` builds it from.
  """

  import Visualize.Color, only: [color: 1]

  # A UI font stack, ending in the generic family: the gallery's text is set in the first
  # face the viewer has, where the library's default theme names only `sans-serif` (#486).
  @font_family "Inter, system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif"

  @doc "The gallery's font stack, which every theme of the picker carries."
  @spec font_family() :: String.t()
  def font_family, do: @font_family

  # A host theme's fields: its page, its series, and its hues. The status hues step down in
  # lightness from green to amber to red — about 55, 50 and 43 L* — so the status ramp's
  # lightness falls by more than 3 L* a step (spec/08 §7.5) and every role fill holds 3:1
  # on the tinted page (§7.7); the default's light-page green does neither there.
  @hosts [
    sunrise: %{
      name: "Sunrise",
      description: "Warm amber to deep oranges, on a cream page",
      series: ~w(#ffd098 #ffbc7a #ffa862 #fa944a #f58035 #f06d20 #e85a10 #d94500),
      page: [
        background: "#fff8f0",
        text: "#5c3d2e",
        axis: "#8b5a2b",
        grid: "#fadbb5",
        surface: "#fff0dc"
      ],
      hues: %{
        green: "#599236",
        amber: "#b1610f",
        red: "#b52f21",
        blue: "#386d9c",
        gray: "#7a6d64"
      },
      title: "#8b3a0f",
      grid: %{width: 1}
    },
    winter: %{
      name: "Winter",
      description: "Cool grays with blue undertones, the grid dashed",
      series: ~w(#4a6278 #5d7a94 #7192aa #88a8bc #a0bccb #b8ced9 #d0dfe6 #e8eff3),
      page: [
        background: "#f5f7f9",
        text: "#2c3e50",
        axis: "#4a6278",
        grid: "#d8e1e8",
        surface: "#ebf0f3"
      ],
      hues: %{
        green: "#449274",
        amber: "#967021",
        red: "#aa3a4d",
        blue: "#2a659b",
        gray: "#697683"
      },
      title: "#2a4a66",
      grid: %{width: 1, dash: [3, 3]}
    },
    sunset: %{
      name: "Sunset",
      description: "Purple to reds to deep orange, on a blush page",
      series: ~w(#341f97 #5f27cd #6c5ce7 #8854d0 #be2edd #e84393 #ff4757 #ff6b35),
      page: [
        background: "#fef5f0",
        text: "#4a1942",
        axis: "#6d3461",
        grid: "#f3d6e3",
        surface: "#faeaec"
      ],
      hues: %{
        green: "#449355",
        amber: "#b16118",
        red: "#bf2341",
        blue: "#4a52ae",
        gray: "#796b78"
      },
      title: "#5f27cd",
      grid: %{width: 1}
    },
    fall: %{
      name: "Fall",
      description: "Browns to orange and yellow, on a parchment page",
      series: ~w(#5d4037 #795548 #a1887f #d7a86e #e6a23c #f5b041 #f9c74f #fcf876),
      page: [
        background: "#fdf6e3",
        text: "#4a3728",
        axis: "#6d5039",
        grid: "#efe0c9",
        surface: "#f6ebd6"
      ],
      # A cream page is a hue of its own, too far round from the browns to make one hue
      # family with them, so the sequential ramp starts from a near-neutral light end.
      light_end: "#faf6f2",
      hues: %{
        green: "#658f34",
        amber: "#ab6517",
        red: "#aa3727",
        blue: "#386c8d",
        gray: "#796d61"
      },
      title: "#5d4037",
      grid: %{width: 1}
    },
    # Spring and Summer run apart (#797): Spring from a medium green to a dark yellow on a
    # warm page, Summer from a dark green to a medium blue on a cool one. Each series is two
    # sweeps of that run in OKLCH, the first four colors the whole run — so a chart of four
    # series reads green to yellow, or green to blue — and the next four the hues between,
    # at the other lightness. Every series color holds 3:1 on its page, which leaves a light
    # page's theme a narrow band of lightness; within it the lightness alternates, so any two
    # colors of a theme stay 0.06 or more apart in OKLab.
    spring: %{
      name: "Spring",
      description:
        "Medium green through yellow-greens to dark yellow, on a warm page, the grid dotted",
      series: ~w(#06a141 #608706 #716d04 #97730e #307505 #869606 #685702 #af880b),
      page: [
        background: "#fbfbec",
        text: "#34481f",
        axis: "#5a6b2e",
        grid: "#e6e8c8",
        surface: "#f3f4dc"
      ],
      hues: %{
        green: "#3f9545",
        amber: "#977000",
        red: "#bc304d",
        blue: "#2071a8",
        gray: "#74726a"
      },
      title: "#4a6a12",
      grid: %{width: 1, dash: [1, 3]}
    },
    summer: %{
      name: "Summer",
      description: "Dark green through teals to medium blue, on a cool page",
      series: ~w(#045e17 #118e7d #066278 #377ee3 #0b764d #025050 #028cbc #015e9d),
      page: [
        background: "#f0f6fa",
        text: "#0f3d3e",
        axis: "#2a5e66",
        grid: "#d2e3ea",
        surface: "#e3eff5"
      ],
      hues: %{
        green: "#2f9657",
        amber: "#9e6c0d",
        red: "#ba3730",
        blue: "#1370a0",
        gray: "#62727a"
      },
      title: "#045e17",
      grid: %{width: 1}
    }
  ]

  @doc "The host themes' keys, in the picker's order."
  @spec keys() :: [atom()]
  def keys, do: Keyword.keys(@hosts)

  @doc "A host theme's name and description, as the picker shows them."
  @spec info(atom()) :: {String.t(), String.t()}
  def info(key) do
    host = Keyword.fetch!(@hosts, key)
    {host.name, host.description}
  end

  @doc """
  The options `Visualize.Theme.new/1` builds the host theme `key` from: its name as a
  string, its series and page slots, its hues — `:info` and `:neutral` naming its blue and
  gray — its sequential ramp, its own `:title` and `:grid`, and the gallery's font stack.
  """
  @spec options(atom()) :: keyword()
  def options(key) do
    host = Keyword.fetch!(@hosts, key)

    [
      name: Atom.to_string(key),
      series: host.series,
      colors: Map.merge(host.hues, %{info: color(:blue), neutral: color(:gray)}),
      ramps: %{
        sequential: [Map.get(host, :light_end, host.page[:background]), hd(host.series)]
      },
      styles: %{
        title: %{
          fill: %{type: :solid, color: host.title},
          font: %{family: :font_family, size: :title_size, weight: :bold}
        },
        grid: %{stroke: Map.merge(%{type: :solid, color: color(:grid)}, host.grid)}
      },
      font_family: @font_family
    ] ++ host.page
  end
end
