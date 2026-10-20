defmodule ExamplesWeb.ChartLive.MidRun do
  @moduledoc """
  A page control changed while a chart runs (spec/14 §12.6, #796): the one place a running
  renderer is re-prepared at the page's new options, so the next frame drawn is the
  chart under them and the run goes on.

  A run's renderer draws every frame with the backend state it prepared — on a canvas,
  and on SVG for a design that carries state between ticks, the compiled chart. What is
  compiled into it (the theme the design was applied with, the size, a mark's own options
  such as the hexbin's radius) reaches a frame only through a re-preparation; what a tick
  takes (`now:`, `at:`, `motion:`, the rows) reaches it on the next tick by itself.

  Either way the renderer re-prepares in place (`Examples.Renderer.prepare/3`), carrying
  the easing, its rows, and the run's tick and window untouched; the frame in flight was
  asked under the old options and is forgotten; the next frame is full; and the view's
  own state for the markup — a canvas run's static furniture, its backdrop and its size —
  is the new options' from the first frame drawn under them, so the furniture of one
  theme or size is never laid over the frame of another.
  """

  import Phoenix.Component, only: [assign: 2]

  alias Examples.{Frames, Renderer, Run}

  @doc """
  The running chart re-prepared at `opts`, the run's options at its tick under the page's
  new controls; a page with no run going is unchanged.
  """
  @spec reprepared(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def reprepared(%{assigns: %{run: %Run{running: true, renderer: renderer} = run}} = socket, opts)
      when is_pid(renderer) do
    %{module: module, run_backend: backend} = socket.assigns
    Renderer.prepare(renderer, backend, opts)

    assign(socket,
      run: Run.reprepared(run),
      run_pending_state: {:state, Frames.prepare(module, opts, backend)}
    )
  end

  def reprepared(socket, _opts), do: socket

  @doc """
  The running chart switched to `backend` at `opts` (spec/14 §12.6, #502, D-128): the
  re-preparation with a backend, the run closing the old backend's segment
  (`Examples.Run.switch/2`).
  """
  @spec switched(Phoenix.LiveView.Socket.t(), Frames.backend(), keyword()) ::
          Phoenix.LiveView.Socket.t()
  def switched(%{assigns: %{run: run, module: module}} = socket, backend, opts) do
    Renderer.prepare(run.renderer, backend, opts)

    assign(socket,
      run: Run.switch(run, backend),
      run_backend: backend,
      run_pending_state: {:state, Frames.prepare(module, opts, backend)}
    )
  end

  @doc """
  The first frame drawn under the new options brings their state into the markup; any
  other frame changes nothing of it.
  """
  @spec markup(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def markup(%{assigns: %{run_pending_state: {:state, state}}} = socket),
    do: assign(socket, run_state: state, run_pending_state: nil)

  def markup(socket), do: socket
end
