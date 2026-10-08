if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Document do
    @moduledoc """
    The builder's import and export: the design's JSON form, in and out (spec/14 §18.12).

    Export is `Visualize.Chart.to_json/1` of the stacked design, and it therefore demands a
    *design*: the stack goes through `Visualize.Chart.from_map/1` first, and a fragment that
    does not validate is its errors, listed by path exactly as the preview lists them. Import
    reads a pasted document through `Visualize.Chart.from_json/1`, and the design it yields
    becomes the builder's single layer, since a document is a whole design and not a layer of
    somebody else's stack (D-88).

    Both are behind the optional `Jason` dependency: without it each reports
    `{:missing_dependency, :jason}` in the panel rather than raising, which is what an
    optional dependency means.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart
    alias Visualize.Chart.Validator

    attr(:id, :string,
      default: "vis-builder-document",
      doc: "the panel's id, and the stem of its import form's"
    )

    attr(:design, :map, required: true, doc: "the stacked design to encode")
    attr(:kind, :atom, default: :composite, doc: "what the stack is of: a composite, or one kind")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the form's events")
    attr(:class, :string, default: nil, doc: "appended to the panel's class")

    @doc """
    Renders the import and export panel (spec/10 §15.3).

    The exported document, or the faults that stop it, and a form that reads one back.
    """
    def panel(assigns) do
      assigns = assign(assigns, encoded(assigns.design, assigns.kind))

      ~H"""
      <div id={@id} class={class(@class)}>
        <textarea :if={@document} class="vis-builder-export" readonly>{@document}</textarea>
        <ul :if={@errors != []} class="vis-builder-errors">
          <li :for={line <- @errors} class="vis-builder-error">{line}</li>
        </ul>
        <form id={@id <> "-import"} class="vis-builder-import" phx-submit="import" phx-target={@target}>
          <textarea name="document"></textarea>
          <button type="submit" class="vis-builder-import-submit">Import</button>
        </form>
      </div>
      """
    end

    defp class(nil), do: "vis-builder-document"
    defp class(extra), do: "vis-builder-document " <> extra

    @doc false
    # A design's JSON document, or the faults that stop it as lines a person reads. Public to
    # the builder, whose import event reports a document's faults the same way.
    @spec faults([Validator.error(), ...] | {:missing_dependency, :jason}) :: [String.t(), ...]
    def faults({:missing_dependency, :jason}), do: ["design: the JSON codec needs Jason"]
    def faults(errors) when is_list(errors), do: Enum.map(errors, &Validator.format/1)

    # A design is the document a chart reads back; any other kind is the fragment itself,
    # valid as that kind (spec/14 §19.8), in the same JSON form.
    defp encoded(design, :composite) do
      with {:ok, chart} <- Chart.from_map(design),
           {:ok, json} <- Chart.to_json(chart) do
        %{document: json, errors: []}
      else
        {:error, reason} -> %{document: nil, errors: faults(reason)}
      end
    end

    defp encoded(fragment, kind) do
      with :ok <- Validator.validate(fragment, kind),
           {:ok, json} <- fragment_json(fragment) do
        %{document: json, errors: []}
      else
        {:error, reason} -> %{document: nil, errors: faults(reason)}
      end
    end

    defp fragment_json(fragment) do
      if Code.ensure_loaded?(Jason) do
        {:ok, fragment |> Chart.Codec.encode() |> Jason.encode!()}
      else
        {:error, {:missing_dependency, :jason}}
      end
    end
  end
end
