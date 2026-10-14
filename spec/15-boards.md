# Boards

**Status:** Implemented

A **board** is a dashboard as data: designs laid out on a grid, sharing a time window, variables and a sync group, but never geometry. It is the layer above the composite of [14-declarative-chart](14-declarative-chart.md) §19.6. A composite is overlapping parts that **flatten** into one chart in one coordinate space, such as a gauge drawn over a line. A board **never flattens**: each cell is its own chart, applied, rendered and updated on its own, and the cells share *state*, not pixels (#531 §1).

This document is the board as a **value**: its keys, its codecs, its validation, the sources it needs and how a connector binds them (#539, D-141). The processes that keep a board live, its feeds and its cells' designed states are the board runtime's, §8 (#540, D-146). A board travels to another host in a bundle with its components and themes, re-keyed on import (§11, #542). A board leaves the screen as a picture — an SVG, a PNG or printed pages — drawn from a frozen snapshot of its data (§12, #578, D-150). A board's cells interact through its shared state: a brush sets every cell's window, a selection is highlighted in every cell that shows it, and a click drills down to another board (§13, #545, D-151).

```
board      — layout + shared state                       (this document)
 └ cell    — placement + a component ref
   component = a composite or a design in the store      (spec/14 §19)
binding    — cell slot → feed, the connector's           (this document, §4)
feeds      — fill the slots, push, answer the window      (#537, #540)
```

## 1. The board

### 1.1 Three separate values

A board, a binding and the providers behind it are three things, held by three owners (#531, further considerations §4):

- **The board** says what is shown and where: cells, each a placement and a reference to a component in the store, and the state the cells share. It names no feed and no provider, so one board serves every host.
- **The binding** says which feed fills each of the board's slots. It is the **connector's**: metresis, Exio or any other host software that knows its feeds. It travels separately from the board, because it belongs to the host (§4.2).
- **The providers** are the feeds themselves (spec/08 §10, #537). The board never sees them.

A board is data in the sense of spec/14 §1.1: a struct of maps, lists and atoms with no function in it. It is versioned (§2.3), encodable as a map and as JSON (§2.1, §2.2), and validated (§3).

### 1.2 Keys

`%Visualize.Board{}` holds one field per key. `Visualize.Board.from_map/2` and `Visualize.Board.to_map/1` are exact inverses, and nested nodes are stored as the author wrote them. A reader takes any default from this table, as a design's reader does (spec/14 §2.1, D-59).

| Key | Type | Default | Meaning |
|---|---|---|---|
| `version` | a positive integer | `Visualize.Chart.Migration.current/0` | the schema version the board was written at (§2.3) |
| `meta` | a node: `name`, a string; `description`, a string | `%{}` | what the board is; nothing renders from it |
| `cells` | a map from a cell's name, an atom, to a cell (§1.3) | `%{}` | what is shown, and where |
| `window` | `nil`, `%{last: seconds}` or `%{from: t, to: t}` (§1.5) | `nil` | the time window every cell shows |
| `zone` | a time-zone name | `"Etc/UTC"` | the zone the window is shown in |
| `vars` | a map from a variable's name, an atom, to a value | `%{}` | the board's variables: the defaults of every cell's (§5) |
| `sync` | a string, or `nil` | `nil` | the sync group the cells join (§1.5) |
| `layout` | a node: `breakpoint`, `row_height` and `gap` (§1.6) | `%{}` | how the grid is drawn and when it reflows |
| `stale_after` | a positive number, seconds, or `nil` | `nil` | how old a cell's newest reading may be before the cell shows it is stale (§8.4); `nil` is never |
| `links` | a map from a field's name to the name it links to, both atoms | `%{}` | fields of different names that mean the same thing, so a selection in one cell finds its datum in another (§13.2) |

A key not in the table is `:unknown_key`, at the board's level and at every node's.

### 1.3 Cells

A cell is a placement on the grid and a **component reference**:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `x` | a non-negative integer | required | the first column, `0` to `11` |
| `y` | a non-negative integer | required | the first row; the grid grows downward without bound |
| `w` | a positive integer | required | the columns spanned |
| `h` | a positive integer | required | the rows spanned |
| `ref` | a composite id, `{:composite, n}` | required | the component: what this cell draws |
| `title` | a string | `nil` | the cell's name for a person; the runtime draws it, and nothing in the component reads it |
| `vars` | a map from a variable's name to a value | `%{}` | this cell's values of its component's variables, over the board's (§5) |
| `sync` | a boolean | `true` | whether this cell joins the board's sync group (§1.5) |
| `drill` | a drill node (§13.3), or `nil` | `nil` | the board a click on one of this cell's data opens, and the variables it is opened with |

**A cell's name is its identity.** Cells are a map by name, as a design's frames are (spec/14 §2.1), so a cell is the same cell wherever it is moved. The name namespaces the cell's sources (§4.1), keys its variables and its realised chart (§6), and is what a binding names. It is never drawn.

**A component is a store entry, referred to by id** (spec/14 §19.2). The ref is an id of kind `:composite`, issued by the store. That entry holds either a composite, which flattens to a design (spec/14 §19.6), or a flat design, such as an imported document. `Visualize.Chart.Composite.flatten/2` reads both, and a design flattens to itself. A design is not a kind of fragment and has no id of its own (spec/14 §19.8), so a composite id is the one form a component reference takes. A local key or an inline design is not a component reference, because a board holds no designs of its own. Whatever it shows is in the store, where the builder edits it and a bundle carries it (§8).

**The rectangle is metresis's** (its spec §8.3), so a metresis panel becomes a cell mechanically: `x`, `y`, `w` and `h` carry over unchanged, its stored design becomes the component, and its query becomes the cell's binding.

### 1.4 The grid: twelve columns

A board is **12 columns wide**. `Visualize.Board.columns/0` is `12`. A cell's `x + w` MUST NOT exceed it, and two cells MUST NOT share a grid square (§3.1). The grid has no last row: `y` and `h` are bounded only by the limits of §2.3.

**The grid is not generalised now** (#539's open question, settled here). Twelve divides into halves, thirds, quarters and sixths, which every dashboard layout this library has seen uses, and it is metresis's grid, which keeps the migration mechanical. A `columns` key would be the general case. It is not a key today, so a board that gives one is `:unknown_key`. Adding it later is additive: boards written before it read as 12 columns, and a board written with it would carry a newer version that an older reader refuses by name (§2.3). Nothing has to be undone to generalise.

### 1.5 Shared state: the window, the zone, the variables and the sync group

**The window is in UTC.** A board's `window` is one of:

- `nil`: the board shares no window, and each cell's component keeps its own (a viewport, spec/14 §12.5, or none);
- `%{last: seconds}`: a trailing window of that many seconds (a positive number), ending at the board's *now*;
- `%{from: from, to: to}`: a fixed window between two `DateTime`s in `Etc/UTC`, with `from` before `to`.

A window that gives `last` together with `from` or `to`, a `from` without a `to`, a `DateTime` in another zone and a `from` not before its `to` are faults (§3.3). **Now comes from the board, never from a feed** (#531, further considerations §3). `Visualize.Board.window/2` resolves the window against the instant the caller passes as now, giving `{from, to}` as two UTC `DateTime`s, or `nil` for a board with no window. That pair is what the runtime asks each feed for (#540): the shorthand `[from, to]` of a feed window, which is the range of the feed's window field in the box a feed may be asked (spec/08 §11.1, D-168) — so a board's window is unchanged by boxes, and asks neither a region nor `latest`. The value says nothing about how a window moves. A brush or a time picker writes a new `window`.

**The window is over instants, and a feed declares its own window domain** (D-154). The board's window applies to every feed whose window field (spec/08 §10.1) is `:time`. A feed whose window field is a `:number` — a signal's tick, a sequence number — counts in units the board's clock does not know, so the board's window does not apply to it: the monitor asks it for its own span (`nil`) and does not trim it, and its present is its own (spec/08 §11.2, §11.4). A brush, being a window of instants, does not move it either. To put such a feed on the board's clock, the connector maps its numbers to instants and describes the result as `:time`, as the examples' wall-clock signal does (§10); the board does not guess a mapping, since only the connector knows what a tick is worth.

**The zone is for display only.** `zone` is the time zone the board's times are *shown* in. It is checked as a time scale's `zone` is (spec/14 §4.3, D-115): a name the host's time-zone database does not know is `{:zone, name, reason}`. The window itself stays in UTC, so two hosts in two zones fetch the same rows and show them in their own zone. Where a cell's component has a `:time` scale that names no `zone` of its own, the board's zone is written into it when the component is prepared (§6, `components/3`), so a cell's time axis reads in the board's wall clock; a scale that names its own zone keeps it, as a cell's own variable beats the board's (§5). `"Etc/UTC"` writes nothing, since a scale with no zone is already UTC.

**Variables cascade** as §5 says.

**The sync group.** `sync` names the group the board's cells join. With it set, every cell whose `sync` is `true` joins: its component's design shares hover and the brush with the others (spec/14 §2.9). The board's group replaces any group the design names, because the board is the page. A cell whose component cannot join a group (a polar gauge, a band x) MUST say `sync: false`. Otherwise it is the component's own `{:sync, …}` fault at the cell's `sync` (§3.2), since a cell that silently fell out of the group would be the kind of quiet difference §3 exists to prevent. With `sync` `nil` no cell joins, and a design's own group stands.

### 1.6 Layout and reflow

`layout` says how the grid becomes pixels and when it reflows. Its keys and defaults are metresis's:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `breakpoint` | a positive integer, pixels | `768` | below this container width, the board reflows |
| `row_height` | a positive integer, pixels | `80` | the height of one grid row |
| `gap` | a non-negative integer, pixels | `8` | the space between two cells, across and down |

`Visualize.Board.layout/1` is the effective layout: the board's keys over these defaults.

**Reflow stacks the cells in reading order.** At a container width of `breakpoint` or more, every cell is where it was placed. Below it, the cells are taken in **reading order**: by `y`, then by `x`, then by name, so the order is total. They are stacked in one column, each across all 12 columns (`x: 0`, `w: 12`), each keeping its own `h`, and each starting on the row the one before it ended on. A cell is never narrowed below its design's use, and a reader on a phone scrolls through the board in the order a reader on a desktop scans it. Nothing is hidden, reordered by size or dropped. `Visualize.Board.arrange/2` gives the placements at a width, as a list of `{name, %{x: x, y: y, w: w, h: h}}` in reading order.

`Visualize.Board.boxes/2` gives each cell's box in pixels at a container width, as `%{name => {x, y, w, h}}`. A column is `(width − 11 × gap) / 12` wide and a row is `row_height` high. A cell spanning `w` columns is `w` columns and the `w − 1` gaps between them across, and likewise down. It starts after `x` columns and their gaps, and `y` rows and theirs. This is the arithmetic of a CSS grid with that gap, which is what metresis draws. **A resize is a recompile at the new size** (spec/14 §12.5): each cell's box is the `size:` its component is applied at (§6).

### 1.7 Where a board is kept

**A host keeps its boards where it likes**, and the value says nothing about where. The builder keeps them **in its store, as entries of the kind `:board`** (spec/14 §22.1, #544, D-152): the fragment `%{board: map}`, whose body is the map form of §2.1 with its `version`, read back by `from_map/2` and so gated and bounded as §2.3 says. A board entry is a library entry like a theme: it is listed, opened in the builder's board mode, saved under a name, and exported in a bundle with the closure of its cells' components, which an import re-keys. It is never composed into a chart: a board is shown, and a composite is what is composed. The binding (§4.2) is not in the entry, because it is the host's.

## 2. Version, codecs and limits

### 2.1 The map form

`Visualize.Board.to_map/1` is the board as a map with every key of §1.2, `version` included. `Visualize.Board.from_map/2` reads a map as §2.3 orders it and returns `{:ok, board}` or `{:error, errors}` with every fault of §3.1 in the shape of spec/14 §10.1. `Visualize.Board.from_map!/2` returns the board or raises `ArgumentError` with the faults formatted. `from_map(to_map(board))` is `{:ok, board}` for every valid board.

### 2.2 The JSON form

`Visualize.Board.to_json/1` writes the board as a JSON document behind the optional `Jason` dependency, as spec/14 §11.1 does for a design. Without Jason, `to_json/1` and `from_json/2` return `{:error, {:missing_dependency, :jason}}`. The document is the map form with string keys, except for the version. **The version is the stamp `"$version"`** at the document's top level, as a fragment document carries it (spec/14 §19.7, D-137), so any JSON document this library writes, other than a design, is stamped under one key. A reader gates a document by that key before it knows anything else about it. Values JSON has no form for are the tagged terms of spec/14 §11.2: a component reference `{:composite, 5}` is `{"$id": ["composite", 5]}`, a window's `DateTime` is `{"$time": "…"}`, and an atom in a variable's value is `{"$atom": "…"}`. A cell's name and a variable's name are object keys. A drill variable taken from a datum, `{:datum, :service}`, is `{"$datum": "service"}`, a tag of the board's own, since no design holds one. `links` is an object of field names to field names, both strings. A drill's `board` is its JSON self when it is a string or an integer, and `{"$atom": "…"}` when it is an atom, `:self` included.

`Visualize.Board.from_json/2` reads the document back. `from_json(to_json(board))` is `{:ok, board}` for every valid board. A document that does not parse is `{:error, [{[], {:json, message}}]}`, and so is one whose top level is not an object. Decoding makes an atom of a cell's name and a variable's name, as a design's names are made atoms (spec/14 §11.1). **A key the board does not know is left a string**, so a misspelt key is reported as `:unknown_key` at its own spelling and makes no atom.

### 2.3 Version and limits

A board follows the version policy of spec/14 §9.1 (D-137), which names the board:

- **The writer stamps** the schema version it wrote: `version` in the map form and `"$version"` in the JSON form, which is `Visualize.Chart.Migration.current/0`. A board shares the one schema version of every document this library writes, so a reader holds one number.
- **A newer board is refused by name before anything is read.** `from_map/2` checks `version`, and `from_json/2` checks the parsed document's `"$version"`, before the limits, before a key is decoded and before any cell is read. A version above the current one is `{:newer_schema, needs, this}`, at `[:version]` in the map form and at `["$version"]` in the JSON form, the document's own key.
- **No stamp reads as the current version**, as an unstamped fragment document does. **Boards begin at schema version 2.** Version 2 is the version this library wrote when boards were introduced, so there is no older board to migrate. A version below 2 is `{:unsupported_version, v}`, and a version that is not an integer is `{:type, :integer}`. When a board's own shape changes, its migration is registered here, step by step, as a design's is (spec/14 §9).
- **A board's components migrate as designs.** A cell refers to a component in the store, and every design a board's reading resolves is read through `Visualize.Chart.from_map/2` with the board reader's `limits:` (§3.2). A stored version 1 design is therefore migrated where the board reads it, like any other design.

**Sanity limits** (spec/14 §9.2). `from_map/2`, `from_map!/2` and `from_json/2` take `limits:` as `Visualize.Chart.from_map/2` takes them, and apply the defaults when it is not given. The board document is held to `depth` and `items` before it is read: before a key is decoded in the JSON form, so a fault's path holds the document's own key strings. `items` bounds the number of cells, the variables, and every list a variable's value holds. The `ticks`, `iterations` and `counts` limits are the designs' and are checked when a component is read (§3.2). A fault is `{path, {:limit, name, max, given}}`, as a design's is.

## 3. Validation

`Visualize.Board.validate/1` checks a board map, or a board, alone. `Visualize.Board.validate/3` checks it **given a store** as well. Each returns `:ok` or `{:error, errors}`, every fault found and not the first, each `{path, reason}` in the shape of spec/14 §10.1, ordered by path. A path runs from the board to the faulty value: `[:cells, :latency, :w]`, `[:window, :from]`, `[:layout, :gap]`, and `[]` is the board itself. `Visualize.Board.format_error/1` words one error, `cells.latency: overlaps cell :errors`, using the words of `Visualize.Chart.Validator.format/1`. The root is named `board`.

### 3.1 Alone

For the board and each of its nodes, in this order: unknown keys, required keys, the type of every present value, and then the checks of placement and the window:

- **Placement.** A cell whose `x + w` exceeds 12 runs off the grid and is `{:off_grid, 12}` at the cell's path. Two cells that share a grid square **overlap**. The pair is reported once, at the path of the later of the two by name, as `{:overlap, other}` naming the earlier, so a board of three cells stacked on one square reports two faults, not six. A rectangle is only checked for overlap once its four keys are integers of the right sign.
- **The window.** A window that is neither `nil` nor one of the two forms is `{:type, :window}` at `[:window]`. `last` together with `from` or `to` is `{:window, :both}`. A `from` without a `to`, or a `to` without a `from`, is `:required` at the missing key. A `DateTime` not in `Etc/UTC`, or a value that is not a `DateTime`, is `{:type, :utc_datetime}` at its key. A `from` not before its `to` is `{:window, :inverted}` at `[:window]`. A `last` that is not a positive number is `{:type, :positive}`.
- **The zone** is checked as §1.5 says.
- **Staleness.** A `stale_after` that is neither `nil` nor a positive number is `{:type, :positive}`.
- **Variables.** A board's or a cell's variable name that is not an atom is `{:type, :name}` at its path. A value that is itself a variable (`%Visualize.Chart.Var{}`) is `{:var_binding, name}`, because a board's variables are values, and resolution is single level (spec/14 §7.1).
- **A component reference** that is not an id `{kind, n}` is `{:type, {:id, :composite}}`. An id of another kind, `{:style, 3}`, is `{:ref_kind, :composite, :style}`, as the validator refuses a wrong-kind id before resolution (spec/14 §19.7).
- **Links.** A `links` that is not a map is `{:type, {:map, :name}}` at `[:links]`. A key or a value that is not an atom is `{:type, :name}` at `[:links, key]`.
- **A drill node** (§13.3) that is not a map is `{:type, {:node, :drill}}` at the cell's `drill`. Its unknown keys are `:unknown_key`, a missing `board` is `:required`, and a `board` that is neither `:self`, an atom, a non-empty string nor a positive integer is `{:type, :board_ref}`. Its `vars` are checked as a board's variables are, and a `{:datum, field}` whose field is not an atom is `{:type, :field}` at the variable's path.

### 3.2 Given a store

`validate/3` takes the board, a **store** and options. The store is anything resolution reads (spec/14 §19.6): a fetch function, `(id -> {:ok, fragment} | :error)`, or a map from id to fragment, which is read as `Map.fetch/2`. A host with a `Visualize.Chart.Builder.Store` gives the fetch that its `get/2` makes, the body of the entry. `limits:` is passed to every design read. When the board is valid alone, each cell's component is then **resolved**: the entry is fetched, flattened through the same store (spec/14 §19.6) and read through `Visualize.Chart.from_map/2` with the limits.

- **A dangling reference.** An id the store does not hold is `{:dangling, id}` at `[:cells, name, :ref]`.
- **A component that reaches itself** through any chain of uses is `{:cycle, chain}` there, with the chain `Visualize.Chart.Composite.flatten/2` names.
- **A component that is not a design.** Every fault of reading the flattened component is reported under the cell's ref, `[:cells, name, :ref | path]`, with `path` the design's own: `cells.latency.ref.marks[0].type: is required`. A composite that flattens to a partial design, such as a house look of a theme and a frame, is not a component.
- **A variable the component does not declare.** A cell's variable that its component's design does not declare is `{:undeclared, :var, name}` at `[:cells, name, :vars, var]`. A board variable that no cell's component declares is **not** a fault. It is a default for whichever components declare it (§5), as a pool entry that no slot names is ignored (spec/14 §7.3).
- **A cell that cannot join the group.** With the board's `sync` set and the cell's `sync` true, the component's design is validated with the board's group written into its `interaction.sync`. Any `{:sync, …}` fault (spec/14 §2.9) is reported at `[:cells, name, :sync]`.

- **A drill target** (§13.3). `validate/3` takes `boards:`, the boards a drill may name: a map from a ref to a `%Visualize.Board{}`, or a fetch function `(ref -> {:ok, board} | :error)`. A target of `:self` is the board being validated. A ref that `boards:` does not hold is `{:no_board, ref}` at `[:cells, name, :drill, :board]`. A drill variable that the target board does not declare, which is a key of its `vars` (§1.2), is `{:undeclared, :var, var}` at `[:cells, name, :drill, :vars, var]`. A `{:datum, field}` whose field no source of the cell's component declares is `{:undeclared, :field, field}` there too, when the component's sources declare any fields at all. Without `boards:`, only a `:self` target is checked against a board, since the board names the others and the host holds them.

A referenced id inside a component that the store no longer holds (a style, a scale) is a mask, as everywhere in spec/14 §19.2. It is not a fault of the board.

### 3.3 Reasons

The board's own reasons, beside those of spec/14 §10.1 it reuses (`:required`, `:unknown_key`, `{:type, type}`, `{:ref_kind, wanted, given}`, `{:zone, name, reason}`, `{:var_binding, name}`, `{:undeclared, :var, name}`, `{:newer_schema, needs, this}`, `{:unsupported_version, v}`, `{:limit, …}`, `{:json, message}`, the `{:sync, …}` reasons, and the schema faults of §4.3):

| Reason | Meaning |
|---|---|
| `{:off_grid, columns}` | a cell whose `x + w` runs past the board's `columns` |
| `{:overlap, other}` | a cell that shares a grid square with cell `other`, reported at the later of the two by name |
| `{:window, :both}` | a window that gives `last` and `from` or `to` |
| `{:window, :inverted}` | a fixed window whose `from` is not before its `to` |
| `{:dangling, id}` | a cell's component id that the store does not hold |
| `{:cycle, chain}` | a cell's component that reaches itself through the chain of ids |
| `{:unbound, :binding, slot}` | a slot of the cell's component that the binding does not bind (§4.3) |
| `{:undescribed, feed}` | a slot that states a contract, bound to a feed whose schema the check was not given (§4.3) |
| `:not_required` | a binding of a slot that no cell's component declares (§4.3) |
| `{:no_board, ref}` | a drill target that the boards given to `validate/3` do not hold (§13.3) |
| `{:missing, :datum, field}` | a drill variable taken from a datum that has no value for its field (§13.3) |

## 4. Sources and binding

### 4.1 Required sources: the aggregate, namespaced per cell

**A board's sources are the aggregate of its cells' slots** (#531, further considerations §4). `Visualize.Board.required_sources/3` resolves each cell's component through the store as §3.2 does and returns `{:ok, required}`, or `{:error, errors}` with the faults of §3.2 that stopped a component from being read. `required` is a map from `{cell, slot}` to the slot's needs:

```elixir
%{
  {:latency, :primary} => %{fields: [:t, :latency], types: %{t: :time, latency: :number},
                            requires: %{latency: [:unit, :label]},
                            reads: [{[:marks, 0, :channels, :x], :t, :time},
                                    {[:marks, 0, :channels, :y], :latency, :number}]},
  {:errors, :primary}  => %{fields: [:t, :count], types: %{}, requires: %{}, reads: []}
}
```

- **Namespaced per cell.** A slot's key is the cell's name and the slot's own name. One design used in two cells is two sets of slots, each bound to its own data. This is what lets a "request time" component show one service in one cell and another service beside it.
- **`fields` and `types`** are the slot's declaration (spec/14 §2.3), with `types` `%{}` when it declares none.
- **`requires` is the slot's whole contract** (spec/14 §7.4, D-136): its `requires` together with every attribute a fact of it reads, as `Visualize.Chart.contract/1` gives it. A connector tests a feed's schema against it before offering the feed, as a picker does (spec/14 §7.2). It is `%{}` for a slot that states none.
- **`reads` is what the slot's fields must be** (spec/14 §7.4, D-153): every field the component reads from the slot through a scale, as `{path, field, need}`. `path` is the read's path in the component (the channel, the style or the offset), and `need` is what the scale's kind needs: `:time`, `:number` or `:category`. It is `[]` for a slot nothing reads through a scale.

### 4.2 The binding

`%Visualize.Board.Binding{slots}` is the binding, a value separate from the board: `slots` maps a `{cell, slot}` to a **feed**, any term that names a feed or a pool entry, as the pool of spec/14 §7.2 names a source. A **connector** supplies it, and the board never holds it. A board travels between hosts and a binding does not, because the feeds it names are one host's (#531, further considerations §4).

`Visualize.Board.Binding.new/0` is the empty binding. `Visualize.Board.Binding.new/1` takes a map or a list of `{{cell, slot}, feed}` pairs, and raises `ArgumentError` for a key that is not a pair of atoms. `Visualize.Board.Binding.put/4` binds one cell's slot, and `Visualize.Board.Binding.fetch/3` reads one back. One feed may fill many slots, in one cell or in several.

### 4.3 The check

`Visualize.Board.Binding.check/3` takes the binding, the required sources of §4.1, and the feeds' **schemas**: a map from feed to `%Visualize.Data.Schema{}`, or a describe function `(feed -> {:ok, schema} | {:error, reason})`, the pull side of a feed (spec/08 §10.3). It returns `:ok` or `{:error, errors}`, **every** fault, each at the path of the slot in the board, `[:cells, cell, :sources, slot]`, ordered by path:

- **Every unbound slot.** A required slot that the binding does not bind is `{:unbound, :binding, slot}`.
- **Every contract the bound schema cannot meet.** For a bound slot whose contract is not empty, the feed's schema is looked up or described once. A feed the map does not hold is `{:undescribed, feed}`, and a describe that answers `{:error, reason}` is `{:describe, feed, reason}`. Each attribute the contract requires that the schema does not give the field is `{:missing_attribute, slot, field, key}` at `[…, slot, :requires, field]`. Each field whose declared type the schema contradicts is `{:schema_type, field, declared, described}` at `[…, slot, :types, field]`. These are the same reasons, with the same words, as `Visualize.Chart.apply/2` reports for one design (spec/14 §7.4), so a connector that checks its binding first sees, before any data flows, every fault the cells would report later.
- **Every field of the wrong type.** For a bound slot whose `reads` is not empty, the feed's schema is looked up or described once, as for the contract. Each read whose field the schema describes with a type that does not satisfy its need is `{:type_mismatch, slot, field, expected, given}` at `[:cells, cell | path]`, the read's path in the component under the cell. These are the reason and the words of `Visualize.Chart.apply/2` (spec/14 §7.4), so a wrong binding is seen before any data flows rather than raised by the cell's frame. Nothing requires a schema for a type check alone. A slot with an empty contract whose feed is undescribed, or whose describe answers an error, has its types unchecked and is not a fault.
- **A binding to nothing.**
 A binding of a `{cell, slot}` that is not required, such as a cell since removed or a slot since renamed, is `:not_required` at its path, so a stale binding is seen rather than kept.

A slot whose contract is empty and whose `reads` is empty is not looked up, as spec/14 §7.4's "the facts the slot did not ask for are not read" holds for one design. Its feed needs no schema.

**A check over known types.** `Visualize.Board.Binding.check_types/3` takes the binding, the required sources and a map from feed to what is known of its fields' types: a `%Visualize.Data.Schema{}`, or a map from field to type such as `Visualize.Data.Table.column_types/1` reads from a sample's rows, each checked by its own column of spec/14 §7.4's table. It returns `:ok` or `{:error, errors}`, only the `{:type_mismatch, …}` faults, by path. A tool whose feeds have no schema, such as the builder over its sample pool (spec/14 §22.8), checks a binding with it before it draws.

### 4.4 Pools

`Visualize.Board.Binding.pools/2` turns a binding and the sources a host holds, a map from feed to source (rows, a `%Visualize.Data.Delivery{}`, anything `Visualize.Data.Table.rows/1` reads), into **one pool per cell**: `%{cell => %{slot => source}}`. That is the pool `Visualize.Chart.apply/2` binds the cell's component from, by the slot's own name. A slot whose feed has no source in the map is left out, so application reports it unbound, as for any pool.

## 5. Variables: the cascade

**Board variables are the defaults of every cell's variables, and a cell may override one** (#539's open question, settled here). For a cell's component, a variable's value is the first of:

1. the cell's own `vars` entry of that name;
2. the board's `vars` entry of that name;
3. the component's declared default (spec/14 §2.4);

and with none of them, it is `{:unresolved, :var, name}` at application, as for any design. `Visualize.Board.vars/2` is steps 1 and 2 for one cell: the board's variables with the cell's merged over them. At application (§6) they are narrowed to the names the component declares. A board variable is a default and not a demand, so it reaches only the components that declare its name. Every other component is untouched. A cell's own variable names one its component declares, and is a fault otherwise (§3.2).

Why this order: a board variable is the dashboard's choice (the service, the region, a threshold), shared by every cell that has the notion. A cell variable is the exception for one place: one cell showing the other region, side by side. The component's default is what its author chose when nothing else is said. This is the cascade of spec/14 §8.2, the higher layer winning, applied to three layers that are always in the same order. A board variable is never renamed on its way into a component. A component whose variable means something else under the same name is given a cell variable, or is bound at a use site inside a composite (spec/14 §19.4), where renaming belongs.

## 6. Realising a board

`Visualize.Board.realise/4` resolves every cell to an applied chart, purely: no process and no feed. It takes the board, the store, the **pools** by cell (§4.4) and options, and returns `{:ok, applied, cache}` or `{:error, errors}`. `applied` maps each cell's name to its `%Visualize.Chart.Applied{}` (spec/14 §14.10), and `cache` is the schema cache grown by every cell. For each cell, in name order:

- the component is resolved as §3.2 says;
- its variables are the cascade of §5, narrowed to the ones the component declares;
- with the board's `sync` set and the cell's `sync` true, the board's group is written into the design's `interaction.sync` (§1.5);
- it is applied with `Visualize.Chart.apply/2`: `sources:` the cell's pool, `size:` the cell's box at `width:` (§1.6), and `theme:`, `now:`, `system:`, `schemas:` and `describe:` as given. The schema cache is threaded from cell to cell, so a version one cell has described is not described again. `describe:` is called with the `{cell, slot}` being described, which the connector maps to its feed through its binding.

The options are `width:` (the board's container width in pixels, `1200` by default), `theme:`, `now:`, `system:` (the viewer's unit system, spec/14 §4.4, D-156), `schemas:`, `describe:` and `limits:`. `realise/3` is `realise/4` with no options.

Every fault of every cell is reported, each under its cell: `[:cells, name | path]`, with `path` application's own. A slot with no source in its cell's pool is therefore `{:unbound, :source, slot}` at `[:cells, name, :sources, slot]`, the same path the binding check uses (§4.3). The board's own faults (§3) come first. A board that does not validate alone is refused before any cell is resolved.

**The first three steps are `Visualize.Board.components/3`**: `components(board, store, opts)` resolves every cell's component, writes the board's group and zone into it, and narrows the cascade to the variables it declares, giving `{:ok, %{cell => %{chart: chart, vars: vars}}}` — a `%Visualize.Chart{}` and the variables to apply it with — or `{:error, errors}` with the board's faults, alone and given the store, exactly as `realise/4` reports them. `realise/4` is `components/3` followed by the application, and the runtime (§8) prepares its cells with `components/3` and applies each one in the cell's own process. Its options are `limits:`.

`realise/4` is what makes a board testable as a value, and it is the step the runtime takes per cell (#540): a cell process applies its component at its box's size, then compiles and renders it. The window (§1.5) is not applied to the component here. It is what the runtime asks the feeds for, and a cell's rows arrive already windowed (spec/08 §10.4).

## 7. Functions

### 7.1 `Visualize.Board`

| Function | Contract |
|---|---|
| `Visualize.Board.columns/0` | The board's width in grid columns: `12` (§1.4). |
| `Visualize.Board.from_map/1` | As `from_map/2` with `[]` options. |
| `Visualize.Board.from_map/2` | The board of a map, read as §2.3 orders it: the version gate, the `depth` and `items` limits under `limits:`, then validation alone (§3.1). `{:ok, board}` or `{:error, errors}`. |
| `Visualize.Board.from_map!/1` | As `from_map!/2` with `[]` options. |
| `Visualize.Board.from_map!/2` | The board, or `ArgumentError` naming every fault. |
| `Visualize.Board.to_map/1` | The board as a map with every key of §1.2, `version` included. |
| `Visualize.Board.from_json/1` | As `from_json/2` with `[]` options. |
| `Visualize.Board.from_json/2` | The board of a JSON document (§2.2): `"$version"` checked and the structural limits applied before a key is decoded, then read as `from_map/2` reads. |
| `Visualize.Board.to_json/1` | The board as a JSON document stamped `"$version"`, `{:ok, json}`, or `{:error, {:missing_dependency, :jason}}`. |
| `Visualize.Board.validate/1` | `:ok`, or every fault of a board or a board map alone (§3.1). |
| `Visualize.Board.validate/2` | As `validate/3` with `[]` options. |
| `Visualize.Board.validate/3` | `:ok`, or every fault of the board alone and then given the store (§3.2), with `limits:` for the components' designs and `boards:` for the cells' drill targets. |
| `Visualize.Board.format_error/1` | One fault as a line a person reads, the root named `board`. |
| `Visualize.Board.layout/1` | The effective layout: the board's `layout` over `breakpoint: 768`, `row_height: 80`, `gap: 8` (§1.6). |
| `Visualize.Board.arrange/2` | Each cell's placement at a container width, `[{name, %{x, y, w, h}}]` in reading order, stacked below the breakpoint (§1.6). |
| `Visualize.Board.boxes/2` | Each cell's box in pixels at a container width, `%{name => {x, y, w, h}}`, after reflow (§1.6). |
| `Visualize.Board.window/2` | The window resolved at now: `{from, to}` in UTC, or `nil` for a board with no window (§1.5). |
| `Visualize.Board.window_text/2` | `window_text(window, zone)`: a resolved window as a person reads it, each end shifted into the zone and written `YYYY-MM-DD HH:MM:SS`, then the zone's name; `nil` for no window (§9.1, §12.1). |
| `Visualize.Board.vars/2` | One cell's variables before narrowing: the board's with the cell's over them (§5). |
| `Visualize.Board.required_sources/2` | As `required_sources/3` with `[]` options. |
| `Visualize.Board.required_sources/3` | Every cell's slots through the store, keyed `{cell, slot}`, each with `fields`, `types` and its `requires` contract (§4.1); `limits:` for the components' designs. |
| `Visualize.Board.components/2` | As `components/3` with `[]` options. |
| `Visualize.Board.components/3` | Every cell's component prepared, purely: `{:ok, %{cell => %{chart, vars}}}` with the group and the zone written and the variables narrowed, or every fault (§6). |
| `Visualize.Board.realise/3` | As `realise/4` with `[]` options. |
| `Visualize.Board.realise/4` | Every cell applied, purely: `{:ok, %{cell => applied}, cache}`, or every fault under its cell (§6). |
| `Visualize.Board.link/2` | `link(board, field)`: the name a field links to through `links`, or the field itself (§13.2). |
| `Visualize.Board.linked/2` | `linked(board, field)`: every field name that links to the same name as `field`, itself included (§13.2). |
| `Visualize.Board.drill/3` | `drill(board, cell, row)`: the cell's drill target with its variables taken from the row, `{:ok, %{board: ref, vars: vars}}`; `:none` for a cell with no `drill`; `{:error, errors}` for a datum with no value for a field it names (§13.3). |

### 7.2 `Visualize.Board.Binding`

| Function | Contract |
|---|---|
| `Visualize.Board.Binding.new/0` | The empty binding. |
| `Visualize.Board.Binding.new/1` | A binding of a map or a list of `{{cell, slot}, feed}` pairs; `ArgumentError` for a key that is not a pair of atoms (§4.2). |
| `Visualize.Board.Binding.put/4` | The binding with one cell's slot bound to a feed. |
| `Visualize.Board.Binding.fetch/3` | The feed a cell's slot is bound to, `{:ok, feed}`, or `:error`. |
| `Visualize.Board.Binding.check/3` | `:ok`, or every unbound slot, every contract the bound schemas cannot meet and every binding to nothing, by path (§4.3). |
| `Visualize.Board.Binding.check_types/3` | `:ok`, or every field a bound slot's component reads through a scale whose known type does not satisfy the need, `{:type_mismatch, slot, field, expected, given}` by path (§4.3). |
| `Visualize.Board.Binding.pools/2` | One pool per cell from the binding and the host's sources by feed (§4.4). |

## 8. The runtime: a process per board and per cell

**Implemented** (#540, #574, D-146). A board value (§1) says what is shown; the runtime keeps it live. It is the processes of #531's further considerations §2: **one process per board** owns the shared state and the feeds, and **one process per cell** applies, compiles and draws that cell's component. The BEAM's scheduler is the fairness: a heavy cell slows only its own frames, and nothing here schedules on top of it. What is left to design is runaway protection, done the BEAM way: each cell runs under a heap limit, and a cell that dies shows that it died and is started again, alone.

```
host's tree
 └ Visualize.Board.Supervisor          a DynamicSupervisor the host adds (§8.1)
    └ Visualize.Board.Server           one per board: window, zone, vars, sync, now, the monitor
       └ DynamicSupervisor             the board's cells, started and linked by the board
          └ Visualize.Board.Cell       one per cell: max_heap_size, apply → compile → frame
```

### 8.1 Who supervises: the host places the supervisor

**The library ships `Visualize.Board.Supervisor`, a `DynamicSupervisor` that a host adds to its own tree** (#540's open question, settled here). The library starts no process of its own: it has no application callback, and nothing runs until a host puts a supervisor in its tree and starts a board under it.

```elixir
children = [
  {Visualize.Board.Supervisor, name: MyApp.Boards},
  MyAppWeb.Endpoint
]

{:ok, board} = Visualize.Board.Server.start(MyApp.Boards, board: board, store: store,
                                            binding: binding, feeds: feeds)
```

`Visualize.Board.Server.start/2` takes **any** `DynamicSupervisor`, so a host that already has one starts boards under it, and `Visualize.Board.Server.child_spec/1` lets a host place one board under a supervisor of any kind. Shipping the module rather than leaving the host to write one gives the place a name in the documentation and one line to copy. It also makes a board's restart policy the library's to state (`:transient`: a board that crashes is started again with its start options, and one stopped with `stop/1` is not). The host is in control of where boards live and of their lifetime, as #531 asks. Neither choice takes that away, and this one costs the host nothing it would not write anyway.

### 8.2 The board process

`Visualize.Board.Server` is a `GenServer`. Its options:

| Option | Default | Meaning |
|---|---|---|
| `board:` | required | the `%Visualize.Board{}` |
| `store:` | required | what resolution reads (§3.2) |
| `binding:` | `Binding.new()` | the connector's `%Visualize.Board.Binding{}` (§4.2) |
| `feeds:` | `%{}` | the feeds by the names the binding uses: a map from a name to a `Visualize.Feed` struct (spec/08 §11.1) |
| `theme:` | `Visualize.Theme.default/0` | the theme every cell and every cell state is drawn in |
| `system:` | `:as_posted` | the unit system every cell's measures are shown in (spec/14 §4.4, D-156): a viewer's preference, so a host that serves viewers of several systems runs a board per system |
| `width:` | `1200` | the container width in pixels, until a `resize/2` |
| `tick:` | `1000` | the data rate: milliseconds between two turns of the loop; `nil` turns only on `tick/1` |
| `budget:` | `nil` | the point budget asked of every feed (spec/08 §11.2) |
| `max_heap:` | `25_000_000` | each cell's heap limit, in words (200 MB on a 64-bit host) |
| `clock:` | `DateTime.utc_now/0` | the board's "now": a function of no argument answering a UTC `DateTime` |
| `limits:` | the defaults | the limits the components' designs are read under (spec/14 §9.2) |
| `boards:` | `%{}` | the boards the cells' drill targets may name, as `Visualize.Board.validate/3` takes them (§3.2, §13.3) |
| `debounce:` | `250` | milliseconds a brushed window waits for the next before it is applied (§13.1); `0` applies each at once |
| `name:` | none | a registered name, as `GenServer.start_link/3` takes it |

**Starting** prepares every cell with `Visualize.Board.components/3` (§6). A board that does not validate alone and given the store and `boards:`, does not prepare, or that names a feed in its binding that `feeds:` does not hold, is **not started**: `start/2` answers `{:error, {:board, errors}}` with the faults of §3, or `{:error, {:feeds, names}}`. A board is refused as a whole, before any process runs, because a dashboard that half starts is the quiet difference §3 exists to prevent. The board then starts its cells' `DynamicSupervisor`, linked to it as its parent, so the cells go when the board goes, and one `Visualize.Board.Cell` per cell under it, each monitored.

**It owns the shared state** (#531, further considerations §3):

- **Now.** The board's `clock:` is read once per turn. That instant is the one "now" of the board: the window is resolved at it (`Visualize.Board.window/2`), each cell's age is measured against it, and it is handed to each cell's application as `now:`. No feed and no cell reads a clock of its own for this.
- **The window**, in UTC. Each turn resolves the board's window at now and gives the monitor `[from, to]`, or `nil` for a board with no window. A trailing window (`%{last: s}`) slides every turn, which costs a pull feed a fetch and a push feed a trim (spec/08 §11.4). `window(board, window)` **sets** the board's window. It is validated as the board's `window` key is (§3.1), answering `{:error, errors}` otherwise, and it **re-asks every feed** (`Visualize.Feed.Monitor.refetch/1`), push feeds included. A window a person chose is a new question: a narrower one may be served at a finer resolution, and a feed that honours a budget can only say so if it is asked.
- **The zone** is the board's, for display (§1.5). It is written into the cells' time scales when they are prepared and sent to subscribers with the window.
- **The variables.** `vars(board, vars)` merges new board variables over the board's and prepares every cell again, sending each its new chart and variables. A cell compiles again when it next draws.
- **The sync group** is written into the components when they are prepared (§1.5), so the cells' frames carry it.
- **The brushed window and the selection** (§13). `brush(board, window)` sets the window as `window/2` does, after the debounce. `reset_window(board)` restores the window the board was started with. `select(board, identity)` holds the board's one selection and sends it to every cell.

**It owns the feeds.** The board holds a `Visualize.Feed.Monitor` (spec/08 §11.4, D-140) over `feeds:`, with `every:` the board's tick, `stale_after:` the board's `stale_after` in milliseconds and `budget:` the option. It is the monitor's owner as that section says: it ticks the monitor at the start of every turn with its own monotonic clock, routes every `{:visualize_feed, ref, message}` in its mailbox to `handle_message/2`, and `stop/1`s the monitor when it terminates. A feed is fetched once however many slots it fills.

**Each turn**, after the tick, the board hands each cell its data: for each of the cell's slots, the delivery of the feed the binding names, the schema that delivery's version resolves to in the monitor's cache, and the feed's status. A slot the binding does not bind has the status `{:down, {:unbound, slot}}`. The message goes to the cell only when it differs from the last one sent, and always with the turn's now. It is a `send`, never a call, so a slow cell never holds the board.

**Resizing.** `resize(board, width)` recomputes every cell's box at the new width (§1.6, `boxes/2`) and sends each cell whose size changed its new size. A board process draws at **one** width, the last one given. A second viewer at another width is drawn the same frames, scaled by the root's `viewBox`.

**Subscribers.** `subscribe(board, pid)` adds a subscriber, monitored and dropped when it exits, and answers `{:ok, info}`. Every cell then sends the newcomer its present view, so a page that subscribes late draws at once. `unsubscribe/2` removes one. The board sends the subscriber list to its cells whenever it changes, and **a cell sends its frames straight to the subscribers**, so no frame passes through the board's mailbox. Every message is `{:visualize_board, board, message}`, `board` the board process's pid:

| Message | When |
|---|---|
| `{:board, info}` | on subscribing, and whenever the resolved window, the zone, the width or the selection changes: `info` is `%{window: {from, to} \| nil, zone: zone, now: now, width: width, sync: group, selection: {field, value} \| %{field => value} \| nil, moved: boolean}`, `moved` whether the window is other than the one the board was started with (§13.1) |
| `{:cell, name, view}` | a cell's view changed: a new frame, a new state, or both (§8.3) |

`info/1` answers the board's present state: `%{board: board, window: window, zone: zone, now: now, width: width, sync: group, selection: selection, moved: moved, cells: %{name => %{pid: pid \| nil, state: state, restarts: n}}}`. `tick/1` runs one turn now and returns once it is done: the way a test, or a host that drives time itself (`tick: nil`), moves the board. `stop/1` stops the board and its cells.

### 8.3 The cell process

`Visualize.Board.Cell` is a `GenServer` with `restart: :temporary` under the board's cells' supervisor. The **board** restarts it, not the supervisor (below).

- **The heap limit.** The cell's first act is `Process.flag(:max_heap_size, %{size: max_heap, kill: true, error_logger: true, include_shared_binaries: false})`. A design that blows up — a 10,000-tick axis, an unbounded layout, a slot bound to a feed with millions of rows — grows the heap of the process that applies and draws it, and the VM kills that process when its heap passes the limit. This is the main defence, and the load-time sanity limits of spec/14 §9.2 are the first, cheaper line in front of it (#541).
- **Crash, show, restart.** The board monitors each cell. A cell that exits with any reason but `:normal` or `:shutdown` — killed for its heap, or raising in a render — is shown at once as `{:crashed, reason}`: the board sends every subscriber that cell's crashed view (§8.4), since the cell can no longer speak for itself. It is then started again after a **backoff**: 100 ms, doubled on each restart up to 10 s, back to 100 ms when the cell had run for 30 s before it died. The restarted cell is sent the board's latest data for it at once. The board and every other cell are unaffected: a cell is linked only to its supervisor, which does not restart it, so no restart intensity can take the board down. This is why the restart is the board's and not a supervisor's: a design that dies on every frame would exhaust any supervisor's intensity and take its siblings with it.
- **Coalescing.** When the cell takes a data message from its mailbox, it first takes every later data message waiting behind it and keeps only the newest. A cell that falls behind therefore skips to the present instead of drawing a backlog. Its mailbox is bounded by what arrives during one draw, and a slow cell drops its own frames, never anyone else's. Size, chart and subscriber messages are taken in order.
- **Drawing.** With every slot holding a delivery, the cell places its rows (§8.5) and applies its chart with `Visualize.Chart.apply/2`: `sources:` the placed deliveries, `vars:`, `size:` its box, `theme:`, `system:`, `now:` the board's, and `schemas:` a cache of the slots' resolved schemas, so application describes nothing. It compiles the applied chart with `Visualize.Chart.compile/2`, one compiled chart per frame in drawing order (`z`, then name), and draws each data change with `Visualize.Chart.Compiled.step/3` per frame inside one accessible root (spec/14 §21.2): titled with the cell's `title`, else the chart's summary name, described by the summary, and `responsive`, so a viewer at another width scales it. **It compiles again** when a slot's delivery names a schema version other than the one its chart was compiled with (`Compiled.stale?/2`, spec/14 §12.1), when its size changes, and when the board sends it a new chart or variables. Each recompilation is `carry/2`'d from the one before (spec/14 §12.5), so an easing goes on from where it stood and a force layout stays warm. A data change that keeps the schema and the size is a `step/3` only.
- **Interaction.** The cell's frame is the compiled one-string form, whose frame group carries the frame's `data-vis-sync`, `data-vis-sync-x` and `data-vis-brush` attributes as `Visualize.Chart.Frame.generate/2`'s does (spec/14 §2.9, §12.4). With each frame the cell computes, for a chart of one frame, the `KeyboardHook` attributes (spec/10 §17.2) and, when that frame is cartesian and its first mark has `x` and `y` channels, the `CrosshairHook` attributes (spec/10 §13.2), both from the frame realised over the step's sources, so hover, the brush and the keyboard follow the data. The board's LiveView component (#575) places them.
- **Selection and picking.** The board sends each cell the selection as the fields that may hold it and the value (§13.2), and the cell draws it, or asks to be drawn as before, with `{:selection, …}`. A cell answers a pick, `{series, index}` into its keyboard points, with the row behind that point and its identity (§13.2). A pick is a call from the caller's process, never from the board's.
- **The view.** A cell sends `{:cell, name, view}` to every subscriber whenever its frame or its state changes. A turn that changes only now sends nothing unless the state changes with it, such as a cell growing stale. `view` is a `%Visualize.Board.View{}`:

  | Field | Meaning |
  |---|---|
  | `cell` | the cell's name |
  | `title` | the cell's `title`, or `nil` |
  | `state` | the cell's state (§8.4) |
  | `svg` | the chart's frame, an SVG root, or `nil` when no chart is drawn |
  | `note` | the state's own SVG: the whole cell when `svg` is `nil`, a banner over the chart when the state is not `:live`, `nil` when it is |
  | `crosshair`, `keyboard` | the hooks' attribute maps, `%{}` when there are none |
  | `size` | `{width, height}`, the cell's box |
  | `frames` | how many chart frames this cell process has drawn |
  | `drawn` | the token of the drawing `svg` is (D-170): a string new at each drawing the cell process makes, `nil` without one or for a snapshot's view, which no click can reach. A click carries it back, and the cell resolves a click only against the drawing whose token it carries (§9.2) |

  A view is never blank: it carries a frame, a state's drawing, or both.

The cell reports its state to the board whenever it changes, so `info/1` answers it.

### 8.4 Cell states

A cell is always in exactly one state, and **every state is drawn deliberately** (#531, further considerations §5): an explicit SVG from the board's theme, never a blank chart, a crash or a spinner of the host's. `Visualize.Board.State` draws them. Each state has a **role** (spec/08 §7.5, D-135) whose colour is its accent and whose cue's glyph (spec/14 §21.7, D-142) stands beside its words, so it reads in greyscale too.

| State | When | Role | Words |
|---|---|---|---|
| `{:crashed, reason}` | the cell's process died; the board draws it until the restarted cell speaks | `:bad` | `Crashed, restarting` |
| `{:down, reason}` | a slot's feed is down, the slot is not bound, or the component cannot be applied to what arrived for any other reason (`{:apply, errors}`, the faults of `Visualize.Chart.apply/2`) | `:bad` | `Feed down` and the reason |
| `{:invalid, errors}` | the component cannot be applied because a slot's field has a type its scale cannot take (`{:apply, errors}` holding a `{:type_mismatch, …}`, spec/14 §7.4, D-153); the builder's previews draw it for a binding its check refuses (spec/14 §18.4) | `:bad` | `Wrong binding` and the first fault |
| `:loading` | a slot has no delivery yet and none is down | `:info` | `Loading…` |
| `:no_data` | every slot has a delivery and every delivery is empty | `:neutral` | `No data yet` |
| `{:stale, age}` | a slot's feed is `:stale` in the monitor, or the newest reading of a slot whose window field holds `DateTime`s is older than the board's `stale_after` at the board's now; `age` is its age in seconds, or `nil` when only the monitor says so | `:warning` | `Stale` and the age (`Visualize.Format.duration/1`) |
| `:capped` | a delivery is `capped`: the feed served less than the window | `:info` | `Capped: part of the window` |
| `:live` | none of the above | — | — |

The first row that holds is the state, in this order: a cell whose feed is down is not also called loading, and a stale chart that is capped says stale.

**Two drawings.** `Visualize.Board.State.render(state, theme, {w, h})` is the **whole cell**: the theme's `surface` filling the box, a frame in the role's colour, and the glyph and the words centred in the theme's `text` colour, as an accessible SVG root whose title is the words. It is drawn where there is no chart: loading, no data, crashed, invalid, and down or stale before anything was drawn. `Visualize.Board.State.banner(state, theme, width)` is a **banner**: one line across the top of a chart, in the role's colour, glyph and words. It is drawn over the chart for stale, capped and down, so a person still sees the last data with what is wrong with it. `:live` draws neither. Both are in `:css` mode (spec/08 §7.3), so a page's stylesheet themes them as it themes the charts.

### 8.5 Time

- **The window is UTC; the zone is for display** (§1.5). The board resolves the window in UTC, the feeds are asked in UTC, and the zone reaches the cells' time scales and the subscribers.
- **Rows are placed by their window field** (spec/08 §10.1): by their timestamp for a `:time` one, by the number for a `:number` one (D-154). A feed's holding is kept in that order by the monitor (spec/08 §11.4). A pushed row older than the end of what the feed holds is a **late** row, placed in order rather than dropped, unless the holding already has that very row. A fetched delivery out of order is put in order before it is reduced. A cell's rows therefore arrive in order, however the feed sent them.
- **Gaps follow `continuity`** (spec/08 §10.1, D-136). For each slot whose schema gives a field a `continuity`, the cell walks the rows in order, series by series, a series being the rows that share every `:category` field. Where two consecutive readings are further apart in time than the field's `continuity`, it puts a **break row** between them: the earlier row with that field `nil`. A line or an area drawn over the field breaks there (spec/14 §5.6, `defined`), and a gap in the data is drawn as a gap, never as a straight line across it. The walk is along the window field. An instant is measured in seconds: a `DateTime` or `NaiveDateTime` by its difference, a `Date` by its days. A numeric window field is measured in its own units, so a tick feed's `continuity` is in ticks (spec/08 §10.1, D-154).

### 8.6 Functions

| Function | Contract |
|---|---|
| `Visualize.Board.Supervisor.start_link/1` | A `DynamicSupervisor` for boards; `name:` as `DynamicSupervisor.start_link/1` takes it. |
| `Visualize.Board.Supervisor.child_spec/1` | Its child spec, for a host's tree: a supervisor, its id the name given. |
| `Visualize.Board.Server.start/2` | A board started under a `DynamicSupervisor`: `{:ok, pid}`, `{:error, {:board, errors}}` or `{:error, {:feeds, names}}` (§8.2). |
| `Visualize.Board.Server.start_link/1` | A board started linked to the caller, for a host's own supervisor. |
| `Visualize.Board.Server.child_spec/1` | Its child spec, `restart: :transient`. |
| `Visualize.Board.Server.subscribe/1` | As `subscribe/2` for `self()`. |
| `Visualize.Board.Server.subscribe/2` | A subscriber added: `{:ok, info}`, every cell resending its view to it (§8.2). |
| `Visualize.Board.Server.unsubscribe/2` | A subscriber removed; `:ok`. |
| `Visualize.Board.Server.window/2` | The board's window set and every feed re-asked: `:ok`, or `{:error, errors}`. |
| `Visualize.Board.Server.brush/2` | A brushed window: validated at once, `:ok` or `{:error, errors}`, and set as `window/2` sets it once `debounce:` has passed with no later brush (§13.1). |
| `Visualize.Board.Server.reset_window/1` | The window the board was started with, set as `window/2` sets it; `:ok` (§13.1). |
| `Visualize.Board.Server.select/2` | `select(board, {field, value} \| %{field => value} \| nil)`: the board's selection, a single field's or a composite identity's, each field read through `links`, sent to every cell and every subscriber; `:ok` (§13.2). |
| `Visualize.Board.Server.pick/4` | `pick(board, cell, series, index)`: the row behind a cell's keyboard point, its identity, its item and its frame, `{:ok, %{row: row, identity: {field, value} \| %{field => value} \| nil, item: {mark, identity} \| nil, frame: name}}` — `item` as a `Visualize.Event`'s (spec/10 §19.1, D-170) — or `:error` for a cell or a point there is not (§13.2). |
| `Visualize.Board.Server.event/3` | `event(board, cell, click)`: a click a cell's `TooltipHook` pushed (`Visualize.Event.decode/1`, spec/10 §19.2) resolved by the cell's process against the drawing it holds, `{:ok, %Visualize.Event{}}` with the cell, the declared name, the typed row and its item, or `:error` for a cell that is not running, a click on a drawing it no longer holds, a key it has no row for, a name the mark does not declare, or `pick` (§9.2, D-170). Asked as `pick/4` asks, never holding the board. |
| `Visualize.Board.Server.vars/2` | Board variables merged and every cell prepared again: `:ok`, or `{:error, errors}`. |
| `Visualize.Board.Server.resize/2` | The container width set and every cell's box recomputed; `:ok`. |
| `Visualize.Board.Server.tick/1` | One turn of the loop now; `:ok` once it is done. |
| `Visualize.Board.Server.info/1` | The board's present state (§8.2). |
| `Visualize.Board.Server.snapshot/1` | The board frozen as it stands: a `Visualize.Board.Snapshot` (§12.2). |
| `Visualize.Board.Server.stop/1` | The board and its cells stopped; `:ok`. |
| `Visualize.Board.Cell.child_spec/1` | A cell's child spec, `restart: :temporary`: the board starts its cells and restarts them itself (§8.3). |
| `Visualize.Board.State.render/3` | A state drawn as the whole cell, an SVG root string (§8.4). |
| `Visualize.Board.State.banner/3` | A state drawn as a banner across a chart, an SVG root string, or `nil` for `:live` (§8.4). |
| `Visualize.Board.State.role/1` | A state's role. |
| `Visualize.Board.State.words/1` | A state's words, as the drawings print them. |
| `Visualize.Board.State.name/1` | A state's name, the `data-vis-state` its drawings carry: `"stale"`, `"down"`, …. |
| `Visualize.Board.State.of/3` | `of(slots, now, stale_after)`: the state of a cell's slots at now, each slot `%{delivery, schema, status}` (§8.4). |
| `Visualize.Board.Rows.place/2` | `place(delivery, schema)`: the delivery's rows in window-field order with a break row in every gap wider than a field's `continuity` (§8.5). |
| `Visualize.Board.Rows.seconds/1` | A window-field value as §8.5 measures a gap: an instant in seconds, a number as itself; `nil` for anything else. |

## 9. The board in LiveView

**Implemented** (#540, #575, #612, #627, D-146, D-161, D-170). `Visualize.Components.Board` draws a running board (§8) in a LiveView page: the grid, its cells, and the hooks that make them interactive. Like the library's other components it compiles only when `Phoenix.Component` is loaded (spec/10 §2, D-45).

### 9.1 The components

`Visualize.Components.Board` is a `Phoenix.LiveComponent`:

```heex
<.live_component module={Visualize.Components.Board} id="ops" server={@board} board={@board_value} />
```

| Assign | Default | Meaning |
|---|---|---|
| `id` | required | the component's id, the board's DOM id and the prefix of its cells' |
| `server` | required | the board process, a pid or a registered name |
| `board` | required | the `%Visualize.Board{}` the process runs: its cells, titles, layout and window |
| `theme` | `Visualize.Theme.default/0` | the theme a cell is drawn in before its first view |
| `title` | the board's `meta.name` | the board's heading |
| `width` | `1200` | the width the grid is arranged at until `BoardHook` pushes one |
| `brush` | `:server` | who sets the window a brush chooses: `:server`, the board process (§13.1), or `:host`, the page, which is sent the brush and the header's *Reset window* as messages (§9.2, D-161) |

Any other `brush` is refused with an `ArgumentError` when the component is updated.

It renders a `<section phx-hook="BoardHook">` holding a header and the grid. **The header** names the board and shows the window **in the board's zone** (§1.5): the window the board process resolved in UTC, each end shifted into the zone by the host's time-zone database and written `YYYY-MM-DD HH:MM:SS`, followed by the zone's name — `Visualize.Board.window_text/2`, which an export's header prints too (§12.1). **The grid** is a CSS grid of 12 equal columns, rows `row_height` high and `gap` apart (§1.6, `Visualize.Board.layout/1`), and each cell is placed with `grid-column` and `grid-row` at its arrangement for the container's width (`Visualize.Board.arrange/2`). **Below the breakpoint the cells reflow** as §1.6 says, stacked full width in reading order, and the section carries the class `vis-board-stacked`. The width is the one the board's hook last pushed (§9.3), or the board process's own width once the page subscribes, and the `width` assign before either.

**Each cell is its own `Visualize.Components.Board.Cell`**, a `Phoenix.LiveComponent` with the id `"<board id>-<cell>"` (`cell_id/2`). A view (§8.3) updates one cell's component, so **the diff a frame costs is that cell's alone**: its SVG and its hooks' attributes, never the grid or another cell. A cell renders an `<article>`:

- carrying `data-vis-cell` (the cell's name), `data-vis-state` (its state's name, `Visualize.Board.State.name/1`), `tabindex="0"`, `role="group"` and an `aria-label` of the cell's title and, when it is not live, its state's words, so **a cell is one tab stop** (spec/14 §21.5);
- holding its title, when it has one, as a heading;
- when the view has a chart, the chart inside four nested hook elements: `CrosshairHook` with the view's crosshair attributes, which shares hover across the board's sync group; `BrushHook` with `data-brush-type="x"`, `data-brush-event="brush"` and `data-brush-target` naming the board's component; `KeyboardHook` with the view's keyboard attributes, `tabindex="-1"`, `data-keyboard-pick-event="pick"` and `data-keyboard-target` naming the cell's component, so the chart is reached through its cell (§9.3) rather than as a second tab stop and a click or Enter on a point picks it (§13); and, innermost, around the SVG, `TooltipHook` (spec/10 §12) with `data-tooltip-target` naming the cell's component and `data-tooltip-drawn` the view's `drawn` token, so a mark's `tooltip` node (spec/14 §5.7) shows its text under the pointer as it does on a single chart, and a click on its datum goes to the cell with the token of the drawing it landed on (§9.2, D-161, D-170). The tooltip's element carries no sync group: the crosshair shares the board's hover;
- the view's `note` (§8.3): above the chart as a banner when there is a chart, alone when there is not. **A cell is never blank.** Before its first view it draws `:loading` from `theme`.

### 9.2 The page's part

The component runs in the page's process. Once the page is connected, the component subscribes **that process** to the board (`Visualize.Board.Server.subscribe/2`), once, so the board's messages arrive at the page. The page hands them on with one clause:

```elixir
def handle_info({:visualize_board, _board, _message} = message, socket) do
  Visualize.Components.Board.forward("ops", message)
  {:noreply, socket}
end
```

`forward(id, message)` sends a cell's view to that cell's component (`send_update/2`), and the board's window, zone and width to the board's. It answers `:ignore` for any other message. When the page's process exits, the board drops the subscriber, since it monitors every subscriber (§8.2).

**The hooks' pushes come to the component, not to the page.** `BoardHook` pushes the container's width with `pushEventTo` its own element, each cell's `BrushHook` pushes to the component that `data-brush-target` names, and each cell's `KeyboardHook` and `TooltipHook` push to the cell's component. The components turn them into calls on the board process, and into events for the page:

| Event | Becomes |
|---|---|
| `resize` `{width}` | `Visualize.Board.Server.resize/2`: every cell drawn at its new box, and the grid arranged at the width |
| `brush` `{domain: [from, to]}` | `Visualize.Board.Server.brush/2` with `%{from, to}`, the domain read as milliseconds since the Unix epoch (a time `x`'s, spec/10 §6.4): the board's window once the debounce has passed, and every feed re-asked (§13.1). With `brush: :host`, the page is sent the `:brush` event instead (below), and the board process is not called |
| `brush_clear` | nothing on the board: the band is gone from the chart, and the window stays until it is reset (§13.1). A click on a chart is a brush too small to keep, so it must not move the window |
| `reset_window` | `Visualize.Board.Server.reset_window/1`: the window the board was started with. With `brush: :host`, the page is sent the `:brush` event with `domain: nil` instead |
| `select_clear` | `Visualize.Board.Server.select/2` with `nil`: the selection cleared (§13.2) |
| a cell's `pick` `{series, index}` | `Visualize.Board.Server.pick/4` for that cell, then for a cell with a `drill` the `:drill` event below, and for any other cell `Visualize.Board.Server.select/2` with the datum's identity, when it has one (§13.2, §13.3) |
| a cell's `visualize_event` (spec/10 §12.3) | `Visualize.Event.decode/1`, then `Visualize.Board.Server.event/3` for that cell: the page is sent the declared event (below); a click the cell cannot resolve sends nothing |

A brush without a domain, which is a chart in no sync group and with no design brush, changes nothing. So the page holds no event of the board's, no margin and no scale.

**Everything the page is sent is one `Visualize.Event`** (#627, D-170, spec/10 §19), as `{:visualize_event, id, %Visualize.Event{}}`, `id` the board component's. A page that ignores the message ignores every interaction. The board sends four:

| `event` | When | `cell` | `frame`, `item`, `path`, `row` | `at`, `modifiers` | `value` |
|---|---|---|---|---|---|
| a mark's declared name, a string | a click on a datum of a mark whose `tooltip` names an `event` | the cell | the frame and item of the clicked element, and its row, typed | the pointer in the frame's plot area, and the keys held | `%{}` |
| `:drill` | a pick in a cell with a `drill` resolves its target (§13.3) | the cell | the picked point's frame, item and row | `nil`, `[]` | `%{board: ref, vars: vars}` |
| `:brush` | under `brush: :host`, a brush (`[from, to]`, UTC `DateTime`s) or *Reset window* (`nil`) | `nil` | `nil`, `nil`, `[]`, `nil` | `nil`, `[]` | `%{domain: [from, to] \| nil}` |
| `:select` | the board's selection changes (§13.2), whoever changed it | `nil` | `nil`, `nil`, `[]`, `nil` | `nil`, `[]` | `%{identity: identity \| nil}`, the selection in its form of §13.2 |

**A mark's click is the page's** (D-161, D-170). A mark with a `tooltip` node naming an `event` (spec/14 §5.7) keys its elements to its rows, and a click on one of its data makes the cell's `TooltipHook` push `visualize_event` with that key and the token of the drawing it landed on to the cell's component. The cell asks its process, `Visualize.Board.Server.event/3`, which resolves the key against **the drawing it holds** — the rows each mark drew at the cell's last frame, `Visualize.Chart.Compiled.rows/3` — and answers the event with the row as the mark drew it, typed and without the selection's state column, and its item by the slot's declared identity, else inference (§13.2). A click whose token is not the drawing the cell holds is dropped: the cell has drawn a newer frame since, and the ordinal may now name another row. So is a click whose name the mark does not declare, and a mark naming its event `pick`, which stays the cell's own and is never forwarded. A click on such a datum is also a click on the chart, so `KeyboardHook` picks the nearest point too (§13.2). The two are independent: the pick selects or drills as §13.2 and §13.3 say, and the event is the page's:

```elixir
def handle_info({:visualize_event, "ops", %Visualize.Event{event: "event_open", row: %{id: id}}}, socket) do
  {:noreply, push_patch(socket, to: ~p"/ops?event=#{id}")}
end
```

**A host may own the window** (`brush: :host`, D-161). A page that keeps the window in its URL, so that a link reproduces the view, cannot let the board process choose it alone: the URL and the board would drift apart. With `brush: :host` the component calls no window function. A brush sends the page's process the `:brush` event with `value: %{domain: [from, to]}`, `from` and `to` the brushed window's ends as UTC `DateTime`s, `from` before `to`; a brush without such a domain sends nothing, as it changes nothing under `:server`. The header's **Reset window** sends it with `domain: nil`: the undo is the page's to apply too. The page decides the window, updates its URL, and tells the board with `Visualize.Board.Server.window/2`: `%{from: from, to: to}` for a domain, and for `nil` the window it started the board with, its own default. The header shows the window the board process holds and its **Reset window** while that is not the board's `board:` window, as under `:server`, so it follows what the page applied. A cleared brush changes nothing in either mode.

```elixir
def handle_info({:visualize_event, "ops", %Visualize.Event{event: :brush, value: %{domain: domain}}}, socket) do
  {:noreply, push_patch(socket, to: ~p"/ops?#{window_params(domain)}")}
end

def handle_params(params, _uri, socket) do
  :ok = Visualize.Board.Server.window(socket.assigns.board, window_from(params))
  {:noreply, socket}
end
```

**A host may keep the selection too.** The board's component sends the `:select` event whenever the selection in the board's info changes — a pick, *Clear selection*, Escape, or a host's own `select/2` — with `value: %{identity: identity}`, `{field, value}`, a map for a composite identity, or `nil` once cleared. It is not sent for the selection the board already holds when the page subscribes. A page that keeps the selection in its URL updates it there, and restores it with `Visualize.Board.Server.select/2` from its params.

**What the page receives, and when.** `BrushHook` pushes a brush once, when the drag ends (spec/10 §6), never during it, so the page receives one message per gesture. The board's debounce (§13.1) is the board process's, and `:host` bypasses it: `window/2` is never debounced, since a page that applies a brush has made one deliberate choice of it, as a button does. A page that would rather coalesce rapid re-brushes applies the domain with `Visualize.Board.Server.brush/2`, which takes the same `%{from, to}` and debounces as §13.1 says, and keeps its URL in step at the same moment.


**The header holds the board's undo.** While the board's window is not the one it was started with (`moved`), the header shows a **Reset window** button, and while a selection is held it shows the selection, `Selected: service api` — a composite one as each field and value in name order, `Selected: host mx1, iface eth0` — and a **Clear selection** button. The section carries `data-board-selection` while a selection is held, so `BoardHook` knows that Escape has something to clear.

**A drill is the page's to follow.** A cell's pick that resolves a drill target sends the page's process the `:drill` event, `value: %{board: ref, vars: vars}`, with the cell, and the picked point's frame, item and row. The component does not navigate: it knows no route of the host's, and a drill to `:self` may mean a page with the variables in its URL or, for a board shown to one person, `Visualize.Board.Server.vars/2`. A page that follows drills adds one clause beside the one that forwards the board's messages:

```elixir
def handle_info({:visualize_event, "ops", %Visualize.Event{event: :drill, value: %{board: :detail, vars: vars}}}, socket) do
  {:noreply, push_navigate(socket, to: ~p"/detail?#{vars}")}
end
```

### 9.3 Keyboard and focus

The order across cells is the board's (spec/14 §21.5, D-142). `BoardHook` (spec/10 §18) acts on a key whose target is a cell. The arrow keys move focus to the next and the previous cell in reading order, which is the order the cells are rendered in. Home and End move to the first and the last cell, and Enter moves focus into the cell's chart. A key pressed inside a chart is the chart's, and Escape there hands focus back to its cell (`KeyboardHook`, spec/10 §17.3). Enter on a chart's point picks it (§13.2). **Escape anywhere in the board clears the selection** when one is held, so one Escape inside a chart both returns focus to the cell and clears it (spec/10 §18.2).

### 9.4 Functions

| Function | Contract |
|---|---|
| `Visualize.Components.Board.cell_id/2` | `cell_id(board_id, cell)`: a cell's component and DOM id, `"<board_id>-<cell>"`. |
| `Visualize.Components.Board.forward/2` | `forward(id, message)`: a board process's message handed to the board's component or a cell's (§9.2); `:ignore` for any other message. |

## 10. The examples' live board

**Implemented** (#576, D-146). The examples site shows a live board at **`/board`**, under the *Client-side Interactions* tab and linked from that tab's page beside the synced dashboard, so the site map holds it (spec/14 §12.6, `examples/test/examples_web/site_map_test.exs`).

- **The host's part, as a host writes it.** The examples' tree holds `{Visualize.Board.Supervisor, name: Examples.Boards}` (§8.1) and `Examples.BoardDemo`, which runs the demo's feed processes. The demo board is started under `Examples.Boards` on the first visit and is the same process on every later one, so every visitor shares its window, which is the board's shared state (§8.2). The page holds the board's pid, renders `Visualize.Components.Board`, and forwards the board's messages with the one `handle_info/2` clause of §9.2.
- **Eight cells over live feeds; five show the runtime.** *Load* is the gallery's *Load* design: its history is fed by a `Visualize.Signals` sine through the library's `Visualize.Feed.Signals` on the wall clock, and its dial's track by a fixed feed. *Wave* is the gallery's *Line Chart* with its `x` a time scale, over a second signal. *Memory* and *Run queue* are **one component in two cells**, each bound to its own in-process `:telemetry` metric through `Visualize.Feed.Telemetry`, which a probe emits every half second. *Offline* is the *Line Chart* bound to a feed that cannot be reached, so the designed "feed down" state is always on the page. A signal counts ticks and a board's window is UTC, so the demo's wall-clock wrapper is the one conversion between them: a window of instants is asked as ticks, and the ticks are answered as instants.
- **The window moves.** Buttons set the board's window to the last 1, 5 or 15 minutes, and brushing a time chart sets it to the brushed span. Both re-ask every feed, and the header's *Reset window* restores the window. The header shows the window in the board's zone. Below the breakpoint the cells stack.
- **The board leaves the page** (#578, §12). *Export* buttons freeze the running board (`Visualize.Board.Server.snapshot/1`) and hand it back as a file: *SVG* (`Visualize.Board.Export.svg/2`), *PNG* (`png/2`; a host with no resvg answers 503 and says why), and *Snapshot*, the snapshot's JSON, which reopens with no feed. *Print* opens the printed pages (`html/2`, A4 portrait in the print theme) in a new tab for the browser to print to paper or a PDF. The buttons `POST` to `ExamplesWeb.BoardExportController` at `/board/export/:format`, since an export is an action on the running board and not a page of the site, so the site map does not list it.
- **Cells that interact** (§13, #545). *Requests* and *Errors* are **one component in two cells**, a line per service over two synthetic feeds that share the field `service`. Picking a service's line in either, by a click or by Enter on a point, selects `{:service, "api"}`, and both cells draw its line `:selected`, heavier, and every other service `:muted`, faded. *Services* is a bar per service over a third feed that calls the field `name`. The board's `links: %{name: :service}` says the two are one, so the same selection fades every other bar. A click on a bar **drills down**: the cell's `drill: %{board: :detail, vars: %{service: {:datum, :name}}}` names the detail board, which the page opens at `/board/detail?service=api`, a board of its own whose variable `service` filters its two cells to that service. The page starts the detail board itself, linked to its own process, so each visitor's detail board is their own and goes when they leave. Escape, or *Clear selection*, clears the selection.

## 11. A board in a bundle

A board names its components by store id, and an id is one store's (spec/14 §19.2). The host that authored a board (metresis) holds those ids; the host that shows it (Exio) does not. So a board travels in a **bundle** (spec/14 §19.7) with everything it shows, and arrives under ids the receiving store issues (#542, D-147).

### 11.1 What travels, and what does not

`Visualize.Chart.Builder.Bundle.export_board/3` takes a store, a board and the source's name for the provenance, as `export/3` does. The bundle holds:

- **the board**, in its map form (§2.1), under the bundle's `board` key;
- **every component its cells reference**, each once, however many cells use it;
- **the library entries those components use**, transitively: the closure of `export/3`, so a style or a scale a component refers to travels with it;
- **every stored theme the board or its components name.** A component names a theme by its design's `theme` (spec/14 §2.5). The flattened design's `theme` is read, and when it is a variable, it is read through the cell's cascade (§5): the cell's value, then the board's, then the component's default. This is how a board names a theme, since a board has no `theme` key of its own. A name that is a built-in theme (`Visualize.Theme.builtins/0`) is not carried, because every host has it. Any other name is looked up in the store by `Visualize.Chart.Builder.Store.theme_entry/2` and that entry is carried with its closure. A theme the store does not hold is not carried, and the host applies it as it would have (spec/14 §2.5). A theme referred to by id from a use site is in the components' closure already.

Entries are in dependency order, each after everything it refers to, and each keeps its original id. A cell whose component the store does not hold is exported as it is, and its component is not carried. Its import reports it (§11.3).

**Bindings never travel.** A bundle has no binding and no feed. A binding (§4.2) is the host's: it names the host's feeds, and the receiving host has others. The importing host binds the board's slots, which `required_sources/3` names, to its own feeds. A cell's `vars`, its title and its placement are the board's and travel with it.

### 11.2 Importing a board

`Visualize.Chart.Builder.Bundle.import_board/3` takes the receiving store, the bundle and options, and returns `{:ok, %{board: board, ids: table, outside: outside}}` or `{:error, errors}`, every fault in the path shape of §3. `board` is the board with every cell's `ref` rewritten to its component's new id. `table` is the `old => new` id table of the store's `import/2` (spec/14 §19.7), and `outside` the references inside the carried entries to ids the bundle does not carry, which import as masks and are reported, never a failure. The board is returned to the host and is not put in the store: where a host keeps the boards it imports is its own (§1.7). A host that keeps them in its store, as the builder does, puts the returned board there as a `:board` entry.

**Every check comes before any entry is put**, so a refused bundle leaves the receiving store as it was. In order:

1. **The bundle's schema.** A provenance `schema` above `Visualize.Chart.Migration.current/0` is `{:newer_schema, needs, this}` at `[:provenance, :schema]`, as D-137 says, and nothing else of the bundle is read. A bundle with no `schema` reads as the current version.
2. **The board.** A bundle with no board is `:required` at `[:board]`. The board map is read by `Visualize.Board.from_map/2` with the `limits:` option: its own `version` is gated as §2.3 says, then held to `depth` and `items`, then validated alone. Its faults are at the board's own paths.
3. **The entries' limits.** A bundle that carries more entries than `items` is `{:limit, :items, max, given}` at `[:entries]`. Each entry's fragment is held to `depth` and `items` as `Visualize.Chart.Fragment.from_json/2` holds a fragment, each fault at `[:entries, id | path]`, with `id` written as `Visualize.Chart.Builder.Store.encode_id/1` writes it (`"style:11"`).
4. **The board given the bundle.** The board is validated as §3.2 validates it, with the bundle's entries as the store and `limits:` for each component's design. The board is therefore read exactly as the receiving store will hold it. **A cell whose component the bundle does not carry** is `{:not_carried, id}` at `[:cells, name, :ref]`, naming the cell. A component that reaches itself, one that is not a design, an undeclared cell variable and a cell that cannot join the group are §3.2's faults at the same paths.
5. **Theme names.** A theme is found by name (spec/14 §2.5), so a carried theme that the receiving store already holds under its name with a different body would be shadowed or would shadow, and a board would draw in a theme it was not designed in. That is `{:theme_taken, name}` at `[:entries, id]`. A theme of that name whose body is the same is not a fault: either draws the board as it was designed.

Then the entries are imported through the store's own `import/2`, which issues each entry a new id from the receiving store's sequences and rewrites the references inside the collection through one `old => new` table (spec/14 §19.7, D-103). **A new id never collides** with one the store already holds, because the store issues it. The board's cell refs are rewritten through the same table, so each cell names its component's new id. A store that refuses the import, `{:error, reason}`, is `{:store, reason}` at `[]`, and the board is not returned.

### 11.3 Reasons

| Reason | Meaning |
|---|---|
| `{:not_carried, id}` | a cell's component that the bundle does not carry, at the cell's `ref` |
| `{:theme_taken, name}` | a carried theme whose name the receiving store already gives a different theme, at the carried entry |
| `{:store, reason}` | the receiving store refused the import, with the store's own reason |

### 11.4 Functions

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.Bundle.export_board/3` | `export_board(store, board, source)`: a bundle of the board's map form, every component its cells reference with their closure, and every stored theme the board or its components name, dependencies first, with provenance (§11.1). |
| `Visualize.Chart.Builder.Bundle.import_board/2` | As `import_board/3` with `[]` options. |
| `Visualize.Chart.Builder.Bundle.import_board/3` | `import_board(store, bundle, opts)`: every check of §11.2 before any entry is put, then the store's `import/2` and the board's refs rewritten through its table; `{:ok, %{board, ids, outside}}` or `{:error, errors}`; `limits:` as `Visualize.Board.from_map/2` takes them. |

## 12. Exporting a board

**Implemented** (#578, D-150). A dashboard is shared and printed, not only watched (#531 item 11). A board leaves the screen in three forms: one SVG document of the whole board, or a PNG of it; a **snapshot**, the board and its data frozen as one value that reopens anywhere; and printed pages. Each is drawn from a snapshot, so every form shows exactly the data the snapshot froze, with no store, no feed and no process.

```
running board ─ Server.snapshot/1 ─┐
                                   ├─ %Snapshot{} ─┬─ Export.svg/2 ─ Export.png/2
board + store + pools ─ realise/4 ─┘   (JSON)      └─ Export.pages/2 ─ Export.html/2
```

### 12.1 The board as one document

`Visualize.Board.Export.svg(snapshot, opts)` draws the board at a width as one SVG document:

- **The page.** The document is the grid's width with a margin of the board's `gap` on each side. A rectangle of the theme's `background` fills it.
- **The header**, when the board has a name or a window: the board's `meta.name` (or `title:`) in the theme's `title_size`, and below it the window in the board's zone, `Visualize.Board.window_text/2`, as the board component's header prints it (§9.1). The root's accessible title is the name and its description the window.
- **The cells, at their grid boxes.** Each cell is a group carrying `data-vis-cell` and `data-vis-state` (`Visualize.Board.State.name/1`), translated to its box of `Visualize.Board.boxes/2` at the width, offset by the margin and the header. In it, in order: the cell's `title`, when it has one, in a strip one and a half `label_size`s high; the state's banner (§8.4), when there is a chart and the state is not `:live`; and the chart. Where the cell has no chart — loading, no data, down or stale before anything was drawn, crashed — the state's panel (`Visualize.Board.State.render/3`) stands in its place: **the same drawing the board component shows** (§9.1).
- **Each cell's own SVG, byte for byte.** A chart, a banner or a panel is the cell's own SVG root, placed unchanged inside a viewport (`<svg x y width height viewBox>`) whose view box is that root's own size, so a strip above it scales it to fit (`xMidYMid meet`) rather than redraws it. The chart is the view a cell process draws of the same data (§12.2). Ids inside a chart are derived from content (a gradient's, a filter's, the accessible root's, spec/14 §21.2), so two cells that draw one definition share an id with one body, and putting the cells into one document changes none of them.

Options: `width:` (default the snapshot's), `theme:` (default the snapshot's), `system:` (default `:as_posted`: the unit system the cells' measures are shown in, a reader's preference that a snapshot does not record, spec/14 §4.4, D-156), `title:`, and `resolve:`. Under `resolve: :css`, the default, every theme value is the custom-property reference with its literal as fallback that the cells draw (spec/08 §7.3), so a page's stylesheet themes the export as it themes the board. Under `resolve: :literal` every reference is replaced by the literal it carries, `Visualize.Board.Export.literal/1`. Since a theme writes each slot's literal as its reference's fallback, this is the document in `:literal` mode, for a reader of no CSS. A reference with no fallback is left as it is.

**PNG.** `Visualize.Board.Export.png(snapshot, opts)` is `svg/2` with `resolve: :literal`, rasterised by `Visualize.Render.to_png/2` (spec/09 §9, D-121), and answers as `to_png/2` does: `{:ok, png, warnings}` or `{:error, reason}`. Its options are `svg/2`'s and `to_png/2`'s raster and font options. resvg reads no custom property (spec/09 §9.1), which is why the literal form is the one rasterised.

### 12.2 The snapshot

A **snapshot** (`%Visualize.Board.Snapshot{}`) is a board frozen at one instant, as one value:

| Field | Meaning |
|---|---|
| `version` | the schema version it was written at (§12.3) |
| `board` | the `%Visualize.Board{}` |
| `now` | the board's now when it was taken, a UTC `DateTime`, or `nil` |
| `window` | the window resolved at now, `{from, to}` in UTC, or `nil` |
| `width` | the container width the board was drawn at |
| `theme` | the `%Visualize.Theme{}` the cells were drawn in |
| `cells` | by name: `chart`, the cell's component **prepared** as `Visualize.Board.components/3` prepares it (resolved, flattened, the group and zone written); `vars`, its variables narrowed; `slots`, each slot's `%{delivery, schema, status}` as the board last handed it to the cell (§8.2), or `nil` before any; and `crashed`, `nil`, or the words of the reason a crashed cell's process died |

**A bundle carries definitions; a snapshot carries data.** A bundle (§11) carries a board and the store entries it refers to, by id, to be imported into another store, re-keyed and edited. A snapshot carries each cell's component already resolved, with the rows it showed, the window and the theme, to be looked at. It refers to no id, needs no store and is never imported into one. A snapshot of a board is to the board what a printout is to a document: the same content, at one moment, with nothing live behind it.

**Taking one.**

- `Visualize.Board.Server.snapshot(board)` freezes a running board (§8): its board, now, resolved window, width and theme, every cell's prepared component and variables, the slots the board last sent each cell, and the reason of any cell that has crashed. It is a call to the board process, which already holds all of this. No cell is called, so a slow cell does not hold the snapshot.
- `Visualize.Board.Snapshot.realise(board, store, pools, opts)` freezes a board purely. It is `Visualize.Board.realise/4` (§6) over the same arguments, refused with every fault as `realise/4` reports them. On success each cell's slots are the sources application bound them to, by the slot's name or its default (spec/14 §7.2), as deliveries (a delivery as it is, any other source as its rows), with the schema that application found for each slot and the status `:live`. Its options are `realise/4`'s. With `now:` the window is the board's resolved at it. Without, a fixed window is kept and a trailing one is `nil`.

A snapshot keeps only what its codecs write: each delivery's rows as a list, each status as `:loading`, `:live`, `:stale` or `{:down, words}`, a down reason as the words a state prints for it (`Feed down: …`), and a crash's reason as its inspected text. So a snapshot that has been through JSON is equal to the one written (§12.3).

**Drawing one.** `Visualize.Board.Snapshot.views(snapshot, opts)` draws every cell, purely, as `%{name => %Visualize.Board.View{}}`. A cell's view is **the view a cell process draws of the same data as its first frame**. The cell process and the snapshot draw through the same steps: the slots' rows placed by their timestamp with a break in every gap (§8.5), the component applied at the cell's box with the board's now and the slots' schemas, compiled, each frame stepped once, wrapped in the accessible root titled with the cell's title, and the state decided and drawn (§8.3–§8.4). A crashed cell is its crashed panel. A running cell that has eased between frames (a transition in flight, spec/14 §12.5) may differ from its snapshot only by where the easing stood. The snapshot draws the data at rest. Options are `width:` and `theme:`, by default the snapshot's, and `system:`, the unit system the cells' measures are shown in (default `:as_posted`, spec/14 §4.4, D-156): which system a reader wants is theirs, not the board's, so a snapshot does not record it. A snapshot carries data rather than pictures, so it redraws at any width and in any theme: printed pages are the same snapshot in the print theme at the page's width (§12.4).

### 12.3 The snapshot's codecs

A snapshot follows the version policy of spec/14 §9.1 (D-137) and the board's codecs (§2):

- **The map form.** `Visualize.Board.Snapshot.to_map/1` is plain data: `version`; `board` in its map form (§2.1); `now`; `window` as `nil` or `%{from, to}`; `width`; `theme` as a theme node (`Visualize.Chart.Theme.node/1`, spec/14 §9.3); and `cells`, each with `chart` in a design's map form, `vars`, `crashed`, and `slots`. Each slot is the delivery's `rows`, `window`, `resolution`, `capped`, `reduced_by` and its schema `version`, the schema's fields as `schema`, and the `status`. A slot with no delivery has `rows: nil`. `Visualize.Board.Snapshot.from_map/2` reads it back, and `from_map(to_map(s))` is `{:ok, s}`.
- **The JSON form.** `Visualize.Board.Snapshot.to_json/1` writes the map form stamped `"$version"`, behind the optional Jason as every JSON function is. Each document inside is spelt as it is on its own: the board as its JSON form (§2.2, with its own stamp), each component as a design's (spec/14 §11) and the theme as a theme node's. Values JSON has no form for are the tagged terms of spec/14 §11.2. **Rows are written column by column**, `{"fields": [name, …], "rows": [[value, …], …]}`, so each field name keeps its spelling: an atom as `{"$atom": "t"}`, a string as itself, which a JSON object's keys could not keep. A row that lacks a field has `{"$absent": true}` in its place. A schema's fields are a list of `[name, description]` pairs for the same reason, and a description's `status` a list of `[value, role]` pairs. `Visualize.Board.Snapshot.from_json/2` reads it back, and `from_json(to_json(s))` is `{:ok, s}`. A row value must be one of spec/14 §11.2's terms (a number, a string, a boolean, `nil`, an atom, a `DateTime`, a list or a map of them).
- **Reading, in order.** A newer snapshot is refused by name before anything is read: `{:newer_schema, needs, this}` at `[:version]` in the map form and at `["$version"]` in the JSON form. No stamp reads as the current version, and snapshots begin at version 2. The document is then held to the `depth` and `items` limits under `limits:` (spec/14 §9.2), before any key is decoded in the JSON form. `items` bounds a slot's rows as it bounds every list. Then every key is checked and every fault reported, each at its path: an unknown key is `:unknown_key`; `board` and `cells` are `:required`; the board is read by `Visualize.Board.from_map/2`, its faults under `[:board]`; the theme by `Visualize.Chart.Theme.from_map/2`; each cell's component by `Visualize.Chart.from_map/2` with the limits, its faults under `[:cells, name, :chart]`; each schema by `Visualize.Data.Schema.new/1`, its faults under the slot's `schema`; `now` and the window's ends are `{:type, :utc_datetime}` unless UTC `DateTime`s; a window whose `from` is after its `to` is `{:window, :inverted}`; a `width` that is not positive is `{:type, :positive}`; a row that is not a map is `{:type, :row}`; a status that is none of the four is `{:type, :status}`. **Every cell of the board must be in `cells`**: a missing one is `:required` at `[:cells, name]`, and a cell the board does not have is `:not_on_board` there. `Visualize.Board.Snapshot.format_error/1` words a fault with the root named `snapshot`.

### 12.4 Print

**The print theme.** `Visualize.Theme.print/0` (spec/08 §7.2), the built-in `:print`, is paper: a white background and a white surface, so a printer lays no ink under the data; near-black text and axes, and a grid dark enough to survive a photocopy; the default theme's series; and the colour-safe theme's blue → orange → red `status` ramp. A printed page is read in whatever light and by whatever eyes it reaches, often in greyscale, where the ramp's falling lightness and each role's glyph (spec/14 §21.7) still carry the order. It passes the contracts of spec/08 §7.5.

**The page layout.** `Visualize.Board.Export.paginate(board, opts)` lays a board out on paper, purely, as `%{size: {w, h}, width: width, pages: [%{name => {x, y, w, h}}, …]}`: the page's size in CSS pixels (96 to the inch), the width the cells are drawn at, and each page's cells at their boxes on the page.

- **Paper.** `paper:` is `:a4` (210 × 297 mm, the default) or `:letter` (8.5 × 11 in). `orientation:` is `:portrait` (the default) or `:landscape`. `margin:` is the page's margin in pixels, `48` (half an inch) by default.
- **Reflowed to the page.** The board is arranged at the page's width less its margins (`Visualize.Board.boxes/2`), as a container of that width arranges it (§1.6). A portrait A4 page is narrower than the default breakpoint, so its cells stack in reading order, each across the page. A landscape page keeps the grid.
- **Bands, never split.** The cells are taken in **bands**: a band is the cells whose rows overlap, joined until no cell in it shares a row with one outside it. A band is the least that can be moved down the page without cutting a cell. Bands are placed below a header of two lines (the name, and the window with the page's number), a `gap` apart, and a band that does not fit below the last starts the next page. A band taller than a page's room is **scaled down to fit one page**, its width with it so a cell keeps its proportions, and centred. No cell is split across pages, and every box lies inside the margins, below the header.
- **Pages.** `Visualize.Board.Export.pages(snapshot, opts)` draws each page as its own SVG document, its root `width` and `height` in the paper's unit (`210mm` by `297mm`) over a view box in pixels, so it prints at the paper's size. The header names the board and gives the window and `page n of m`. The cells are drawn as §12.1 draws them, from the snapshot redrawn at the layout's width in `theme:`, `Visualize.Theme.print/0` by default, and a scaled band is placed scaled. Its options are `paginate/2`'s with `svg/2`'s `system:`, `title:` and `resolve:`.
- **One document to print.** `Visualize.Board.Export.html(snapshot, opts)` puts the pages in one HTML document whose `@page` rule is the paper's size with no margin, each page filling one sheet. A browser prints it as paper or as one multi-page PDF.

**Why SVG pages and not a PDF.** resvg, the rasteriser the library already uses (D-121), makes PNG and not PDF. No PDF writer is cheap to add: a PDF library is a native or a large dependency for one output, and none is on the hosts this library is run on. Each page is a standalone SVG that `Visualize.Render.to_png/2` rasterises with `resolve: :literal`, and the HTML document gives a host that wants a PDF one through any browser's print, which every host that shows a board already has.

### 12.5 Functions

| Function | Contract |
|---|---|
| `Visualize.Board.Export.svg/1` | As `svg/2` with `[]` options. |
| `Visualize.Board.Export.svg/2` | The board as one SVG document: the header, and each cell at its box with its title, its banner and its own SVG embedded byte for byte, or its state's panel (§12.1). |
| `Visualize.Board.Export.png/1` | As `png/2` with `[]` options. |
| `Visualize.Board.Export.png/2` | `svg/2` with `resolve: :literal`, rasterised by `Visualize.Render.to_png/2`; as `to_png/2` answers (§12.1). |
| `Visualize.Board.Export.literal/1` | An SVG with every custom-property reference replaced by the fallback it carries (§12.1). |
| `Visualize.Board.Export.paginate/1` | As `paginate/2` with `[]` options: A4 portrait. |
| `Visualize.Board.Export.paginate/2` | The board laid out on paper, purely: the page's size, the drawing width, and each page's cells at their boxes, bands never split (§12.4). |
| `Visualize.Board.Export.pages/1` | As `pages/2` with `[]` options. |
| `Visualize.Board.Export.pages/2` | One SVG document per page, of the paper's size, in the print theme by default (§12.4). |
| `Visualize.Board.Export.html/1` | As `html/2` with `[]` options. |
| `Visualize.Board.Export.html/2` | The pages in one HTML document with an `@page` rule of the paper's size (§12.4). |
| `Visualize.Board.Snapshot.realise/3` | As `realise/4` with `[]` options. |
| `Visualize.Board.Snapshot.realise/4` | A snapshot of a board realised purely: `Visualize.Board.realise/4`'s faults, or `{:ok, snapshot}` (§12.2). |
| `Visualize.Board.Snapshot.views/1` | As `views/2` with `[]` options: the snapshot's width and theme. |
| `Visualize.Board.Snapshot.views/2` | Every cell drawn, purely, as the cell process draws the same data: `%{name => %Visualize.Board.View{}}`; `width:`, `theme:` and `system:` (§12.2, D-156). |
| `Visualize.Board.Snapshot.to_map/1` | The snapshot as plain data (§12.3). |
| `Visualize.Board.Snapshot.from_map/1` | As `from_map/2` with `[]` options. |
| `Visualize.Board.Snapshot.from_map/2` | The snapshot of a map: the version gate, the limits, then every key; `{:ok, snapshot}` or every fault (§12.3). |
| `Visualize.Board.Snapshot.to_json/1` | The snapshot as a JSON document stamped `"$version"`, rows column by column (§12.3). |
| `Visualize.Board.Snapshot.from_json/1` | As `from_json/2` with `[]` options. |
| `Visualize.Board.Snapshot.from_json/2` | The snapshot of a JSON document, `"$version"` and the limits checked before a key is decoded (§12.3). |
| `Visualize.Board.Snapshot.format_error/1` | One fault as a line a person reads, the root named `snapshot`. |

`Visualize.Board.Server.snapshot/1` is in §8.6, `Visualize.Board.window_text/2` in §7.1 and `Visualize.Theme.print/0` in spec/08 §7.6.


## 13. Interaction across cells

**Implemented** (#545, #612, #627, D-151, D-161, D-170). Interaction on a board spans its cells (#531 items 8–10). A brush in one cell moves every cell's window, a selection in one cell is highlighted in every cell that shows it, and a click on a datum opens another board with variables taken from it. All three are the board's **shared state**, held by the board process (§8.2). A cell's chart does not talk to another cell's: it tells the board, and the board tells every cell.

### 13.1 Brush to window

A brush on a time chart in any cell chooses a window (`interaction: %{brush: :x}`, spec/14 §2.9, or the sync group's brush, spec/10 §6.4), and its `domain` reaches the board's component as `brush` (§9.2). The component calls `Visualize.Board.Server.brush/2`, and the board sets the window as `window/2` does: validated as the board's `window` key (§3.1), resolved at the board's now, and **every feed re-asked** (`Visualize.Feed.Monitor.refetch/1`). Each cell then receives its slots' rows in the new window and draws them, so **every cell follows**, whichever cell was brushed, including cells in no sync group.

- **Rapid brushes are debounced in the board process.** A brushed window is validated at once, so a bad one answers `{:error, errors}` to its caller, and then waits `debounce:` milliseconds (`250`) for the next. A later brush replaces it and the wait starts again, so a person re-brushing three times in quick succession costs every feed one fetch, for the last window. `debounce: 0` applies each brush at once. `window/2`, from a host's buttons, is never debounced: a button is one deliberate choice. A `window/2` call drops a brush still waiting, since it is the later choice.
- **Undo is "Reset window".** `Visualize.Board.Server.reset_window/1` sets the window the board was started with, its `board:` option's `window`, and re-asks every feed. The board reports `moved: true` in its info (§8.2) whenever its window is other than that one, and the component shows a **Reset window** button while it is. A cleared brush (`brush_clear`) changes nothing on the board: a click on a chart is a brush too small to keep, and it must not throw away the window a person chose.
- **A host may own the window.** With the component's `brush: :host` (§9.1, D-161), the brush and *Reset window* go to the page as the `:brush` event, `%Visualize.Event{event: :brush, value: %{domain: [from, to] | nil}}` (§9.2, D-170), instead of to the board process, and the page sets the window with `window/2` once it has put it in its URL (§9.2). Every cell still follows, since `window/2` re-asks every feed as a brush does. The debounce above is then the page's choice: `window/2` applies at once, and `brush/2`, called by the page, still debounces.

### 13.2 Linked selection

**The identity is `{field, value}`, or a map for a composite one.** A selection names a field and a value, such as `{:service, "api"}`, or, when the thing selected is named by several fields together (spec/08 §10.1, D-167), a map from each field to its value, such as `%{host: "mx1", iface: "eth0"}`. Cells over different feeds agree on it when their rows have those fields with those values, so two feeds that describe the same thing in the same terms link with no configuration, as the schema's meaning makes them comparable (spec/08 §10.1, D-136). A map of one field is the same selection as the pair, and is held as the pair, so one identity has one form.

**`links` names fields that mean the same thing under different names.** `links: %{name: :service, svc: :service}` says that a row's `name` and a row's `svc` are both the field `service`. `Visualize.Board.link/2` gives the name a field links to, the field itself when `links` does not name it. `Visualize.Board.linked/2` gives every field that links to the same name, so `linked(board, :name)` is `[:name, :service, :svc]` in name order. A link is one step: the name a field links to is not looked up again.

**Picking.** A selection starts with a **pick**: a click on a cell's chart, or Enter on the point the keyboard has reached (spec/10 §17.3), names one of the cell's keyboard points as `{series, index}` (spec/10 §17.2). The cell's component calls `Visualize.Board.Server.pick/4`, which asks the board for the cell's process and then asks that process, from the caller's process, so a pick never holds the board. The cell answers with **the row behind the point** and its **identity**, read in this order:

1. **the identity the schema of the mark's slot declares** (`identity: true`, spec/08 §10.1, D-167), by `Visualize.Data.Schema.identity/2`: `{field, value}` for one declared field, `%{field => value}` for several, and `nil` when the row has no value for one of them — a declared identity is the feed's word, so a row that lacks it names nothing rather than being guessed at;
2. else, when the schema declares none, **inference** as before the declaration existed: the point's mark's `series` channel, when it reads a field, `{field, value}` with the row's value;
3. else the first field, by name, that the schema of the mark's slot types `:category` and the row has a value for;
4. else none, `nil`: a point that names nothing a board can share selects nothing.

A board over feeds that declare no identity therefore picks exactly as it did. Inference stays as the fallback because a pick is a one-off a person makes and sees: a wrong guess selects the wrong thing visibly, where tracking an entity over time on a guess would merge two entities silently, which is why what follows entities requires a declared identity (#626).

The row is the datum as the mark drew it, with its typed values: a `DateTime` is a `DateTime`, not the string a data attribute would hold.

**Selecting.** `Visualize.Board.Server.select(board, {field, value})` holds the selection, with its field read through `link/2`, so `{:name, "api"}` and `{:service, "api"}` are one selection under `links: %{name: :service}`. `select(board, %{field => value})` holds a composite one, each of its fields read through `link/2`. `select(board, nil)` clears it. The board sends every cell the selection as, for each of its fields, `linked/2`'s fields and the value, sends every subscriber its info (§8.2) with `selection`, and keeps it for a cell it restarts. The selection is the board's, so every viewer of one board process sees it, as every viewer sees its window.

**Highlighting: the view states `:selected` and `:muted`, laid per datum** (#638, D-171). A cell **shows** the selection when a row of any of its slots **holds** it: for each field of the selection, one of the fields linked to it has that field's value — for a single field's selection, the value at one of the linked fields; for a composite one, every field's value at once, so `%{host: "mx1", iface: "eth0"}` is held by mx1's eth0 and by no other interface of mx1. Such a cell draws every datum in a **view state** from the style palette (spec/08 §7.7): a row that holds the selection is drawn `:selected`, every other row `:muted`. It does so through the style grammar's own per-datum mechanism, a field entry in the style stack whose value names the style (spec/14 §3.6, #644), with nothing of its own:

- it adds a **state column**, `:"$vis_state"`, to its slots' rows: `:selected` for a row that holds the selection, `:muted` for every other row;
- it declares, for that drawing alone, the column among the fields of every source that declares its fields;
- it appends `{:field, :"$vis_state"}` to the style stack of every mark that has `data`, so the state is the stack's last layer and wins where it overlaps the mark's own style. No scale is declared: the column's value is the style's name.

The two names resolve as every palette name does (spec/14 §3.3): the design's own `styles` entry of that name first, then the palette of the theme the cell is drawn with, the default theme's entry where that theme lacks one. A design restyles its board's selection by declaring `selected:` or `muted:` in its `styles`, and a theme swap restyles every board that does not. The built-in palette's `:muted` is `opacity: 0.25`, so the data a selection leaves out fade exactly as they did before view states existed; its `:selected` is `stroke_width: 2` alone, with no stroke colour and no `stroke_style` (#638), so it changes a non-hue key (D-171's state contract) without painting over a mark's own look: a selected line or rule keeps its series colour and draws heavier, and a bar, a point or a text with no stroke of its own draws as it is, the selection shown by contrast with the faded rest. A design that wants an outline declares its own `selected:`, `%{stroke: :text, stroke_width: 2, stroke_style: :outside}` for instance; which key suits which kind of mark is #640's question, and the built-in entry does not lean on it. By §3.6's binding rule a mark drawing an element per datum lays each element's state from its row — a faded point beside its selected neighbour — and a line or an area lays a whole series' from its first datum. A cell that does not show the selection is drawn exactly as before, byte for byte — no column, no stack entry — because a selection it cannot find says nothing about it. The highlight therefore needs no hook, works on every render target the cell's chart has, and a stylesheet sees it as the attributes it is. A transform that derives new rows without the column, such as a `:sum`, leaves its mark in its own style: a value that names no style lays nothing (spec/14 §3.6), and the selection's identity is not on those rows. A pick and a click read a row without the state column (§9.2). A selection change recompiles each cell that shows it or showed it, as a change of chart does (§8.3).

**Clearing.** Escape anywhere in the board clears the selection (§9.3), and so does the header's **Clear selection** button. Selecting with no identity changes nothing, so a click on a datum that names nothing keeps the selection. Every change of the selection, made or cleared, reaches the page as the `:select` event, `value: %{identity: identity | nil}` (§9.2, D-170).

### 13.3 Drill-down

**A drill target is stored data on the cell.** A cell's `drill` node says which board a click on one of its data opens and with which variables:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `board` | `:self`, an atom, a non-empty string or a positive integer | required | the target: `:self` is this board, and anything else is the host's name for a board, since a board is not a store entry and where a host keeps its boards is its own (§11.2) |
| `vars` | a map from the target's variable name to `{:datum, field}` or a value | `%{}` | the variables the target is opened with: a field of the clicked datum, or a fixed value |

```elixir
drill: %{board: :detail, vars: %{service: {:datum, :name}, range: "1h"}}
```

**It is validated against the target.** Alone, the node's shape is checked (§3.1). Given `boards:` (§3.2), its target must be a board the host holds, and every variable it sets must be one the target declares, a key of the target's `vars`. A `{:datum, field}` must name a field the cell's component's sources declare, when they declare any. A target of `:self` is checked against the board itself, with or without `boards:`. An invalid target is refused when the board is read with the store, and the runtime refuses to start such a board (§8.2), so a drill cannot fail later for want of a variable the target never had.

**A click resolves it.** A pick (§13.2) in a cell with a `drill` resolves the target instead of selecting. `Visualize.Board.drill(board, cell, row)` gives `{:ok, %{board: ref, vars: vars}}` with every `{:datum, field}` read from the picked row and every fixed value as it is. A row with no value for a datum field is `{:error, [{[:cells, cell, :drill, :vars, var], {:missing, :datum, field}}]}`, and nothing opens. The board's component hands the target to the page as the `:drill` event (§9.2, D-170), and the page decides what opening it means (§9.2). The library holds no route, and `push_navigate` from the component would have to guess one. A callback assign would put a function in the component's assigns, where a message is how a LiveView already talks to its own page. A page that ignores the message ignores drills.

**A mark's own event goes the same way.** A mark whose `tooltip` node names an `event` reaches the page on a click as `%Visualize.Event{event: name, cell: cell, row: row}`, the row resolved by the cell against the drawing it holds (§9.2, D-161, D-170), so a host can open what a datum names, such as an event marker, without the board knowing what it is.

### 13.4 Functions

The functions are listed with their modules: `link/2`, `linked/2` and `drill/3` in §7.1, and `brush/2`, `reset_window/1`, `select/2` and `pick/4` in §8.6.
