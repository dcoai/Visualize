# Boards

**Status:** Implemented

A **board** is a dashboard as data: designs laid out on a grid, sharing a time window, variables and a sync group, but never geometry. It is the layer above the composite of [14-declarative-chart](14-declarative-chart.md) §19.6. A composite is overlapping parts that **flatten** into one chart in one coordinate space, such as a gauge drawn over a line. A board **never flattens**: each cell is its own chart, applied, rendered and updated on its own, and the cells share *state*, not pixels (#531 §1).

This document is the board as a **value**: its keys, its codecs, its validation, the sources it needs and how a connector binds them (#539, D-141). The processes that keep a board live, its feeds and its cells' designed states are the board runtime's (#540). A board's travel with its components in a bundle is #542's.

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

**A cell's name is its identity.** Cells are a map by name, as a design's frames are (spec/14 §2.1), so a cell is the same cell wherever it is moved. The name namespaces the cell's sources (§4.1), keys its variables and its realised chart (§6), and is what a binding names. It is never drawn.

**A component is a store entry, referred to by id** (spec/14 §19.2). The ref is an id of kind `:composite`, issued by the store. That entry holds either a composite, which flattens to a design (spec/14 §19.6), or a flat design, such as an imported document. `Visualize.Chart.Composite.flatten/2` reads both, and a design flattens to itself. A design is not a kind of fragment and has no id of its own (spec/14 §19.8), so a composite id is the one form a component reference takes. A local key or an inline design is not a component reference, because a board holds no designs of its own. Whatever it shows is in the store, where the builder edits it and a bundle carries it (#542).

**The rectangle is metresis's** (its spec §8.3), so a metresis panel becomes a cell mechanically: `x`, `y`, `w` and `h` carry over unchanged, its stored design becomes the component, and its query becomes the cell's binding.

### 1.4 The grid: twelve columns

A board is **12 columns wide**. `Visualize.Board.columns/0` is `12`. A cell's `x + w` MUST NOT exceed it, and two cells MUST NOT share a grid square (§3.1). The grid has no last row: `y` and `h` are bounded only by the limits of §2.3.

**The grid is not generalised now** (#539's open question, settled here). Twelve divides into halves, thirds, quarters and sixths, which every dashboard layout this library has seen uses, and it is metresis's grid, which keeps the migration mechanical. A `columns` key would be the general case. It is not a key today, so a board that gives one is `:unknown_key`. Adding it later is additive: boards written before it read as 12 columns, and a board written with it would carry a newer version that an older reader refuses by name (§2.3). Nothing has to be undone to generalise.

### 1.5 Shared state: the window, the zone, the variables and the sync group

**The window is in UTC.** A board's `window` is one of:

- `nil`: the board shares no window, and each cell's component keeps its own (a viewport, spec/14 §12.5, or none);
- `%{last: seconds}`: a trailing window of that many seconds (a positive number), ending at the board's *now*;
- `%{from: from, to: to}`: a fixed window between two `DateTime`s in `Etc/UTC`, with `from` before `to`.

A window that gives `last` together with `from` or `to`, a `from` without a `to`, a `DateTime` in another zone and a `from` not before its `to` are faults (§3.3). **Now comes from the board, never from a feed** (#531, further considerations §3). `Visualize.Board.window/2` resolves the window against the instant the caller passes as now, giving `{from, to}` as two UTC `DateTime`s, or `nil` for a board with no window. That pair is what the runtime asks each feed for (#540). The value says nothing about how a window moves. A brush or a time picker writes a new `window`.

**The zone is for display only.** `zone` is the time zone the board's times are *shown* in. It is checked as a time scale's `zone` is (spec/14 §4.3, D-115): a name the host's time-zone database does not know is `{:zone, name, reason}`. The window itself stays in UTC, so two hosts in two zones fetch the same rows and show them in their own zone.

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

## 2. Version, codecs and limits

### 2.1 The map form

`Visualize.Board.to_map/1` is the board as a map with every key of §1.2, `version` included. `Visualize.Board.from_map/2` reads a map as §2.3 orders it and returns `{:ok, board}` or `{:error, errors}` with every fault of §3.1 in the shape of spec/14 §10.1. `Visualize.Board.from_map!/2` returns the board or raises `ArgumentError` with the faults formatted. `from_map(to_map(board))` is `{:ok, board}` for every valid board.

### 2.2 The JSON form

`Visualize.Board.to_json/1` writes the board as a JSON document behind the optional `Jason` dependency, as spec/14 §11.1 does for a design. Without Jason, `to_json/1` and `from_json/2` return `{:error, {:missing_dependency, :jason}}`. The document is the map form with string keys, except for the version. **The version is the stamp `"$version"`** at the document's top level, as a fragment document carries it (spec/14 §19.7, D-137), so any JSON document this library writes, other than a design, is stamped under one key. A reader gates a document by that key before it knows anything else about it. Values JSON has no form for are the tagged terms of spec/14 §11.2: a component reference `{:composite, 5}` is `{"$id": ["composite", 5]}`, a window's `DateTime` is `{"$time": "…"}`, and an atom in a variable's value is `{"$atom": "…"}`. A cell's name and a variable's name are object keys.

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
- **Variables.** A board's or a cell's variable name that is not an atom is `{:type, :name}` at its path. A value that is itself a variable (`%Visualize.Chart.Var{}`) is `{:var_binding, name}`, because a board's variables are values, and resolution is single level (spec/14 §7.1).
- **A component reference** that is not an id `{kind, n}` is `{:type, {:id, :composite}}`. An id of another kind, `{:style, 3}`, is `{:ref_kind, :composite, :style}`, as the validator refuses a wrong-kind id before resolution (spec/14 §19.7).

### 3.2 Given a store

`validate/3` takes the board, a **store** and options. The store is anything resolution reads (spec/14 §19.6): a fetch function, `(id -> {:ok, fragment} | :error)`, or a map from id to fragment, which is read as `Map.fetch/2`. A host with a `Visualize.Chart.Builder.Store` gives the fetch that its `get/2` makes, the body of the entry. `limits:` is passed to every design read. When the board is valid alone, each cell's component is then **resolved**: the entry is fetched, flattened through the same store (spec/14 §19.6) and read through `Visualize.Chart.from_map/2` with the limits.

- **A dangling reference.** An id the store does not hold is `{:dangling, id}` at `[:cells, name, :ref]`.
- **A component that reaches itself** through any chain of uses is `{:cycle, chain}` there, with the chain `Visualize.Chart.Composite.flatten/2` names.
- **A component that is not a design.** Every fault of reading the flattened component is reported under the cell's ref, `[:cells, name, :ref | path]`, with `path` the design's own: `cells.latency.ref.marks[0].type: is required`. A composite that flattens to a partial design, such as a house look of a theme and a frame, is not a component.
- **A variable the component does not declare.** A cell's variable that its component's design does not declare is `{:undeclared, :var, name}` at `[:cells, name, :vars, var]`. A board variable that no cell's component declares is **not** a fault. It is a default for whichever components declare it (§5), as a pool entry that no slot names is ignored (spec/14 §7.3).
- **A cell that cannot join the group.** With the board's `sync` set and the cell's `sync` true, the component's design is validated with the board's group written into its `interaction.sync`. Any `{:sync, …}` fault (spec/14 §2.9) is reported at `[:cells, name, :sync]`.

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

## 4. Sources and binding

### 4.1 Required sources: the aggregate, namespaced per cell

**A board's sources are the aggregate of its cells' slots** (#531, further considerations §4). `Visualize.Board.required_sources/3` resolves each cell's component through the store as §3.2 does and returns `{:ok, required}`, or `{:error, errors}` with the faults of §3.2 that stopped a component from being read. `required` is a map from `{cell, slot}` to the slot's needs:

```elixir
%{
  {:latency, :primary} => %{fields: [:t, :latency], types: %{t: :time, latency: :number},
                            requires: %{latency: [:unit, :label]}},
  {:errors, :primary}  => %{fields: [:t, :count], types: %{}, requires: %{}}
}
```

- **Namespaced per cell.** A slot's key is the cell's name and the slot's own name. One design used in two cells is two sets of slots, each bound to its own data. This is what lets a "request time" component show one service in one cell and another service beside it.
- **`fields` and `types`** are the slot's declaration (spec/14 §2.3), with `types` `%{}` when it declares none.
- **`requires` is the slot's whole contract** (spec/14 §7.4, D-136): its `requires` together with every attribute a fact of it reads, as `Visualize.Chart.contract/1` gives it. A connector tests a feed's schema against it before offering the feed, as a picker does (spec/14 §7.2). It is `%{}` for a slot that states none.

### 4.2 The binding

`%Visualize.Board.Binding{slots}` is the binding, a value separate from the board: `slots` maps a `{cell, slot}` to a **feed**, any term that names a feed or a pool entry, as the pool of spec/14 §7.2 names a source. A **connector** supplies it, and the board never holds it. A board travels between hosts and a binding does not, because the feeds it names are one host's (#531, further considerations §4).

`Visualize.Board.Binding.new/0` is the empty binding. `Visualize.Board.Binding.new/1` takes a map or a list of `{{cell, slot}, feed}` pairs, and raises `ArgumentError` for a key that is not a pair of atoms. `Visualize.Board.Binding.put/4` binds one cell's slot, and `Visualize.Board.Binding.fetch/3` reads one back. One feed may fill many slots, in one cell or in several.

### 4.3 The check

`Visualize.Board.Binding.check/3` takes the binding, the required sources of §4.1, and the feeds' **schemas**: a map from feed to `%Visualize.Data.Schema{}`, or a describe function `(feed -> {:ok, schema} | {:error, reason})`, the pull side of a feed (spec/08 §10.3). It returns `:ok` or `{:error, errors}`, **every** fault, each at the path of the slot in the board, `[:cells, cell, :sources, slot]`, ordered by path:

- **Every unbound slot.** A required slot that the binding does not bind is `{:unbound, :binding, slot}`.
- **Every contract the bound schema cannot meet.** For a bound slot whose contract is not empty, the feed's schema is looked up or described once. A feed the map does not hold is `{:undescribed, feed}`, and a describe that answers `{:error, reason}` is `{:describe, feed, reason}`. Each attribute the contract requires that the schema does not give the field is `{:missing_attribute, slot, field, key}` at `[…, slot, :requires, field]`. Each field whose declared type the schema contradicts is `{:schema_type, field, declared, described}` at `[…, slot, :types, field]`. These are the same reasons, with the same words, as `Visualize.Chart.apply/2` reports for one design (spec/14 §7.4), so a connector that checks its binding first sees, before any data flows, every fault the cells would report later.
- **A binding to nothing.** A binding of a `{cell, slot}` that is not required, such as a cell since removed or a slot since renamed, is `:not_required` at its path, so a stale binding is seen rather than kept.

A slot whose contract is empty is not looked up, as spec/14 §7.4's "the facts the slot did not ask for are not read" holds for one design. Its feed needs no schema.

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
- it is applied with `Visualize.Chart.apply/2`: `sources:` the cell's pool, `size:` the cell's box at `width:` (§1.6), and `theme:`, `now:`, `schemas:` and `describe:` as given. The schema cache is threaded from cell to cell, so a version one cell has described is not described again. `describe:` is called with the `{cell, slot}` being described, which the connector maps to its feed through its binding.

The options are `width:` (the board's container width in pixels, `1200` by default), `theme:`, `now:`, `schemas:`, `describe:` and `limits:`. `realise/3` is `realise/4` with no options.

Every fault of every cell is reported, each under its cell: `[:cells, name | path]`, with `path` application's own. A slot with no source in its cell's pool is therefore `{:unbound, :source, slot}` at `[:cells, name, :sources, slot]`, the same path the binding check uses (§4.3). The board's own faults (§3) come first. A board that does not validate alone is refused before any cell is resolved.

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
| `Visualize.Board.validate/3` | `:ok`, or every fault of the board alone and then given the store (§3.2), with `limits:` for the components' designs. |
| `Visualize.Board.format_error/1` | One fault as a line a person reads, the root named `board`. |
| `Visualize.Board.layout/1` | The effective layout: the board's `layout` over `breakpoint: 768`, `row_height: 80`, `gap: 8` (§1.6). |
| `Visualize.Board.arrange/2` | Each cell's placement at a container width, `[{name, %{x, y, w, h}}]` in reading order, stacked below the breakpoint (§1.6). |
| `Visualize.Board.boxes/2` | Each cell's box in pixels at a container width, `%{name => {x, y, w, h}}`, after reflow (§1.6). |
| `Visualize.Board.window/2` | The window resolved at now: `{from, to}` in UTC, or `nil` for a board with no window (§1.5). |
| `Visualize.Board.vars/2` | One cell's variables before narrowing: the board's with the cell's over them (§5). |
| `Visualize.Board.required_sources/2` | As `required_sources/3` with `[]` options. |
| `Visualize.Board.required_sources/3` | Every cell's slots through the store, keyed `{cell, slot}`, each with `fields`, `types` and its `requires` contract (§4.1); `limits:` for the components' designs. |
| `Visualize.Board.realise/3` | As `realise/4` with `[]` options. |
| `Visualize.Board.realise/4` | Every cell applied, purely: `{:ok, %{cell => applied}, cache}`, or every fault under its cell (§6). |

### 7.2 `Visualize.Board.Binding`

| Function | Contract |
|---|---|
| `Visualize.Board.Binding.new/0` | The empty binding. |
| `Visualize.Board.Binding.new/1` | A binding of a map or a list of `{{cell, slot}, feed}` pairs; `ArgumentError` for a key that is not a pair of atoms (§4.2). |
| `Visualize.Board.Binding.put/4` | The binding with one cell's slot bound to a feed. |
| `Visualize.Board.Binding.fetch/3` | The feed a cell's slot is bound to, `{:ok, feed}`, or `:error`. |
| `Visualize.Board.Binding.check/3` | `:ok`, or every unbound slot, every contract the bound schemas cannot meet and every binding to nothing, by path (§4.3). |
| `Visualize.Board.Binding.pools/2` | One pool per cell from the binding and the host's sources by feed (§4.4). |
