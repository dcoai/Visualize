defmodule Visualize.Board.Export do
  @moduledoc """
  A whole board as one picture: an SVG document, a PNG, or printed pages (spec/15 §12,
  D-150).

  Everything here draws a `Visualize.Board.Snapshot` — taken from a running board with
  `Visualize.Board.Server.snapshot/1`, or purely with `Visualize.Board.Snapshot.realize/4`
  — so an export needs no store, no feed and no process, and shows exactly the data the
  snapshot froze.

  - **`svg/2`** is the board at a width: a header with the board's name and its window in
    the board's zone (`Visualize.Board.window_text/2`), and each cell at its grid box
    (`Visualize.Board.boxes/2`) — its title, its state's banner over a chart that is not
    live, and its chart's own SVG **embedded byte for byte** as the cell draws it
    (`Visualize.Board.Snapshot.views/2`). A cell with no chart — loading, down, crashed —
    is its state's panel, the one the board component draws.
  - **`png/2`** is that document rasterised by `Visualize.Render.to_png/2`, with every
    theme reference resolved to the literal it carries (`literal/1`), since resvg reads no
    CSS custom property.
  - **`pages/2`** lays the board out on paper — A4 or Letter, portrait or landscape — in
    `Visualize.Theme.print/0` by default: the board reflowed to the page's width as a
    narrow container reflows it (spec/15 §1.6), its cells in bands that never split across
    a page (`paginate/2`), one SVG document per page. `html/2` puts the pages in one HTML
    document whose `@page` rule is the paper size, which a browser prints as one
    multi-page PDF. resvg makes PNG, not PDF, and this library takes no PDF dependency.

  The cells' charts carry ids derived from their content (a gradient's, a filter's, the
  accessible root's), so two cells that draw the same definition share its id with the
  same body, and embedding one cell beside another changes neither.
  """

  alias Visualize.Board
  alias Visualize.Board.{Snapshot, State, View}
  alias Visualize.IR.Element
  alias Visualize.{Render, Theme}

  # Paper, in CSS pixels at 96 to the inch, with the length a page's root states.
  @papers %{
    a4: {210 / 25.4 * 96, 297 / 25.4 * 96, "210mm", "297mm"},
    letter: {8.5 * 96, 11 * 96, "8.5in", "11in"}
  }

  # What a cell is drawn with beside the snapshot's data: the reader's unit system, and the
  # board's generators and assigns (spec/15 §12.2, D-156, D-181).
  @drawing [:system, :generators, :assigns]

  @typedoc "A box on the document or the page: `{x, y, w, h}` in pixels."
  @type box :: {number(), number(), number(), number()}

  # -- one document ---------------------------------------------------------------------------

  @doc """
  The board as one SVG document (spec/15 §12.1).

  The document is the grid's width and twice the board's gap wider, a gap of margin each
  side; the header, when there is a name or a window, stands above the grid. Each cell is
  a group `data-vis-cell` at its box, translated by the margin and the header, holding its
  title, its banner, and its chart or its state's panel, each in its own viewport so the
  cell's own SVG is placed unchanged.

  ## Options

    * `:width` - the grid's width, the container width the cells are drawn at (default
      the snapshot's)
    * `:theme` - the theme the cells and the page are drawn in (default the snapshot's)
    * `:system` - the unit system the cells' measures are shown in (default `:as_posted`,
      spec/14 §4.4, D-156)
    * `:generators`, `:assigns` - the generator modules the cells' frames call and the
      host's assigns, as `Visualize.Board.Snapshot.views/2` takes them (default none and
      `%{}`): the board's own, so the export draws what the board draws for its viewer
      (D-181). `Visualize.Board.Server.export/3` passes a running board's
    * `:title` - the header's name (default the board's `meta.name`)
    * `:resolve` - `:css` (default), every theme value a custom-property reference with
      its literal as fallback, as the cells draw it; or `:literal`, each reference
      replaced by its literal, for a reader of no CSS (`literal/1`)
  """
  @spec svg(Snapshot.t(), keyword()) :: String.t()
  def svg(%Snapshot{} = snapshot, opts \\ []) do
    width = Keyword.get(opts, :width, snapshot.width)
    theme = Keyword.get(opts, :theme, snapshot.theme)

    views = Snapshot.views(snapshot, [width: width, theme: theme] ++ Keyword.take(opts, @drawing))

    %{gap: margin} = Board.layout(snapshot.board)
    lines = header_lines(snapshot, Keyword.get(opts, :title), nil)
    header = header_height(theme, lines, margin)

    placed =
      for {name, {x, y, w, h}} <- Board.boxes(snapshot.board, width),
          do: {name, {x + margin, y + margin + header, w, h}}

    bottom =
      Enum.reduce(placed, margin + header, fn {_n, {_x, y, _w, h}}, acc -> max(acc, y + h) end)

    document(
      {width + 2 * margin, bottom + margin},
      nil,
      theme,
      lines,
      margin,
      placed,
      views
    )
    |> resolved(Keyword.get(opts, :resolve, :css))
  end

  @doc """
  The board as a PNG (spec/15 §12.1): `svg/2` with `resolve: :literal`, rasterised by
  `Visualize.Render.to_png/2`. `{:ok, png, warnings}` or `{:error, reason}`, as `to_png/2`
  answers. The options are `svg/2`'s, `:generators` and `:assigns` among them, and
  `to_png/2`'s `:scale`, `:background`,
  `:timeout` and font options.
  """
  @spec png(Snapshot.t(), keyword()) ::
          {:ok, binary(), [Render.png_warning()]} | {:error, Render.png_error()}
  def png(%Snapshot{} = snapshot, opts \\ []) do
    {ours, raster} = Keyword.split(opts, [:width, :theme, :title | @drawing])
    snapshot |> svg([resolve: :literal] ++ ours) |> Render.to_png(raster)
  end

  # -- paper ------------------------------------------------------------------------------------

  @doc """
  The board laid out on paper (spec/15 §12.4), purely: `%{size: {w, h}, width: width,
  pages: [%{name => box}, …]}`, the page's size in pixels, the width the cells are drawn
  at, and each page's cells at their boxes on that page.

  The board is arranged at the page's width less its margins, so a page narrower than the
  board's breakpoint stacks the cells as a phone does (spec/15 §1.6). Cells are taken in
  **bands**: a band is the cells whose rows overlap, joined until no cell of the band
  shares a row with one outside it, so a band is the least that can be moved without
  cutting a cell. Bands are placed down the page, a gap apart, and a band that does not
  fit below the last starts the next page. A band taller than a whole page is scaled down
  to fit one, its width with it, and centred. No cell is ever split, and every box is
  inside the page's margins, below the header.

  ## Options

    * `:paper` - `:a4` (default) or `:letter`
    * `:orientation` - `:portrait` (default) or `:landscape`
    * `:margin` - the page's margin in pixels (default `48`, half an inch)
    * `:theme` - the theme whose sizes set the header's height (default
      `Visualize.Theme.print/0`)
  """
  @spec paginate(Board.t(), keyword()) :: %{
          size: {number(), number()},
          width: number(),
          pages: [%{atom() => box()}]
        }
  def paginate(%Board{} = board, opts \\ []) do
    {pw, ph, _, _} = paper(opts)
    margin = Keyword.get(opts, :margin, 48)
    theme = Keyword.get_lazy(opts, :theme, &Theme.print/0)
    %{gap: gap} = Board.layout(board)
    top = margin + header_height(theme, 2, gap)
    width = pw - 2 * margin
    room = ph - top - margin

    {pages, current, _cursor} =
      board
      |> Board.boxes(width)
      |> bands()
      |> Enum.reduce({[], %{}, 0}, fn {band_top, band_bottom, boxes}, {pages, current, cursor} ->
        height = band_bottom - band_top
        scale = min(1, room / height)
        drawn = height * scale

        {pages, current, cursor} =
          if current != %{} and cursor + drawn > room,
            do: {[current | pages], %{}, 0},
            else: {pages, current, cursor}

        shift = margin + (width - width * scale) / 2

        current =
          Enum.reduce(boxes, current, fn {name, {x, y, w, h}}, acc ->
            Map.put(
              acc,
              name,
              {shift + x * scale, top + cursor + (y - band_top) * scale, w * scale, h * scale}
            )
          end)

        {pages, current, cursor + drawn + gap}
      end)

    pages = Enum.reverse(if current == %{}, do: pages, else: [current | pages])
    %{size: {pw, ph}, width: width, pages: if(pages == [], do: [%{}], else: pages)}
  end

  # The cells in bands of overlapping rows, top to bottom: `{top, bottom, boxes}`.
  defp bands(boxes) do
    boxes
    |> Enum.sort_by(fn {name, {x, y, _w, _h}} -> {y, x, name} end)
    |> Enum.reduce([], fn {_name, {_x, y, _w, h}} = cell, bands ->
      case bands do
        [{top, bottom, cells} | rest] when y < bottom ->
          [{top, max(bottom, y + h), [cell | cells]} | rest]

        bands ->
          [{y, y + h, [cell]} | bands]
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  The board printed (spec/15 §12.4): one SVG document per page of `paginate/2`, each the
  page's size in its own unit (`210mm` by `297mm` for A4 portrait), with the header — the
  board's name, and its window and the page's number — and the page's cells drawn as
  `svg/2` draws them, a band scaled down where `paginate/2` scaled it. The cells are
  drawn at the page's width in `:theme`, the print theme by default, from the snapshot's
  data.

  The options are `paginate/2`'s, `svg/2`'s `:system`, `:generators`, `:assigns`, `:title`
  and `:resolve`.
  """
  @spec pages(Snapshot.t(), keyword()) :: [String.t()]
  def pages(%Snapshot{} = snapshot, opts \\ []) do
    theme = Keyword.get_lazy(opts, :theme, &Theme.print/0)
    opts = Keyword.put(opts, :theme, theme)
    {_pw, _ph, wl, hl} = paper(opts)
    %{size: size, width: width, pages: pages} = paginate(snapshot.board, opts)

    views = Snapshot.views(snapshot, [width: width, theme: theme] ++ Keyword.take(opts, @drawing))

    margin = Keyword.get(opts, :margin, 48)
    count = length(pages)

    pages
    |> Enum.with_index(1)
    |> Enum.map(fn {boxes, n} ->
      title = Keyword.get(opts, :title) || get_in(snapshot.board.meta, [:name]) || "Board"
      lines = header_lines(snapshot, title, "page #{n} of #{count}")
      placed = Enum.sort_by(boxes, fn {name, {x, y, _w, _h}} -> {y, x, name} end)

      size
      |> document({wl, hl}, theme, lines, margin, placed, views)
      |> resolved(Keyword.get(opts, :resolve, :css))
    end)
  end

  @doc """
  The printed pages in one HTML document (spec/15 §12.4): an `@page` rule of the paper's
  size and no margin, and each page of `pages/2` filling one sheet. A browser prints it as
  a multi-page PDF. The options are `pages/2`'s.
  """
  @spec html(Snapshot.t(), keyword()) :: String.t()
  def html(%Snapshot{} = snapshot, opts \\ []) do
    {_pw, _ph, wl, hl} = paper(opts)
    title = escape(Keyword.get(opts, :title) || get_in(snapshot.board.meta, [:name]) || "Board")

    sheets =
      Enum.map(pages(snapshot, opts), fn page ->
        [~s(<section class="vis-page">), page, "</section>\n"]
      end)

    IO.iodata_to_binary([
      "<!doctype html>\n<html><head><meta charset=\"utf-8\"><title>",
      title,
      "</title>\n<style>\n@page { size: #{wl} #{hl}; margin: 0; }\n",
      "body { margin: 0; }\n",
      ".vis-page { width: #{wl}; height: #{hl}; break-after: page; overflow: hidden; }\n",
      ".vis-page > svg { display: block; width: 100%; height: 100%; }\n",
      "</style></head><body>\n",
      sheets,
      "</body></html>\n"
    ])
  end

  defp paper(opts) do
    {w, h, wl, hl} =
      case Map.fetch(@papers, Keyword.get(opts, :paper, :a4)) do
        {:ok, paper} ->
          paper

        :error ->
          raise ArgumentError, ":paper is :a4 or :letter, got: #{inspect(opts[:paper])}"
      end

    case Keyword.get(opts, :orientation, :portrait) do
      :portrait ->
        {clean(w), clean(h), wl, hl}

      :landscape ->
        {clean(h), clean(w), hl, wl}

      other ->
        raise ArgumentError, ":orientation is :portrait or :landscape, got: #{inspect(other)}"
    end
  end

  # -- literal colours ----------------------------------------------------------------------------

  @doc """
  An SVG with every CSS custom-property reference replaced by the fallback it carries
  (spec/15 §12.1): `var(--vis-axis, #666666)` becomes `#666666`. A theme writes each
  slot's literal as the fallback of its reference (spec/08 §7.3), so this is the document
  in `:literal` mode, for a reader that knows no custom property — resvg among them. A
  reference with no fallback is left as it is.

      iex> Visualize.Board.Export.literal(~s[<rect fill="var(--vis-good, rgb(1, 2, 3))"/>])
      ~s[<rect fill="rgb(1, 2, 3)"/>]
  """
  @spec literal(String.t()) :: String.t()
  def literal(svg) when is_binary(svg) do
    case :binary.split(svg, "var(--") do
      [whole] -> whole
      [before, rest] -> before <> reference(rest)
    end
  end

  defp resolved(svg, :css), do: svg
  defp resolved(svg, :literal), do: literal(svg)

  defp resolved(_svg, other),
    do: raise(ArgumentError, ":resolve is :css or :literal, got: #{inspect(other)}")

  # The text after a `var(--`: its name to the first comma, the fallback to the bracket that
  # closes the reference, which may itself hold brackets (`rgb(…)`) or references.
  defp reference(rest) do
    with [name, after_name] <- :binary.split(rest, ","),
         false <- String.contains?(name, ")"),
         {fallback, tail} when is_binary(tail) <- closing(after_name, 0, []) do
      literal(String.trim(fallback)) <> literal(tail)
    else
      _no_fallback -> "var(--" <> literal(rest)
    end
  end

  defp closing(<<")", tail::binary>>, 0, acc),
    do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), tail}

  defp closing(<<")", tail::binary>>, depth, acc), do: closing(tail, depth - 1, [")" | acc])
  defp closing(<<"(", tail::binary>>, depth, acc), do: closing(tail, depth + 1, ["(" | acc])

  defp closing(<<c::utf8, tail::binary>>, depth, acc),
    do: closing(tail, depth, [<<c::utf8>> | acc])

  defp closing(<<>>, _depth, _acc), do: :unclosed

  # -- drawing --------------------------------------------------------------------------------

  # The header's lines: the name, then the window in the board's zone with an extra word
  # (a page's number) after it; a line with nothing to say is left out.
  defp header_lines(snapshot, title, extra) do
    name = title || get_in(snapshot.board.meta, [:name])
    window = Board.window_text(snapshot.window, snapshot.board.zone)
    second = [window, extra] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")

    Enum.reject([{:title, name}, {:window, second}], fn {_kind, text} -> text in [nil, ""] end)
  end

  defp header_height(_theme, [], _pad), do: 0

  defp header_height(theme, lines, pad) when is_list(lines),
    do: header_height(theme, length(lines), pad)

  defp header_height(theme, n, pad) when is_integer(n) do
    lines = [theme.title_size, theme.label_size] |> Enum.take(n) |> Enum.map(&(&1 * 1.25))
    pad + Enum.sum(lines)
  end

  defp document(size, units, theme, lines, margin, placed, views) do
    {w, h} = {clean(elem(size, 0)), clean(elem(size, 1))}

    {width, height, view_box} =
      case units do
        nil -> {w, h, "0 0 #{w} #{h}"}
        {wl, hl} -> {wl, hl, "0 0 #{w} #{h}"}
      end

    title = Enum.find_value(lines, "Board", fn {kind, text} -> kind == :title && text end)
    description = Enum.find_value(lines, fn {kind, text} -> kind == :window && text end)

    root =
      Element.root(width, height,
        view_box: view_box,
        title: title,
        description: description,
        children: [
          Element.rect(0, 0, w, h, %{
            class: "vis-board-ground",
            fill: Theme.resolve(theme, :background, :css)
          })
          | header(theme, lines, margin)
        ]
      )
      |> Element.set_attrs(%{class: "vis-board-export"})
      |> Render.to_string()

    cells = for {name, box} <- placed, do: cell(Map.fetch!(views, name), box, theme)

    # The cells' own SVG is placed as it is, so the document's root is closed after them.
    body = binary_part(root, 0, byte_size(root) - byte_size("</svg>"))
    IO.iodata_to_binary([body, cells, "</svg>"])
  end

  # The header's lines from the margin's corner down, each `1.25` of its size high.
  defp header(_theme, [], _margin), do: []

  defp header(theme, lines, margin) do
    {texts, _y} =
      Enum.map_reduce(lines, margin, fn {kind, text}, y ->
        size = if kind == :title, do: theme.title_size, else: theme.label_size
        baseline = y + size

        element =
          Element.text(text, margin, baseline, %{
            class: "vis-board-#{kind}",
            fill: Theme.resolve(theme, :text, :css),
            font_family: Theme.resolve(theme, :font_family, :css),
            font_size:
              Theme.resolve(theme, if(kind == :title, do: :title_size, else: :label_size), :css),
            font_weight: if(kind == :title, do: "bold")
          })

        {element, y + size * 1.25}
      end)

    [Element.group(texts, style: %{class: "vis-board-header"})]
  end

  # One cell at its box: drawn at its view's own size and scaled to the box, so a cell on
  # a page that `paginate/2` scaled keeps its proportions. Inside, the title's strip, then
  # the banner over a chart, then the chart — or, with no chart, the state's panel — each
  # in a viewport of its own drawing's size.
  defp cell(%View{size: {vw, vh}} = view, {x, y, w, _h}, theme) do
    scale = w / vw
    strip = if view.title, do: theme.label_size * 1.5, else: 0
    banner = if view.svg && view.note, do: State.banner_height(), else: 0

    transform =
      if scale == 1,
        do: "translate(#{num(x)},#{num(y)})",
        else: "translate(#{num(x)},#{num(y)}) scale(#{num(scale)})"

    [
      ~s(<g class="vis-board-cell" data-vis-cell="#{escape(Atom.to_string(view.cell))}" ),
      ~s(data-vis-state="#{State.name(view.state)}" transform="#{transform}">),
      title(view.title, theme),
      if(banner > 0,
        do: viewport(view.note, {0, strip, vw, banner}, {vw, banner}, "none"),
        else: []
      ),
      if(view.svg,
        do:
          viewport(
            view.svg,
            {0, strip + banner, vw, vh - strip - banner},
            {vw, vh},
            "xMidYMid meet"
          ),
        else: viewport(view.note, {0, strip, vw, vh - strip}, {vw, vh}, "xMidYMid meet")
      ),
      "</g>"
    ]
  end

  defp title(nil, _theme), do: []

  defp title(text, theme) do
    Element.text(text, 0, theme.label_size * 1.1, %{
      class: "vis-cell-title",
      fill: Theme.resolve(theme, :text, :css),
      font_family: Theme.resolve(theme, :font_family, :css),
      font_size: Theme.resolve(theme, :label_size, :css),
      font_weight: "bold"
    })
    |> Render.to_string()
  end

  # A drawing's own SVG, unchanged, in a viewport at `{x, y, w, h}` whose view box is the
  # drawing's own size.
  defp viewport(svg, {x, y, w, h}, {vw, vh}, ratio) do
    [
      ~s(<svg class="vis-board-place" x="#{num(x)}" y="#{num(y)}" width="#{num(w)}" ),
      ~s(height="#{num(max(h, 0))}" viewBox="0 0 #{num(vw)} #{num(vh)}" preserveAspectRatio="#{ratio}">),
      svg,
      "</svg>"
    ]
  end

  # A length to two places, an integer when it is whole, so a document never prints `1.0e3`.
  defp clean(n) do
    rounded = Float.round(n * 1.0, 2)
    if rounded == trunc(rounded), do: trunc(rounded), else: rounded
  end

  defp num(n) when is_integer(n), do: Integer.to_string(n)

  defp num(n) when is_float(n) do
    rounded = Float.round(n, 3)

    if rounded == trunc(rounded),
      do: Integer.to_string(trunc(rounded)),
      else: Float.to_string(rounded)
  end

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
