defmodule ExamplesWeb.BuilderLiveTest do
  @moduledoc """
  The builder page starts from its own library (spec/14 §19.9): every row names an entry,
  the two verbs report differently, and the drag diagnostics are gone.
  """
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias ExamplesWeb.BuilderLive
  alias ExamplesWeb.BuilderLive.Library
  alias Phoenix.LiveView.Socket
  alias Visualize.Chart

  @endpoint ExamplesWeb.Endpoint

  setup do
    {:ok, _} = Application.ensure_all_started(:examples)
    :ok
  end

  test "every row on the start screen names a library entry" do
    html = build_conn() |> get("/builder") |> html_response(200)

    for name <- ~w(Uptime::house Uptime::shared Uptime::panel) do
      assert html =~ ~s(<span class="vis-builder-layer-name">#{name}</span>)
      assert Library.id_of(name) != nil
    end

    refute html =~ "drag diagnostics"
    refute html =~ "builder-diagnostics"
    assert html =~ ~s(<button type="submit" class="vis-builder-new-submit">New</button>)
    assert html =~ ~s(class="vis-builder-deploy")
  end

  test "save keeps structure; deploy applies the design and says so" do
    {:ok, socket} = BuilderLive.mount(%{}, %{}, %Socket{})

    structure = %{
      composite: %{
        uses: Enum.map(socket.assigns.layers, fn {_name, id} -> Chart.Use.new(id) end),
        vars: %{}
      }
    }

    {:noreply, saved} = BuilderLive.handle_info({:design_saved, "b", structure}, socket)
    assert saved.assigns.saved == "saved: a structure of 3 site(s)"

    fetch = fn id ->
      case Library.get(id, nil) do
        {:ok, entry} -> {:ok, entry.fragment}
        :error -> :error
      end
    end

    {:ok, design, %{missing: []}} = Chart.flatten(structure, fetch)
    {:noreply, deployed} = BuilderLive.handle_info({:design_deployed, "b", design}, socket)
    assert deployed.assigns.saved == "deployed: the design applies"
  end
end
