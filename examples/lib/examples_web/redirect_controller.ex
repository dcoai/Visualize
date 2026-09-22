defmodule ExamplesWeb.RedirectController do
  @moduledoc """
  Routes that moved: `/high-performance` is the Scrolling series chart's page (#327) and
  `/incremental` the Incremental line chart's (#402) — each demo is a design now.
  """
  use Phoenix.Controller, formats: [:html]

  def scrolling_series(conn, _params), do: redirect(conn, to: "/chart/scrolling_series")

  def incremental_line(conn, _params), do: redirect(conn, to: "/chart/incremental_line")
end
