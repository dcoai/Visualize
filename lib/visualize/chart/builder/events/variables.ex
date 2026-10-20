if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Events.Variables do
    @moduledoc false
    # Variables as chips (spec/14 §19.9, §19.10): found, expanded, bound to a field, a root
    # or a site, unbound, created, promoted from a value and defaulted; and a color patch
    # dropped on a well.
    #
    # Split from `Visualize.Chart.Builder` by area (#568); compiled only with
    # `Phoenix.Component`, as the builder is (spec/10 §1.1, D-45, D-85).

    import Phoenix.Component, only: [assign: 2, assign: 3, update: 3]
    import Visualize.Chart.Builder.Editing, only: [editing: 1, root_word: 1]
    import Visualize.Chart.Builder.Selection, only: [aimed: 2, row_use: 2]

    import Visualize.Chart.Builder.Writes,
      only: [locked_notice: 2, update_layer: 4, update_node: 3]

    alias Visualize.Chart.{Builder, Fragment, Use}
    alias Visualize.Chart.Builder.{Editor, Params, Stack, Variables}

    # The events this module handles: `Visualize.Chart.Builder.handle_event/3` routes
    # each here.
    @events ~w(
      find_variable expand_variable bind_field bind_root unbind_field drop_color
      create_variable promote set_default bind_site
    )

    @doc false
    def events, do: @events

    # -- variables as chips (spec/14 §19.9, §19.10) --------------------------------------

    @doc false
    def handle_event("find_variable", %{"find" => find}, socket) do
      {:noreply, assign(socket, :find, find)}
    end

    def handle_event("expand_variable", %{"name" => name}, socket) do
      expanded = socket.assigns.expanded

      expanded =
        if MapSet.member?(expanded, name),
          do: MapSet.delete(expanded, name),
          else: MapSet.put(expanded, name)

      {:noreply, assign(socket, :expanded, expanded)}
    end

    # A chip dropped on a field binds it: the field's key takes var(:name). A variable
    # already typed by a use of another type is refused by name; one used nowhere takes
    # the control's type by being used here (spec/14 §19.9).
    def handle_event("bind_field", %{"field" => field, "name" => name} = params, socket) do
      socket = aimed(socket, params)
      %{entry: entry, layers: layers, design: design, editing: node} = editing(socket.assigns)

      # A part's key by its path (§18.7): the variable is written into the part.
      with %{path: at, spec: %{key: key, type: type}} when type != :text <-
             Editor.locate(entry.kind, field),
           {:ok, var} <- Editor.variable(name),
           :ok <- fits(Variables.list(layers, design), var.name, element(type), key) do
        value =
          case type do
            # A list of scalars takes the variable as an item (§19.9): fields: [:t, var(:y)].
            {:list, _scalar} -> List.wrap(Editor.value_at(entry.kind, node, at)) ++ [var]
            _single -> var
          end

        {:noreply,
         socket
         |> update_node(entry.path, Editor.write(entry.kind, node, at, {:ok, value}))
         |> assign(:notice, nil)}
      else
        %{spec: %{type: :text}} ->
          # A text takes a variable as text among text, at the caret, by the hook (§7.1).
          {:noreply, socket}

        {:refused, notice} ->
          {:noreply, assign(socket, :notice, notice)}

        _other ->
          {:noreply, assign(socket, :notice, "#{field} is not a field here")}
      end
    end

    # A chip dropped on a strip tab binds the first key of that root the variable fits.
    def handle_event("bind_root", %{"root" => root, "name" => name}, socket) do
      %{layers: layers, design: design} = editing(socket.assigns)

      with {:ok, var} <- Editor.variable(name),
           {:noreply, socket} <- Builder.handle_event("select_root", %{"root" => root}, socket),
           %{entry: entry} <- editing(socket.assigns),
           %{key: key} <- first_fit(entry.kind, Variables.list(layers, design), var.name) do
        {:noreply, socket |> update_layer(entry.path, key, {:ok, var}) |> assign(:notice, nil)}
      else
        _other ->
          {:noreply, assign(socket, :notice, "nothing under #{root_word(root)} takes #{name}")}
      end
    end

    def handle_event("unbind_field", %{"field" => field} = params, socket) do
      socket = aimed(socket, params)
      %{entry: entry, editing: node} = editing(socket.assigns)

      case Editor.locate(entry.kind, field) do
        nil ->
          {:noreply, socket}

        %{path: at} ->
          {:noreply, update_node(socket, entry.path, Editor.write(entry.kind, node, at, :error))}
      end
    end

    # A patch dropped on a well writes that well's key, selected or not (spec/14 §19.10): a
    # word is a slot, a `#rrggbb` a literal, each through the edit the chooser would make;
    # the form the well sits in says which edit. A key that is not a color refuses by name.
    def handle_event("drop_color", %{"field" => field, "color" => color} = params, socket) do
      socket = aimed(socket, params)
      edit = if Map.get(params, "edit") == "edit_style", do: "edit_style", else: "edit"
      kind = if edit == "edit_style", do: :style, else: editing(socket.assigns).entry.kind

      # A part's color by its path — `stroke.color`, `fill.stops.0.color` (§18.7).
      case Editor.locate(kind, field) do
        %{spec: %{type: :color}} ->
          control = if String.starts_with?(color, "#"), do: field, else: field <> ".slot"
          Builder.handle_event(edit, %{"_target" => [control], control => color}, socket)

        _other ->
          {:noreply, assign(socket, :notice, "#{field} is not a color")}
      end
    end

    # A new variable is a var site of the stack, keyed by its name, with its default.
    def handle_event("create_variable", %{"name" => name} = params, socket) do
      case Editor.variable(name) do
        {:ok, var} -> {:noreply, declared(socket, var.name, Map.get(params, "default", ""))}
        :error -> {:noreply, assign(socket, :notice, "a variable needs a name")}
      end
    end

    # A field's value promoted: a variable named for the key, its literal as the default,
    # and the field bound to it.
    def handle_event("promote", %{"field" => field} = params, socket) do
      socket = aimed(socket, params)
      %{entry: entry, editing: node, layers: layers, design: design} = editing(socket.assigns)

      located = Editor.locate(entry.kind, field)
      value = located && Editor.value_at(entry.kind, node, located.path)

      case located do
        %{path: at} when value != nil ->
          # Named for the key, or for a part's key by its path: `stroke_width` (D-178).
          key = Enum.map_join(at, "_", &to_string/1)
          name = fresh_name(key, Variables.list(layers, design))
          var = %Visualize.Chart.Var{name: name}

          {:noreply,
           socket
           |> declared(name, value)
           |> update_node(entry.path, Editor.write(entry.kind, node, at, {:ok, var}))}

        _other ->
          {:noreply, assign(socket, :notice, "#{field} has no value to promote")}
      end
    end

    # The declaration's default, from the expanded chip (spec/14 §19.10): written where the
    # stack declares the name — the highest site that does, a var site by its key or a
    # layer under its `vars` — else declared by a new var site on top, so it is what wins.
    def handle_event("set_default", %{"_target" => [name]} = params, socket) do
      %{uses: uses} = socket.assigns

      case Editor.variable(name) do
        {:ok, var} ->
          default = parsed_default(Map.get(params, name, ""))
          write = if default == nil, do: :error, else: {:ok, default}

          case declarer(uses, var.name) do
            nil ->
              {:noreply, declared(socket, var.name, default, :top)}

            {%Use{ref: ref} = site, _path} when ref != nil ->
              {:noreply, assign(socket, :notice, locked_notice(socket.assigns, site))}

            {site, path} ->
              {:noreply,
               update(
                 socket,
                 :uses,
                 &Stack.update(&1, site.id, fn u -> Stack.write(u, path, :default, write) end)
               )}
          end

        :error ->
          {:noreply, socket}
      end
    end

    # A site's binding, from its row in the Variables tab (spec/14 §19.4, §19.10): a value,
    # one of the stack's own variables, or — blank — nothing, so the name flows up. This is
    # the one surface that writes `Use.vars`.
    def handle_event("bind_site", %{"site" => site, "_target" => [target]} = params, socket) do
      %{uses: uses, labels: labels, store: store} = socket.assigns

      with %Use{} = use <- row_use(uses, site),
           {name, control} <- control(target),
           %{free: free} <- Enum.find(Stack.sites([use], labels, Stack.fetch(store)), & &1),
           %{} = var <- Enum.find(free, &(to_string(&1.name) == name)) do
        bound =
          case {control, Editor.submitted(Params.expects(var), params[target])} do
            {:variable, _typed} -> Editor.variable(params[target])
            {:literal, typed} -> typed
          end

        {:noreply,
         update(socket, :uses, &Stack.update(&1, use.id, fn u -> rebound(u, var.name, bound) end))}
      else
        _other -> {:noreply, socket}
      end
    end

    # Whether a variable fits a key's type: untyped fits anything; a typed one must match.
    # A list of scalars takes items of its element's type.
    defp element({:list, scalar}), do: scalar
    defp element(type), do: type

    # Whether a variable fits a key's type: untyped fits anything; a typed one must match —
    # and a field is a channel (a channel is a field or a constant), so a variable typed by
    # a mark's channel fits a source's field list and the other way round (§19.9).
    defp fits(vars, name, type, key) do
      case Enum.find(vars, &(&1.name == name)) do
        nil ->
          :ok

        %{type: nil} ->
          :ok

        %{type: other} when other in [:field, :channel] and type in [:field, :channel] ->
          :ok

        %{type: ^type} ->
          :ok

        %{type: other} ->
          {:refused, "#{name} is #{type_word(other)}; #{key} takes #{type_word(type)}"}
      end
    end

    defp first_fit(kind, vars, name) do
      typed = Enum.find(vars, &(&1.name == name))

      Enum.find(Editor.describe(kind), fn spec ->
        typed == nil or typed.type == nil or typed.type == spec.type
      end)
    end

    defp type_word({:enum, _}), do: "a choice"
    defp type_word({:ref, kind}), do: "a #{kind}"
    defp type_word({:one_of, [first | _]}), do: type_word(first)
    defp type_word(type), do: "a #{inspect(type)}"

    # A var site at the bottom of the stack, keyed by the name, with the default.
    defp declared(socket, name, default, where \\ :bottom) do
      %{uses: uses, labels: labels} = socket.assigns
      default = if is_binary(default), do: parsed_default(default), else: default
      body = if default == nil, do: %{}, else: %{default: default}
      use = %{Use.new(nil, uses) | ref: nil, local: %{var: body}, key: name}

      assign(socket,
        uses: if(where == :top, do: uses ++ [use], else: [use | uses]),
        labels: Map.put(labels, use.id, "var #{name}"),
        notice: nil
      )
    end

    # The highest site declaring a variable, and the path of its declaration in that
    # site's local: `[:var]` for a var site keyed by the name, `[:vars, name]` for a layer.
    defp declarer(uses, name) do
      uses
      |> Enum.reverse()
      |> Enum.find_value(fn use ->
        cond do
          use.key == name and match?({:var, _}, Fragment.wrapped(use.local)) ->
            {use, [:var]}

          is_map(use.local) and is_map(Map.get(use.local, :vars)) and
              Map.has_key?(use.local.vars, name) ->
            {use, [:vars, name]}

          true ->
            nil
        end
      end)
    end

    defp parsed_default(string) do
      case Editor.parse(:term, string) do
        {:ok, value} -> value
        :error -> nil
      end
    end

    defp fresh_name(key, vars) do
      taken = Enum.map(vars, &to_string(&1.name))

      Stream.iterate(1, &(&1 + 1))
      |> Enum.find_value(fn
        1 -> if key in taken, do: nil, else: key
        n -> if "#{key}_#{n}" in taken, do: nil, else: "#{key}_#{n}"
      end)
    end

    defp control(target) do
      case String.split(target, ".", parts: 2) do
        [name, "var"] -> {name, :variable}
        [name] -> {name, :literal}
        _other -> nil
      end
    end

    defp rebound(use, name, {:ok, value}), do: %{use | vars: Map.put(use.vars, name, value)}
    defp rebound(use, name, :error), do: %{use | vars: Map.delete(use.vars, name)}
  end
end
