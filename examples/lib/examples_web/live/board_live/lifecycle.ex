defmodule ExamplesWeb.BoardLive.Lifecycle do
  @moduledoc """
  The board outside its process (spec/15 §11, §12, spec/08 §12, #781, work item #822): what
  `/board` shows of a board after it leaves the screen, as values the page holds and a
  panel that draws them.

  - **A snapshot reopened.** The JSON *Export → Snapshot* downloads, uploaded back — or the
    running board frozen in place — read by `Visualize.Board.Snapshot.from_json/2` and drawn
    by `Visualize.Board.Export.svg/2` with no feed and no process: the data it froze, at the
    instant it froze it. A document the reader refuses is its faults, worded by
    `Snapshot.format_error/1`.
  - **A board in a bundle.** The demo board exported from the authoring host's library with
    `Visualize.Chart.Builder.Bundle.export_board/3` and imported into a second host's with
    `import_board/3` — between them written to the JSON file another host would receive
    (`Bundle.to_json/1`) and read back from it (`from_json/2`): the file, the entries it
    carried, the ids the receiving library issued them,
    each cell's ref rewritten, and the slots the receiving host must bind to its own feeds,
    since a binding never travels.
  - **The conformance kit.** `Visualize.Feed.Conformance.check/3` over each of the board's
    feeds, each check passing or its findings in `format/1`'s words: the kit a host runs in
    its tests, shown to a visitor.
  """

  use Phoenix.Component

  alias Examples.BoardDemo
  alias Examples.BoardDemo.Library
  alias ExamplesWeb.Highlight
  alias Visualize.Board
  alias Visualize.Board.{Export, Server, Snapshot}
  alias Visualize.Chart.Builder.Bundle
  alias Visualize.Feed.Conformance

  @doc """
  A snapshot document reopened: `{:ok, %{svg, now, window, cells}}` drawn with no feed, or
  `{:error, faults}`, each a line a person reads.
  """
  @spec reopen(String.t()) :: {:ok, map()} | {:error, [String.t()]}
  def reopen(json) when is_binary(json) do
    case Snapshot.from_json(json) do
      {:ok, snapshot} ->
        {:ok,
         %{
           svg: Export.svg(snapshot, width: 960),
           now: snapshot.now,
           window: snapshot.window,
           cells: map_size(snapshot.cells),
           bytes: byte_size(json)
         }}

      {:error, faults} when is_list(faults) ->
        {:error, Enum.map(faults, &Snapshot.format_error/1)}

      {:error, reason} ->
        {:error, [inspect(reason)]}
    end
  end

  @doc "The running board frozen, written as JSON and reopened from it, as an upload is."
  @spec freeze(GenServer.server()) :: {:ok, map()} | {:error, [String.t()]}
  def freeze(board) do
    {:ok, json} = Snapshot.to_json(Server.snapshot(board))
    reopen(json)
  end

  @doc """
  The demo board carried in a bundle from the authoring host's library to a second host's,
  as a file: the bundle written as JSON (`Bundle.to_json/1`) and its size, read back
  (`Bundle.from_json/2`) and the bundle read imported; the entries carried, the receiving library before and after, the `old → new` id table,
  each cell's ref as exported and as imported, and the slots the receiving host binds.
  `{:error, faults}` when the file does not read or the import refuses the bundle.
  """
  @spec carry() :: {:ok, map()} | {:error, term()}
  def carry do
    authoring = Library.authoring()
    receiving = Library.receiving()
    before = Library.entries(receiving)
    board = BoardDemo.value()
    {:ok, json} = Bundle.to_json(Bundle.export_board(authoring, board, "examples /board"))

    with {:ok, bundle} <- Bundle.from_json(json),
         {:ok, %{board: imported, ids: ids, outside: outside}} <-
           Bundle.import_board(receiving, bundle),
         {:ok, needs} <- Board.required_sources(imported, Library.fragments(receiving)) do
      {:ok,
       %{
         file: json |> Jason.decode!() |> Jason.encode!(pretty: true),
         bytes: byte_size(json),
         carried: for(entry <- bundle.entries, do: {entry.id, entry.name}),
         schema: bundle.provenance.schema,
         before: before,
         after: Library.entries(receiving),
         ids: Enum.sort(ids),
         outside: outside,
         refs:
           for(
             {name, cell} <- Enum.sort(board.cells),
             do: {name, cell.ref, imported.cells[name].ref}
           ),
         needs:
           for(
             {{cell, slot}, need} <- Enum.sort(needs),
             do: {cell, slot, need.fields}
           )
       }}
    end
  end

  @doc """
  The conformance kit over every feed of the demo board: `[{feed, [{check, findings}]}]`,
  in name order, `findings` the words of each, `[]` for a check the feed passes. Each feed
  is asked for no window and for the last five minutes; the telemetry feeds are made to push
  by emitting their event.
  """
  @spec conformance(map()) :: [{String.t(), [{atom(), [String.t()]}]}]
  def conformance(feeds \\ BoardDemo.feeds()) do
    now = DateTime.utc_now()
    windows = [nil, [DateTime.add(now, -300), now]]

    for {name, feed} <- Enum.sort_by(feeds, &to_string(elem(&1, 0))) do
      opts = [windows: windows] ++ push(name)

      {to_string(name),
       for(
         check <- Conformance.checks(),
         do: {check, Enum.map(Conformance.check(check, feed, opts), &Conformance.format/1)}
       )}
    end
  end

  # The telemetry feeds push when their event is emitted: the probe's own event, now.
  defp push(name) when name in ["examples.vm.memory", "examples.vm.run_queue"],
    do: [
      push: fn _feed ->
        :telemetry.execute([:examples, :vm], %{memory: 64.0, run_queue: 0}, %{})
      end
    ]

  defp push(_name), do: []

  attr(:uploads, :map, required: true, doc: "the page's uploads, `:snapshot` among them")
  attr(:reopened, :any, required: true, doc: "`reopen/1`'s answer, or `nil`")
  attr(:bundle, :any, required: true, doc: "`carry/0`'s answer, or `nil`")
  attr(:conformance, :any, required: true, doc: "`conformance/1`'s rows, `:running` or `nil`")

  @doc "The panel: a snapshot reopened, a board in a bundle and the conformance report."
  def panel(assigns) do
    ~H"""
    <section class="board-lifecycle">
      <h3>A snapshot, reopened</h3>
      <p class="panel-note">
        <em>Export → Snapshot</em>
        above downloads the board frozen as JSON: its cells'
        designs, the rows they showed, the window and the theme. Upload it back — or freeze
        the board here — and it is read by <code>Visualize.Board.Snapshot.from_json/2</code>
        and drawn by <code>Visualize.Board.Export.svg/2</code>, with no feed and no process:
        what the board showed at that instant, however long ago.
      </p>
      <form id="board-reopen" phx-submit="reopen" phx-change="reopen_pick">
        <.live_file_input upload={@uploads.snapshot} />
        <button type="submit">Reopen</button>
        <button type="button" phx-click="freeze">Freeze the board now</button>
      </form>
      <%= case @reopened do %>
        <% {:ok, shown} -> %>
          <p class="board-reopened">
            Reopened: {shown.cells} cells, taken <strong>{stamp(shown.now)}</strong>, window {window(
              shown.window
            )}, from {shown.bytes} bytes of JSON.
          </p>
          <div class="board-reopened-svg">{Phoenix.HTML.raw(shown.svg)}</div>
        <% {:error, faults} -> %>
          <p class="board-refused">Refused:</p>
          <p :for={fault <- faults} class="board-fault">{fault}</p>
        <% nil -> %>
      <% end %>

      <h3>The board in a bundle, to another host</h3>
      <p class="panel-note">
        A board names its designs by one library's ids, so it travels in a bundle with every
        design it shows (<code>Bundle.export_board/3</code>), and arrives under ids the
        receiving library issues (<code>import_board/3</code>): every check runs before any
        entry is put. Bindings never travel: the receiving host binds the slots to its own
        feeds. Between the two libraries the bundle travels as the file another host would
        receive: <code>Bundle.to_json/1</code>
        writes it, and <code>Bundle.from_json/2</code>
        reads it back — its version and the limits checked before a key is read — into the
        bundle the import is given.
      </p>
      <button type="button" phx-click="carry">Carry the board to a second library</button>
      <%= case @bundle do %>
        <% {:ok, carried} -> %>
          <p class="board-bundle-summary">
            {length(carried.carried)} designs carried at schema v{carried.schema}; the
            receiving library held {length(carried.before)} and now holds {length(carried.after)};
            references outside the bundle: {length(carried.outside)}.
          </p>
          <details class="board-bundle-file">
            <summary>The bundle as a file: {carried.bytes} bytes of JSON</summary>
            <div class="board-bundle-json"><Highlight.code code={carried.file} lang="json" /></div>
          </details>
          <table class="board-bundle-ids">
            <tr>
              <th>carried as</th>
              <th>imported as</th>
            </tr>
            <tr :for={{old, new} <- carried.ids}>
              <td><code>{inspect(old)}</code></td>
              <td><code>{inspect(new)}</code></td>
            </tr>
          </table>
          <table class="board-bundle-refs">
            <tr>
              <th>cell</th>
              <th>ref</th>
              <th>after import</th>
            </tr>
            <tr :for={{cell, old, new} <- carried.refs}>
              <td>{cell}</td>
              <td><code>{inspect(old)}</code></td>
              <td><code>{inspect(new)}</code></td>
            </tr>
          </table>
          <p class="panel-note">The slots the receiving host binds:</p>
          <ul class="board-bundle-needs">
            <li :for={{cell, slot, fields} <- carried.needs}>
              <code>{cell}.{slot}</code>: {Enum.join(fields, ", ")}
            </li>
          </ul>
        <% {:error, faults} -> %>
          <p :for={fault <- faults} class="board-fault">{fault_words(fault)}</p>
        <% nil -> %>
      <% end %>

      <h3>The feeds, held to the contract</h3>
      <p class="panel-note">
        <code>Visualize.Feed.Conformance</code> is the kit a host runs over its own feeds in
        its tests; here it runs over every feed of this board. Each feed is asked for no
        window and the last five minutes. <em>Offline</em> fails on purpose: its source
        cannot be reached.
      </p>
      <button type="button" phx-click="conformance" disabled={@conformance == :running}>
        {if @conformance == :running, do: "Running…", else: "Run the conformance kit"}
      </button>
      <table :if={is_list(@conformance)} class="board-conformance">
        <tr>
          <th>feed</th>
          <th :for={check <- Visualize.Feed.Conformance.checks()}>{check}</th>
        </tr>
        <tr :for={{feed, checks} <- @conformance} data-feed={feed}>
          <td><code>{feed}</code></td>
          <td
            :for={{check, findings} <- checks}
            class={if findings == [], do: "pass", else: "fail"}
            data-check={check}
          >
            <%= if findings == [] do %>
              ✓
            <% else %>
              <span :for={finding <- findings} class="board-finding">{finding}</span>
            <% end %>
          </td>
        </tr>
      </table>
    </section>
    """
  end

  defp fault_words({path, _reason} = fault) when is_list(path),
    do: Visualize.Chart.Validator.format(fault)

  defp fault_words(other), do: inspect(other)

  defp stamp(nil), do: "with no clock"
  defp stamp(%DateTime{} = t), do: Calendar.strftime(t, "%Y-%m-%d %H:%M:%S UTC")

  defp window(nil), do: "none"
  defp window({from, to}), do: "#{stamp(from)} to #{stamp(to)}"
end
