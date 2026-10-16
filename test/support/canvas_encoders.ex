defmodule Visualize.CanvasEncoders do
  @moduledoc """
  Every canvas encoder, as one list the guards read (spec/12 §6, #693, #744).

  `encoders/0` maps each module under `Visualize.Backend.Canvas*` that encodes an element to
  the stream it writes for an IR element — the SVG-element encoder is given the element as
  `Visualize.SVG.Element.from_ir/1` makes it — and `not_encoders/0` names every other such
  module, so a new encoder cannot escape a guard that walks the list. `draws/2` replays one
  encoder's streams on the recording stub through the hook that reads it, in one node run.
  """

  import Visualize.JsHooks, only: [run: 1]

  alias Visualize.Backend.{Canvas, CanvasBinary, CanvasIncremental}

  @size {240, 200}

  @doc "Every canvas encoder, by its module, as the stream it writes for an IR element."
  @spec encoders() :: %{module() => (Visualize.IR.Element.t() -> binary())}
  def encoders do
    %{
      Canvas => &__MODULE__.commands/1,
      CanvasBinary => &CanvasBinary.encode_element!/1,
      CanvasBinary.SVG => &__MODULE__.svg_elements/1,
      CanvasIncremental => &CanvasIncremental.encode_full_redraw/1
    }
  end

  @doc """
  The modules under `Visualize.Backend.Canvas*` that encode no element: a geometry helper,
  the commands' serializer (the canvas commands' `:json` is it), the decoder, the opcode
  table and the path record writer.
  """
  @spec not_encoders() :: [module()]
  def not_encoders do
    [
      Canvas.Arc,
      Canvas.Output,
      CanvasBinary.Decoder,
      CanvasBinary.Opcodes,
      CanvasBinary.PathEncoder
    ]
  end

  @doc "The canvas commands' `:json` for an IR element."
  @spec commands(Visualize.IR.Element.t()) :: binary()
  def commands(element), do: IO.iodata_to_binary(Canvas.render_element(element, format: :json))

  @doc "The binary stream of the SVG elements an IR element renders as."
  @spec svg_elements(Visualize.IR.Element.t()) :: binary()
  def svg_elements(element),
    do: CanvasBinary.encode_element!(Visualize.SVG.Element.from_ir(element))

  @doc """
  What the hook that reads `encoder`'s stream draws for each element, in order: one list of
  the stub's draw records per element, each without the canvas it drew on. Every element is
  mounted on a canvas of its own, in one node run.
  """
  @spec draws(module(), [Visualize.IR.Element.t()]) :: [[map()]]
  def draws(encoder, elements) do
    encode = Map.fetch!(encoders(), encoder)
    {width, height} = @size
    mounts = Enum.map_join(elements, "\n", &mount(encoder, encode.(&1), width, height))

    {:ok, %{"draws" => draws, "report" => %{"canvases" => canvases}}} =
      run("""
      const canvases = [];
      #{mounts}
      Stub.done({canvases});
      """)

    by_canvas = Enum.group_by(draws, & &1["on"], &Map.delete(&1, "on"))
    Enum.map(canvases, &Map.get(by_canvas, &1, []))
  end

  defp mount(Canvas, json, width, height) do
    data = %{commands: json, width: "#{width}", height: "#{height}"}

    """
    canvases.push(Stub.mount(CanvasChart, Stub.element(#{Jason.encode!(data)}, #{width}, #{height})).canvas.id);
    """
  end

  defp mount(CanvasIncremental, binary, width, height) do
    data = %{width: "#{width}", height: "#{height}"}
    payload = %{binary: Base.encode64(binary), dx: 0, dy: 0, mode: "full"}

    """
    {
      const hook = Stub.mount(CanvasIncrementalChart, Stub.element(#{Jason.encode!(data)}, #{width}, #{height}));
      Stub.deliver(hook, 'canvas_incremental', #{Jason.encode!(payload)});
      canvases.push(hook.canvas.id);
    }
    """
  end

  defp mount(_binary_encoder, binary, width, height) do
    data = %{binary: CanvasBinary.to_base64(binary), width: "#{width}", height: "#{height}"}

    """
    canvases.push(Stub.mount(CanvasBinaryChart, Stub.element(#{Jason.encode!(data)}, #{width}, #{height})).canvas.id);
    """
  end
end
