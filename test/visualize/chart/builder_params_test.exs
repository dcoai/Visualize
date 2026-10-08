defmodule Visualize.Chart.Builder.ParamsTest do
  @moduledoc """
  The parameters form and the design's JSON form (spec/14 §18.11-§18.12, spec/10 §15, D-88).

  The form is `Visualize.Chart.free_vars/1` rendered, so the tests are about what the stack
  leaves open rather than about a list of controls: a variable a higher layer writes over
  disappears, one a higher layer opens appears, and each takes the widget its first use's
  type asks for.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Visualize.BuilderFixture
  alias Visualize.Chart
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.{Document, Params}

  for name <- ~w(params params_bound document document_errors)a do
    test "#{name} renders as recorded" do
      c = Keyword.fetch!(BuilderFixture.cases(), unquote(name))
      assert BuilderFixture.golden(unquote(name)) == BuilderFixture.render_case(c)
    end
  end

  describe "the parameters form (spec/14 §18.11)" do
    test "one control per free variable, ordered by name, with its uses beside it" do
      html = rendered(:params)

      names =
        ~r|<span class="vis-builder-param-name">(\w+)</span>|
        |> Regex.scan(html)
        |> Enum.map(fn [_, name] -> name end)

      assert names == ~w(accent ticks unit)

      assert names ==
               Enum.map(Chart.free_vars(BuilderFixture.parameterised()), &to_string(&1.name))

      assert html =~ ~s(<span class="vis-builder-param-uses">frames.main.axes[0].ticks</span>)
    end

    test "the widget is the one the first use's expectation asks for" do
      html = rendered(:params)
      assert html =~ ~s(<input type="text" name="accent">)
      assert html =~ ~s(<input type="number" name="ticks")
      # A text is a text field (§7.1, §18.6).
      assert html =~ ~s(<input type="text" name="unit")
    end

    test "a variable with no default is required, and its default is the placeholder" do
      html = rendered(:params)
      assert html =~ ~s(<label class="vis-builder-param vis-builder-param-required">)
      assert html =~ ~s(placeholder="3")
      assert rendered(:params_bound) =~ ~s(<input type="number" name="ticks" value="6")
    end

    test "a variable a higher layer writes over disappears, and one it opens appears" do
      base = %{version: 2, frames: %{main: %{kind: :cartesian}}}

      titled = %{
        vars: %{unit: %{}},
        labels: [%{id: :title, anchor: :title, text: [Chart.var(:unit)]}]
      }

      literal = %{labels: [%{id: :title, anchor: :title, text: ["Uptime"]}]}
      widened = %{vars: %{wide: %{}}, frames: %{main: %{margin: %{top: Chart.var(:wide)}}}}

      open = render_component(&Params.panel/1, %{layers: [base, titled]})
      closed = render_component(&Params.panel/1, %{layers: [base, titled, literal]})
      opened = render_component(&Params.panel/1, %{layers: [base, titled, widened]})

      assert open =~ ">unit</span>"
      refute closed =~ "vis-builder-param-name"
      assert opened =~ ">wide</span>"
    end

    test "a stack with no free variable renders an empty form" do
      html = render_component(&Params.panel/1, %{layers: [%{version: 2}]})

      assert html =~
               ~s(<form id="vis-builder-params" class="vis-builder-params" phx-change="set_var" ) <>
                 ~s(phx-submit="submitted">)

      refute html =~ "vis-builder-param-name"
    end
  end

  describe "binding a parameter (spec/14 §18.11)" do
    test "a value is parsed with the type its control was chosen from, and reaches the preview" do
      socket = socket()
      params = %{"_target" => ["ticks"], "ticks" => "6"}
      {:noreply, bound} = Builder.handle_event("set_var", params, socket)

      assert bound.assigns.bindings == %{ticks: 6}
      refute bound.assigns.bindings == %{ticks: "6"}
    end

    test "a blank control removes the binding and the declared default returns" do
      {:noreply, bound} =
        Builder.handle_event("set_var", %{"_target" => ["ticks"], "ticks" => "6"}, socket())

      {:noreply, blank} =
        Builder.handle_event("set_var", %{"_target" => ["ticks"], "ticks" => ""}, bound)

      assert blank.assigns.bindings == %{}
    end

    test "a name no variable carries changes nothing" do
      params = %{"_target" => ["nonsense"], "nonsense" => "1"}
      {:noreply, unchanged} = Builder.handle_event("set_var", params, socket())
      assert unchanged.assigns.bindings == %{}
    end

    test "the bindings are the builder's own copy of the vars assign" do
      html =
        render_component(Builder, %{
          id: "b",
          layers: BuilderFixture.layers(),
          sources: BuilderFixture.sources(),
          vars: %{unit: "mg/hr"}
        })

      assert html =~ "Uptime — mg/hr"
    end
  end

  describe "import and export (spec/14 §18.12)" do
    test "the exported document reads back as the same design" do
      design = Chart.stack(BuilderFixture.layers())
      html = rendered(:document)

      [_, encoded] =
        Regex.run(~r|<textarea class="vis-builder-export" readonly>(.*?)</textarea>|s, html)

      {:ok, chart} = html_unescape(encoded) |> Chart.from_json()
      {:ok, expected} = Chart.from_map(design)
      assert chart == expected
    end

    test "a design that does not encode is its faults, and no document" do
      html = rendered(:document_errors)
      assert html =~ ~s(<li class="vis-builder-error">version: is required</li>)
      refute html =~ "vis-builder-export"
    end

    test "an imported document replaces the stack with its sites, one kind each" do
      {:ok, chart} = Chart.from_map(Chart.stack(BuilderFixture.layers()))
      {:ok, json} = Chart.to_json(chart)
      {:noreply, opened} = Builder.handle_event("import", %{"document" => json}, socket())

      # Every row is one kind, keyed where the document keyed it, and the stack flattens
      # back to the document.
      assert BuilderFixture.names(opened) == [
               "theme",
               "frame",
               "style series",
               "scale x",
               "scale y",
               "source primary",
               "var unit",
               "axis x bottom",
               "axis y left",
               "mark series",
               "label 1"
             ]

      # A node that declares nothing has no site: an empty `defs` (§2.7), an empty
      # `meta` (§2.2) and an empty `layout` (§2.8) are the schema's defaults, which
      # `to_map/1` writes and a person did not.
      assert BuilderFixture.design(opened) ==
               Chart.to_map(chart) |> Map.drop([:defs, :meta, :layout, :interaction])

      assert BuilderFixture.selected(opened) == 0
      assert BuilderFixture.disabled(opened) == MapSet.new()
      assert opened.assigns.bindings == %{}
      assert opened.assigns.notice == nil
    end

    test "a document that does not parse or does not validate is a notice, and no layer moves" do
      broken = Builder.handle_event("import", %{"document" => "{"}, socket())
      invalid = Builder.handle_event("import", %{"document" => "{\"marks\": []}"}, socket())

      assert {:noreply, %{assigns: %{notice: "design: " <> _}}} = broken
      assert {:noreply, %{assigns: %{notice: "version: is required"}}} = invalid
      assert BuilderFixture.layers(elem(broken, 1)) == BuilderFixture.parameterised()
    end

    test "without Jason the panel says so rather than raising" do
      assert Document.faults({:missing_dependency, :jason}) == [
               "design: the JSON codec needs Jason"
             ]
    end
  end

  describe "the forms' ids (spec/10 §15.3, #444)" do
    # LiveView recovers a form after a crash or reconnect only by its id.
    test "the parameters form carries the panel's id, and each site form one derived from it" do
      sites = [
        %{index: 0, label: "base", free: [%{name: :unit}], vars: %{}},
        %{index: 2, label: "titled", free: [%{name: :ticks}], vars: %{ticks: 6}}
      ]

      html =
        render_component(&Params.panel/1, %{layers: BuilderFixture.parameterised(), sites: sites})

      assert html =~
               ~s(<form id="vis-builder-params" class="vis-builder-params" phx-change="set_var")

      assert html =~
               ~s(<form id="vis-builder-params-site-0" class="vis-builder-site" phx-change="bind_site")

      assert html =~
               ~s(<form id="vis-builder-params-site-2" class="vis-builder-site" phx-change="bind_site")

      assert BuilderFixture.forms_without_id(html) == []
      assert BuilderFixture.duplicate_ids(html) == []
    end

    test "an explicit id wins" do
      sites = [%{index: 1, label: "base", free: [%{name: :unit}], vars: %{}}]

      html =
        render_component(&Params.panel/1, %{
          id: "host-params",
          layers: BuilderFixture.parameterised(),
          sites: sites
        })

      assert html =~ ~s(<form id="host-params" class="vis-builder-params")
      assert html =~ ~s(<form id="host-params-site-1" class="vis-builder-site")
      assert html =~ ~s(<datalist id="host-params-names">)
    end
  end

  defp rendered(name),
    do: BuilderFixture.render_case(Keyword.fetch!(BuilderFixture.cases(), name))

  defp html_unescape(text) do
    text
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
  end

  defp socket(opts \\ []) do
    BuilderFixture.socket(
      BuilderFixture.parameterised(),
      Keyword.merge([on_save: :visualize_chart_saved, vars: %{}, theme: nil], opts)
    )
  end
end
